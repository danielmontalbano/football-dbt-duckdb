-- A run can only be "received" if it happened: received <= total.
-- Cheap, but it catches the classic bug of a fan-out join inflating one
-- counter and not the other.

select
    player_match_id,
    off_ball_runs,
    runs_received
from {{ ref('gold_player_match_metrics') }}
where runs_received > off_ball_runs
