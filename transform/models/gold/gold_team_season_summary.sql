-- Gold: one row per team across all of its matches in the sample.
--
-- The season grain. Nothing here is a ranking: teams appear a different
-- number of times in the open dataset (one to four matches), so
-- `matches_in_sample` is carried as a column and any reading of the table
-- has to account for it.
--
-- Rates are recomputed from summed counts and summed minutes. Averaging the
-- per-match rates would weight a single match the same as four.

with per_match as (

    select * from {{ ref('gold_team_match_summary') }}

),

season as (

    select
        team_id,
        max(team_name) as team_name,
        count(*) as matches_in_sample,
        min(match_date) as first_match_date,
        max(match_date) as last_match_date,

        round(sum(team_minutes_tip), 1) as minutes_tip,
        round(sum(team_minutes_otip), 1) as minutes_otip,

        sum(off_ball_runs) as off_ball_runs,
        sum(runs_in_behind) as runs_in_behind,
        sum(runs_received) as runs_received,
        round(sum(run_distance_m), 1) as run_distance_m,
        sum(passing_options) as passing_options,
        sum(dangerous_options) as dangerous_options,
        sum(options_breaking_last_line) as options_breaking_last_line,
        sum(on_ball_engagements) as on_ball_engagements,
        sum(counter_press_engagements) as counter_press_engagements,
        sum(forced_backward_passes) as forced_backward_passes
    from per_match
    group by team_id

)

select
    *,
    {{ per_30('off_ball_runs', 'minutes_tip') }} as off_ball_runs_per_30_tip,
    {{ per_30('runs_in_behind', 'minutes_tip') }} as runs_in_behind_per_30_tip,
    {{ per_30('passing_options', 'minutes_tip') }} as passing_options_per_30_tip,
    {{ per_30('dangerous_options', 'minutes_tip') }} as dangerous_options_per_30_tip,
    {{ per_30('on_ball_engagements', 'minutes_otip') }} as engagements_per_30_otip,
    {{ per_30('counter_press_engagements', 'minutes_otip') }} as counter_press_per_30_otip
from season
