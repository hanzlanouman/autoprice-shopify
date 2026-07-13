# Shopify AI Dynamic Pricing Assistant

A single-store Rails and React prototype that adjusts Shopify variant prices as
inventory becomes scarce. Gemini may recommend a price, but deterministic Ruby
rules decide whether a write is allowed. Every material outcome is visible in a
Shopify Polaris dashboard and retained in searchable history.

## What it demonstrates

- Shopify GraphQL product/variant sync, pagination, currency, and price writes;
- inventory threshold and base-relative maximum-price settings;
- hourly, daily, weekly, monthly, and demo-minute automation with Solid Queue;
- structured Gemini recommendations with strict server validation;
- reliable, clearly labeled deterministic fallback pricing;
- current-price conflict protection and durable write reconciliation;
- base/current/latest-change clarity and per-variant history;
- optional, off-by-default restoration of app-owned increases after restock;
- credential-free local demo and a DigitalOcean App Platform deployment spec.

This is a private, standalone, single-store prototype. It is not an embedded or
multi-tenant Shopify App Store application.

## Run the demo

Prerequisite: Docker Desktop or Docker Engine with Compose v2.

```bash
cp .env.example .env
docker compose up --build
```

PowerShell:

```powershell
Copy-Item .env.example .env
docker compose up --build
```

Open <http://localhost:3000>. No Shopify or Gemini credentials are required.
Blank Shopify credentials select a seeded local store; with no live Shopify
connection, blank Gemini credentials select the deterministic recommender.

Suggested walkthrough:

1. Review the threshold and 150%-of-base maximum in **Settings**.
2. Keep automatic pricing off and click **Run now** on **Dashboard**.
3. Compare base price, current price, latest change, source, outcome, and reason.
4. Open a variant's details, then search and sort **Price History**.
5. Run again without lowering inventory to demonstrate repeat-adjustment
   protection.

Useful commands:

```bash
docker compose logs -f web worker
docker compose exec web bin/rails demo:seed_local
docker compose exec web bin/rails console
docker compose down
```

`docker compose down -v` also deletes the local PostgreSQL volume and history.

## Pricing rules in brief

The global maximum is a percentage of each variant's stored merchant base:

```text
floor   = live current Shopify price
ceiling = base price * maximum percentage / 100
floor <= accepted recommendation <= ceiling
```

Only active, inventory-tracked, non-gift-card variants with
`0 < inventory <= threshold` are considered. Sold-out, untracked, at-ceiling,
and unchanged already-adjusted variants are skipped before AI. Invalid model
output is rejected rather than clamped.

AI and fallback never recommend below current price. Restoration is a separate
system action, disabled by default, which may return only an app-owned increase
to base after stock recovers. A merchant or third-party Shopify edit always wins
and becomes the new base.

The fallback is base-anchored rather than compounded:

```text
scarcity = clamp((threshold - inventory + 1) / (threshold + 1), 0, 1)
target   = base + (ceiling - base) * scarcity
```

## Connect Shopify and Gemini

Use a disposable Shopify development store. In the Shopify Dev Dashboard,
create/release an app for the same organization and grant required Admin API
scopes:

- `read_products`
- `write_products`
- `read_inventory`

The optional live-store seeder also needs `read_locations` and
`write_inventory`. Install the released app, then configure `.env`:

```dotenv
SHOPIFY_STORE_DOMAIN=your-store.myshopify.com
SHOPIFY_API_KEY=<client-id>
SHOPIFY_API_SECRET=<client-secret>
SHOPIFY_ACCESS_TOKEN=

GEMINI_API_KEY=<optional-google-ai-studio-key>
GEMINI_MODEL=gemini-3.5-flash
```

For an existing legacy custom app, leave the key/secret blank and set its static
`SHOPIFY_ACCESS_TOKEN`. Never commit `.env`.

Restart after editing environment values:

```bash
docker compose up -d --force-recreate web worker
docker compose exec web bin/rails runner "puts Shopify::Client.new.fetch_shop_currency"
```

Optionally populate only a disposable development store:

```bash
docker compose exec web bin/rails demo:seed_shopify
```

With live Shopify configured but Gemini unavailable, the default behavior is no
AI-driven change. The merchant can explicitly enable the labeled fallback in
Settings.

## Configuration

Copy `.env.example`; it is the authoritative variable template. Important
production values are:

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | PostgreSQL shared by Rails and Solid Queue |
| `SECRET_KEY_BASE` | Rails cryptographic secret |
| `APP_USERNAME`, `APP_PASSWORD` | Dashboard Basic auth; production password must be at least 16 characters |
| `SHOPIFY_STORE_DOMAIN` | Permanent `*.myshopify.com` hostname |
| `SHOPIFY_API_KEY`, `SHOPIFY_API_SECRET` | Current own-store client credentials |
| `SHOPIFY_ACCESS_TOKEN` | Alternative legacy static token |
| `SHOPIFY_API_VERSION` | Explicit Shopify version, default `2026-07` |
| `GEMINI_API_KEY`, `GEMINI_MODEL` | Optional Gemini integration |
| `SOLID_QUEUE_IN_PUMA` | Single-component hosting only; do not combine with a worker |

## Deploy the demo

Use **DigitalOcean App Platform** for the simplest hosted demo. The included
`.do/app.yaml` creates a pre-deploy migration job, one web component, and a
PostgreSQL development database. Solid Queue runs inside Puma to avoid a second
paid component.

The database is provisioned and wired automatically by App Platform; it is not
a separately configured Managed Database. The current expected standing cost is
about $17/month: $10 for the 1 GB web component and $7 for the development
database, plus any overages.

1. Push the repository to GitHub.
2. Replace `GITHUB_OWNER/GITHUB_REPO` in `.do/app.yaml`.
3. Create the app:

   ```bash
   doctl apps create --spec .do/app.yaml
   ```

4. Set encrypted `SECRET_KEY_BASE`, `APP_PASSWORD`, Shopify credentials, and
   optional `GEMINI_API_KEY` in DigitalOcean.
5. Verify `/up`, sign in, confirm automatic pricing is off, sync products, and
   perform one controlled manual run.

The included database is appropriate for a challenge demo, not important
merchant data. Production use needs managed PostgreSQL backups, a dedicated
`bin/jobs` worker, monitoring, alerting, and tested recovery.

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for exact setup and incident steps.

## Technical shape

```text
React + Polaris + TanStack Query
             |
        Rails JSON API
             |
pricing pipeline + Shopify/Gemini clients
             |
PostgreSQL + Solid Queue
```

Rails serves the Vite-built React SPA. Controllers stay thin; pricing rules,
provider clients, immutable values, writes, and reconciliation are separated in
focused service layers. TanStack Query owns server state while form, filter,
pagination, and modal state remain local to components. PostgreSQL provides
decimal money, indexes, audit data, advisory locks, recovery intents, and jobs;
Redis and a separate frontend host are unnecessary for this prototype.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the component and safety
design, and [docs/ENGINEERING-CASE-STUDY.md](docs/ENGINEERING-CASE-STUDY.md) for
the requirements interpretation, alternatives, iteration history, and lessons.

## Verification

```bash
docker compose exec web bundle exec rspec
docker compose exec web bundle exec rubocop
docker compose exec web npm run format:check
docker compose exec web npm run lint
docker compose exec web npm run typecheck
docker compose exec web npm test
docker compose exec web npm run build
docker compose exec web bin/brakeman --no-pager
docker compose exec web bin/bundler-audit
docker build -t dynamic-pricing-assistant:verify .
```

Final audit: 129 RSpec examples and 15 frontend tests passed; RuboCop, ESLint,
TypeScript, Prettier, Vite, Brakeman, bundler-audit, runtime smoke checks, and
the production Docker build also passed. CI runs these non-live gates without
calling Shopify or Gemini. Full evidence is in
[docs/VALIDATION.md](docs/VALIDATION.md).

## Documentation

- [Original challenge](docs/initial/Shopify%20AI%20Dynamic%20Pricing%20Assistant.md)
- [Engineering case study](docs/ENGINEERING-CASE-STUDY.md)
- [Solution architecture](docs/ARCHITECTURE.md)
- [Requirements and validation](docs/VALIDATION.md)
- [DigitalOcean deployment](docs/DEPLOYMENT.md)

## Scope and safety

Automatic pricing changes real Shopify prices without approval. Keep it off
until settings and one manual development-store run are verified. Stop web/jobs
to halt writes at infrastructure level. Shopify is authoritative for live price;
PostgreSQL is authoritative for this application's history and guards.

Not implemented: multi-store OAuth/App Bridge/billing, webhooks, per-product
caps, bulk rollback, preferred schedule time zones, or production-grade identity
and observability. These are documented product boundaries, not hidden claims.
