# Changelog

All notable changes to `manza-elixir` (formerly `zazu-elixir`) are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-11-14

Synced to the Manza API at getmanza/app `906ec486e5` (API version `2026-11-13`), mirroring manza-ruby 2.0.0. A major release: see Migrating from 1.x below.

### Removed

- **Breaking:** `Manza.Invoices.create_payment_link/3` (`POST /api/invoices/:id/payment_link`). The API retired the endpoint: ask for the link with `"generate_payment_link" => true` on `Manza.Invoices.create/2` or `Manza.Invoices.update/3` instead
- **Breaking:** the v1 transfer-authorization signer. `Manza.TransferAuthorization` builds only the v2 input (below)

### Changed

- **Breaking:** `Manza.TransferAuthorization.signature_input/8` signs `manza.transfer-authorization.v2` and takes `transfer_method` as a required last argument, after `client_reference` (`""` when `nil`): `manza.transfer-authorization.v2|payment_id|nonce|amount|currency_code|account_id|payee|client_reference|transfer_method`. `client_reference` is required too (`nil` when the transfer has none): `signature_input/6` and `/7` are gone, so a 1.x call warns at compile time and raises `UndefinedFunctionError` before any request instead of signing a wrong input. The API verifies v2 for every request that is unpinned or sends `Manza-Version: 2026-11-13`; only `2026-03-27` still verifies v1. Pass the payment's `transfer_method` as the API returned it
- **Breaking:** a 422 of `type` `plan_limit_reached` is a `%Manza.Error{}` of the new `kind: :plan_limit_reached`, not `:validation` (the API used to answer a plan cap with a 500, `:server`)
- The example authorizer (`examples/transfer_authorizer`) records the create response's `transfer_method` in its ledger, checks it against the webhook's `payment.transfer_method` (a `nil` matches an entry without one), signs v2, and compares its input with the webhook's `signature_input_v2`. The preflight points at `trust_new_payees`
- Invoice docs: `account_id` is required on `Manza.Invoices.create/2` (without one the API answers 422 `state_error` with no `param`; an account that is not the entity's, 422 with `param` `account_id`), and `Manza.Invoices.update/3` takes it too. An invoice's `status` may be `declined`, and `Manza.Invoices.delete/2` also takes a `declined` invoice that has no number
- The legacy `ZAZU_*` environment fallback and the `Manza.TransferDrafts` alias stay, now until a later major release (they were announced for removal in 2.0)

### Added

- `kind: :plan_limit_reached` on `Manza.Error` (the other SDKs' `PlanLimitReachedError`, a validation subclass there): a 422 whose `type` is `plan_limit_reached`. `limit_kind` names what is capped (e.g. `"invoices"`; the API's `error.kind`, renamed because `kind` is the error's category), `limit_current` the count the entity holds and `limit_max` the cap; all three are `nil` on any other error. Retrying does not help until the plan changes
- `generate_payment_link` on `Manza.Invoices.create/2` and `Manza.Invoices.update/3` (needs the `payment_links:write` scope; taken only while payment links are enabled for the entity). Invoice responses carry `generate_payment_link` and the embedded `account`
- `transfer_method` on `Manza.Payments.create/2`: `eft` or `rtc` in South Africa, `standard` or `instant` in Morocco; one the market does not offer returns a `:validation` error with `param` `transfer_method`. Payment responses carry `transfer_method` (the rail sent, the provider's default when left out, `nil` where the market offers no choice)
- Documented: the authorization `refusal_reason` `rail_limit_exceeded` (status `superseded`): an authorized transfer over its rail's limit at execution, sent to the approvers; `Manza.Payments.authorize/4` returns a 422 `:validation` error (`state_error`). A non-boolean `generate_payment_link` returns a 400 `:validation` error
- Documented: the `payment.authorization_requested` webhook's `signature_input_v2` and `payment.transfer_method` (events stay string-keyed maps: read them from `data`), and `Manza.TransferAuthorizer.get/1`'s `trust_new_payees` and `new_payee_limit`

### Fixed (API side, no wire change)

- `Manza.Accounts.list_transactions/3` and `Manza.Accounts.get_transaction/3` return posted movements only (getmanza/app 818432457a); the SDK is unchanged

### Changed (cassettes)

Cassettes come from `cassettes-v2.0.0` (was `v1.3.0`): every cassette was re-recorded against staging. New replay tests mirror manza-ruby 2.0.0's specs:

| Cassette | Request |
|---|---|
| `invoices/create` | `POST /api/invoices` with `account_id`, `generate_payment_link: true`, `issue_date` `2026-11-14`, `due_date` `2026-12-14` |
| `invoices/create_invalid_generate_payment_link` (new) | `generate_payment_link: "yes please"`: 400 |
| `invoices/create_without_account` (new) | no `account_id`: 422 `state_error` |
| `invoices/update` | `PATCH /api/invoices/fixture-invoice-id` with `account_id`, `notes`, `generate_payment_link: true` |
| `payments/create` | `POST /api/payments` with `transfer_method: "standard"` |
| `payments/create_invalid_transfer_method` (new) | an unoffered `transfer_method`: 422, `param` `transfer_method` |

The authorize cassettes sign v2 over `transfer_method` `standard`; the recorded `signature` stays scrubbed to `<SIGNATURE>`, and replay matches the body without it.

### Migrating from 1.x

- **`create_payment_link` is gone.** Replace `Manza.Invoices.create_payment_link(client, id, account_id)` with `Manza.Invoices.update(client, id, %{"account_id" => account_id, "generate_payment_link" => true})`, or pass `"generate_payment_link" => true` on create. `update/3` returns the invoice, not a link: the link is made from the invoice's account when the invoice is approved, and appears in the invoice's `payment_link`. `update/3` takes only an invoice that is still `draft`, `pending_approval` or `declined` (any other returns a `:validation` error, `state_error`); for an invoice already approved or sent there is no API path to attach a link to it: `Manza.PaymentLinks.create/2` makes a standalone link instead
- **`account_id` is required on invoice create.** Pass the account the invoice is paid into (`Manza.Accounts.list/2`); 1.x calls without it now return a `:validation` error
- **v2 signatures only.** Add the payment's `transfer_method` (the create response's `"transfer_method"`; `nil` only when it is null) as the last argument of every `Manza.TransferAuthorization.signature_input` call, passing `nil` for a missing `client_reference`, and compare with the webhook's `signature_input_v2` instead of `signature_input`. A call left on the 1.x arity shows as an "undefined function `signature_input/7`" compile warning: grep your calls, or build with `mix compile --warnings-as-errors`, before you deploy. A client pinned to `Manza-Version: 2026-03-27` (`api_version:` or `MANZA_API_VERSION`) is verified v1 and must stay on manza 1.x; unpin it, or pin `2026-11-13`, to move to 2.0
- **Plan caps.** A match on `%Manza.Error{kind: :server}` around creates that may hit a plan cap no longer matches: match `%Manza.Error{kind: :plan_limit_reached}`, and do not retry it. It is not `:validation`, so a `kind: :validation` clause does not catch it either

## [1.1.0]

### Added

- `Manza.Payments` (`create/2`, `get/2`, `authorize/4`, `decline/4`) on the API's canonical paths: `POST /api/payments`, `GET /api/payments/:id`, `POST /api/payments/:id/authorize` and `…/decline`. The API renamed transfer drafts to payments; request and response bodies are unchanged, and so is the `Manza.TransferAuthorization` signature input
- `Manza.TransferAuthorizer.get/1` (`GET /api/transfer_authorizer`): the enrolled authorizer's `status`, `suspension_reason`, limits, `daily_authorized_total`, `secret_expires_at` and `webhook_endpoint_id`; `{:error, %Manza.Error{kind: :not_found}}` when none is enrolled
- `Manza.Webhook` verifies incoming webhook deliveries: `construct_event/4` (`{:ok, event}` / `{:error, %ArgumentError{}}`), `construct_event!/4` (raises `ArgumentError`), `verify?/5` (boolean) and `sign/3`. Reads `X-Manza-*` headers in any case, from a map or Plug's `req_headers`, the CGI `HTTP_X_MANZA_*` form and the legacy `X-Zazu-*` names; checks the timestamp within 5 minutes (`tolerance: nil` skips it, for local replay only). Passes the test vector shared by every SDK. No new error type
- Documented the new pass-through fields: a payment's `authorization` carries `refusal_reason` (status `refused` when it went to the approvers at create time), bank accounts carry `trusted`, and the challenge webhook's `payment.payee_trusted` says whether the payee was trusted already
- `examples/transfer_authorizer/`: a runnable two-key transfer authorizer (a Plug served by Bandit, `mix authorizer`), a creator (`mix create_transfer`), a preflight that checks every setup step and prints the fix (`mix preflight`) and a JSON ledger. Its own Mix project with its own dependencies, tested in CI, not in the published package
- README: "Setup, step by step" for machine-authorized transfers, and the verifier

### Changed

- Cassettes are pinned to manza-ruby `v1.3.0`: the payment cassettes moved from `transfer_drafts/` to `payments/` and match `/api/payments…`; `payments/create` and `beneficiaries/create` match new request bodies; new fixture ids for the refused and new-payee drafts

### Deprecated

- `Manza.TransferDrafts`: a soft-deprecated alias of `Manza.Payments` for all of 1.x. Every function delegates, so it calls `/api/payments` too. The deprecation shows in the docs and emits no compile warning

## [1.0.0]

### Changed

- **Renamed zazu to manza.** The Hex package is now `manza`, the OTP app `:manza`, the modules `Manza.*`, the repo `getmanza/manza-elixir`. The version restarts under the new name at 1.0.0 (set by `bin/release` at release time)
- Requests send the `Manza-Version` header (was `Zazu-Version`) and `User-Agent: manza-elixir/<version>`
- Config reads `MANZA_API_KEY`, `MANZA_BASE_URL` and `MANZA_API_VERSION` first, then falls back to the old `ZAZU_*` names with a one-time deprecation warning per variable. The fallback stays for all of 1.x
- Cassettes are fetched from `getmanza/manza-ruby`, pinned to `v1.0.0`; the fixture env vars are `MANZA_FIXTURE_*` (no fallback, dev-only)

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
