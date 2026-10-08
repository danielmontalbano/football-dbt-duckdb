-- Examples of what the gold layer contains.
--   duckdb data/warehouse/football.duckdb < examples.sql
--
-- These are illustrations of the aggregation, not analysis. The sample is ten
-- matches, so nothing here supports a comparison between players or teams.
.mode box

select '1. Match grain - every player in one match' as example;
select player_name, team_name, position_acronym, minutes_played, minutes_tip,
       off_ball_runs, passing_options, on_ball_engagements
from main_gold.gold_player_match_metrics
where match_id = 1886347
order by team_name, minutes_played desc
limit 12;

select '2. Match grain - the same match, normalised by the possession clock' as example;
select player_name, position_acronym, minutes_tip, off_ball_runs, off_ball_runs_per_30_tip,
       minutes_otip, on_ball_engagements, engagements_per_30_otip
from main_gold.gold_player_match_metrics
where match_id = 1886347 and minutes_played > 45
order by off_ball_runs_per_30_tip desc
limit 12;

select '3. Match grain - both teams in every match' as example;
select fixture, team_name, off_ball_runs, passing_options, dangerous_options,
       on_ball_engagements, counter_press_engagements
from main_gold.gold_team_match_summary
order by match_date, fixture, team_name;

select '4. Season grain - team totals across the matches in the sample' as example;
select team_name, matches_in_sample, minutes_tip, off_ball_runs, off_ball_runs_per_30_tip,
       passing_options, dangerous_options, on_ball_engagements, engagements_per_30_otip
from main_gold.gold_team_season_summary
order by matches_in_sample desc, team_name;

select '5. Silver grain - distribution of off-ball run types' as example;
select run_type,
       count(*) as runs,
       round(100.0 * count(*) filter (was_received) / count(*), 1) as pct_received,
       round(avg(distance_covered_m), 1) as avg_distance_m,
       round(avg(speed_avg_kmh), 1) as avg_speed_kmh
from main_silver.silver_off_ball_runs
group by run_type
order by runs desc;

select '6. Reconciliation - events survive bronze -> silver unchanged' as example;
select 'bronze (filtered)' as layer, event_type, count(*) as events
from main_bronze.bronze_dynamic_events
where event_type in ('off_ball_run', 'passing_option', 'on_ball_engagement')
group by all
union all
select 'silver', 'off_ball_run', count(*) from main_silver.silver_off_ball_runs
union all
select 'silver', 'passing_option', count(*) from main_silver.silver_passing_options
union all
select 'silver', 'on_ball_engagement', count(*) from main_silver.silver_on_ball_engagements
order by event_type, layer;
