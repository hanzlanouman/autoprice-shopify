# Solution architecture

## System shape

```text
Browser
  React 18 + Polaris + TanStack Query
                   |
                   | same-origin JSON + CSRF
                   v
Rails 8.1 web process -------------------------+
  API controllers                              |
  pricing services                             |
  Shopify/Gemini clients                       |
                   |                           |
                   +--> Shopify Admin GraphQL  |
                   +--> Gemini generateContent |
                                               |
Solid Queue scheduler/workers -----------------+
                   |
                   v
PostgreSQL
  products, settings, runs, changes, write intents, queue tables
```

React is compiled by Vite and served by Rails; it is not a separate hosted
application. Shopify and Gemini calls are outbound. One PostgreSQL database
holds both domain and Solid Queue data.

## Pricing flow

```text
fetch Shopify
  -> reconcile pending writes
  -> cache/rebase external edits
  -> deterministic eligibility
  -> Gemini or fallback recommendation
  -> deterministic validation
  -> live-price preflight
  -> durable intent
  -> Shopify mutation
  -> transactional finalization and history
  -> run summary
```

`Pricing::Bounds` is the single source of truth for the floor, base, ceiling,
and increase eligibility. It is consumed by the dashboard serializer, Gemini
prompt, fallback, and post-response validator.

## Backend organization

| Area | Responsibility |
|---|---|
| `app/clients/shopify` | GraphQL reads/writes, authentication, pagination, throttling, provider errors |
| `app/clients/gemini` | Structured requests, retries, parsing boundary |
| `app/services/pricing` | Fetch, eligibility, bounds, recommendation, validation, apply, reconciliation, history |
| `app/services/value` | Immutable values passed between pipeline stages |
| `app/jobs` | Manual pricing execution and persisted due-time scheduler tick |
| `app/controllers/api/v1` | Thin versioned transport layer and consistent errors |
| `app/serializers` | Stable decimal-string JSON contracts and presentation fields |

Models own persistence constraints and small state transitions; orchestration
does not live in controllers or callbacks. Money uses decimal/`BigDecimal`, not
binary floating point.

## Data model

- `settings`: one concurrency-safe policy row, including switches and next due
  time;
- `products`: Shopify metadata plus variant snapshots and adjustment guards;
- `pricing_runs`: trigger, lifecycle, settings/statistics snapshot, and errors;
- `price_changes`: append-only material audit decisions;
- `price_write_intents`: pre-write recovery records for ambiguous Shopify
  outcomes;
- `solid_queue_*`: durable jobs and recurring schedule state.

PostgreSQL partial/unique indexes reinforce singleton settings, one running
pricing run, and one decision per run/variant. Advisory locks protect execution
across processes.

## Provider boundaries

### Shopify

The client supports own-organization Dev Dashboard client credentials and
existing static Admin API tokens. Product and variant connections are fully
cursor-paginated. Shopify remains authoritative for current price; a preflight
read cancels a stale write, and a price not owned by this application becomes
the new base.

### Gemini

Gemini receives only pre-eligible variants and an explicit response schema.
Merchant instructions are delimited, length-limited guidance, not authority to
change hard rules. Failures are classified, retried only when transient, and
either skipped safely or filled by the merchant-enabled fallback.

## Frontend organization

- route-level lazy loading keeps Dashboard, History, and Settings in separate
  chunks;
- TanStack Query owns remote cache, cancellation, polling, pagination, and
  invalidation;
- local React state owns form drafts, filters, pagination, and modal state;
- one typed fetch wrapper handles CSRF, credentials, JSON parsing, cancellation,
  and the shared error envelope;
- formatting and reason translation are centralized;
- the large catalogue table is memoized and isolates horizontal overflow;
- Polaris supplies semantic forms, tables, navigation, status text, and modal
  focus behavior.

No global client-state library is needed because there is no complex shared
client state. Server state is not copied into another store.

## Scheduling and deployment topology

Solid Queue invokes `SchedulerTickJob` every minute. It compares the database
clock with `next_run_at` and only enqueues a due run. Hourly, daily, weekly, and
monthly behavior is therefore persisted policy rather than separate cron
definitions. The demo-only minute frequency makes automation observable.

Local Docker Compose runs separate web and worker containers. The DigitalOcean
demo spec deliberately runs Solid Queue in the single Puma web component to
minimize hosted components. A dedicated worker is the upgrade path when web
restarts must not pause jobs or workload becomes business-critical.

## Security and failure posture

- production refuses to boot without a dashboard password of at least 16
  characters;
- HTTPS is forced behind the platform proxy, excluding `/up` health checks;
- CSRF protects mutations and provider credentials remain server-side;
- tests blank provider environment values and block unstubbed external HTTP;
- model output is untrusted and revalidated immediately before writes;
- scheduled writes re-check the auto-pricing kill switch;
- pending intents reconcile before a variant can be adjusted again;
- audit history cannot be updated or destroyed through normal Active Record
  operations.

## Scope boundary

This is a private single-store control plane, not an embedded Shopify App Store
application. Public distribution requires OAuth/token exchange for unrelated
shops, tenant-scoped settings/locks/currency/data, proper user identity, billing,
webhook lifecycle handling, and compliance work.
