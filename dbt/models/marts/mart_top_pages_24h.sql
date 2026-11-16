-- The 50 most edited articles (namespace 0) in the last 24 hours.
select
    title,
    count(*) as edits,
    countif(editor_type = 'bot') as bot_edits,
    sum(byte_diff) as net_bytes,
    max(event_ts) as last_edit_ts
from {{ ref('stg_wiki_edits') }}
where namespace = 0
  and event_ts >= timestamp_sub(current_timestamp(), interval 24 hour)
group by title
qualify row_number() over (order by edits desc, title) <= 50
