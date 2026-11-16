-- Grain: one row per Wikimedia event, for the last `lookback_days` days of raw partitions.
-- The collector is at-least-once, so raw repeats event_ids; dedupe here.
-- The date filter sits directly on the partitioned raw table so BigQuery prunes partitions. A time filter
-- applied later (in a mart) would NOT be pushed below this window function and would scan the whole table.
select
    event_id,
    event_ts,
    timestamp_trunc(event_ts, hour) as event_hour,
    rc_id,
    title,
    namespace,
    type,
    type = 'new' as is_new_page,
    bot,
    minor,
    is_anon,
    case when bot then 'bot' when is_anon then 'anonymous' else 'registered' end as editor_type,
    length_old,
    length_new,
    -- new pages have no old length: the whole page counts as added
    coalesce(length_new, 0) - coalesce(length_old, 0) as byte_diff
from {{ source('raw', 'wiki_edits') }}
where date(event_ts) >= date_sub(current_date(), interval {{ var('lookback_days') - 1 }} day)
qualify row_number() over (partition by event_id order by event_ts) = 1
