# Changelog

All notable changes to `zazu-elixir` are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
