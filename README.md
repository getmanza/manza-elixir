# zazu-elixir

Elixir SDK for the [Zazu](https://zazu.ma) API.

```elixir
# mix.exs
def deps do
  [
    {:zazu, github: "getzazu/zazu-elixir"}
  ]
end
```

```elixir
{:ok, client} = Zazu.new(api_key: System.fetch_env!("ZAZU_API_KEY"))

{:ok, entity} = Zazu.Entity.get(client)

{:ok, page} = Zazu.Accounts.list(client)

for account <- page.data do
  IO.puts("#{account["id"]} #{account["name"]}")
end

# Initiate a transfer — it lands in your workspace's in-app approval
# queue; the API never executes a transfer itself.
{:ok, draft} =
  Zazu.TransferDrafts.create(client, %{
    "account_id" => account_id,
    "beneficiary_id" => beneficiary_id,
    "amount" => "150.00",
    "payment_reference" => "INV-000042"
  })
```

## Hosts

The default base URL is production Morocco, `https://ma.manza.finance`. For
South Africa pass `base_url: "https://za.manza.finance"` (or set
`ZAZU_BASE_URL`). The replay cassettes are recorded against
`https://ma.manza.dev`.

## Resources

| Module | Calls |
|---|---|
| `Zazu.Entity` | `get/1` |
| `Zazu.Accounts` | `list/2`, `get/2`, `list_transactions/3`, `get_transaction/3` |
| `Zazu.Customers` | `list/2`, `get/2`, `create/2`, `update/3`, `delete/2` |
| `Zazu.Invoices` | list, get, create, update, send, mark as paid, cancel, credit note, delete, payment link |
| `Zazu.PaymentLinks` | `list/2`, `get/2`, `create/2`, `cancel/2` |
| `Zazu.CheckoutSessions` | `create/2`, `get/2` |
| `Zazu.WebhookEndpoints` | CRUD, enable/disable, test, regenerate secret |
| `Zazu.Beneficiaries` | `list/2`, `get/2`, `create/2`, `list_external_accounts/3`, `get_external_account/3`, `create_external_account/3` |
| `Zazu.PayeeTrustRequests` | `create/2` (`external_account_ids`), `get/2` |
| `Zazu.TransferDrafts` | `create/2`, `get/2`, `authorize/4`, `decline/4` |

## Machine-authorized transfers

A transfer draft inside your machine-authorization envelope (trusted payee,
within limits) is sent to your enrolled transfer authorizer as a
`payment.authorization_requested` webhook carrying the `authorization_id` and
a one-time `nonce`. Answer it with a *different* API key than the one that
created the draft (scope `transfers:authorize`). `Zazu.TransferAuthorization`
holds the pure signing functions:

```elixir
payee = Zazu.TransferAuthorization.payee_for(external_account_id: draft["external_account_id"])

# Build the input from your own record of the transfer, not the webhook's
# `signature_input`. `amount` must be the API's decimal string, e.g. "2500.0".
input =
  Zazu.TransferAuthorization.signature_input(
    draft["id"], nonce, draft["amount"], draft["currency_code"],
    draft["account_id"], payee, draft["client_reference"]
  )

signature = Zazu.TransferAuthorization.sign(signing_secret, input)

{:ok, _} = Zazu.TransferDrafts.authorize(authorizer_client, draft["id"], authorization_id, signature)
# or: Zazu.TransferDrafts.decline(authorizer_client, draft["id"], authorization_id, "reason")
```

A blank signature returns `{:error, %Zazu.ConfigurationError{}}` without
calling the API (the server counts a missing signature as a failed attempt).
`create/2` accepts an optional `client_reference` (unique per entity, at most
128 characters); a duplicate returns `{:error, %Zazu.Error{kind: :conflict}}`
whose `payment_id` names the existing draft.

## Response shape

Response bodies are returned as-is from the API — `snake_case` string-keyed
maps in `response.body`, no struct mapping. The same shape ships across every
Zazu SDK (Ruby, TypeScript, Python, Go, ...) so the cassette contract is
one-to-one.

List endpoints return a `Zazu.Page` (`data`, `has_more`, `next_cursor`);
`Zazu.Page.next/1` fetches the following page (`nil` on the last one). Page
size is capped at 100 records.

## Errors

Non-2xx responses come back as `{:error, %Zazu.Error{}}` with `status`,
`kind` (`:authentication`, `:forbidden`, `:not_found`, `:validation` for 400
and 422, `:conflict` for 409, `:rate_limit`, `:server`, `:api`), the API's
`type`/`message`/`param`, and the `request_id`. Rate limits carry
`retry_after`; conflicts carry `payment_id`. Transport failures are
`{:error, %Zazu.ConnectionError{}}`; invalid config is
`{:error, %Zazu.ConfigurationError{}}`.

## Tests

Tests replay the canonical cassettes recorded by
[zazu-ruby](https://github.com/getzazu/zazu-ruby). The cassettes are
downloaded from the Ruby SDK's release tarball and served from a Bypass
server. Same interactions, same assertions, every language.

```bash
scripts/fetch-cassettes.sh
mix test
```

## The SDK family

- [zazu-ruby](https://github.com/getzazu/zazu-ruby) — reference implementation (records the cassettes)
- [zazu-ts](https://github.com/getzazu/zazu-ts)
- [zazu-python](https://github.com/getzazu/zazu-python)
- [zazu-go](https://github.com/getzazu/zazu-go)
- [cli](https://github.com/getzazu/cli)
