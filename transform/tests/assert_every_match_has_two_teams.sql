-- Completeness: a football match has exactly two teams. If ingestion dropped
-- a file, or a team join failed, this is where it shows up.

select
    match_id,
    count(*) as teams
from {{ ref('gold_team_match_summary') }}
group by match_id
having count(*) != 2
