# Project: Wikipedia edits, near-real-time (BigQuery sandbox + dbt)

GCP project `bq-stream-514812` (BigQuery sandbox, **no billing**), location `US`.
Source: Wikimedia `recentchange` SSE stream, filtered to enwiki edit + new-page events.
Flow: collector (load job every 15 min) -> `raw` -> `staging` (view) -> `marts` (tables) -> Looker Studio.
Read `docs/decisions.md` before changing the filter, budget or materializations.

## Commands
- dbt: `uv run dbt <cmd> --project-dir dbt --profiles-dir dbt`
- Python is pinned to 3.12.
- Run `bq` from **bash with stdin closed** (`bq ... < /dev/null`): in PowerShell it hung once, probably on a prompt.
  Always pass `--project_id=bq-stream-514812` (the global gcloud default belongs to another project; do not change it).

## Rules
- Cost: dry-run first and always set `--maximum_bytes_billed` (1 GB). dbt caps it in `dbt/profiles.yml`.
- Auth is ADC. Never create or commit service account keys or `.env`.
- Ask before: linking billing, enabling APIs, creating/deleting projects, deleting data.
- Keep every dataset in `US`. Keep commits small.

## Gotchas
- Sandbox: no streaming inserts, **no DML** (no dbt incremental or snapshots), tables expire after 60 days, storage is a 10 GiB **lifetime** budget (deleting does not refund it).
- Avoid rewriting big tables; staging is a view for that reason.
- Raw is a typed subset of the event, not the full JSON. Do not store the `user` field in clear (anonymous edits are IP addresses).
- Delete throwaway test objects once the test is done.
