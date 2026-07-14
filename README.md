# Shopify AI Dynamic Pricing Assistant

A submission for the MGLogics practical challenge: a single-store dynamic
pricing system built with Ruby on Rails, React, Shopify Polaris, PostgreSQL,
Shopify Admin GraphQL, and Google Gemini.

The application synchronizes Shopify products and variants, evaluates
inventory-sensitive pricing rules, writes valid prices automatically, and
provides a clear dashboard and audit history. Gemini can recommend prices, but
deterministic server-side rules remain the authority for every Shopify write.

## Solution coverage

| Challenge requirement | Implementation |
|---|---|
| Fetch product title, ID, price, inventory, type, and vendor | Cursor-paginated Shopify GraphQL synchronization and local cache |
| Automatically update prices | Manual and scheduled Solid Queue jobs use Shopify bulk variant updates |
| Inventory threshold | Persisted setting evaluated before recommendation |
| Maximum allowed price | Global percentage computes a separate ceiling from each variant's base price |
| Hourly, daily, weekly, and monthly execution | Persisted due time checked by the recurring scheduler; minute cadence is included for demonstration |
| Optional AI behavior prompt | Length-limited merchant instructions are included in the structured Gemini request |
| Never exceed maximum or recommend below current | Shared Ruby bounds and validator run before every write |
| Safely ignore malformed AI output | Structured schema, parsing, validation, classified retries, safe skip, and optional labeled fallback |
| Read-only monitoring dashboard | Product, inventory, base/current price, latest change, source, outcome, reason, and run status |
| Price history | Append-only searchable outcomes with old/new price, inventory, timestamp, source, and explanation |

The original challenge is preserved unchanged in
[`docs/initial`](docs/initial/Shopify%20AI%20Dynamic%20Pricing%20Assistant.md).

## Key engineering decisions

- **AI advises; deterministic code authorizes.** Model output is untrusted and
  revalidated immediately before an external write.
- **The maximum is percentage-based.** The challenge's `100 → 150` example is
  represented by a default maximum of 150% of base, which also scales correctly
  for products priced at 800, 1,000, or any other value.
- **Shopify is authoritative for live price.** A final price read prevents a
  concurrent merchant edit from being overwritten.
- **External writes are recoverable.** A durable intent is stored before the
  Shopify mutation and reconciled if the remote result is ambiguous.
- **Scheduled runs cannot ratchet a stable product.** A previously adjusted
  variant requires a further inventory drop before another increase.
- **Price restoration is explicit.** Recommendations remain increase-only as
  required. An off-by-default system option may restore only an app-owned price
  to base after inventory recovers; merchant edits always win.
- **One database is sufficient.** PostgreSQL stores application data, audit
  history, locks, recovery intents, and Solid Queue jobs without Redis.

## Pricing behavior

Each active, inventory-tracked, non-gift-card variant is considered when:

```text
0 < inventory <= inventory threshold
```

Accepted recommendations must satisfy:

```text
floor   = live current Shopify price
ceiling = stored base price × maximum percentage / 100

floor <= recommendation <= ceiling
```

Sold-out, untracked, gift-card, at-ceiling, and guard-blocked variants are
excluded before Gemini. Invalid recommendations are rejected rather than
silently clamped.

When Gemini is unavailable, the merchant may enable a deterministic fallback:

```text
scarcity = clamp((threshold - inventory + 1) / (threshold + 1), 0, 1)
target   = base + (ceiling - base) × scarcity
```

The formula is anchored to base price, so repeated runs at the same inventory
produce the same target instead of compounding. Its source is always displayed
as **Fallback formula**.

## Architecture

```text
React 18 + Shopify Polaris + TanStack Query
                       |
                 Rails JSON API
                       |
     pricing rules, provider clients, reconciliation
                  /                 \
     Shopify Admin GraphQL       Gemini API
                       |
             PostgreSQL + Solid Queue
```

Rails serves the Vite-built React application. Controllers remain thin;
provider communication, eligibility, bounds, recommendation, validation,
application, reconciliation, and history are separated into focused services.
TanStack Query owns remote state and cancellation, while form, filter,
pagination, and modal state remain local to React components.

## Run locally

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

Open <http://localhost:3000>. With Shopify and Gemini credentials blank, the
application uses the seeded local store and deterministic recommender.

Suggested evaluation flow:

1. Open **Settings** and review the threshold and maximum percentage.
2. Keep automatic pricing off and select **Run now**.
3. Review base price, current price, latest change, source, outcome, and reason.
4. Open variant details and search/sort **Price History**.
5. Run again without reducing inventory to demonstrate repeat-adjustment
   protection.

## Connect a Shopify development store

Create and release an app in Shopify's Dev Dashboard for the same organization
as the development store. Required Admin API scopes are:

- `read_products`
- `write_products`
- `read_inventory`

The optional `demo:seed_shopify` task additionally needs `read_locations` and
`write_inventory`. Install the released app and configure `.env`:

```dotenv
SHOPIFY_STORE_DOMAIN=store-name.myshopify.com
SHOPIFY_API_KEY=<client-id>
SHOPIFY_API_SECRET=<client-secret>
SHOPIFY_ACCESS_TOKEN=

GEMINI_API_KEY=<optional-key>
GEMINI_MODEL=gemini-3.5-flash
```

Restart the services and verify the connection:

```bash
docker compose up -d --force-recreate web worker
docker compose exec web bin/rails runner "puts Shopify::Client.new.fetch_shop_currency"
```

The control panel is hosted by this application, not embedded in Shopify Admin.
Installing the Shopify app grants Admin API access; operators use the local or
deployed application URL for Dashboard, History, and Settings.

## Deploy to DigitalOcean App Platform

The included `.do/app.yaml` defines a demonstration deployment in Bangalore:

- one pre-deploy `bin/rails db:prepare` job;
- one 1 GB web service;
- one automatically provisioned PostgreSQL development database;
- Solid Queue inside Puma, avoiding a second worker component;
- `/up` health checks and encrypted runtime configuration.

Create it with:

```bash
doctl apps create --spec .do/app.yaml
```

Required encrypted values are `SECRET_KEY_BASE`, `APP_PASSWORD`, Shopify
credentials, and optionally `GEMINI_API_KEY`. `APP_PASSWORD` must contain at
least 16 characters. The database reference is already bound to
`${pricing-db.DATABASE_PRIVATE_URL}`; do not paste a database URL manually.

After deployment, verify `/up`, sign in, confirm automatic pricing is off, sync
the development-store catalogue, and complete one controlled manual run before
enabling scheduling.

This App Platform configuration is appropriate for a challenge demonstration.
Business-critical use would require managed database backups, a dedicated job
worker, monitoring, alerting, and tested recovery.

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

Final audit results:

- 129 RSpec examples passed;
- 15 Vitest/Testing Library tests passed;
- RuboCop, ESLint, TypeScript, and Prettier passed;
- Brakeman reported zero warnings;
- bundler-audit reported no known vulnerable gems;
- Vite and the production Docker image built successfully;
- health, SPA, settings, and product API smoke checks passed.

GitHub Actions repeats the non-live lint, test, security, asset, and production
image gates without calling Shopify or Gemini.

## Repository structure

```text
app/clients/              Shopify and Gemini adapters
app/services/pricing/     Pricing pipeline and safety rules
app/controllers/api/v1/   Versioned JSON API
app/jobs/                 Pricing execution and scheduler
app/frontend/             React, Polaris, queries, and tests
db/migrate/               Application and Solid Queue schema
docs/initial/             Original challenge document
.do/app.yaml              DigitalOcean demonstration topology
```

## Scope

This is a private, single-store engineered prototype. Multi-store OAuth,
Shopify App Bridge embedding, billing, webhooks, user roles, per-product caps,
bulk rollback, preferred schedule time zones, and production observability are
outside the challenge scope and are not represented as completed features.
