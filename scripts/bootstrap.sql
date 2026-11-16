-- Datasets and the raw table for the streaming project. Idempotent. Location US (keep every dataset in one location).
-- Run (bash, stdin closed so bq cannot block on a prompt):
--   bq --project_id=bq-stream-514812 query --use_legacy_sql=false --location=US --maximum_bytes_billed=1000000000 "$(grep -v '^--' scripts/bootstrap.sql)" < /dev/null
CREATE SCHEMA IF NOT EXISTS `bq-stream-514812.raw`     OPTIONS (location = 'US');
CREATE SCHEMA IF NOT EXISTS `bq-stream-514812.staging` OPTIONS (location = 'US');
CREATE SCHEMA IF NOT EXISTS `bq-stream-514812.marts`   OPTIONS (location = 'US');

-- Typed subset of the Wikimedia event (decisions D4). The user name is deliberately NOT stored (D5).
-- Day partition on event time: safe here because the data is recent (the sandbox expires partitions after 60 days).
CREATE TABLE IF NOT EXISTS `bq-stream-514812.raw.wiki_edits` (
  event_id   STRING    NOT NULL OPTIONS (description = 'Wikimedia meta.id. Unique per event, but duplicates are expected (at-least-once load)'),
  event_ts   TIMESTAMP NOT NULL OPTIONS (description = 'meta.dt: when the event was published on the stream'),
  rc_id      INT64     OPTIONS (description = 'recentchange id on the wiki'),
  wiki       STRING    OPTIONS (description = 'Wiki database name, e.g. enwiki'),
  type       STRING    OPTIONS (description = 'edit or new'),
  namespace  INT64     OPTIONS (description = 'MediaWiki namespace, 0 = article'),
  title      STRING    OPTIONS (description = 'Page title'),
  bot        BOOL      OPTIONS (description = 'Edit flagged as a bot edit'),
  minor      BOOL      OPTIONS (description = 'Edit flagged as minor'),
  is_anon    BOOL      OPTIONS (description = 'Editor is anonymous (IP address or temporary account); the name itself is not stored'),
  length_old INT64     OPTIONS (description = 'Page size in bytes before the edit (NULL for new pages)'),
  length_new INT64     OPTIONS (description = 'Page size in bytes after the edit')
)
PARTITION BY DATE(event_ts)
OPTIONS (description = 'enwiki edit and new-page events from the Wikimedia recentchange stream, appended by collector/collect.py');
