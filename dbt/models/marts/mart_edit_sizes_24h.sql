-- Distribution of edit sizes (bytes added or removed) in the last 24 hours, by editor type.
with sized as (
    select
        editor_type,
        case
            when byte_diff < -1000 then 1
            when byte_diff < -100 then 2
            when byte_diff < 0 then 3
            when byte_diff = 0 then 4
            when byte_diff <= 100 then 5
            when byte_diff <= 1000 then 6
            else 7
        end as bucket_order
    from {{ ref('stg_wiki_edits') }}
    where event_ts >= timestamp_sub(current_timestamp(), interval 24 hour)
)

select
    bucket_order,
    case bucket_order
        when 1 then 'removed > 1000'
        when 2 then 'removed 101-1000'
        when 3 then 'removed 1-100'
        when 4 then 'no size change'
        when 5 then 'added 1-100'
        when 6 then 'added 101-1000'
        else 'added > 1000'
    end as size_bucket,
    editor_type,
    count(*) as edits
from sized
group by bucket_order, editor_type
