---
name: football-dbt-duckdb
description: How to run, query, extend and chart this project — a local dbt + DuckDB pipeline on SkillCorner open football data (A-League 2024/25). Use whenever the work touches the ingestion script, the bronze/silver/gold dbt models, the DuckDB warehouse file, examples.sql, the notebook in notebooks/, or a question answered from this data (team styles, off-ball runs, passing options, pressing, per-30 rates) — even if the user only asks "how many runs did X make" or "add a chart".
---

# football-dbt-duckdb

A laptop-sized pipeline: `ingestion/ingest.py` downloads SkillCorner open data into
`data/landing/`, dbt (via dbt-duckdb) builds bronze → silver → gold into one DuckDB file,
`data/warehouse/football.duckdb`. No cloud, no credentials.

## Commands

All from the project root. The virtualenv lives in `.venv/`.

| Goal | Command |
|---|---|
| First run | `make setup ingest build` |
| New matches + rebuild | `make update` |
| Re-download every file (provider revised data) | `.venv/bin/python ingestion/ingest.py --force && make build` |
| Build one model and its children | `cd transform && DBT_PROFILES_DIR=. ../.venv/bin/dbt build -s <model>+` |
| Tests only | `make test` |
| SQL shell | `make query` (or `duckdb -readonly data/warehouse/football.duckdb`) |
| Notebook | `make notebook` (installs the `notebook` extra on first run) |

A full build is ~2 s and runs 67 tests. Always finish a change with `make build` and report
the `PASS=… ERROR=…` line.

## Where things are

- Schemas are named after the layer: `main_bronze`, `main_silver`, `main_gold`.
- Gold models: `gold_player_match_metrics` (match × player), `gold_team_match_summary`
  (match × team), `gold_team_season_summary` (team across its matches in the sample).
- Silver event tables: `silver_off_ball_runs`, `silver_passing_options`,
  `silver_on_ball_engagements`; plus `silver_matches`, `silver_player_matches`.
- `player_possession` events exist in bronze only — there is no silver model for them yet.
- Normalisation macro: `transform/macros/per_30.sql`. Singular tests: `transform/tests/`.
- Example queries: `examples.sql`. Tutorial for a new file type: `docs/add-a-source.md`.

## Rules the models follow — keep them when adding models

1. **The key is `(match_id, event_id)`.** `event_id` restarts every match. Never join or
   dedupe on `event_id` alone.
2. **Attacking rates per 30′ in possession, defensive rates per 30′ out of possession.**
   Use the `per_30` macro and name the column `<metric>_per_30_tip` or `_per_30_otip`.
   Don't normalise per 90 or by `minutes_played`.
3. **Season rates come from summed counts and minutes**, never an average of per-match
   rates. Keep the count next to every rate, and keep `matches_in_sample`.
4. **Deterministic aggregates.** Pick one value with `max(...)` or an ordered
   `row_number()`, never `any_value(...)`.
5. **Bronze changes nothing** beyond adding `_source_file` / `_loaded_at`. Renames, casts
   and `is_…` booleans happen in silver.
6. New categorical columns get an `accepted_values` test, so a new provider value fails
   the build instead of silently shifting a gold number.

## Gotchas already paid for

- **The provider revises files it has already published** (e.g. the 14 September 2026
  "dynamic events v3" refresh). `ingest.py` only downloads *missing* files, so an old
  checkout keeps stale versions forever and can mix revisions. Quick check:
  `find data/landing -type f ! -newermt 2026-09-14` lists files downloaded before v3
  (no output = all current).
  If so, or if numbers don't match a fresh clone, re-download with `--force` (ask the
  user first; it rewrites ~90 MB).
- **Team possession clocks are approximate.** `team_minutes_tip` / `team_minutes_otip` in
  `gold_team_match_summary` are the squad's `max(minutes_tip/otip)`, assuming someone
  played the whole match.
- **DuckDB allows one writer.** An open connection — the notebook, a `duckdb` shell, a
  Python session — makes `make build` fail with `Could not set lock on file`. Close it
  (`con.close()` / restart the kernel) and rebuild. Open the warehouse with
  `read_only=True` whenever you only read.
- **Sample size is small and uneven:** 20 matches, each team appears 1–7 times. Say so next
  to any team ranking, and use a minutes threshold for player rankings.
- The `*_tracking_extrapolated.jsonl` files upstream are git-LFS stubs; the project doesn't
  use them.
- Team names are the provider's short names (`Melbourne V FC`, `Wellington P FC`,
  `Newcastle`).

## Answering a question from the data

Query read-only and show the SQL you ran:

```bash
duckdb -readonly data/warehouse/football.duckdb -c "select ... from main_gold.<model>"
```

Prefer gold; drop to silver only for event-level detail (run type, coordinates, xThreat).

### Which column answers what

| Question about… | Count | Rate | Where |
|---|---|---|---|
| Off-ball movement | `off_ball_runs` | `off_ball_runs_per_30_tip` | all three gold models |
| Runs in behind | `runs_in_behind` | `runs_in_behind_per_30_tip` | season, player |
| Dangerous runs | `dangerous_runs` | `dangerous_runs_per_30_tip` | player |
| Being an option | `passing_options`, `dangerous_options` | `passing_options_per_30_tip`, `dangerous_options_per_30_tip` | season, player (match: dangerous only) |
| Pressing, all types | `on_ball_engagements` | `engagements_per_30_otip` | all three gold models |
| Counter-pressing | `counter_press_engagements` | `counter_press_per_30_otip` | season, player (match: count only) |
| Other press types | `pressing_engagements`, `recovery_press_engagements` | compute with the per-30 rule | player |
| Defensive outcomes | `forced_backward_passes`, `times_beaten`, `danger_stopped` | — | player (team: `forced_backward_passes`) |

Counter-press is `engagement_type = 'counter_press'` in `silver_on_ball_engagements`; the
five types are `pressing`, `pressure`, `counter_press`, `recovery_press`, `other`. Off-ball
run types live in `silver_off_ball_runs.run_type` (10 values).

### Reading a team ranking

A season rate alone overstates certainty. Before naming a "top" team:

1. Show `matches_in_sample` and the count behind the rate.
2. Check the per-match spread from `gold_team_match_summary` (per-match rate = count × 30 /
   `team_minutes_otip` or `_tip`). If the top teams' ranges overlap, say it's a group, not
   an order.
3. Name the denominator's bias when it matters: per-30-OTIP flatters teams that rarely lose
   the ball for events triggered by losing it (counter-press). Offer a second view — per
   match, or share of all engagements — when the two disagree.
4. Look at who they played: with 1–7 matches, one opponent can dominate a team's sample.

## Charts

`notebooks/explore.ipynb` sets the house style in its first cell (palette, thin marks,
recessive grid) and has one chart to copy from: off-ball runs per 30′ in possession per
player, as a ranked horizontal bar built from summed counts with a minutes threshold. Reuse
those conventions for new charts:

- Blue `#2a78d6` for a single series; add orange `#eb6834` for a second. Never colour by rank.
- Label marks directly and sparingly; name the source model in the title or a caption.
- Flag small samples (e.g. hollow markers for teams with 1–2 matches).
- One y-axis per chart.

After editing the notebook, re-run it top to bottom
(`.venv/bin/jupyter nbconvert --to notebook --execute --inplace notebooks/explore.ipynb`)
so the committed outputs match the code, and close the connection before the next build.
