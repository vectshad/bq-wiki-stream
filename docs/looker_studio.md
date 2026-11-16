# Data Studio dashboard spec

Data Studio was called Looker Studio until April 2026. Free tier only: standard Data Studio (https://lookerstudio.google.com). Do not upgrade to Data Studio Pro.
Build time: about 20 minutes. Do this after the scheduled pipeline has run a few times, so the charts have data.

## Data sources (Create > Data source > BigQuery > bq-stream-514812 > marts)

| Data source | Used for |
|---|---|
| `mart_pipeline_health` | freshness and volume scorecards |
| `mart_edits_per_hour` | hourly trend |
| `mart_top_pages_24h` | most edited articles |
| `mart_edit_sizes_24h` | edit size distribution |

For each source: **Data freshness = 15 minutes** (the lowest option; the pipeline refreshes every 15 minutes) and
**Owner's credentials**, so viewers need no BigQuery access. The tables are replaced in place on every run, so the
table names (and the report) keep working.

## Page 1: Live (single page)

| # | Chart | Data source | Dimension | Metric(s) | Notes |
|---|---|---|---|---|---|
| 1 | Scorecard "Minutes since last event" | `mart_pipeline_health` | - | `minutes_since_latest_event` | Value as of the last build. Show `computed_at` in a small text field next to it |
| 2 | Scorecard "Edits, last hour" | `mart_pipeline_health` | - | `events_last_hour` | |
| 3 | Scorecard "Edits, last 24 h" | `mart_pipeline_health` | - | `events_last_24h` | |
| 4 | Stacked column "Edits per hour by editor type" | `mart_edits_per_hour` | `event_hour` | `bot_edits`, `anonymous_edits`, `registered_edits` | Sort by `event_hour` ascending. The newest hour is partial |
| 5 | Scorecard "Bot share" | `mart_edits_per_hour` | - | calculated field `SUM(bot_edits) / SUM(edits)` | A ratio of sums is correct across hours. Never average per-hour shares |
| 6 | Time series "Bytes added vs removed" | `mart_edits_per_hour` | `event_hour` | `bytes_added`, `bytes_removed` | |
| 7 | Bar "Most edited articles, last 24 h" | `mart_top_pages_24h` | `title` | `edits` | Top 15 rows, sort descending |
| 8 | Stacked bar "Edit sizes by editor type" | `mart_edit_sizes_24h` | `size_bucket` | `edits`, breakdown dimension `editor_type` | Sort by `bucket_order` ascending |

Add a text box: "Data: Wikimedia EventStreams (English Wikipedia edits), CC BY-SA. No editor names are stored."

## Things to know
- The bot share swings a lot (about 7% on a Sunday sample, 44% on a Monday morning), so do not put a fixed number in any title.
- The first hours after a fresh start are short, so the hourly chart begins with a partial bucket.
- If the pipeline stops, scorecard 1 keeps growing only when dbt runs, so read it with `computed_at`; the daily check also fails on stale source data.

## Share
Share > Manage access > **Anyone with the link can view**. Save two screenshots to `docs/img/` and add the report link to the README.
