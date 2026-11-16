-- One row: how fresh is the data. Computed when dbt runs, so read it together with computed_at.
select
    current_timestamp() as computed_at,
    max(event_ts) as latest_event_ts,
    timestamp_diff(current_timestamp(), max(event_ts), minute) as minutes_since_latest_event,
    countif(event_ts >= timestamp_sub(current_timestamp(), interval 1 hour)) as events_last_hour,
    count(*) as events_last_24h
from {{ ref('stg_wiki_edits') }}
where event_ts >= timestamp_sub(current_timestamp(), interval 24 hour)
