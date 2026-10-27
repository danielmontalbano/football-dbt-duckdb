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

- **The provider revises files it has already published** (e.g. the September 2026
  "dynamic events v3" refresh). `ingest.py` only downloads *missing* files, so an old
  checkout keeps stale versions forever and can mix revisions. If numbers don't match a
  fresh clone, re-download with `--force`.
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
