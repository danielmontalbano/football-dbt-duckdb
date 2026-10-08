-- Silver: one row per player per match, with the minutes that every rate
-- metric downstream is divided by.
--
-- Three different clocks matter in football tracking data:
--   minutes_played - the player was on the pitch
--   minutes_tip    - ... and his team had the ball   (In Possession)
--   minutes_otip   - ... and the opponent had the ball (Out of Possession)
--
-- Players who never came on are dropped here: they are noise in every
-- downstream aggregate.

with teams as (

    -- a tiny team lookup, built from the home/away sides of every match
    select match_id, home_team_id as team_id, home_team_name as team_name from {{ ref('silver_matches') }}
    union
    select match_id, away_team_id as team_id, away_team_name as team_name from {{ ref('silver_matches') }}

)

select
    p.match_id || '-' || p.player_id as player_match_id,
    p.match_id,
    p.player_id,
    p.team_id,
    t.team_name,
    p.player_short_name as player_name,
    p.position_acronym,
    p.position_group,
    p.shirt_number,
    p.minutes_played,
    p.minutes_tip,
    p.minutes_otip,
    p.goals,
    p.yellow_cards,
    p.red_cards
from {{ ref('bronze_match_players') }} as p
left join teams as t
    on p.match_id = t.match_id
    and p.team_id = t.team_id
where p.minutes_played > 0
