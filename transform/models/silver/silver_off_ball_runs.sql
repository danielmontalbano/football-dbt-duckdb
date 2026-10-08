-- Silver: off-ball runs, one row per run.
--
-- SkillCorner detects a run when a player moves at 15+ km/h for at least
-- 0.7s while a team-mate is in control of the ball, and is a passing option
-- during or just after it. This is the movement traditional event data never
-- records, because nothing happens to the ball.
--
-- Out of 294 raw columns we keep the ~20 that are actually populated for
-- this event type and that we have a use for. That selection *is* the work
-- of the silver layer.

select
    -- `event_id` is only unique *within* a match, so the real key is the
    -- pair. Building it explicitly here saves every downstream join from
    -- silently fanning out.
    match_id || '-' || event_id as run_id,
    event_id,
    match_id,
    period,
    minute_start,
    cast(duration as double) as duration_seconds,

    player_id,
    player_name,
    team_id,
    team_shortname as team_name,
    player_position as position_acronym,

    event_subtype as run_type,

    -- where the run started and ended (metres, origin at the centre spot)
    x_start, y_start, x_end, y_end,
    third_start, third_end,

    -- how hard the run was
    cast(distance_covered as double) as distance_covered_m,
    cast(speed_avg as double) as speed_avg_kmh,

    -- what the run achieved
    cast(dangerous as boolean) as is_dangerous,
    cast(targeted as boolean) as was_targeted,
    cast(received as boolean) as was_received,
    cast(intended_run_behind as boolean) as is_run_in_behind,
    cast(break_defensive_line as boolean) as breaks_defensive_line,
    cast(xthreat as double) as xthreat,
    cast(lead_to_shot as boolean) as led_to_shot,
    cast(lead_to_goal as boolean) as led_to_goal

from {{ ref('bronze_dynamic_events') }}
where event_type = 'off_ball_run'
