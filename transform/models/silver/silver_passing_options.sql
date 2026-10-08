-- Silver: passing options, one row per option offered.
--
-- A passing option is a moment where SkillCorner's receiver model says this
-- player was a genuinely available target. It answers "how often does this
-- player make himself available, and how good are the options he offers?"
-- - a question no on-ball event feed can answer.

select
    -- `event_id` is only unique *within* a match, so the real key is the
    -- pair. Building it explicitly here saves every downstream join from
    -- silently fanning out.
    match_id || '-' || event_id as passing_option_id,
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

    player_in_possession_id,
    player_in_possession_name,

    x_start, y_start,
    third_start,

    cast(xthreat as double) as xthreat,
    cast(dangerous as boolean) as is_dangerous,
    cast(difficult_pass_target as boolean) as is_difficult_target,
    cast(targeted as boolean) as was_targeted,
    cast(received as boolean) as was_received,
    cast(received_in_space as boolean) as was_received_in_space,
    cast(first_line_break as boolean) as breaks_first_line,
    cast(last_line_break as boolean) as breaks_last_line

from {{ ref('bronze_dynamic_events') }}
where event_type = 'passing_option'
