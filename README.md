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
`kind` (`:authentication`, `:forbidden`, `:not_found`, `:validation`,
`:rate_limit`, `:server`, `:api`), the API's `type`/`message`/`param`, and
the `request_id`. Rate limits carry `retry_after`. Transport failures are
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
