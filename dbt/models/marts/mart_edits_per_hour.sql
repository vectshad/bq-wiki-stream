-- Edits per hour over the last 48 hours, split by editor type. Ratios (bot share) are left to the dashboard:
-- a share computed here cannot be summed or averaged across hours.
select
    event_hour,
    event_hour < timestamp_trunc(current_timestamp(), hour) as is_complete_hour,
    count(*) as edits,
    countif(is_new_page) as new_pages,
    countif(editor_type = 'bot') as bot_edits,
    countif(editor_type = 'anonymous') as anonymous_edits,
    countif(editor_type = 'registered') as registered_edits,
    sum(greatest(byte_diff, 0)) as bytes_added,
    sum(least(byte_diff, 0)) as bytes_removed
from {{ ref('stg_wiki_edits') }}
where event_hour >= timestamp_trunc(timestamp_sub(current_timestamp(), interval 48 hour), hour)
group by event_hour
