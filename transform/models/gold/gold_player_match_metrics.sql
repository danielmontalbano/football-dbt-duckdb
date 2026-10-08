-- Gold: one row per player per match, ready to be read by a human or a chart.
--
-- This is where the three event streams meet the minutes clock. Counts are
-- kept (you need them to judge sample size) and each one is paired with a
-- rate normalised by the right clock: in-possession metrics per 30 minutes
-- of team possession, out-of-possession metrics per 30 minutes without
-- the ball.

with runs as (

    select
        match_id,
        player_id,
        count(*) as off_ball_runs,
        count(*) filter (is_run_in_behind) as runs_in_behind,
        count(*) filter (is_dangerous) as dangerous_runs,
        count(*) filter (was_targeted) as runs_targeted,
        count(*) filter (was_received) as runs_received,
        round(sum(distance_covered_m), 1) as run_distance_m,
        round(avg(speed_avg_kmh), 1) as avg_run_speed_kmh,
        round(sum(xthreat), 4) as run_xthreat
    from {{ ref('silver_off_ball_runs') }}
    group by 1, 2

),

options as (

    select
        match_id,
        player_id,
        count(*) as passing_options,
        count(*) filter (is_dangerous) as dangerous_options,
        count(*) filter (was_received) as options_received,
        count(*) filter (breaks_last_line) as options_breaking_last_line,
        round(sum(xthreat), 4) as option_xthreat
    from {{ ref('silver_passing_options') }}
    group by 1, 2

),

engagements as (

    select
        match_id,
        player_id,
        count(*) as on_ball_engagements,
        count(*) filter (engagement_type = 'pressing') as pressing_engagements,
        count(*) filter (engagement_type = 'counter_press') as counter_press_engagements,
        count(*) filter (engagement_type = 'recovery_press') as recovery_press_engagements,
        count(*) filter (was_beaten_by_ball or was_beaten_by_movement) as times_beaten,
        count(*) filter (forced_backward_pass) as forced_backward_passes,
        count(*) filter (stopped_danger) as danger_stopped,
        round(sum(distance_covered_m), 1) as engagement_distance_m
    from {{ ref('silver_on_ball_engagements') }}
    group by 1, 2

)

select
    pm.player_match_id,
    pm.match_id,
    m.match_date,
    m.home_team_name || ' v ' || m.away_team_name as fixture,
    pm.player_id,
    pm.player_name,
    pm.team_name,
    pm.position_acronym,
    pm.position_group,
    pm.minutes_played,
    pm.minutes_tip,
    pm.minutes_otip,

    -- ---------- in possession ----------
    coalesce(r.off_ball_runs, 0) as off_ball_runs,
    coalesce(r.runs_in_behind, 0) as runs_in_behind,
    coalesce(r.dangerous_runs, 0) as dangerous_runs,
    coalesce(r.runs_received, 0) as runs_received,
    coalesce(r.run_distance_m, 0) as run_distance_m,
    r.avg_run_speed_kmh,
    coalesce(o.passing_options, 0) as passing_options,
    coalesce(o.dangerous_options, 0) as dangerous_options,
    coalesce(o.options_received, 0) as options_received,
    coalesce(o.options_breaking_last_line, 0) as options_breaking_last_line,
    coalesce(o.option_xthreat, 0) as option_xthreat,

    {{ per_30('coalesce(r.off_ball_runs, 0)', 'pm.minutes_tip') }} as off_ball_runs_per_30_tip,
    {{ per_30('coalesce(r.runs_in_behind, 0)', 'pm.minutes_tip') }} as runs_in_behind_per_30_tip,
    {{ per_30('coalesce(r.dangerous_runs, 0)', 'pm.minutes_tip') }} as dangerous_runs_per_30_tip,
    {{ per_30('coalesce(o.passing_options, 0)', 'pm.minutes_tip') }} as passing_options_per_30_tip,
    {{ per_30('coalesce(o.dangerous_options, 0)', 'pm.minutes_tip') }} as dangerous_options_per_30_tip,

    -- ---------- out of possession ----------
    coalesce(e.on_ball_engagements, 0) as on_ball_engagements,
    coalesce(e.pressing_engagements, 0) as pressing_engagements,
    coalesce(e.counter_press_engagements, 0) as counter_press_engagements,
    coalesce(e.recovery_press_engagements, 0) as recovery_press_engagements,
    coalesce(e.times_beaten, 0) as times_beaten,
    coalesce(e.forced_backward_passes, 0) as forced_backward_passes,
    coalesce(e.danger_stopped, 0) as danger_stopped,

    {{ per_30('coalesce(e.on_ball_engagements, 0)', 'pm.minutes_otip') }} as engagements_per_30_otip,
    {{ per_30('coalesce(e.counter_press_engagements, 0)', 'pm.minutes_otip') }} as counter_press_per_30_otip

from {{ ref('silver_player_matches') }} as pm
inner join {{ ref('silver_matches') }} as m on pm.match_id = m.match_id
left join runs as r on pm.match_id = r.match_id and pm.player_id = r.player_id
left join options as o on pm.match_id = o.match_id and pm.player_id = o.player_id
left join engagements as e on pm.match_id = e.match_id and pm.player_id = e.player_id
