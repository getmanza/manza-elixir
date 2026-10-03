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

# Initiate a transfer — it lands in your workspace's in-app approval
# queue; the API never executes a transfer itself.
{:ok, draft} =
  Manza.TransferDrafts.create(client, %{
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
| `Manza.Beneficiaries` | `list/2`, `get/2`, `create/2`, `list_external_accounts/3`, `get_external_account/3`, `create_external_account/3` |
| `Manza.PayeeTrustRequests` | `create/2` (`external_account_ids`), `get/2` |
| `Manza.TransferDrafts` | `create/2`, `get/2`, `authorize/4`, `decline/4` |

## Machine-authorized transfers

A transfer draft inside your machine-authorization envelope (trusted payee,
within limits) is sent to your enrolled transfer authorizer as a
`payment.authorization_requested` webhook carrying the `authorization_id` and
a one-time `nonce`. Answer it with a *different* API key than the one that
created the draft (scope `transfers:authorize`). `Manza.TransferAuthorization`
holds the pure signing functions:

```elixir
payee = Manza.TransferAuthorization.payee_for(external_account_id: draft["external_account_id"])

# Build the input from your own record of the transfer, not the webhook's
# `signature_input`. `amount` must be the API's decimal string, e.g. "2500.0".
input =
  Manza.TransferAuthorization.signature_input(
    draft["id"], nonce, draft["amount"], draft["currency_code"],
    draft["account_id"], payee, draft["client_reference"]
  )

signature = Manza.TransferAuthorization.sign(signing_secret, input)

{:ok, _} = Manza.TransferDrafts.authorize(authorizer_client, draft["id"], authorization_id, signature)
# or: Manza.TransferDrafts.decline(authorizer_client, draft["id"], authorization_id, "reason")
```

A blank signature returns `{:error, %Manza.ConfigurationError{}}` without
calling the API (the server counts a missing signature as a failed attempt).
`create/2` accepts an optional `client_reference` (unique per entity, at most
128 characters); a duplicate returns `{:error, %Manza.Error{kind: :conflict}}`
whose `payment_id` names the existing draft.

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
