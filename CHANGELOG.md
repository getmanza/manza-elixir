# Changelog

All notable changes to `manza-elixir` (formerly `zazu-elixir`) are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Manza.Payments` (`create/2`, `get/2`, `authorize/4`, `decline/4`) on the API's canonical paths: `POST /api/payments`, `GET /api/payments/:id`, `POST /api/payments/:id/authorize` and `…/decline`. The API renamed transfer drafts to payments; request and response bodies are unchanged, and so is the `Manza.TransferAuthorization` signature input
- `Manza.TransferAuthorizer.get/1` (`GET /api/transfer_authorizer`): the enrolled authorizer's `status`, `suspension_reason`, limits, `daily_authorized_total`, `secret_expires_at` and `webhook_endpoint_id`; `{:error, %Manza.Error{kind: :not_found}}` when none is enrolled
- `Manza.Webhook` verifies incoming webhook deliveries: `construct_event/4` (`{:ok, event}` / `{:error, %ArgumentError{}}`), `construct_event!/4` (raises `ArgumentError`), `verify?/5` (boolean) and `sign/3`. Reads `X-Manza-*` headers in any case, from a map or Plug's `req_headers`, the CGI `HTTP_X_MANZA_*` form and the legacy `X-Zazu-*` names; checks the timestamp within 5 minutes (`tolerance: nil` skips it, for local replay only). Passes the test vector shared by every SDK. No new error type
- Documented the new pass-through fields: a payment's `authorization` carries `refusal_reason` (status `refused` when it went to the approvers at create time), bank accounts carry `trusted`, and the challenge webhook's `payment.payee_trusted` says whether the payee was trusted already
- `examples/transfer_authorizer/`: a runnable two-key transfer authorizer (a Plug served by Bandit, `mix authorizer`), a creator (`mix create_transfer`), a preflight that checks every setup step and prints the fix (`mix preflight`) and a JSON ledger. Its own Mix project with its own dependencies, tested in CI, not in the published package
- README: "Setup, step by step" for machine-authorized transfers, and the verifier

### Deprecated

- `Manza.TransferDrafts`: a soft-deprecated alias of `Manza.Payments` for all of 1.x. Every function delegates, so it calls `/api/payments` too. The deprecation shows in the docs and emits no compile warning

### Changed

- **Renamed zazu to manza.** The Hex package is now `manza`, the OTP app `:manza`, the modules `Manza.*`, the repo `getmanza/manza-elixir`. The version restarts under the new name at 1.0.0 (set by `bin/release` at release time)
- Requests send the `Manza-Version` header (was `Zazu-Version`) and `User-Agent: manza-elixir/<version>`
- Config reads `MANZA_API_KEY`, `MANZA_BASE_URL` and `MANZA_API_VERSION` first, then falls back to the old `ZAZU_*` names with a one-time deprecation warning per variable. The fallback stays for all of 1.x
- Cassettes are fetched from `getmanza/manza-ruby`, pinned to `v1.0.0`; the fixture env vars are `MANZA_FIXTURE_*` (no fallback, dev-only)
- Cassettes are pinned to manza-ruby `v1.3.0`: the payment cassettes moved from `transfer_drafts/` to `payments/` and match `/api/payments…`; `payments/create` and `beneficiaries/create` match new request bodies; new fixture ids for the refused and new-payee drafts

### Migration from `zazu` 0.x

| Before | After |
|---|---|
| `{:zazu, "~> 0.3"}` | `{:manza, "~> 1.0"}` |
| `Zazu.new(...)`, `Zazu.Accounts`, `%Zazu.Error{}`, ... | `Manza.new(...)`, `Manza.Accounts`, `%Manza.Error{}`, ... |
| `Application.get_env(:zazu, ...)` | `Application.get_env(:manza, ...)` |
| `ZAZU_API_KEY`, `ZAZU_BASE_URL`, `ZAZU_API_VERSION` | `MANZA_API_KEY`, `MANZA_BASE_URL`, `MANZA_API_VERSION` (old names still work in 1.x, with a warning) |

Search and replace `Zazu` with `Manza` across your code; the API surface is otherwise unchanged.

## [0.3.0] (as zazu-elixir)

### Added

- `:conflict` error kind (409) on `Zazu.Error`, with `payment_id` read from `error.payment_id`; 400 now maps to `:validation`
- `Zazu.TransferDrafts.authorize/4` (a blank signature is refused locally with `Zazu.ConfigurationError`) and `decline/4` (omits `reason` when absent); `client_reference` documented on `create/2`
- `Zazu.TransferAuthorization` signer: `signature_input/7`, `sign/2`, `payee_for/1`, checked against the vectors shared with every SDK
- `Zazu.Beneficiaries.create/2`, `list_external_accounts/3`, `get_external_account/3`, `create_external_account/3`
- `Zazu.PayeeTrustRequests` (`create/2`, `get/2`)
- Docs for the new response fields (`client_reference`, `authorization`, `settled_at`, `transaction`, `billing_address`, `collect_billing_address`, `customer_name`, `registration_number`, `vat_number`, the `clearing` status) and the market-gated `tax_id`, `ice_number` and `delivery_date`

### Changed

- Default base URL is now `https://ma.manza.finance` (`https://za.manza.finance` for South Africa); replay cassettes are recorded against `https://ma.manza.dev`
- `Zazu.Beneficiaries` is no longer documented as read-only
- Replay harness: one cassette per test where method + URI collide, and an `ignore_signature` option for the authorize cassettes

## [0.2.1]

Version alignment: the whole SDK family now releases in lockstep with zazu-ruby. No functional changes since [0.1.0].

## [0.1.0]

Initial release.

### Added

- `Zazu.Client` built on `Req` (`Zazu.new/1`, tuple-based returns)
- Resources: `Zazu.Accounts`, `Zazu.Beneficiaries`, `Zazu.CheckoutSessions`, `Zazu.Customers`, `Zazu.Entity`, `Zazu.Invoices`, `Zazu.PaymentLinks`, `Zazu.TransferDrafts`, `Zazu.WebhookEndpoints`
- Cursor-based `Zazu.Page` with `Zazu.Page.next/1` (max 100 records per page)
- `Zazu.Error` mirroring the shared SDK error taxonomy, plus distinct `Zazu.ConfigurationError` and `Zazu.ConnectionError`
- Cassette-replay test harness driven by the Ruby SDK's release tarball
