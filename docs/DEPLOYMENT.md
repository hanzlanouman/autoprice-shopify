# DigitalOcean demo deployment

## Recommendation

Use **DigitalOcean App Platform**, not a Droplet, for this challenge demo.

The application already has a production Dockerfile and App Platform spec. App
Platform builds from GitHub, supplies HTTPS and a public URL, runs the health
check, injects secrets/database bindings, performs the pre-deploy migration, and
retains deployment logs. The demo topology uses:

- one pre-deploy `bin/rails db:prepare` job;
- one web service running Rails, Thruster, and Solid Queue in Puma;
- one PostgreSQL development database.

A Droplet can reduce raw infrastructure cost, but shifts Ubuntu patching, SSH,
firewalling, Docker installation, TLS/reverse proxy, process restart policy,
database persistence/backups, logs, and deploy rollback to the candidate. That
is less simple operationally and adds little evaluation value.

The single-component App Platform topology is for a demo. Move Solid Queue to a
dedicated worker and use managed PostgreSQL backups before business-critical
use.

The spec provisions the development PostgreSQL database automatically; you do
not create or administer a separate Managed Database cluster. At current July
2026 pricing, the 1 GB web component is $10/month and the 512 MB development
database is $7/month. The pre-deploy job is charged only while it runs, making
the expected standing demo cost about $17/month plus any overages.

## Before deploying

1. Push the repository to GitHub.
2. Replace both `GITHUB_OWNER/GITHUB_REPO` placeholders in `.do/app.yaml`.
3. Keep automatic pricing disabled in the existing database.
4. Use only a Shopify development store.
5. Rotate any credential that appeared in a screenshot, transcript, or commit.

## Create the application

Install and authenticate `doctl`, then run:

```bash
doctl apps create --spec .do/app.yaml
```

You can alternatively create an App from the DigitalOcean control panel, select
the GitHub repository, and use `.do/app.yaml` as the specification.

## Required secrets

Set these encrypted values for the components indicated by the spec:

```dotenv
SECRET_KEY_BASE=<output of bin/rails secret>
APP_PASSWORD=<unique value of at least 16 characters>

SHOPIFY_STORE_DOMAIN=your-store.myshopify.com
SHOPIFY_API_KEY=<Dev Dashboard client ID>
SHOPIFY_API_SECRET=<Dev Dashboard client secret>

GEMINI_API_KEY=<optional Google AI Studio key>
```

`APP_USERNAME` defaults to `admin`. Use either Shopify client credentials or a
legacy `SHOPIFY_ACCESS_TOKEN`, never both. `SHOPIFY_API_VERSION` and
`GEMINI_MODEL` have explicit defaults in the spec.

Do not set `DATABASE_URL` manually; the spec binds `${pricing-db.DATABASE_URL}`.
Do not remove `SOLID_QUEUE_IN_PUMA=true` from this demo topology, or manual and
scheduled jobs will remain queued.

## First deployment

App Platform will build the production Dockerfile, run the pre-deploy migration,
then start the service. Verify:

1. the deployment and release job both succeed;
2. `/up` is healthy;
3. the login challenge appears and accepts the configured credentials;
4. Dashboard, History, and Settings render;
5. Settings shows automatic pricing off;
6. **Sync products** loads the development-store catalogue and correct currency;
7. one controlled **Run now** produces the expected Shopify price and history.

Only enable scheduled pricing after the controlled run. Use the one-minute
frequency briefly if the demonstration needs visible background execution, then
return to a normal cadence or disable it.

## Operations

### Stop writes

Turn **Automatic pricing** off first. Manual runs remain intentionally possible,
so do not click **Run now**. If behavior is unsafe, scale the web service to zero
or stop the deployment; in this demo topology the worker runs inside web.

### Diagnose

| Symptom | Check |
|---|---|
| App does not boot | release/web logs, `APP_PASSWORD`, database binding |
| Manual run stays queued | `SOLID_QUEUE_IN_PUMA=true`, web logs, queue tables |
| Shopify 401/403 | permanent myshopify domain, app ownership, released scopes, installed version, rotated secret |
| Gemini unavailable | key restrictions/quota/model; leave fallback off to fail inert or enable labeled fallback |
| Pending reconciliation | leave the service running; the next fresh fetch resolves the intent before another adjustment |
| Raised price remains after restock | restoration is off by default; enable it only if app-owned prices should return to base |

### Data safety

The included App Platform development database is suitable for the challenge
demo, not important merchant history. It has no production backup guarantees.
Before live use, attach a managed PostgreSQL cluster with backups, update the
binding, test restore, add monitoring/alerts, and separate `bin/jobs` into a
worker component.

## Deployment commands

```bash
# Validate the local production image
docker build -t dynamic-pricing-assistant:verify .

# Create from the specification
doctl apps create --spec .do/app.yaml

# Later, after editing the spec
doctl apps update <app-id> --spec .do/app.yaml
```

The platform URL is sufficient for a demo; a custom domain is optional.
