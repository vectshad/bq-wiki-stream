{{ config(severity='warn') }}
-- An event published more than 10 minutes in the future means a clock or parsing problem upstream.
select event_id, event_ts
from {{ ref('stg_wiki_edits') }}
where event_ts > timestamp_add(current_timestamp(), interval 10 minute)
