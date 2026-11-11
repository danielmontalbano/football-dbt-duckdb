-- Staging: one flat row per match, straight from the match JSON.
-- Nested objects (home_team, stadium, ...) are flattened and renamed here;
-- nothing is joined or filtered.

select
    id as match_id,
    cast(date_time as timestamp) as kicked_off_at,
    cast(date_time as date) as match_date,
    competition_edition.competition.name as competition_name,
    competition_edition.season.name as season_name,
    home_team.id as home_team_id,
    home_team.short_name as home_team_name,
    away_team.id as away_team_id,
    away_team.short_name as away_team_name,
    home_team_score,
    away_team_score,
    stadium.name as stadium_name,
    pitch_length,
    pitch_width,
    filename as _source_file,
    current_localtimestamp() as _loaded_at
from {{ source('skillcorner', 'match_info') }}
