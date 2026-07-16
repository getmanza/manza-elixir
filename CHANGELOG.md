# Changelog

All notable changes to `zazu-elixir` are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
