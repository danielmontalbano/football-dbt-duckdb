-- Bronze: one row per match, straight from the match JSON.
-- Nested objects (home_team, stadium, ...) are kept as DuckDB structs here;
-- flattening them is silver's job.

select
    id as match_id,
    date_time,
    status,
    home_team,
    away_team,
    home_team_score,
    away_team_score,
    competition_edition,
    competition_round,
    stadium,
    pitch_length,
    pitch_width,
    match_periods,
    filename as _source_file,
    current_localtimestamp() as _loaded_at
from {{ source('skillcorner', 'match_info') }}
