# Solus

A B2B distribution platform for everyday goods (FMCG) in Nigeria. It connects **manufacturers → distributors →
sales agents → retail shops**, and keeps every item of stock and every naira accounted for.

Two ways goods reach shops, on one shared stock and money system:

- **Pull (shops order):** a shop orders → the nearest warehouse with stock reserves it → batch → pack →
  driver delivers with photo + GPS proof → partial / missing / damaged reported → shop pays.
- **Push (agents sell):** an agent requests stock → manager approves → handover confirmed with a one-time
  code → agent sells shop to shop (works offline) → returns what's left → reconciliation. A run can't close
  while anything is unaccounted for.

## Who uses it

| Role | What they do |
|---|---|
| Manufacturer | Adds products, sees sales totals per distributor |
| Distributor admin | Runs the business: warehouses, staff, credit limits, finance |
| Branch manager | Approves shops, staff and stock requests; resolves problems |
| Warehouse staff | Receives stock, packs orders, hands stock to agents |
| Driver | Delivers orders with photo proof |
| Sales agent | Sells from the phone app, online or offline |
| Shop owner | Orders, pays from wallet or on credit, raises support tickets |
| Platform admin | Onboards companies, watches payments |

## Features

- Ordering with nearest-warehouse routing and atomic stock reservation (no overselling, ever)
- Batching, packing, dispatch, e-POD (photo + GPS), partial/missing/damaged deliveries
- Agent stock runs with two-party OTP handover and return, variance cases, manager approval
- **Offline agent app** (Expo / React Native): sales are queued on the phone and synced as events; anything
  the server can't accept goes to a manager review queue and is never dropped
- Wallets backed by virtual bank accounts (the platform never holds money), trade credit with SMS OTP,
  signed and replay-safe payment webhooks, reconciliation
- Dashboards (sales, top products, agent leaderboard, stock value), in-app inbox, support tickets
- Row-level security on every table: a company can only ever see its own data
- Full audit log of every change

## Tech stack

- **Database:** Postgres 17 + PostGIS on Supabase. Business rules live in SQL functions.
  - Stock is an append-only ledger.
  - Money is double-entry bookkeeping.
- **Web:** Next.js 15 (all web roles)
- **Phone:** Expo SDK 58 / React Native (agent app, SQLite outbox)
- **Language:** TypeScript everywhere, npm workspaces
- **Integrations:** KYC, SMS and payments each sit behind an interface. Only mocks exist so far, each with
  contract tests.

## Run it locally

You need **Node 20+**, **Docker** (running) and the **Supabase CLI**.

```bash
npm install
npm run db:start                     # start local Postgres/Auth/API in Docker
npm run db:reset                     # create tables + demo data
npm run web:env                      # write apps/web/.env.local from the running stack
npm run dev --workspace @solus/web   # http://localhost:3100
```

### Demo logins

Password for every account: **`SolusDev-2026!`**, and each email ends in `@solus.test`.

| Role | Emails |
|---|---|
| Platform admin | `platform.admin` |
| Manufacturer | `sunrise.admin` |
| Distributor admin | `lp.admin` (Lagos Prime), `ac.admin` (Abuja Central) |
| Branch manager | `lp.bm.ikeja`, `lp.bm.lekki`, `ac.bm.wuse` |
| Warehouse staff | `lp.wh.ikeja`, `lp.wh.lekki`, `ac.wh.wuse` |
| Sales agent | `lp.agent1`–`lp.agent3`, `ac.agent1`–`ac.agent2` |
| Driver | `lp.driver1`, `ac.driver1` |
| Shop owner | `retailer01` … `retailer20` |

SMS, payments and ID checks are mocks in development:
- **SMS codes** show on screen in the web app. Also set `MOCK_SMS_LOG=1` (written by `npm run web:env`) and
  codes are printed in the web server log.
- **Wallet top-ups:** use the "simulate transfer" button on a shop's Wallet page.

### Phone app (agents)

```bash
npm run agent:env     # points the app at this computer's local server
npm run agent:start   # starts the Expo dev server and shows a QR code
```

- **On a phone:** install **Expo Go** (App Store / Play Store), stay on the same Wi-Fi, and scan the QR code.
- **On a Mac:** press `i` in the Expo terminal to open the iOS simulator.

Then sign in as an agent, e.g. `lp.agent3@solus.test`.

## Tests

```bash
npm run test:all
```

Runs everything from a clean database:
- 677 pgTAP database checks, covering security, ledgers and invariants
- typecheck
- 44 Node tests: unit, contract, a 50-way concurrency test, and end-to-end tests of both flows
- web production build
- Android bundle of the agent app

All tests run against a real Postgres, never a mock.

## Project layout

```
apps/web                 Next.js web app (all web roles)
apps/agent               Expo agent app (offline-first)
packages/core            shared types, money (kobo) and unit helpers
packages/db              repository layer: the only TypeScript that touches the database
packages/agent-core      offline outbox + sync engine
packages/integrations    KYC / SMS / payments interfaces, mocks, contract tests
supabase/migrations      SQL schema and business logic
supabase/tests           pgTAP tests
tests/                   integration, concurrency and end-to-end tests
docs/                    spec, architecture, decisions (ADRs), progress
```

## Docs

- [Product spec](docs/SPEC.md)
- [Architecture](docs/architecture/README.md)
- [Decisions (ADRs)](docs/adr/README.md)
- [Progress, assumptions and known gaps](docs/PROGRESS.md)
- [Engineering rules](CLAUDE.md)

## Status and known gaps

All planned phases are built and tested. Before real money can flow:

- Real KYC, SMS and payment providers need to be connected. This needs provider accounts and API keys.
- Production must be hosted in Nigeria (data-residency rules, see ADR-0001).
- Phone-number verification at sign-up and SMS/push notifications are still to do.
- There are no screens yet for stock transfers or price-list publishing. The database side exists and is tested.
