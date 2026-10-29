# manza-elixir

Elixir SDK for the [Manza](https://get-manza.com) API.

```elixir
# mix.exs
def deps do
  [
    {:manza, github: "getmanza/manza-elixir"}
  ]
end
```

```elixir
{:ok, client} = Manza.new(api_key: System.fetch_env!("MANZA_API_KEY"))

{:ok, entity} = Manza.Entity.get(client)

{:ok, page} = Manza.Accounts.list(client)

for account <- page.data do
  IO.puts("#{account["id"]} #{account["name"]}")
end

# Initiate a transfer. Creating it never executes it: it goes to your
# enrolled transfer authorizer or to your workspace's in-app approvers.
{:ok, draft} =
  Manza.Payments.create(client, %{
    "account_id" => account_id,
    "beneficiary_id" => beneficiary_id,
    "amount" => "150.00",
    "payment_reference" => "INV-000042"
  })
```

## Hosts

The default base URL is production Morocco, `https://ma.manza.finance`. For
South Africa pass `base_url: "https://za.manza.finance"` (or set
`MANZA_BASE_URL`). The replay cassettes are recorded against
`https://ma.manza.dev`.

## Environment variables

`MANZA_API_KEY`, `MANZA_BASE_URL` and `MANZA_API_VERSION` are read when the
matching option is not passed. The old `ZAZU_API_KEY`, `ZAZU_BASE_URL` and
`ZAZU_API_VERSION` names still work for all of 1.x as a fallback and log a
one-time deprecation warning per variable.

## Resources

| Module | Calls |
|---|---|
| `Manza.Entity` | `get/1` |
| `Manza.Accounts` | `list/2`, `get/2`, `list_transactions/3`, `get_transaction/3` |
| `Manza.Customers` | `list/2`, `get/2`, `create/2`, `update/3`, `delete/2` |
| `Manza.Invoices` | list, get, create, update, send, mark as paid, cancel, credit note, delete, payment link |
| `Manza.PaymentLinks` | `list/2`, `get/2`, `create/2`, `cancel/2` |
| `Manza.CheckoutSessions` | `create/2`, `get/2` |
| `Manza.WebhookEndpoints` | CRUD, enable/disable, test, regenerate secret |
| `Manza.Beneficiaries` | `list/2`, `get/2`, `create/2`, `list_external_accounts/3`, `get_external_account/3` (`"trusted"` once a trusted payee), `create_external_account/3` |
| `Manza.PayeeTrustRequests` | `create/2` (`external_account_ids`), `get/2` |
| `Manza.Payments` | `create/2`, `get/2` (`"authorization"`: `"status"`, `"refusal_reason"`), `authorize/4`, `decline/4` |
| `Manza.TransferAuthorizer` | `get/1`: `status`, `suspension_reason`, limits, `daily_authorized_total`; `:not_found` when none is enrolled |
| `Manza.Webhook` | `construct_event/4`, `construct_event!/4`, `verify?/5`, `sign/3` (pure, no HTTP) |

`Manza.TransferDrafts` is a deprecated alias of `Manza.Payments`, kept for all
of 1.x: same functions, and it calls `/api/payments` too.

## Machine-authorized transfers

A draft inside your entity's authorization envelope (trusted payee, or a new
one when you allow it, within limits) is sent to your enrolled authorizer
endpoint as a `payment.authorization_requested` webhook carrying an
`authorization.id` and a one-time `nonce`. Your system checks it against its
own ledger, signs it and authorizes it with a **different API key** from the
one that created it. [`examples/transfer_authorizer/`](examples/transfer_authorizer/)
runs the whole flow. The [transfer authorization docs](https://ma.manza.finance/docs/api/transfer-authorization)
have the full guide.

### Setup, step by step

1. **Feature flags.** Ask support to enable API transfers and transfer authorization (`release_api_webhook_authorization`) on your workspace.
2. **Two API keys.** Key A creates drafts (`transfers:write`; `beneficiaries:request_trust` for step 6; `entity:read`, `accounts:read`, `webhook_endpoints:read` and `beneficiaries:read` for the preflight in step 7). Key B answers the challenges (`transfers:authorize`). The creating key is always refused with 403 `same_key_forbidden`, so keep key B and the signing secret on the system that holds your ledger. Bind key B to an IP allowlist: authorizing from a key without one is refused with 403 `unrestricted_api_key`. Bind key A to one too if you allow new payees (step 6): a draft to a new payee from a key without an allowlist goes to your approvers (`unrestricted_api_key`).
3. **A stable public URL.** Your authorizer needs an HTTPS URL that never changes: an enrolled endpoint's URL is locked. Use a reserved ngrok domain (`ngrok http --url=your-name.ngrok.app 4599`) or a named Cloudflare tunnel. Never a free ngrok URL: it changes on every restart.
4. **Create the webhook endpoint** at that URL:

   ```elixir
   Manza.WebhookEndpoints.create(client, %{"url" => "https://your-name.ngrok.app/", "events" => ["transfer.executed"]})
   ```

5. **Enrol it in the app**: Settings → Developer → Transfer approval. Pick the endpoint, the currency and both limits, confirm with your two-factor code, and copy the signing secret: it is shown once.
6. **Allow new payees, or trust each payee.** Turn on *Approve transfers to new payees* at enrolment (or later, same page, with your two-factor code) and set the *Limit per transfer to a new payee*. Your authorizer may then approve a transfer to bank details your workspace never trusted, up to that limit, and its signature trusts them: the webhook's `payment.payee_trusted` is `false` for such a transfer. Bank details whose trust was revoked, or that were edited after trusting, still go to your approvers. Without the option, an approver marks the beneficiary's bank account as trusted from the Beneficiaries list, or you ask them to:

   ```elixir
   Manza.PayeeTrustRequests.create(client, ["01a1..."])
   ```

   `"trusted"` on `Manza.Beneficiaries.get_external_account/3` says which it is. The API does not show whether the option is on.
7. **Run the preflight, then the example** (from `examples/transfer_authorizer/`, after `mix deps.get` and filling in `.env`): `mix preflight` checks what the API shows of steps 1–6 and prints a fix for each that fails. What it cannot see, check by hand: that key B is bound to an IP allowlist, and, for a payee not trusted yet, that *Approve transfers to new payees* is on and key A is bound to an IP allowlist too (it warns, it does not fail). Then `mix authorizer` in one terminal, `mix create_transfer` in another.
8. **Troubleshooting**: a draft that goes to your approvers instead has an `"authorization"` with status `"refused"` and a `"refusal_reason"` (`mix create_transfer` prints it in words); `Manza.TransferAuthorizer.get/1` shows a suspension and its `"suspension_reason"`. An authorize answered 409 `authorization_busy` (a bank-detail edit, trust or trust revocation on the same payee was in flight) is safe to retry. The reasons, and an API error's `type`, are in the [transfer authorization docs](https://ma.manza.finance/docs/api/transfer-authorization).

### Verifying the webhook

Pass the **raw request body**, never re-encoded JSON: read it before any
`Plug.Parsers`. `construct_event/4` reads `X-Manza-Signature` and
`X-Manza-Timestamp` (any case, a map or Plug's `conn.req_headers`, the CGI
`HTTP_X_MANZA_*` form, or the legacy `X-Zazu-*` names), checks the signature
in constant time and the timestamp within 5 minutes, and returns the parsed
event (a string-keyed map):

```elixir
{:ok, body, conn} = Plug.Conn.read_body(conn)

case Manza.Webhook.construct_event(body, conn.req_headers, signing_secret) do
  {:ok, event} -> handle(event)
  {:error, %ArgumentError{message: message}} -> Plug.Conn.send_resp(conn, 401, message)
end
```

`construct_event!/4` returns the event or raises `ArgumentError`;
`Manza.Webhook.verify?(payload, signature, timestamp, secret)` returns a
boolean. All accept `tolerance: nil` to skip the timestamp check. Use it only
to replay a captured delivery in a local tool or test, never on a live
endpoint: without the check, anyone holding a captured delivery can replay it.

### Signing the challenge

Sign the draft from **your own record** of it with the endpoint's signing
secret, not from the webhook's `signature_input` (it is there only to compare
against):

```elixir
payee = Manza.TransferAuthorization.payee_for(external_account_id: draft["external_account_id"])

# `amount` must be the API's decimal string, e.g. "2500.0".
input =
  Manza.TransferAuthorization.signature_input(
    draft["id"], webhook["data"]["authorization"]["nonce"], draft["amount"],
    draft["currency_code"], draft["account_id"], payee, draft["client_reference"]
  )

signature = Manza.TransferAuthorization.sign(signing_secret, input)

authorizer = Manza.new!(api_key: System.fetch_env!("MANZA_AUTHORIZER_API_KEY"))
{:ok, _} = Manza.Payments.authorize(authorizer, draft["id"], webhook["data"]["authorization"]["id"], signature)
# or: Manza.Payments.decline(authorizer, draft["id"], authorization_id, "reason")
```

A wrong signature returns `{:error, %Manza.Error{kind: :validation, type:
"invalid_signature"}}`. Five on one challenge send the draft to your in-app
approvers; five in a row suspend the authorizer. A blank signature returns
`{:error, %Manza.ConfigurationError{}}` without calling the API (the server
counts a missing signature as a failed attempt). `create/2` accepts an
optional `client_reference` (unique per entity, at most 128 characters); a
duplicate returns `{:error, %Manza.Error{kind: :conflict}}` whose
`payment_id` names the existing draft.

## Response shape

Response bodies are returned as-is from the API — `snake_case` string-keyed
maps in `response.body`, no struct mapping. The same shape ships across every
Manza SDK (Ruby, TypeScript, Python, Go, ...) so the cassette contract is
one-to-one.

List endpoints return a `Manza.Page` (`data`, `has_more`, `next_cursor`);
`Manza.Page.next/1` fetches the following page (`nil` on the last one). Page
size is capped at 100 records.

## Errors

Non-2xx responses come back as `{:error, %Manza.Error{}}` with `status`,
`kind` (`:authentication`, `:forbidden`, `:not_found`, `:validation` for 400
and 422, `:conflict` for 409, `:rate_limit`, `:server`, `:api`), the API's
`type`/`message`/`param`, and the `request_id`. Rate limits carry
`retry_after`; conflicts carry `payment_id`. Transport failures are
`{:error, %Manza.ConnectionError{}}`; invalid config is
`{:error, %Manza.ConfigurationError{}}`.

## Tests

Tests replay the canonical cassettes recorded by
[manza-ruby](https://github.com/getmanza/manza-ruby). The cassettes are
downloaded from the Ruby SDK's release tarball and served from a Bypass
server. Same interactions, same assertions, every language.

```bash
scripts/fetch-cassettes.sh
mix test
```

## The SDK family

| SDK | Repository | Install |
|---|---|---|
| Ruby (reference implementation, records the cassettes) | [getmanza/manza-ruby](https://github.com/getmanza/manza-ruby) | `gem "manza"` |
| TypeScript / JavaScript | [getmanza/manza-ts](https://github.com/getmanza/manza-ts) | `npm install @getmanza/sdk` |
| Python | [getmanza/manza-python](https://github.com/getmanza/manza-python) | `pip install manza` |
| Go | [getmanza/manza-go](https://github.com/getmanza/manza-go) | `go get github.com/getmanza/manza-go` |
| PHP | [getmanza/manza-php](https://github.com/getmanza/manza-php) | `composer require manza/manza-php` |
| Rust | [getmanza/manza-rust](https://github.com/getmanza/manza-rust) | `cargo add manza` |
| Crystal | [getmanza/manza-crystal](https://github.com/getmanza/manza-crystal) | shard `manza` (`github: getmanza/manza-crystal`) |
| Elixir | [getmanza/manza-elixir](https://github.com/getmanza/manza-elixir) (this repo) | `{:manza, "~> 1.0"}` |
| CLI | [getmanza/cli](https://github.com/getmanza/cli) | `npm install -g @getzazu/cli` or `brew install getmanza/tap/zazu` |
