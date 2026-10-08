-- Bronze: the `players` array of each match JSON, unnested to one row per
-- player per match. Unnesting is a structural change, not a business rule,
-- so it belongs here: the values themselves are still exactly as delivered.

with unnested as (

    select
        id as match_id,
        filename,
        unnest(players) as player
    from {{ source('skillcorner', 'match_info') }}

)

select
    match_id,
    player.id as player_id,
    player.team_id as team_id,
    player.short_name as player_short_name,
    player.first_name as player_first_name,
    player.last_name as player_last_name,
    player.birthday as birthday,
    player.number as shirt_number,
    player.player_role.acronym as position_acronym,
    player.player_role.position_group as position_group,
    player.start_time as start_time,
    player.end_time as end_time,
    player.goal as goals,
    player.own_goal as own_goals,
    player.yellow_card as yellow_cards,
    player.red_card as red_cards,
    player.playing_time.total.minutes_played as minutes_played,
    player.playing_time.total.minutes_tip as minutes_tip,
    player.playing_time.total.minutes_otip as minutes_otip,
    filename as _source_file,
    current_localtimestamp() as _loaded_at
from unnested
