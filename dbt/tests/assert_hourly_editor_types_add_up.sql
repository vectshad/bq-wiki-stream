-- Every edit is exactly one of bot / anonymous / registered, so the three counts must add up to the total.
select event_hour, edits, bot_edits, anonymous_edits, registered_edits
from {{ ref('mart_edits_per_hour') }}
where edits != bot_edits + anonymous_edits + registered_edits
