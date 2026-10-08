-- A singular test: plain SQL that must return zero rows.
--
-- `event_id` looks like a primary key but repeats across matches. This test
-- pins down the real grain, so that if a future data drop breaks it, the
-- build fails here instead of silently duplicating rows in a join.

select
    match_id,
    event_id,
    count(*) as n
from {{ ref('bronze_dynamic_events') }}
group by match_id, event_id
having count(*) > 1
