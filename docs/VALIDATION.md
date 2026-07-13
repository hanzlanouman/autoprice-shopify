# Requirements and validation

## Traceability

| Original requirement | Implementation evidence |
|---|---|
| Fetch title, product ID, current price, inventory, type, vendor | Paginated Shopify GraphQL client and cached dashboard catalogue |
| Update prices automatically | Scheduled/manual `PricingRunJob` and Shopify bulk variant mutation |
| Inventory threshold | Singleton setting and deterministic eligibility before recommendation |
| Maximum allowed price | Global percentage computes a base-relative ceiling for every variant |
| Hourly/daily/weekly/monthly | Persisted due time checked by one-minute Solid Queue tick; minute also available for demo |
| Optional AI behavior | Length-limited merchant prompt included in the structured Gemini request |
| Never above maximum | Shared bounds and post-response validator reject `exceeds_max` |
| Never below current | AI and fallback floor is the live current price; restoration is a separate opt-in system action |
| Only threshold products | Ineligible variants do not reach Gemini/fallback |
| Malformed AI ignored safely | Schema, parsing, per-item validation, classified retries, skip or labeled fallback |
| Read-only monitoring dashboard | Inventory, base/current price, latest change/proposal, source, outcome, reason, run health |
| Store updates locally | Successful remote writes finalize cache guards, intents, and history transactionally |
| Price history | Searchable append-only outcomes with product, prices, inventory, time, source, action, reason |
| Required stack and delivery | Rails, React/Polaris, PostgreSQL, Gemini, Shopify, Docker, README, `.env.example` |

## Automated evidence

Final verification on 13 July 2026:

| Gate | Result |
|---|---|
| RSpec | 129 examples, 0 failures |
| Vitest/Testing Library/MSW | 15 tests, 0 failures |
| RuboCop | 107 files, 0 offenses |
| ESLint | no errors or warnings |
| TypeScript | passed |
| Prettier | passed |
| Vite production build | passed |
| Production Docker image | built successfully |
| Brakeman | 0 security warnings |
| bundler-audit | no known vulnerable gems |
| Compose and DigitalOcean YAML | valid |
| Runtime smoke | health, SPA, settings, and products endpoints returned successfully |

CI repeats Ruby security/style and backend tests plus frontend format, lint,
types, behavior tests, production assets, and a production Docker image build.
Provider calls are stubbed; CI cannot mutate Shopify or consume Gemini quota.

## High-risk cases covered

- inventory and exact threshold boundaries;
- base-relative maximum across heterogeneous product prices;
- below-current, above-maximum, malformed, duplicate, unknown, and missing AI
  recommendations;
- deterministic fallback monotonicity and non-compounding behavior;
- repeated runs, further inventory drops, restock restoration, and merchant
  edits;
- full product/variant pagination and Shopify throttle behavior;
- transient provider failures and authentication failures;
- current-price conflict immediately before mutation;
- ambiguous Shopify response and durable intent reconciliation;
- overlapping manual/scheduled runs and stale-run cleanup;
- API validation/error envelopes and dashboard/history/settings interactions.

## Manual demo acceptance

1. Start with automatic pricing off.
2. Sync a disposable development store and confirm currency/products.
3. Record one variant's base/current price, inventory, threshold, and ceiling.
4. Run manually and compare Shopify, dashboard outcome, source, explanation, and
   history.
5. Run again without an inventory drop and confirm the guard prevents ratcheting.
6. Exercise one invalid/unavailable AI path and confirm no unsafe write.
7. Enable the minute frequency only for a short background-job demonstration.
8. Turn automation off again before handoff.

## Remaining validation boundary

Automated tests cannot prove external credentials, Shopify installation scopes,
provider quotas, platform proxy behavior, or a live merchant's catalogue shape.
Those must be checked against a disposable development store and the deployed
platform. A browser-driven visual regression suite and production observability
are appropriate next investments, not silently claimed as complete here.
