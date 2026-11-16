-- Datasets for the streaming project. Idempotent. Location US (the project default; keep every dataset in one location).
-- Run (bash, stdin closed so bq cannot block on a prompt):
--   bq --project_id=bq-stream-514812 query --use_legacy_sql=false --location=US --maximum_bytes_billed=1000000000 "$(grep -v '^--' scripts/bootstrap.sql)" < /dev/null
CREATE SCHEMA IF NOT EXISTS `bq-stream-514812.raw`     OPTIONS (location = 'US');
CREATE SCHEMA IF NOT EXISTS `bq-stream-514812.staging` OPTIONS (location = 'US');
CREATE SCHEMA IF NOT EXISTS `bq-stream-514812.marts`   OPTIONS (location = 'US');
