# manza-elixir

Project instructions for every agent: Claude Code (`CLAUDE.md` imports this file); other agents read this file directly. Claude's workflow comes from the `flow` plugin (`.claude/settings.json`), which acts on the facts in `## Workflow` below.

Elixir SDK for the Manza API (Hex package `manza`). This SDK **replays manza-ruby's cassettes**: manza-ruby is the reference implementation that records them against the API and ships them as a release tarball. Every request shape and response here must match what those cassettes recorded.

## Stack

| Concern | Tool | Notes |
|---|---|---|
| Language | Elixir 1.18 on OTP 27 (CI) | `mix.exs` requires `~> 1.15`. CI (`ci.yml`, `release.yml`) runs a single version, no matrix |
| HTTP | Req ~> 0.5 | `lib/manza/client.ex`: `retry: false`, `decode_body: false` (JSON is decoded by the SDK with Jason) |
| Test runner | ExUnit | `test/manza/*_test.exs` |
| Cassette replay (tests) | Bypass + `yaml_elixir` | `test/support/cassette_replay.ex`. Reads manza-ruby's release tarball from `testdata/cassettes/` (gitignored) |
| Format | `mix format` | `.formatter.exs`. CI runs `mix format --check-formatted` |
| Lint / typecheck | none | No Credo, no Dialyzer in this repo |
| Registry | Hex, package `manza` | https://hex.pm/packages/manza |
| Release | `bin/release` | manza SDK release kit (byte-identical across SDK repos; repo-specific bits in `scripts/version` + `scripts/release-check`). `release.yml` publishes with `mix hex.publish` |

## Public API surface

```elixir
{:ok, client} = Manza.new(api_key: "sk_live_...")   # or MANZA_API_KEY; Manza.new!/1 raises

{:ok, entity} = Manza.Entity.get(client)
{:ok, page} = Manza.Accounts.list(client, currency_code: "MAD")
{:ok, page} = Manza.Customers.list(client, q: "Acme")
Manza.Page.next(page)                               # {:ok, page} | {:error, _} | nil on the last page

# Payments (formerly transfer drafts): authorize/decline with a key other than the creator's
{:ok, draft} = Manza.Payments.create(client, %{"account_id" => id, "amount" => "150.00", "beneficiary_id" => bid, "client_reference" => "INV-1"})
{:error, %Manza.Error{kind: :conflict, payment_id: existing}} = Manza.Payments.create(client, same_attrs)  # 409

payee = Manza.TransferAuthorization.payee_for(external_account_id: draft.body["external_account_id"])
input = Manza.TransferAuthorization.signature_input(pid, nonce, amount, currency, account_id, payee, client_reference)
signature = Manza.TransferAuthorization.sign(signing_secret, input)
Manza.Payments.authorize(authorizer_client, pid, authorization_id, signature)
Manza.Payments.decline(authorizer_client, pid, authorization_id, "reason")
{:ok, authorizer} = Manza.TransferAuthorizer.get(client)   # :not_found when none is enrolled

# Webhooks: verify the raw body, never re-encoded JSON
{:ok, event} = Manza.Webhook.construct_event(raw_body, conn.req_headers, signing_secret)  # {:error, %ArgumentError{}}

# Beneficiaries (create + external accounts) and payee trust requests
Manza.Beneficiaries.create(client, attrs)
Manza.Beneficiaries.list_external_accounts(client, beneficiary_id)
Manza.Beneficiaries.create_external_account(client, beneficiary_id, attrs)
Manza.PayeeTrustRequests.create(client, [external_account_id])
```

- Resource modules: `Entity`, `Accounts`, `Customers`, `Invoices`, `PaymentLinks`, `CheckoutSessions`, `WebhookEndpoints`, `Beneficiaries`, `PayeeTrustRequests`, `Payments`, `TransferAuthorizer`, plus the pure `TransferAuthorization` signer and `Webhook` verifier (all under `Manza.`, in `lib/manza/`). `TransferDrafts` is a soft-deprecated alias of `Payments` (`defdelegate`, `@doc deprecated:`, no compile warning) for all of 1.x
- Tuple returns: `{:ok, %Manza.Response{}}` (body as `response.body`), list calls return `{:ok, %Manza.Page{}}`; errors are `{:error, exception}`
- `Manza.Page`: cursor-based, hard cap of 100/page (`Manza.Page.max_per_page/0`), `Manza.Page.next/1`
- **Error model**: one `Manza.Error` struct with a `kind`, not a class hierarchy. Discriminate on `error.kind`, never on `status` or `message`:
  - kinds: `:authentication` (401), `:forbidden` (403), `:not_found` (404), `:validation` (400, 422), `:conflict` (409, carries `payment_id`), `:rate_limit` (429, carries `retry_after`), `:server` (5xx), `:api` (any other non-2xx)
  - `Manza.ConfigurationError` is the argument error: bad client config, `limit` over 100, a blank authorization signature (all refused before any request)
  - `Manza.ConnectionError` wraps transport failures
  - `Manza.TransferAuthorization` is the exception: it is pure and raises `ArgumentError` on programming mistakes (non-string amount, wrong payee options)
  - `Manza.Webhook` reuses that `ArgumentError`: `construct_event/4` returns `{:error, %ArgumentError{}}`, `construct_event!/4` raises it. Its messages match manza-ruby's `Manza::Webhook` verbatim
- Snake-case wire format: request and response bodies are string-keyed maps returned as-is. **No auto-camelCasing, no struct mapping.**

## How to work in this codebase

1. **Tests come first.** Every change to `lib/` ships with a test. Cassette-replay tests are the contract: they enforce the same wire format across Ruby, TS, Elixir and the other SDKs.
2. **Use the SDK's primitives.** `Manza.Client` (`get/post/patch/delete/list_page`), `Manza.Page`, `Manza.Error` kinds, `Manza.Client.encode_path/1` for URL construction, `Manza.Client.query_filters/2`. Don't hand-roll Req calls, string-interpolate URLs, or match on `error.message`.
3. **Snake-case stays.** Response keys are wire format. We don't atomize or camelCase them.
4. **Format must be clean.** CI gates on `mix format --check-formatted`. There is no other linter.

## Critical rules

- **Never call a live Manza API** from tests, scripts or Claude sessions, staging (`https://ma.manza.dev`) included. Tests replay manza-ruby's cassettes only. Live staging calls create real transfers and approval requests for the team. Only manza-ruby records cassettes.
- **A replay mismatch is a wire-format drift, never a reason to loosen the matcher.** Check, in order: two cassettes sharing method + URI in one test; an authorize cassette without `ignore_signature: true`; a fixture id that drifted from manza-ruby's `spec/support/fixture_ids.rb`. Otherwise fix the SDK, or have manza-ruby re-record and ship a new tag. Never touch a cassette, mock HTTP, or hand-roll a Req call to make a test pass. `scripts/fetch-cassettes.sh` fetches the pinned tag; a failure means the release has no tarball yet or GitHub is flaky (it retries).
- **`mix format --check-formatted` and `mix test` before every commit.** `scripts/release-check` and CI run the same.
- **Cassette contract.**
  - Cassettes come from the manza-ruby release pinned in `scripts/fetch-cassettes.sh` (`PINNED_TAG`, `cassettes-vX.Y.Z.tar.gz`; bump it on purpose), extracted to `testdata/cassettes/` (gitignored). They are recorded against `https://ma.manza.dev`.
  - Load **one cassette per test**: `payments/authorize` vs `authorize_same_key`, `create` vs `create_duplicate`, and `beneficiaries/get_external_account` vs `get_external_account_trusted` share method + URI, and the first matching interaction wins.
  - The four authorize cassettes (`payments/authorize`, `authorize_same_key`, `authorize_bad_signature`, `authorize_new_payee`) are loaded with `ignore_signature: true`: they match the body minus `signature` (the recorded one is scrubbed to `<SIGNATURE>`).
  - Every other body is matched semantically: method + path + query (host ignored) + JSON bodies decoded and compared as terms (key order and whitespace never matter); non-JSON bodies compare byte-for-byte.
  - Cassette responses carry no `Content-Length`.
  - `test/support/fixture_ids.ex` must stay identical to manza-ruby's `spec/support/fixture_ids.rb` (same env var names, same placeholders). Add new ids to both.
- **Hosts.** Default `https://ma.manza.finance`, South Africa `https://za.manza.finance`, staging and cassettes `https://ma.manza.dev`. Env vars: `MANZA_API_KEY`, `MANZA_BASE_URL`, `MANZA_API_VERSION`, read first; the legacy `ZAZU_*` names are a fallback for all of 1.x that logs a one-time deprecation warning per variable (`Manza.Client`).
- **The error model is shared across the SDK family.** Adding an error kind (or class, elsewhere) means coordinating manza-ruby and manza-ts at minimum. The 10th is the conflict (409), here `kind: :conflict`. A break of the public API is made only on purpose, named in the CHANGELOG and released as a major.
- **Signer.** `Manza.TransferAuthorization` must keep reproducing the two fixed vectors from manza-ruby's `spec/manza/transfer_authorization_spec.rb` (see `test/manza/transfer_authorization_test.exs`). Never sign the server's `signature_input` blindly: build it from your own record of the transfer.
- **Webhook verifier.** `Manza.Webhook` must keep accepting the fixed vector shared by every SDK (manza-ruby's `spec/manza/webhook_spec.rb`; see `test/manza/webhook_test.exs`).
- **Example.** `examples/transfer_authorizer/` is its own Mix project (`{:manza, path: "../.."}` plus `plug`, `bandit`, `decimal`, and `bypass` for its tests). Its dependencies never go into the library's `mix.exs`, and the Hex package never ships `examples/` (the default `package` files exclude it; check with `mix hex.build`). CI runs its `mix test`; the root `mix format` covers its `lib` and `test`. Its tests stub the API with Bypass, like manza-ruby's example specs with WebMock: the cassette contract covers the SDK, not the example.
- **Release.** `bin/release` is byte-identical across the SDK repos and never edited in place (nor the release workflow's release-kit parts). Cut releases with it, never by hand-tagging: `release.yml` fails the publish when the tag differs from `@version`. Never run `mix hex.publish` locally; verify through CI. Repo-specific logic lives in `scripts/version` (reads/writes `@version` in `mix.exs`) and `scripts/release-check` (fetch cassettes, deps, format, test). `release.yml` gates on tag == `mix.exs` version.
- **Hex has no OIDC trusted publishing.** `release.yml` publishes with the `HEX_API_KEY` secret on the `hex` GitHub environment (add required reviewers there for a human gate). Generate the key on https://hex.pm/dashboard/keys with API write permission (Hex 2.5 removed `mix hex.user key generate`). The `hex` environment and the secret must live on `getmanza/manza-elixir`, and the key's Hex account must own the package `manza`.
- **Names.** Repo `getmanza/manza-elixir`, Hex package `manza`, app `:manza`, modules `Manza.*`. The old `zazu` Hex package is retired separately; never reintroduce `Zazu`/`ZAZU_` outside the env fallback and the CHANGELOG.
- **Never escape backticks in PR bodies.** With `<<'EOF'` (single-quoted heredoc) the shell passes everything through verbatim. See "PR descriptions" below.

## PR descriptions

Write PR description bodies in plain Markdown. **Do not escape backticks** with `` \` `` — GitHub renders `` \` `` literally as a backslash followed by a backtick, producing output like `` \`Manza.Page\` `` instead of the monospace `Manza.Page` the reader expects.

The usual cause is writing the description inside a bash heredoc (`gh pr create --body "$(cat <<'EOF' ... EOF)"`) and then reflexively escaping every backtick because of shell-quoting muscle memory. With `<<'EOF'` (single-quoted delimiter) the shell does NOT interpret anything inside the heredoc — backticks, dollars, and backslashes all pass through verbatim. So write them exactly as you want them rendered:

```bash
# Good — renders as `Manza.Page` in monospace
gh pr create --body "$(cat <<'EOF'
Uses the `Manza.Page` helper.
EOF
)"

# Bad — renders as \`Manza.Page\` literally in the PR body
gh pr create --body "$(cat <<'EOF'
Uses the \`Manza.Page\` helper.
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
scripts/fetch-cassettes.sh          # the pinned manza-ruby tarball (v1.3.0) -> testdata/cassettes/
scripts/fetch-cassettes.sh v1.0.1   # or another tag
mix deps.get

# Daily loop
mix test test/manza/resources_test.exs   # while iterating
mix format                              # auto-format
mix format --check-formatted            # what CI gates on
mix test                                # full suite
(cd examples/transfer_authorizer && mix deps.get && mix test)   # the example, as CI runs it

# Release (after PR merge, from a clean, up-to-date main)
bin/release list        # last releases + what patch/minor/major would give
bin/release --dry-run   # version + changes since the last tag, publishes nothing
bin/release minor       # or patch (default), major, an explicit 0.4.0; --force re-creates
# -> bumps @version in mix.exs, runs scripts/release-check, pushes main, publishes the GH release
# -> release.yml workflow tests, checks tag == mix.exs version, runs mix hex.publish, creates the release
```

## Workflow

- **Verify:** `MIX_ENV=test mix format --check-formatted` · `MIX_ENV=test mix test` · in `examples/transfer_authorizer/`: `MIX_ENV=test mix test` (no Credo, no Dialyzer; `scripts/fetch-cassettes.sh` first if `testdata/cassettes/` is missing or stale)
- **Specs:** fast loop `MIX_ENV=test mix test test/manza/<file>_test.exs`; full suite `MIX_ENV=test mix test` (replay: no network); two worktrees at once: yes, each fetches its own cassettes (`testdata/cassettes/` is gitignored)
- **CI:** required none; job `test` (`ci.yml`, Elixir 1.18 / OTP 27, no matrix), check `cubic · AI code reviewer`; full suite on the PR; failure report none
- **Review bot:** cubic; push back, citing this file, on mocks instead of cassettes, camelCased or atomized wire keys, hand-rolled Req calls, speculative abstractions
- **Merge:** squash — `gh pr merge <PR> --squash --delete-branch`; fallback after the gate: `--admin` for the required approving review
- **PR contract:** `## Summary` (`Closes #N`), `## Fable validation` (verdict, Not verified), `## Test plan`; backticks unescaped; labels none; screenshots none
- **Conflicts:** `CHANGELOG.md` — both sides under `## [Unreleased]`, main's first; `mix.exs` `@version` — main's; `testdata/cassettes/**` is gitignored, never merged; `bin/release`, `release.yml` outside its `test` job — main's (release kit)
- **Worktree setup:** `mix deps.get` and `scripts/fetch-cassettes.sh` (both gitignored output); undo none
- **Release:** `bin/release [patch|minor|major|X.Y.Z]` from a clean, current main (`--dry-run` previews) → `release.yml` tests, checks tag == `@version`, publishes to Hex, creates the GitHub release; changelog `CHANGELOG.md`, `[Unreleased]` headed `## [X.Y.Z]` by hand
- **Main health:** `gh run list --workflow ci.yml --branch main --event push --limit 1 --json conclusion,headSha`
- **Upstream:** libraries we own `getmanza/*`; scrub none

## Agent commands

Plugin (`.claude/settings.json`): `/flow:lfg`, `/flow:plan`, `/flow:follow-through`, `/flow:finish-prs`, `/flow:github-review-pr` (`-failures`, `-comments`; cubic's threads included), `/flow:review-pr`, `/flow:tdd`, `/flow:debug-flaky`, the `flow:fable-validator` agent. No local commands.

**Models.** Sessions run on `opus` with `fable` as the advisor (`.claude/settings.json`); consult it before choosing an approach, a public API, a dependency, anything irreversible, and when a failure repeats. Every spawned agent names its `model:`; one that does not runs on `sonnet` (`CLAUDE_CODE_SUBAGENT_MODEL`), never on the session's model.

## Cross-SDK contract

`manza-ruby` is the reference implementation:

- Records cassettes against `https://ma.manza.dev`
- Ships them as a release tarball (`cassettes-vX.Y.Z.tar.gz`) on each version
- All other SDKs (`manza-ts`, `manza-elixir`, future `manza-python`, `manza-go`, `manza-php`, `manza-crystal`, `manza-rust`) replay these cassettes in their own test harness

If the contract breaks (e.g., new request shape, new error kind), it's a coordinated change across at least two repos: manza-ruby and manza-ts.

## Repository links

- Ruby SDK (reference): https://github.com/getmanza/manza-ruby
- TypeScript SDK: https://github.com/getmanza/manza-ts
- This repo: https://github.com/getmanza/manza-elixir
- Hex package: https://hex.pm/packages/manza
- CLI consumer: https://github.com/getmanza/cli
