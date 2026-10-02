# zazu-elixir

Elixir SDK for the Zazu API (Hex package `zazu`). This SDK **replays zazu-ruby's cassettes**: zazu-ruby is the reference implementation that records them against the API and ships them as a release tarball. Every request shape and response here must match what those cassettes recorded.

## Stack

| Concern | Tool | Notes |
|---|---|---|
| Language | Elixir 1.18 on OTP 27 (CI) | `mix.exs` requires `~> 1.15`. CI (`ci.yml`, `release.yml`) runs a single version, no matrix |
| HTTP | Req ~> 0.5 | `lib/zazu/client.ex`: `retry: false`, `decode_body: false` (JSON is decoded by the SDK with Jason) |
| Test runner | ExUnit | `test/zazu/*_test.exs` |
| Cassette replay (tests) | Bypass + `yaml_elixir` | `test/support/cassette_replay.ex`. Reads zazu-ruby's release tarball from `testdata/cassettes/` (gitignored) |
| Format | `mix format` | `.formatter.exs`. CI runs `mix format --check-formatted` |
| Lint / typecheck | none | No Credo, no Dialyzer in this repo |
| Registry | Hex, package `zazu` | https://hex.pm/packages/zazu |
| Release | `bin/release` | zazu SDK release kit (byte-identical across SDK repos; repo-specific bits in `scripts/version` + `scripts/release-check`). `release.yml` publishes with `mix hex.publish` |

## Public API surface

```elixir
{:ok, client} = Zazu.new(api_key: "sk_live_...")   # or ZAZU_API_KEY; Zazu.new!/1 raises

{:ok, entity} = Zazu.Entity.get(client)
{:ok, page} = Zazu.Accounts.list(client, currency_code: "MAD")
{:ok, page} = Zazu.Customers.list(client, q: "Acme")
Zazu.Page.next(page)                               # {:ok, page} | {:error, _} | nil on the last page

# Transfer drafts: authorize/decline with a key other than the creator's
{:ok, draft} = Zazu.TransferDrafts.create(client, %{"account_id" => id, "amount" => "150.00", "beneficiary_id" => bid, "client_reference" => "INV-1"})
{:error, %Zazu.Error{kind: :conflict, payment_id: existing}} = Zazu.TransferDrafts.create(client, same_attrs)  # 409

payee = Zazu.TransferAuthorization.payee_for(external_account_id: draft.body["external_account_id"])
input = Zazu.TransferAuthorization.signature_input(pid, nonce, amount, currency, account_id, payee, client_reference)
signature = Zazu.TransferAuthorization.sign(signing_secret, input)
Zazu.TransferDrafts.authorize(authorizer_client, pid, authorization_id, signature)
Zazu.TransferDrafts.decline(authorizer_client, pid, authorization_id, "reason")

# Beneficiaries (create + external accounts) and payee trust requests
Zazu.Beneficiaries.create(client, attrs)
Zazu.Beneficiaries.list_external_accounts(client, beneficiary_id)
Zazu.Beneficiaries.create_external_account(client, beneficiary_id, attrs)
Zazu.PayeeTrustRequests.create(client, [external_account_id])
```

- Resource modules: `Entity`, `Accounts`, `Customers`, `Invoices`, `PaymentLinks`, `CheckoutSessions`, `WebhookEndpoints`, `Beneficiaries`, `PayeeTrustRequests`, `TransferDrafts`, plus the pure `TransferAuthorization` signer (all under `Zazu.`, in `lib/zazu/`)
- Tuple returns: `{:ok, %Zazu.Response{}}` (body as `response.body`), list calls return `{:ok, %Zazu.Page{}}`; errors are `{:error, exception}`
- `Zazu.Page`: cursor-based, hard cap of 100/page (`Zazu.Page.max_per_page/0`), `Zazu.Page.next/1`
- **Error model**: one `Zazu.Error` struct with a `kind`, not a class hierarchy. Discriminate on `error.kind`, never on `status` or `message`:
  - kinds: `:authentication` (401), `:forbidden` (403), `:not_found` (404), `:validation` (400, 422), `:conflict` (409, carries `payment_id`), `:rate_limit` (429, carries `retry_after`), `:server` (5xx), `:api` (any other non-2xx)
  - `Zazu.ConfigurationError` is the argument error: bad client config, `limit` over 100, a blank authorization signature (all refused before any request)
  - `Zazu.ConnectionError` wraps transport failures
  - `Zazu.TransferAuthorization` is the exception: it is pure and raises `ArgumentError` on programming mistakes (non-string amount, wrong payee options)
- Snake-case wire format: request and response bodies are string-keyed maps returned as-is. **No auto-camelCasing, no struct mapping.**

## How to work in this codebase

1. **Tests come first.** Every change to `lib/` ships with a test. Cassette-replay tests are the contract: they enforce the same wire format across Ruby, TS, Elixir and the other SDKs.
2. **Use the SDK's primitives.** `Zazu.Client` (`get/post/patch/delete/list_page`), `Zazu.Page`, `Zazu.Error` kinds, `Zazu.Client.encode_path/1` for URL construction, `Zazu.Client.query_filters/2`. Don't hand-roll Req calls, string-interpolate URLs, or match on `error.message`.
3. **Snake-case stays.** Response keys are wire format. We don't atomize or camelCase them.
4. **Format must be clean.** CI gates on `mix format --check-formatted`. There is no other linter.

## Critical rules

- **Never call a live Zazu/Manza API** from tests, scripts or Claude sessions. Tests replay zazu-ruby's cassettes only. Live staging calls create real transfers and approval requests for the team. Only zazu-ruby records cassettes.
- **`mix format --check-formatted` and `mix test` before every commit.** `scripts/release-check` and CI run the same.
- **Cassette contract.**
  - Cassettes come from the newest zazu-ruby `v*` release (`cassettes-vX.Y.Z.tar.gz`) via `scripts/fetch-cassettes.sh`, extracted to `testdata/cassettes/` (gitignored). They are recorded against `https://ma.manza.dev`.
  - Load **one cassette per test**: `transfer_drafts/authorize` vs `authorize_same_key`, and `create` vs `create_duplicate`, share method + URI, and the first matching interaction wins.
  - The three authorize cassettes (`authorize`, `authorize_same_key`, `authorize_bad_signature`) are loaded with `ignore_signature: true`: they match the body minus `signature` (the recorded one is scrubbed to `<SIGNATURE>`).
  - Every other body is matched semantically: method + path + query (host ignored) + JSON bodies decoded and compared as terms (key order and whitespace never matter); non-JSON bodies compare byte-for-byte.
  - Cassette responses carry no `Content-Length`.
  - `test/support/fixture_ids.ex` must stay identical to zazu-ruby's `spec/support/fixture_ids.rb` (same env var names, same placeholders). Add new ids to both.
- **Hosts.** Default `https://ma.manza.finance`, South Africa `https://za.manza.finance`, staging and cassettes `https://ma.manza.dev`. Env var names stay `ZAZU_*` (`ZAZU_API_KEY`, `ZAZU_BASE_URL`, `ZAZU_API_VERSION`) and the namespace stays `Zazu` until the rename plan (zazu-ruby `docs/plans/2026-10-manza-rename.md`).
- **The error model is shared across the SDK family.** Adding an error kind (or class, elsewhere) means coordinating zazu-ruby and zazu-ts at minimum. The 10th is the conflict (409), here `kind: :conflict`.
- **Signer.** `Zazu.TransferAuthorization` must keep reproducing the two fixed vectors from zazu-ruby's `spec/zazu/transfer_authorization_spec.rb` (see `test/zazu/transfer_authorization_test.exs`). Never sign the server's `signature_input` blindly: build it from your own record of the transfer.
- **Release.** `bin/release` is byte-identical across the SDK repos and never edited in place. Repo-specific logic lives in `scripts/version` (reads/writes `@version` in `mix.exs`) and `scripts/release-check` (fetch cassettes, deps, format, test). `release.yml` gates on tag == `mix.exs` version.
- **Hex has no OIDC trusted publishing.** `release.yml` publishes with the `HEX_API_KEY` secret on the `hex` GitHub environment (add required reviewers there for a human gate). Generate the key with `mix hex.user key generate --permission api:write`. The `hex` environment and the secret must live on `getmanza/zazu-elixir`, and the key's Hex account must own the package `zazu`.
- **The repo moved from `getzazu` to `getmanza`.** Remotes and URLs must say `getmanza`. Known stragglers (left alone in this repo's docs-only change): `REPO` in `scripts/fetch-cassettes.sh`, `@source_url` in `mix.exs`, and links in `README.md`.
- **Never escape backticks in PR bodies.** With `<<'EOF'` (single-quoted heredoc) the shell passes everything through verbatim. See "PR descriptions" below.

## PR descriptions

Write PR description bodies in plain Markdown. **Do not escape backticks** with `` \` `` — GitHub renders `` \` `` literally as a backslash followed by a backtick, producing output like `` \`Zazu.Page\` `` instead of the monospace `Zazu.Page` the reader expects.

The usual cause is writing the description inside a bash heredoc (`gh pr create --body "$(cat <<'EOF' ... EOF)"`) and then reflexively escaping every backtick because of shell-quoting muscle memory. With `<<'EOF'` (single-quoted delimiter) the shell does NOT interpret anything inside the heredoc — backticks, dollars, and backslashes all pass through verbatim. So write them exactly as you want them rendered:

```bash
# Good — renders as `Zazu.Page` in monospace
gh pr create --body "$(cat <<'EOF'
Uses the `Zazu.Page` helper.
EOF
)"

# Bad — renders as \`Zazu.Page\` literally in the PR body
gh pr create --body "$(cat <<'EOF'
Uses the \`Zazu.Page\` helper.
EOF
)"
```

Same rule for code blocks — write triple-backticks unescaped. The single-quoted heredoc delimiter is doing all the shell-escaping work. If you find yourself typing `` \` `` inside a PR body, stop and remove the backslash.

## Striving for excellence

These are the Karpathy guidelines we apply on every change. They reduce common LLM coding mistakes.

### 1. Think before coding

Don't assume. Don't hide confusion. Surface tradeoffs.

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity first

Minimum code that solves the problem. Nothing speculative.

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Senior engineer test: would they call this overcomplicated?

### 3. Surgical changes

Touch only what you must. Clean up only your own mess.

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.
- Remove imports/variables/functions that *your* changes orphaned. Don't remove pre-existing dead code unless asked.

### 4. Goal-driven execution

Define success criteria. Loop until verified.

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan with verification at each step.

## Development workflow

Commands are the ones in `.github/workflows/ci.yml` (CI sets `MIX_ENV=test`):

```bash
# One-time setup
export MIX_ENV=test
scripts/fetch-cassettes.sh          # newest zazu-ruby v* tarball -> testdata/cassettes/ (git ls-remote + curl, no API calls)
scripts/fetch-cassettes.sh v0.3.0   # or pin a tag
mix deps.get

# Daily loop
mix test test/zazu/resources_test.exs   # while iterating
mix format                              # auto-format
mix format --check-formatted            # what CI gates on
mix test                                # full suite

# Release (after PR merge, from a clean, up-to-date main)
bin/release list        # last releases + what patch/minor/major would give
bin/release --dry-run   # version + changes since the last tag, publishes nothing
bin/release minor       # or patch (default), major, an explicit 0.4.0; --force re-creates
# -> bumps @version in mix.exs, runs scripts/release-check, pushes main, publishes the GH release
# -> release.yml workflow tests, checks tag == mix.exs version, runs mix hex.publish, creates the release
```

## Models

Sessions run on `opus` (Opus 5.5) with `fable` (Fable 5.1) as the advisor (`.claude/settings.json`). Fable is spent where judgment matters most: ask for a plan on Fable (a `fable` subagent or `/model fable`); plan mode itself runs on Opus and asks the advisor. The advisor is consulted at decision points (before choosing an approach, a schema or public API, a migration, a dependency, anything irreversible, and when a failure repeats). The `fable-validator` agent checks every finished implementation before its pull request opens (`/lfg`, Phase 6.5). Agents pin their tier by alias, never by full model ID: `fable` for plans and validation; `opus` for orchestration, security, full PR review, payments and production debugging; `sonnet` for the implementation specialists and TDD; `haiku` for mechanical scans. Every spawned agent names its `model:`; a subagent whose definition names no model runs on `sonnet` (`CLAUDE_CODE_SUBAGENT_MODEL`), never on the session's model.

## Slash commands

These live in `.claude/commands/` and are available in any Claude Code session:

| Command | When |
|---|---|
| `/lfg <issue or feature>` | Full autonomous workflow with TDD + verification |
| `/github-review-pr <PR#>` | Full PR review pass: failures first, then comments |
| `/github-review-failures <PR#>` | Just fix CI failures on a PR |
| `/github-review-comments <PR#>` | Just respond to reviewer comments on a PR |
| `/coderabbit-review <PR#>` | Specifically address CodeRabbit findings (verify, fix valid, push back on stale/wrong) |

## Cross-SDK contract

`zazu-ruby` is the reference implementation:

- Records cassettes against `https://ma.manza.dev`
- Ships them as a release tarball (`cassettes-vX.Y.Z.tar.gz`) on each version
- All other SDKs (`zazu-ts`, `zazu-elixir`, future `zazu-python`, `zazu-go`, `zazu-php`, `zazu-crystal`, `zazu-rust`) replay these cassettes in their own test harness

If the contract breaks (e.g., new request shape, new error kind), it's a coordinated change across at least two repos: zazu-ruby and zazu-ts.

## Repository links

- Ruby SDK (reference): https://github.com/getmanza/zazu-ruby
- TypeScript SDK: https://github.com/getmanza/zazu-ts
- This repo: https://github.com/getmanza/zazu-elixir
- Hex package: https://hex.pm/packages/zazu
- CLI consumer: https://github.com/getmanza/cli
