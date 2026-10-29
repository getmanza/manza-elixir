defmodule TransferAuthorizer.Preflight do
  @moduledoc """
  Checks every setup step before you create a transfer, and says how to fix
  the ones that fail. Prints one line per step: `✓` passed, `✗` failed (with
  the fix), `!` a warning the API cannot settle.

      mix preflight          # for a 10.00 transfer
      mix preflight 250.00
  """

  @secret_min_days 7
  # Hosts that hand out a new URL on every restart. An enrolled endpoint's URL
  # is locked, so the next restart breaks the authorizer.
  @unstable_tunnel_hosts ["ngrok-free.app", "trycloudflare.com"]
  @suspension_fixes %{
    "member" => "an approver suspended it: resume it in Settings → Developer → Transfer approval",
    "signature_failures" =>
      "five invalid signatures in a row: fix the signing, then an approver resumes it in the app",
    "secret_expired" =>
      "an approver rotates the secret in the app (and resumes it if it stays suspended); " <>
        "set the new one as MANZA_AUTHORIZER_SECRET",
    "endpoint_disabled" =>
      "re-enable the webhook endpoint (Manza.WebhookEndpoints.enable/2), or enrol a new one if it was " <>
        "deleted; if it stays suspended, an approver resumes it in the app"
  }

  @doc """
  Runs each applicable check in order; `true` when none failed.

  Options: `:env` (a map, default `System.get_env/0`), `:amount` (default
  `"10.00"`), `:out` (an IO device, default `:stdio`), `:now` (a `DateTime`,
  default now).
  """
  def run(opts \\ []) do
    raw_amount = Keyword.get(opts, :amount, "10.00")

    ctx = %{
      env: Keyword.get_lazy(opts, :env, &System.get_env/0),
      raw_amount: raw_amount,
      amount: parse_amount(raw_amount),
      out: Keyword.get(opts, :out, :stdio),
      now: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    }

    amount_ok =
      ctx.amount != nil or
        fail_step(
          ctx,
          "amount #{inspect(raw_amount)} is not a positive decimal",
          "pass an amount like 10.00 or 250.00"
        )

    # A missing key or id, or the same key twice, stops it before any request.
    if keys?(ctx), do: run_checks(ctx) and amount_ok, else: false
  end

  defp run_checks(ctx) do
    entity_ok = creator_reaches_entity(ctx)
    {authorizer, authorizer_ok} = enrolled_authorizer(ctx)
    currency_ok = authorizer == nil or currency_matches(ctx, authorizer)

    # An expired secret already failed the authorizer line, with its fix.
    fresh_ok =
      authorizer == nil or authorizer["suspension_reason"] == "secret_expired" or
        secret_fresh(ctx, authorizer)

    secret_ok = secret_set(ctx)
    endpoint_ok = authorizer == nil or endpoint_enabled(ctx, authorizer)
    limits_ok = authorizer == nil or ctx.amount == nil or amount_within_limits(ctx, authorizer)
    payee_ok = payee_trusted(ctx)

    Enum.all?([
      entity_ok,
      authorizer_ok,
      currency_ok,
      fresh_ok,
      secret_ok,
      endpoint_ok,
      limits_ok,
      payee_ok
    ])
  end

  # Plain decimals only: mix create_transfer sends the string as is, so
  # "1/2" or "1e2" would not mean the same to the API.
  defp parse_amount(amount) when is_binary(amount) do
    if Regex.match?(~r/\A\d+(?:\.\d+)?\z/, amount) do
      decimal = Decimal.new(amount)
      if Decimal.gt?(decimal, 0), do: decimal
    end
  end

  defp parse_amount(_amount), do: nil

  # 1. Both keys (and the ids the other steps read) are set, the keys different.
  defp keys?(ctx) do
    missing =
      Enum.filter(
        ~w(MANZA_CREATOR_API_KEY MANZA_AUTHORIZER_API_KEY MANZA_ACCOUNT_ID MANZA_BENEFICIARY_ID),
        &(value(ctx, &1) == "")
      )

    cond do
      missing != [] ->
        fail_step(ctx, "#{Enum.join(missing, ", ")} not set", "set them in .env")

      value(ctx, "MANZA_CREATOR_API_KEY") == value(ctx, "MANZA_AUTHORIZER_API_KEY") ->
        fail_step(
          ctx,
          "key A and key B are the same key",
          "use two different keys: the API refuses to let the key that created a transfer authorize it"
        )

      true ->
        pass(ctx, "key A and key B are set and different")
    end
  end

  # 2. Key A reaches the API.
  defp creator_reaches_entity(ctx) do
    case Manza.Entity.get(creator(ctx)) do
      {:ok, response} ->
        pass(ctx, "key A reaches the API (entity #{inspect(response.body["name"])})")

      {:error, error} ->
        fail_step(
          ctx,
          "key A cannot read the entity: #{describe(error)}",
          key_fix(error, "MANZA_CREATOR_API_KEY", "entity:read")
        )
    end
  end

  # 3. Key B reads the authorizer, which must be active.
  defp enrolled_authorizer(ctx) do
    case Manza.TransferAuthorizer.get(authorizer_client(ctx)) do
      {:ok, %{body: %{"status" => "active"} = authorizer}} ->
        {authorizer, pass(ctx, "transfer authorizer is active")}

      {:ok, %{body: authorizer}} ->
        reason = authorizer["suspension_reason"]

        fix =
          Map.get(
            @suspension_fixes,
            reason,
            "see suspension_reason in the transfer authorization docs"
          )

        {authorizer,
         fail_step(ctx, "transfer authorizer is #{authorizer["status"]} (#{reason})", fix)}

      {:error, %Manza.Error{kind: :not_found}} ->
        {nil,
         fail_step(
           ctx,
           "no transfer authorizer is enrolled",
           "enrol your webhook endpoint in Settings → Developer → Transfer approval"
         )}

      {:error, error} ->
        {nil,
         fail_step(
           ctx,
           "key B cannot read the transfer authorizer: #{describe(error)}",
           key_fix(error, "MANZA_AUTHORIZER_API_KEY", "transfers:authorize")
         )}
    end
  end

  defp currency_matches(ctx, authorizer) do
    enrolled = authorizer["currency_code"]

    case Manza.Accounts.get(creator(ctx), value(ctx, "MANZA_ACCOUNT_ID")) do
      {:ok, %{body: %{"currency_code" => ^enrolled}}} ->
        pass(ctx, "account currency #{enrolled} is the enrolled currency")

      {:ok, %{body: %{"currency_code" => currency}}} ->
        fail_step(
          ctx,
          "account currency #{currency} is not the enrolled currency #{enrolled}",
          "pay from a #{enrolled} account (MANZA_ACCOUNT_ID), or enrol #{currency}"
        )

      {:error, error} ->
        fail_step(
          ctx,
          "key A cannot read account #{inspect(value(ctx, "MANZA_ACCOUNT_ID"))}: #{describe(error)}",
          key_fix(error, "MANZA_CREATOR_API_KEY", "accounts:read", "MANZA_ACCOUNT_ID")
        )
    end
  end

  defp secret_fresh(ctx, authorizer) do
    expires = authorizer["secret_expires_at"]
    {:ok, expires_at, _offset} = DateTime.from_iso8601(expires)
    days = Integer.floor_div(DateTime.diff(expires_at, ctx.now), 86_400)

    if days >= @secret_min_days do
      pass(ctx, "signing secret expires in #{days} days")
    else
      state = if days < 0, do: "expired", else: "expires in #{days} days"

      fail_step(
        ctx,
        "signing secret #{state} (#{expires})",
        "an approver should rotate the secret in Settings → Developer → Transfer approval; " <>
          "set the new one as MANZA_AUTHORIZER_SECRET"
      )
    end
  end

  # 4. The signing secret is set.
  defp secret_set(ctx) do
    if value(ctx, "MANZA_AUTHORIZER_SECRET") == "" do
      fail_step(
        ctx,
        "MANZA_AUTHORIZER_SECRET is not set",
        "set it to the signing secret shown at enrolment or at the last rotation"
      )
    else
      pass(ctx, "MANZA_AUTHORIZER_SECRET is set")
    end
  end

  # 5. The enrolled webhook endpoint is enabled, on a URL that lasts.
  defp endpoint_enabled(ctx, authorizer) do
    case Manza.WebhookEndpoints.get(creator(ctx), authorizer["webhook_endpoint_id"]) do
      {:ok, %{body: endpoint}} ->
        ok =
          if endpoint["status"] == "active" do
            pass(ctx, "webhook endpoint #{endpoint["url"]} is enabled")
          else
            fail_step(
              ctx,
              "webhook endpoint #{endpoint["url"]} is #{endpoint["status"]}",
              "enable it (Manza.WebhookEndpoints.enable(client, #{inspect(endpoint["id"])})); " <>
                "if the authorizer stays suspended, an approver resumes it in the app"
            )
          end

        host = URI.parse(to_string(endpoint["url"])).host || ""

        unstable =
          Enum.find(@unstable_tunnel_hosts, &(host == &1 or String.ends_with?(host, "." <> &1)))

        if unstable do
          warn_step(
            ctx,
            "webhook endpoint is on #{unstable}, whose URL changes when the tunnel restarts",
            "use a reserved domain or a named tunnel, then enrol an endpoint at that URL"
          )
        end

        ok

      {:error, %Manza.Error{kind: :not_found}} ->
        fail_step(
          ctx,
          "the enrolled webhook endpoint #{authorizer["webhook_endpoint_id"]} was deleted",
          "create an endpoint at a stable URL and enrol it in Settings → Developer → Transfer approval"
        )

      {:error, error} ->
        fail_step(
          ctx,
          "key A cannot read the enrolled webhook endpoint: #{describe(error)}",
          key_fix(error, "MANZA_CREATOR_API_KEY", "webhook_endpoints:read")
        )
    end
  end

  # 6a. The test amount fits both limits.
  defp amount_within_limits(ctx, authorizer) do
    per_transfer = Decimal.new(authorizer["per_transfer_limit"])

    room =
      Decimal.sub(
        Decimal.new(authorizer["daily_limit"]),
        Decimal.new(authorizer["daily_authorized_total"])
      )

    amount = format_amount(ctx.amount)

    cond do
      Decimal.gt?(ctx.amount, per_transfer) ->
        fail_step(
          ctx,
          "#{amount} is over the limit per transfer (#{format_amount(per_transfer)})",
          "send at most #{format_amount(per_transfer)}, or have an approver raise the limit"
        )

      Decimal.gt?(ctx.amount, room) ->
        fail_step(
          ctx,
          "#{amount} does not fit the last 24 hours' room (#{format_amount(room)} left)",
          "wait for older authorizations to leave the 24-hour window, or have an approver raise the limit"
        )

      true ->
        pass(ctx, "#{amount} is within the limit per transfer and the 24-hour room")
    end
  end

  # 6b. The payee is trusted, or may be trusted on authorize.
  defp payee_trusted(ctx) do
    case Manza.Beneficiaries.get(creator(ctx), value(ctx, "MANZA_BENEFICIARY_ID")) do
      {:ok, %{body: beneficiary}} ->
        account = Enum.find(beneficiary["external_accounts"] || [], & &1["default"])

        cond do
          account == nil ->
            fail_step(
              ctx,
              "beneficiary has no default bank account",
              "add one, or set a beneficiary that has one"
            )

          account["trusted"] ->
            pass(ctx, "payee #{account["id"]} is trusted")

          true ->
            warn_step(
              ctx,
              "payee #{account["id"]} is not trusted yet",
              "it qualifies only with \"Approve transfers to new payees\" on in Settings → Developer → " <>
                "Transfer approval (not visible through the API), key A bound to an IP allowlist, and the " <>
                "amount within the limit per transfer to a new payee, and only if its bank details were " <>
                "never trusted (revoked or edited details always go to your approvers); otherwise have an " <>
                "approver trust it"
            )
        end

      {:error, error} ->
        fail_step(
          ctx,
          "key A cannot read beneficiary #{inspect(value(ctx, "MANZA_BENEFICIARY_ID"))}: #{describe(error)}",
          key_fix(error, "MANZA_CREATOR_API_KEY", "beneficiaries:read", "MANZA_BENEFICIARY_ID")
        )
    end
  end

  defp creator(ctx), do: client(ctx, "MANZA_CREATOR_API_KEY")
  defp authorizer_client(ctx), do: client(ctx, "MANZA_AUTHORIZER_API_KEY")

  # Without MANZA_BASE_URL, Manza.new/1 uses its own default.
  defp client(ctx, key_var) do
    base_url = value(ctx, "MANZA_BASE_URL")
    opts = [api_key: value(ctx, key_var)]
    Manza.new!(if base_url == "", do: opts, else: [{:base_url, base_url} | opts])
  end

  defp value(ctx, name), do: to_string(Map.get(ctx.env, name, ""))

  defp describe(%Manza.Error{} = error),
    do: "#{error.kind} #{error.type || error.status}: #{error.message}"

  defp describe(error), do: Exception.message(error)

  defp key_fix(error, key_var, scope, id_var \\ nil)

  defp key_fix(%Manza.Error{kind: :authentication}, key_var, _scope, _id_var),
    do: "check #{key_var}: the key is wrong or revoked"

  defp key_fix(%Manza.Error{kind: :forbidden}, _key_var, scope, _id_var),
    do: "give the key the #{scope} scope, or add this machine's address to its IP allowlist"

  defp key_fix(%Manza.Error{kind: :not_found}, _key_var, _scope, id_var),
    do: "check #{id_var || "MANZA_BASE_URL"}"

  defp key_fix(_error, _key_var, _scope, _id_var),
    do: "check MANZA_BASE_URL and the network, then rerun"

  # Two places, or more when the amount has them: never hide what was compared.
  defp format_amount(decimal) do
    rounded = Decimal.round(decimal, 2)
    shown = if Decimal.equal?(rounded, decimal), do: rounded, else: decimal
    Decimal.to_string(shown, :normal)
  end

  defp pass(ctx, message) do
    IO.puts(ctx.out, "✓ #{message}")
    true
  end

  defp fail_step(ctx, message, fix) do
    IO.puts(ctx.out, "✗ #{message}: #{fix}")
    false
  end

  defp warn_step(ctx, message, note) do
    IO.puts(ctx.out, "! #{message}: #{note}")
    true
  end
end
