# Engineering case study

## Challenge and working approach

The assignment was intentionally small but safety-sensitive: read Shopify
inventory, ask an LLM for scarcity-sensitive prices, enforce merchant rules,
write accepted prices automatically, and retain an explainable history.

The work was approached as an evolving prototype rather than a UI-first demo:

1. translate the brief into testable functional and non-functional rules;
2. identify ambiguities before encoding business behavior;
3. establish deterministic safety boundaries around AI and external writes;
4. implement the pipeline in vertical slices;
5. exercise it with a credential-free simulator before live Shopify access;
6. improve the operator experience after the end-to-end path worked;
7. audit the result against the original document and harden failure paths;
8. package the same application for repeatable local and hosted demos.

The original brief is preserved verbatim in
[`docs/initial`](initial/Shopify%20AI%20Dynamic%20Pricing%20Assistant.md).

## Requirements interpretation

### Maximum price

The example `current price 100, maximum 150` was ambiguous as a global setting.
An absolute store-wide value would be meaningless for a catalogue containing
both inexpensive and expensive products. The implementation interprets it as
**150% of the product variant's base price**:

| Base | Global setting | Variant maximum |
|---:|---:|---:|
| 100 | 150% | 150 |
| 800 | 150% | 1,200 |
| 1,000 | 150% | 1,500 |

This retains the example, scales to new products, and keeps one understandable
merchant policy. Per-product overrides were considered but left out because no
requirement established how exceptions should be managed.

### Price decreases and restocking

The brief says a recommendation must not be below the current price. Therefore
AI and fallback recommendations are increase-only. During review, true dynamic
recovery was still useful, so restoration was added as a separate deterministic
policy:

- off by default, preserving the assignment;
- only restores a price previously written by this application;
- returns to the stored base, never below it;
- only runs after inventory rises above the threshold;
- refuses to overwrite a merchant or third-party price edit;
- recorded as `system / restore`, never presented as AI.

### Eligibility

The numeric rule is `inventory <= threshold`, but blindly processing every such
variant produces poor behavior. The following deterministic exclusions happen
before an LLM request:

- inventory is not tracked;
- inventory is zero or negative;
- product is a gift card;
- current price is already at its ceiling;
- the application already adjusted the variant and inventory has not fallen
  further.

This avoids model spend on ineligible items and prevents scheduled runs from
ratcheting a stable low-stock product to its maximum.

## Design decisions and alternatives

| Decision | Alternatives considered | Why this choice |
|---|---|---|
| Price variants independently | First/default variant only | Shopify price and inventory live at variant level |
| LLM advises; Ruby authorizes | Trust structured model output | Automatic writes must remain correct if AI is wrong |
| One `Pricing::Bounds` implementation | Repeat bounds in prompt/UI/validator | Prevents displayed, requested, and enforced limits drifting |
| Reject invalid output | Clamp it to a valid range | Preserves the real failure and raw proposal in the audit trail |
| Shopify remains live source of truth | Trust cached prices | Protects concurrent merchant edits |
| Durable write intents | Write then record history | Handles the ambiguous gap between remote success and local commit |
| PostgreSQL + Solid Queue | Redis/Sidekiq or several Rails databases | One durable datastore is sufficient at prototype scale |
| Small service objects and immutable values | Fat models or an interactor framework | Explicit dependencies and focused tests without another abstraction |
| Hand-written Faraday adapters | Large provider SDKs | Authentication, retry, parsing, and error behavior remain visible |
| Standalone single-store control plane | Embedded multi-store Shopify app | Matches the supplied credential model and two-week scope |
| Cursor pagination | Whole-catalog response or Bulk Operations | Simple, correct, and sufficient for a prototype catalogue |
| HTTP Basic operator access | Full user/account system | Proportionate for one private demo operator; not a public-product design |

## Implementation journey

### 1. Foundation

Rails, PostgreSQL, RSpec, React, Polaris, Vite, TypeScript, Docker Compose,
consistent JSON errors, CSRF protection, and production fail-closed Basic
authentication established the application boundary.

### 2. Shopify read path

The first usable vertical slice fetched products and variants and cached them
for the dashboard. Hardening added independent variant pagination, stale-product
marking only after a complete successful sync, cost-aware throttling, store
currency, current client-credentials exchange, and legacy static-token support.

### 3. Rules before AI

The settings singleton, threshold eligibility, percentage ceiling, sold-out and
gift-card exclusions, re-adjustment guard, and external-edit rebasing were built
before Gemini. This made the safety behavior independently testable.

### 4. Writes, audit, and recovery

Price application re-reads live Shopify prices immediately before mutation.
A durable intent is stored before the remote call. Confirmed writes finalize
cache guard state, history, and intent together. If the response is lost, the
next fresh fetch reconciles live price against expected-old and target values.

This replaced an earlier, weaker assumption that a later sync alone was enough.
It is the most important reliability improvement made during review.

### 5. Gemini and deterministic fallback

Gemini receives only eligible variants with server-computed floor and ceiling.
It returns a structured schema in bounded chunks. Parsing, precision, duplicate
IDs, missing IDs, unknown IDs, timeouts, rate limits, and transient failures are
handled explicitly. Every parsed value is validated again by Ruby.

The fallback implements the same recommender interface and is base-anchored:

```text
scarcity = clamp((threshold - inventory + 1) / (threshold + 1), 0, 1)
target   = base + (ceiling - base) * scarcity
result   = max(current_price, round(target, 2))
```

The same inventory always produces the same target, so it does not compound
from the last raised price. Its source is visibly labeled `Fallback formula`.

### 6. Automation and operator experience

Manual and scheduled runs use the same job and pipeline. A one-minute scheduler
tick checks persisted `next_run_at`; it does not mean every product is repriced
each minute. PostgreSQL advisory locking and a unique running-row constraint
prevent overlap.

The dashboard evolved after live use exposed clarity issues. The final table
uses separate base price, current price, latest delta, source, outcome,
explanation, and activity columns. Exact old/new/proposed values remain in
tooltips, variant details, and searchable history instead of overwhelming the
main table. Eligibility was removed from the table because an immediately
applied decision made that snapshot misleading.

### 7. Final audit and packaging

The final audit aligned development jobs with production Solid Queue semantics,
made pricing history append-only through Active Record, added request
cancellation and bounded frontend caching, memoized the large catalogue table,
validated deployment YAML, and built the real production Docker image.

## Current result

The prototype fulfills the requested Shopify read/write, settings, scheduled
automation, AI behavior, deterministic validation, monitoring, and history
flows. It can run entirely locally without provider keys, connect to a Shopify
development store, or deploy through the included DigitalOcean App Platform
specification.

## Accepted limits and next steps

These are intentionally not presented as completed features:

- public Shopify distribution, OAuth, App Bridge, billing, GDPR webhooks, and
  multi-store tenancy;
- webhook-triggered real-time inventory updates;
- per-product maximum overrides and preferred schedule time zones;
- Shopify Bulk Operations for very large catalogues;
- relational variant analytics beyond the current product JSON document;
- identity roles, error tracking, metrics, scheduler alerts, and audit export;
- operator preview/bulk rollback with live-price conflict protection.

Triggers for revisiting these choices are concrete: multiple merchants require
tenant-scoped OAuth and data; catalogue syncs lasting minutes require Bulk
Operations; JSON row contention requires a variants table; business-critical
use requires managed backups, alerting, and a dedicated job worker.

## Reflection

The challenge was less about inventing a sophisticated pricing model and more
about safely connecting uncertain recommendations to consequential writes. The
solution therefore invests most heavily in deterministic bounds, current-state
checks, idempotency, reconciliation, transparent sources, and auditability. The
LLM improves judgment and explanation, but the application remains functional
and safe without it.
