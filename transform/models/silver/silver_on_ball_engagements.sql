-- Silver: on-ball engagements, one row per defensive engagement.
--
-- The out-of-possession counterpart: a defender actively pressing,
-- containing or challenging the player on the ball. Unlike a "tackle" or
-- "duel" in event data, it is detected from movement, so it also captures
-- the pressure that never turns into a touch.

select
    -- `event_id` is only unique *within* a match, so the real key is the
    -- pair. Building it explicitly here saves every downstream join from
    -- silently fanning out.
    match_id || '-' || event_id as engagement_id,
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

    event_subtype as engagement_type,

    player_in_possession_id,
    player_in_possession_name,

    x_start, y_start,
    third_start,

    cast(distance_covered as double) as distance_covered_m,
    cast(speed_avg as double) as speed_avg_kmh,
    cast(interplayer_distance_min as double) as closest_distance_m,

    -- outcomes
    cast(beaten_by_possession as boolean) as was_beaten_by_ball,
    cast(beaten_by_movement as boolean) as was_beaten_by_movement,
    cast(stop_possession_danger as boolean) as stopped_danger,
    cast(reduce_possession_danger as boolean) as reduced_danger,
    cast(force_backward as boolean) as forced_backward_pass,
    cast(pressing_chain as boolean) as part_of_pressing_chain

from {{ ref('bronze_dynamic_events') }}
where event_type = 'on_ball_engagement'
