---
description: "Use when CI checks are failing on a PR — fetches failure logs, diagnoses root causes, implements fixes, pushes until CI is green."
model: opus
argument-hint: "PR number (e.g., 1690 or #1690)"
allowed-tools: Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh pr diff:*), Bash(gh api:*), Bash(gh run view:*), Bash(git log:*), Bash(git diff:*), Bash(git push:*), Bash(git commit:*), Bash(git add:*), Bash(mix:*), Bash(scripts/fetch-cassettes.sh:*), Read, Write, Edit, Glob, Grep, Agent
---

# Fix GitHub CI Failures: $ARGUMENTS

Diagnose and fix CI failures. Work systematically: identify failures → read logs → diagnose root cause → fix locally → verify → push.

## Phase 0: Determine the PR

Number → PR. `#N` → strip `#`. Empty → current branch (`gh pr view --json number`).

## Phase 1: Inventory failures

```bash
gh pr checks <PR>
```

For each failing check, get the run id and load the failed logs:

```bash
gh run view <run-id> --log-failed
```

Categorize:
- **Test failures** — ExUnit assertion failed, timeout
- **Format failures** — `mix format --check-formatted` (the only lint/format gate; there is no Credo or Dialyzer)
- **Compile failures** — `mix deps.get` or compilation errors, warnings from a new Elixir/OTP
- **Cassette fetch failures** — `scripts/fetch-cassettes.sh` could not resolve or download the manza-ruby tarball
- **Cassette replay failures** — the Bypass server answered 501 `no cassette interaction matches ...`
- **Release / publish failures** — `HEX_API_KEY` secret or `hex` environment, `mix hex.publish`, tag/version mismatch

## Phase 2: Diagnose

Read the actual error message, not the surrounding noise. The first stacktrace line that points at our code is usually the culprit.

For each failure:

### Reproduce locally

```bash
export MIX_ENV=test
scripts/fetch-cassettes.sh            # cassettes (the manza-ruby release pinned in the script)
mix deps.get
mix test test/manza/<file>_test.exs    # one test file
mix format --check-formatted          # format (fix with: mix format)
mix test                              # full suite
```

Never reproduce a failure by calling a live Manza API. Replay cassettes only.

If you can't reproduce locally, the failure is environmental (CI-only):
- Different Elixir/OTP version → CI pins OTP 27 and Elixir 1.18 via `erlef/setup-beam` in `ci.yml` and `release.yml`; a newer local toolchain may format or warn differently
- Stale cassettes → `scripts/fetch-cassettes.sh` fetches the pinned `PINNED_TAG`; to pick up a newer manza-ruby release, bump `PINNED_TAG` (or pass the tag as an argument) and re-run it
- Race condition → re-running the job fixes it
- Network → GitHub (cassette tarball, `git ls-remote`) or Hex hiccup; the fetch script already retries
- Secret missing → `HEX_API_KEY` not set on the `hex` environment of `getmanza/manza-elixir`

### Find the root cause

Apply the five-whys ladder until you reach a fix point that prevents the same class of failure recurring. Don't:

- Disable the failing test
- Edit `.formatter.exs` to dodge the format check
- Touch a cassette or loosen the replay matcher to make a test pass
- Add a dependency to paper over a missing alias or import

These hide the failure; the underlying bug returns elsewhere.

## Phase 3: Fix and verify

### 3.1 Implement the fix

Touch only what the failure cites, plus what the fix requires.

### 3.2 Run the equivalent local check

The CI step that failed has a local equivalent — run it, get green:

| CI step | Local equivalent |
|---|---|
| Fetch cassettes | `scripts/fetch-cassettes.sh` |
| Install dependencies | `mix deps.get` |
| Check formatting | `mix format --check-formatted` |
| Run tests | `mix test` |
| Verify tag matches package version (release.yml) | `scripts/version` prints the `mix.exs` version to compare with the tag |
| `mix hex.publish --yes` (release.yml) | requires `HEX_API_KEY` — never run locally, verify via CI |

### 3.3 Run the full pipeline

```bash
export MIX_ENV=test
mix format --check-formatted
mix test
```

### 3.4 Commit + push

```bash
git add <files>
git commit -m "fix(ci): <what was failing>

<root cause and how this addresses it>"
git push origin <branch>
```

Use `fix:` for prod fixes, `chore(ci):` for workflow / config changes.

## Phase 4: Watch the next run

```bash
gh pr checks <PR> --watch
# or
gh run watch <run-id> --exit-status
```

Track until green. If the same step fails again with a different error, repeat. If it fails the same way, your fix is wrong — revert and rethink.

## Phase 5: Verify and document

```bash
gh pr checks <PR>            # all green
gh pr view <PR> --json mergeable,reviewDecision
```

If the failure was CI-config drift (workflow YAML out of sync with reality), also update relevant docs:
- the `otp-version` / `elixir-version` in `ci.yml` and `release.yml`
- `mix.exs` `elixir:` requirement
- `CLAUDE.md` if a convention changed

## Common patterns and fixes

### Cassette replay says "no cassette interaction matches"

The recorded request shape drifted from what the SDK now sends, or the test loaded the wrong cassettes. Check, in order:
- Two cassettes sharing method + URI in one test (`authorize` vs `authorize_same_key`, `create` vs `create_duplicate`): load one per test.
- An authorize cassette without `ignore_signature: true` (recorded `signature` is scrubbed to `<SIGNATURE>`).
- A fixture id that drifted from manza-ruby's `spec/support/fixture_ids.rb`.
- Otherwise the wire format changed: re-record via manza-ruby (never here) and ship a new SDK version.

### `scripts/fetch-cassettes.sh` fails

It downloads the manza-ruby tag pinned in the script (`PINNED_TAG`, currently `v1.0.0`) as `cassettes-<tag>.tar.gz` from that release. A failure usually means the release has no tarball yet, or GitHub is flaky (the script retries). Pin a tag to confirm: `scripts/fetch-cassettes.sh v1.0.0`.

### Hex publish failed (401/403)

Hex has no OIDC trusted publishing: `release.yml` publishes with the `HEX_API_KEY` secret on the `hex` environment. Check the secret exists on `getmanza/manza-elixir`'s `hex` environment, was generated with `api:write`, and belongs to an owner of the Hex package `manza`.

### Tag does not match mix.exs version

`release.yml` fails the publish job when the tag differs from `@version` in `mix.exs`. Cut releases with `bin/release`, never by hand-tagging.

## Karpathy guidelines

- **Think before coding** — read the actual error, don't pattern-match on the first guess.
- **Goal-driven execution** — the green CI check is the verification.
- **Surgical changes** — fix the failing class of error, not adjacent things.
