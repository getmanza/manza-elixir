defmodule TransferAuthorizer.App do
  @moduledoc """
  A Plug that answers `payment.authorization_requested` webhooks with key B
  (the authorizer key):

    1. Verify the delivery (401 when the signature or timestamp is bad).
    2. Find the draft in your own ledger by its `client_reference`.
    3. Missing or different from what you created: decline with a reason.
    4. A payee not trusted yet (`payee_trusted: false`, only with "Approve
       transfers to new payees" on) is trusted by the authorize, unless
       `allow_new_payees: false` (`ALLOW_NEW_PAYEES=false`) declines it.
    5. Otherwise sign the challenge from the ledger and authorize it.

  It answers 200 first and does steps 2-5 on the executor (a `Task` by
  default): the delivery has a timeout, and a retried webhook is safe
  because authorize replays idempotently.

  Mount it without `Plug.Parsers` in front: the signature covers the raw body.

  ## Options

    * `:client` — a `Manza.Client` built with key B.
    * `:secret` — the enrolled endpoint's signing secret.
    * `:ledger` — the ledger file (`TransferAuthorizer.Ledger`).
    * `:allow_new_payees` — `false` declines payees not trusted yet (default `true`).
    * `:ledger_wait` — seconds to wait for the ledger entry (default 10): the
      webhook can arrive before `mix create_transfer` has written it.
    * `:retry_delay` — base seconds between attempts (default 2).
    * `:executor` — runs the answer (default `&Task.start/1`).
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  @event "payment.authorization_requested"

  # Ledger field → webhook `data.payment` field. All must match.
  @checked_fields [
    {"payment_id", "id"},
    {"amount", "amount"},
    {"currency_code", "currency_code"},
    {"account_id", "account_id"},
    {"payee", "payee"}
  ]

  @attempts 3
  # A challenge expires, so never park the process for long.
  @max_retry_after 30

  @impl true
  def init(opts) do
    %{
      client: Keyword.fetch!(opts, :client),
      secret: Keyword.fetch!(opts, :secret),
      ledger: Keyword.fetch!(opts, :ledger),
      allow_new_payees: Keyword.get(opts, :allow_new_payees, true),
      ledger_wait: Keyword.get(opts, :ledger_wait, 10),
      retry_delay: Keyword.get(opts, :retry_delay, 2),
      executor: Keyword.get(opts, :executor, &Task.start/1)
    }
  end

  @impl true
  def call(conn, config) do
    {:ok, body, conn} = read_body(conn)

    case Manza.Webhook.construct_event(body, conn.req_headers, config.secret) do
      {:ok, %{"event" => @event} = event} ->
        log_verified(event)
        config.executor.(fn -> answer(event["data"], config) end)
        respond(conn, 200)

      {:ok, event} ->
        log_verified(event)
        Logger.info("ignoring #{event["event"]}: this app only answers #{@event}")
        respond(conn, 200)

      {:error, %ArgumentError{message: message}} ->
        Logger.warning("rejected a delivery: #{message}")
        respond(conn, 401)
    end
  end

  defp log_verified(event) do
    Logger.info("received #{event["event"]} (#{event["event_id"]}), signature verified")
  end

  defp answer(data, config) do
    payment = Map.fetch!(data, "payment")
    authorization = Map.fetch!(data, "authorization")
    client_reference = payment["client_reference"]
    entry = wait_for_entry(config, client_reference)

    mismatch =
      if entry,
        do: mismatch_reason(entry, payment),
        else: "client_reference #{inspect(client_reference)} is not in the ledger"

    # Anything but true counts as new, so a webhook without the field is
    # declined under ALLOW_NEW_PAYEES=false rather than trusted blindly.
    new_payee? = payment["payee_trusted"] != true

    cond do
      mismatch ->
        decline(config, payment["id"], authorization["id"], mismatch)

      new_payee? and not config.allow_new_payees ->
        decline(
          config,
          payment["id"],
          authorization["id"],
          "new payee #{payment["payee"]}: ALLOW_NEW_PAYEES=false declines payees not trusted yet"
        )

      true ->
        if new_payee?,
          do: Logger.info("new payee #{payment["payee"]}, will be trusted on authorize")

        Logger.info(
          "ledger match for #{client_reference}: #{payment["amount"]} #{payment["currency_code"]} to #{payment["payee"]}"
        )

        authorize(config, entry, authorization, client_reference, data["signature_input"])
    end
  rescue
    error -> Logger.error("could not answer the challenge: #{Exception.message(error)}")
  end

  defp wait_for_entry(config, client_reference) do
    deadline = System.monotonic_time(:millisecond) + config.ledger_wait * 1000
    poll_ledger(config.ledger, client_reference, deadline)
  end

  defp poll_ledger(ledger, client_reference, deadline) do
    entry = TransferAuthorizer.Ledger.find(ledger, client_reference)

    if entry || System.monotonic_time(:millisecond) >= deadline do
      entry
    else
      Process.sleep(500)
      poll_ledger(ledger, client_reference, deadline)
    end
  end

  defp mismatch_reason(entry, payment) do
    case Enum.find(@checked_fields, fn {ledger, webhook} -> entry[ledger] != payment[webhook] end) do
      nil ->
        nil

      {field, webhook_field} ->
        "#{field} differs from the ledger (ledger #{inspect(entry[field])}, webhook #{inspect(payment[webhook_field])})"
    end
  end

  # Sign from the ledger, never from the webhook: `signature_input` in the
  # webhook is only there to compare against.
  defp authorize(config, entry, authorization, client_reference, webhook_input) do
    input =
      Manza.TransferAuthorization.signature_input(
        entry["payment_id"],
        authorization["nonce"],
        entry["amount"],
        entry["currency_code"],
        entry["account_id"],
        entry["payee"],
        client_reference
      )

    # A signature over a different input is sure to fail, and failed attempts
    # count toward suspending the authorizer. Leave the challenge unanswered
    # instead: it expires and goes to your approvers.
    if input == webhook_input do
      signature = Manza.TransferAuthorization.sign(config.secret, input)
      Logger.info("signed the challenge for payment #{entry["payment_id"]}")

      result =
        with_retries(config, fn ->
          Manza.Payments.authorize(
            config.client,
            entry["payment_id"],
            authorization["id"],
            signature
          )
        end)

      case result do
        {:ok, response} ->
          Logger.info(
            "authorized payment #{entry["payment_id"]} (status #{inspect(response.body["status"])})"
          )

        {:error, error} ->
          log_api_error(error)
      end
    else
      Logger.warning(
        "signature input differs from the webhook's: ledger #{inspect(input)}, webhook #{inspect(webhook_input)}; " <>
          "not answering, the challenge goes to your approvers when it expires"
      )
    end
  end

  defp decline(config, payment_id, authorization_id, reason) do
    case with_retries(config, fn ->
           Manza.Payments.decline(config.client, payment_id, authorization_id, reason)
         end) do
      {:ok, _response} -> Logger.warning("declined payment #{payment_id}: #{reason}")
      {:error, error} -> log_api_error(error)
    end
  end

  # Retries what is worth another try: the API did not answer, asked us to
  # slow down, or was busy with a bank-detail edit, trust or revocation on the
  # same payee (409 `authorization_busy`). Authorize and decline replay
  # idempotently, so a retry is safe.
  defp with_retries(config, fun, attempt \\ 1) do
    case fun.() do
      {:error, error} = result ->
        if attempt < @attempts and transient?(error) do
          delay = retry_delay(error, config, attempt)

          Logger.warning(
            "#{label(error)} (request_id #{inspect(request_id(error))}), retrying in #{delay}s"
          )

          Process.sleep(round(delay * 1000))
          with_retries(config, fun, attempt + 1)
        else
          result
        end

      result ->
        result
    end
  end

  defp transient?(%Manza.ConnectionError{}), do: true
  defp transient?(%Manza.Error{kind: kind}) when kind in [:server, :rate_limit], do: true
  defp transient?(%Manza.Error{kind: :conflict, type: "authorization_busy"}), do: true
  defp transient?(_error), do: false

  defp retry_delay(%Manza.Error{kind: :rate_limit, retry_after: seconds}, _config, _attempt)
       when is_integer(seconds),
       do: min(seconds, @max_retry_after)

  defp retry_delay(_error, config, attempt), do: config.retry_delay * attempt

  defp log_api_error(error) do
    Logger.error(
      "API error #{label(error)}: #{Exception.message(error)} " <>
        "(type #{inspect(Map.get(error, :type))}, request_id #{inspect(request_id(error))})"
    )
  end

  defp label(%Manza.Error{kind: kind}), do: Atom.to_string(kind)
  defp label(%Manza.ConnectionError{}), do: "connection"
  defp label(error), do: inspect(error.__struct__)

  defp request_id(error), do: Map.get(error, :request_id)

  defp respond(conn, 200), do: conn |> put_resp_content_type("text/plain") |> send_resp(200, "ok")

  defp respond(conn, status),
    do: conn |> put_resp_content_type("text/plain") |> send_resp(status, "unauthorized")
end
