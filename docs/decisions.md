# Decisions, findings and cost notes

## Sandbox facts (BigQuery sandbox, no billing; project `bq-stream-514812`, location US)

Source: <https://docs.cloud.google.com/bigquery/docs/sandbox> and the quotas page.

| Capability | Status |
|---|---|
| Streaming inserts / Storage Write API | **Not supported** |
| DML (INSERT / UPDATE / MERGE) | **Not supported** -> no dbt `incremental`, no snapshots |
| Load jobs, including append | **Works** (tested 2026-11-15: one create + one append, no billing) |
| Tables and partitions | Expire after 60 days |
| Storage | 10 GiB **lifetime**, "not refunded upon data deletion" (read from the docs; how table rewrites count is unverified) |
| Queries | 1 TiB / month |
| Load jobs per table per day | 1,500 |
| Pub/Sub | Skipped: unclear without a billing account |

## Source: Wikimedia EventStreams `recentchange`

`https://stream.wikimedia.org/v2/stream/recentchange` (SSE, no key). Supports replay with `since=`
(7-31 days of history) and `Last-Event-ID`; the server closes connections after ~15 minutes.
Data is CC BY-SA: keep the attribution in the README.

Measured 2026-11-15 (Sunday, ~12:30 UTC), 15 minutes, 28,379 events, 36 MB raw JSON:

| Filter | Events/s | Rows/day | ~MB/day in BigQuery |
|---|---|---|---|
| Everything | 31.5 | 2.7M | 440 |
| Edit + new, all wikis | 19.4 | 1.7M | 255 |
| Edit + new, excluding wikidata and commons | 8.0 | 692k | 103 |
| enwiki, all types | 2.4 | 207k | 32 |
| **enwiki, edit + new (chosen)** | **1.26** | **109k** | **16** |

Row size is an estimate (~150 B for ~12 typed fields); a single 15-minute sample, so budget 2x.
The first 10-second sample suggested enwiki was 13% of events; the 15-minute figure is 7.6%.

## Decisions

### D1. Micro-batch, not streaming
No streaming API in the sandbox, so a collector appends events with a load job every 15 minutes
(96/day vs the 1,500/day limit). Latency is ~15 minutes. True streaming (Pub/Sub or the Write API)
needs a billing account and is out of scope.

### D2. English Wikipedia, edit + new page, bot flag kept
~16 MB/day measured. The other filters would exhaust the lifetime storage budget within
~100 days. Keeping `bot` allows a bot-vs-human share chart (~7% of edits).

### D3. At-least-once delivery, dedupe downstream
The collector checkpoints on `MAX(event_ts)` in raw (no external state), re-reads a small overlap
and relies on staging to dedupe by event id. Same lesson as the replayed events in the video-games project.

### D4. Raw keeps ~12 typed fields, not the full event
A full event is ~1.5 KB; at 109k rows/day that is ~160 MB/day. Raw is therefore a typed subset, NOT an untouched copy.

### D5. Privacy
The `user` field holds IP addresses for anonymous edits, which are personal data. The user name is not
stored at all; raw keeps only `is_anon` (IP address or temporary account) so marts can still show
anonymous vs registered editing. The collector test checks that no user name reaches a row.

### D6. Staging is a view, marts are tables rebuilt every 15 minutes over a 48-hour window
Views cost no storage. Without DML there are no incremental models, so marts are rebuilt in full,
but over a 48-hour window of a day-partitioned raw table so each build scans at most ~50 MB.
Time partitioning is safe here (unlike the old project) because the data is recent, never older than 60 days.

### D7. Storage guard
The collector stops loading when `raw` exceeds 3 GiB.

### D8. How the collector knows it has caught up (found by testing the replay)
A `since=` replay is not a clean ordered feed: it opens with a few out-of-order events (stale ones and
heartbeats with no wiki or type), and this PC's clock was ~40 s off the event times. So the collector
(a) takes "now" from the server's `Date` header, and (b) stops only after 25 consecutive events at or
after "now - 5 s". A first version that stopped at the first recent event read 0 rows.
A 5-minute replay of enwiki edit + new returned 583 rows (1.8/s, Monday morning UTC) vs 1.26/s measured on a Sunday.

### D9. Scheduled run: GitHub Actions with Workload Identity Federation
- `pipeline.yml` runs every 15 minutes: collector, then `dbt build --select marts`. `daily-checks.yml` runs
  source freshness and the staging tests once a day.
- **Keyless.** GitHub's OIDC token is exchanged for a short-lived Google token; no service account key exists.
  The provider only trusts `vectshad/bq-wiki-stream` on `refs/heads/main`, so a fork or another branch cannot
  get a token. The service account has `bigquery.jobUser` and `bigquery.dataEditor` on this sandbox project only.
  Setup and teardown are scripts (`scripts/setup_wif.sh`, `teardown_wif.sh`); the two repository variables it sets are identifiers, not secrets.
- **The staging tests are not in the 15-minute run.** Staging is a view over a 3-day window; each of its 9 tests
  would rescan it. Marts-only builds scan roughly 4 x 30 MB at steady state (about 350 GB/month, ~34% of the free
  1 TiB). Measure the real figure from `INFORMATION_SCHEMA.JOBS_BY_PROJECT` after a few days and adjust the cadence.
- Jobs are skipped (not failed) until the repository variables exist.
- Public repository: scheduled workflows are disabled after 60 days without repository activity.
- **Sandbox expiry (verified 2026-11-17):** views and non-partitioned tables expire 60 days after creation. Marts are
  recreated every run and the staging view daily, so they renew themselves. `raw.wiki_edits` is day-partitioned and has
  NO table-level expiry: only each partition expires, 60 days after its date, so history is a rolling 60-day window.
- **GitHub schedule reliability (measured 2026-11-16/17):** in 19 hours only 2 scheduled runs started (expected ~76),
  6.7 hours apart. GitHub delays or drops scheduled runs under load and does so more for low-activity repos. Data
  completeness is not affected (the collector replays from the last loaded event: 0 gaps over 60 s in 184k events), but
  freshness is: the dashboard can be hours behind. Manual `workflow_dispatch` runs always start immediately.

### First real load (2026-11-16, Monday ~08:30 UTC)
- 60-minute bootstrap: 7,896 rows in one load job, every event id distinct, every 10-minute bucket filled.
- Real row size is **125 B** (estimate was ~150). Volume was 2.2 events/s, i.e. ~24 MB/day.
- Bot share was **44%** this hour vs ~7% in the Sunday sample: do not hard-code a bot share anywhere.
- Second run resumed at `MAX(event_ts) - 2 min`, loaded 624 rows, 274 of them duplicates of the overlap
  (276 events lie in the overlap). After dedupe: 8,246 distinct events, largest gap between events 5 s.

## Cost estimate (to be re-measured after the first real load)

- Storage: ~16-50 MB/day -> 1-3 GB per 60 days of the 10 GiB lifetime budget.
- Queries: marts scan <= ~50 MB per build x 96 builds/day <= ~4.8 GB/day <= ~144 GB/month (~14% of 1 TiB).
- GitHub Actions: free on a public repo (~100 runs/day); a private repo would exceed 2,000 free minutes.
