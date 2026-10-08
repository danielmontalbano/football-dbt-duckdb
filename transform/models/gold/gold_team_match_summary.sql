-- Gold: one row per team per match - the team-level view of the same events.
--
-- A team has no "minutes played", so we take the possession clock of a player
-- who was on the pitch throughout: the maximum minutes_tip / minutes_otip in
-- the squad. It is an approximation, and calling it out here is cheaper than
-- someone rediscovering it in six months.

with team_minutes as (

    select
        match_id,
        team_id,
        max(team_name) as team_name,
        round(max(minutes_tip), 1) as team_minutes_tip,
        round(max(minutes_otip), 1) as team_minutes_otip
    from {{ ref('silver_player_matches') }}
    group by match_id, team_id

),

runs as (

    select match_id, team_id,
        count(*) as off_ball_runs,
        count(*) filter (is_run_in_behind) as runs_in_behind,
        count(*) filter (was_received) as runs_received,
        round(sum(distance_covered_m), 1) as run_distance_m
    from {{ ref('silver_off_ball_runs') }}
    group by 1, 2

),

options as (

    select match_id, team_id,
        count(*) as passing_options,
        count(*) filter (is_dangerous) as dangerous_options,
        count(*) filter (breaks_last_line) as options_breaking_last_line
    from {{ ref('silver_passing_options') }}
    group by 1, 2

),

engagements as (

    select match_id, team_id,
        count(*) as on_ball_engagements,
        count(*) filter (engagement_type = 'counter_press') as counter_press_engagements,
        count(*) filter (forced_backward_pass) as forced_backward_passes
    from {{ ref('silver_on_ball_engagements') }}
    group by 1, 2

)

select
    tm.match_id || '-' || tm.team_id as team_match_id,
    tm.match_id,
    m.match_date,
    m.home_team_name || ' v ' || m.away_team_name as fixture,
    tm.team_id,
    tm.team_name,
    tm.team_minutes_tip,
    tm.team_minutes_otip,

    coalesce(r.off_ball_runs, 0) as off_ball_runs,
    coalesce(r.runs_in_behind, 0) as runs_in_behind,
    coalesce(r.runs_received, 0) as runs_received,
    coalesce(r.run_distance_m, 0) as run_distance_m,
    coalesce(o.passing_options, 0) as passing_options,
    coalesce(o.dangerous_options, 0) as dangerous_options,
    coalesce(o.options_breaking_last_line, 0) as options_breaking_last_line,
    coalesce(e.on_ball_engagements, 0) as on_ball_engagements,
    coalesce(e.counter_press_engagements, 0) as counter_press_engagements,
    coalesce(e.forced_backward_passes, 0) as forced_backward_passes,

    {{ per_30('coalesce(r.off_ball_runs, 0)', 'tm.team_minutes_tip') }} as off_ball_runs_per_30_tip,
    {{ per_30('coalesce(o.dangerous_options, 0)', 'tm.team_minutes_tip') }} as dangerous_options_per_30_tip,
    {{ per_30('coalesce(e.on_ball_engagements, 0)', 'tm.team_minutes_otip') }} as engagements_per_30_otip

from team_minutes as tm
inner join {{ ref('silver_matches') }} as m on tm.match_id = m.match_id
left join runs as r on tm.match_id = r.match_id and tm.team_id = r.team_id
left join options as o on tm.match_id = o.match_id and tm.team_id = o.team_id
left join engagements as e on tm.match_id = e.match_id and tm.team_id = e.team_id
