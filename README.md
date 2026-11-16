# Wikipedia edits, near-real-time: BigQuery sandbox + dbt

An end-to-end pipeline on the **free BigQuery sandbox** (no billing account): English Wikipedia edits
are collected from the Wikimedia live stream, landed in BigQuery every 15 minutes, modelled with dbt
and shown in a Looker Studio dashboard.

```
Wikimedia SSE ──► collector (load job / 15 min) ──► raw ──► staging (view) ──► marts ──► Looker Studio
```

**Why micro-batch and not streaming:** the sandbox does not support streaming inserts or DML.
Load jobs work and are free, so the collector appends a small file every 15 minutes (latency ~15 min).
See [docs/decisions.md](docs/decisions.md) for the measurements and trade-offs.

| Stage | Status |
|---|---|
| Feasibility (load + append in sandbox, stream volume) | done |
| Repo and dbt scaffold | done |
| Collector (`collector/collect.py`, 9 tests, dry-run verified on the live stream) | done, first load pending |
| dbt models and tests | planned |
| Looker Studio dashboard | planned |
| Scheduled run on GitHub Actions (keyless, Workload Identity Federation) | planned |

## Setup

```bash
gcloud auth application-default login
uv sync
bq --project_id=bq-stream-514812 query --use_legacy_sql=false --location=US \
   --maximum_bytes_billed=1000000000 "$(grep -v '^--' scripts/bootstrap.sql)" < /dev/null
```

## Data

Edit events from the [Wikimedia EventStreams](https://wikitech.wikimedia.org/wiki/Event_Platform/EventStreams_HTTP_Service)
`recentchange` stream. Wikimedia content is available under CC BY-SA; see the Wikimedia Terms of Use.
