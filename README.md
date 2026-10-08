# football-dbt-duckdb

A free, laptop-sized football data stack: **dbt + DuckDB on SkillCorner open
data**. Everything here is open source and the data is openly licensed, so it
runs on your laptop in a few minutes with no cloud account, no credentials and
no cost.

You can use it in two ways:

- **Learn analytics engineering.** A complete, working pipeline on real
  tracking-derived data (ingestion, bronze / silver / gold layers, tests, docs
  and lineage) that you can read, run and extend.
- **Test dbt models locally.** Develop and test models against a single DuckDB
  file, then point `profiles.yml` at your warehouse when they're ready.

---

## Quickstart

You need Python 3.10+ and [uv](https://docs.astral.sh/uv/). The `duckdb` CLI
is optional, for querying outside dbt.

```bash
make setup     # create a virtualenv and install dbt-duckdb
make ingest    # download the open data into data/landing/  (~45 MB)
make build     # run every model and test                   (~1.5 s)
```

That's it. You now have a warehouse at `data/warehouse/football.duckdb`. Try
the example queries:

```bash
duckdb data/warehouse/football.duckdb < examples.sql
```

Or look at the lineage graph:

```bash
make docs
```

<details>
<summary>All make targets</summary>

```bash
make setup     # virtualenv + dbt-duckdb
make ingest    # download the dataset into data/landing/
make build     # run all models and tests
make update    # ingest + build: pick up new matches and rebuild
make test      # tests only
make docs      # dbt docs + lineage graph
make query     # DuckDB shell on the warehouse
make clean     # drop the warehouse; landed files are kept
```

</details>

---

## The stack

| Tool | What it does here |
|---|---|
| [dbt](https://www.getdbt.com/) | Turns SQL files into a tested, documented pipeline with lineage |
| [DuckDB](https://duckdb.org/) | The warehouse: a single file on disk, no server |
| [dbt-duckdb](https://github.com/duckdb/dbt-duckdb) | The adapter; it also reads CSV and JSON straight off disk, so there's no load step |
| [uv](https://docs.astral.sh/uv/) | Sets up the Python environment |
| [SkillCorner open data](https://github.com/SkillCorner/opendata) | Ten 2024/25 A-League matches, MIT licensed |

---

## How it works

Data moves through four stages, and each one has a single job:

`data/landing/` → **bronze** → **silver** → **gold**

| Stage | Its job | Models |
|---|---|---|
| `data/landing/` | The provider's files, byte for byte | `matches.json`<br>`{id}_match.json`<br>`{id}_dynamic_events.csv` |
| **bronze** | The files as delivered, plus which file each row came from | `bronze_matches`<br>`bronze_match_players`<br>`bronze_dynamic_events` |
| **silver** | Clean, typed tables, one per event type | `silver_matches`<br>`silver_player_matches`<br>`silver_off_ball_runs`<br>`silver_passing_options`<br>`silver_on_ball_engagements` |
| **gold** | Answers to questions, per match and per season | `gold_player_match_metrics`<br>`gold_team_match_summary`<br>`gold_team_season_summary` |

### 1. Ingestion: land the files

[`ingestion/ingest.py`](ingestion/ingest.py) downloads the files into
`data/landing/` and does nothing else: no parsing, no cleaning. That's dbt's
job.

It's safe to re-run. The match index (`matches.json`) is always re-fetched,
because that's how a newly published match gets discovered. Per-match files are
only downloaded if they're missing, so an update costs one small request plus
the new match:

```
Match index (always refreshed)
  10 matches in the index
  9 already landed
  1 to download: [2017461]

Match 2017461
  landed   0.03 MB  2017461_match.json
  landed   3.79 MB  2017461_dynamic_events.csv
```

### 2. Bronze: the data as delivered

Bronze reads the landed files directly. dbt-duckdb lets a source point at a
file glob, so there's no separate loader:

```yaml
- name: dynamic_events
  meta:
    external_location: "read_csv('../data/landing/dynamic_events/*.csv',
                                 union_by_name=true, sample_size=-1, filename=true)"
```

Bronze doesn't rename, filter or fix anything. It only adds `_source_file` and
`_loaded_at`. If a number downstream ever looks wrong, bronze is what you
compare with the original file.

### 3. Silver: clean and typed

Each silver model keeps the ~20 columns that matter for one event type (out of
294 in the raw file), casts them, and gives booleans names that read as
questions: `dangerous` becomes `is_dangerous`, `break_defensive_line` becomes
`breaks_defensive_line`. Every fact table gets a proper key, such as `run_id`
or `engagement_id`.

### 4. Gold: answer a question

Gold models are aggregated, normalised and named for what they answer. Rates
are always shown next to their counts, so you can see the sample behind every
number.

### Picking up new data

`make update` runs ingestion and then rebuilds. Ingestion is incremental, but
the dbt build is a full rebuild on purpose: the whole warehouse rebuilds in
about 1.2 seconds, so incremental models would add complexity for no gain.
They become worth it when a full rebuild no longer fits in the time you have.

---

## The data

[SkillCorner open data](https://github.com/SkillCorner/opendata): ten 2024/25
Australian A-League matches, MIT licensed. The project uses two of the
published file types:

| File | Contents |
|---|---|
| `{id}_match.json` | Lineups, minutes played (total / in possession / out of possession), pitch dimensions |
| `{id}_dynamic_events.csv` | 294 columns, four event types stacked in one table |

Dynamic Events are derived from tracking data rather than from ball actions,
so they describe off-ball behaviour that ordinary event feeds don't record:

| `event_type` | What it is | Rows |
|---|---|---|
| `off_ball_run` | A run at 15+ km/h while a team-mate has the ball, ending as a passing option | 5,002 |
| `passing_option` | A moment when a player is rated as an available target | 24,374 |
| `on_ball_engagement` | A defender pressing or containing the player on the ball | 8,911 |
| `player_possession` | A player in control of the ball | 9,566 |

Column definitions come from *Dynamic Events CSV Specifications* (2025-02-16).

Things to keep in mind:

- Ten matches means each team appears one to four times, so season-level
  numbers are illustrations, not analysis.
- The `*_tracking_extrapolated.jsonl` files in the SkillCorner repo are git-LFS
  pointers: a plain download gives you a 133-byte stub. This project doesn't
  use them.
- The four event types share one wide table, so most columns are empty for any
  given row.

---

## Try it yourself

- **Add a source.** [docs/add-a-source.md](docs/add-a-source.md) walks you
  through adding SkillCorner's Phases of Play file, from download to a gold
  model, in about 30 minutes.
- **Model possessions.** `player_possession` events are already in bronze but
  not in silver yet. Build `silver_player_possessions` with `xshot`, `xloss`
  and `end_type`.
- **Add a dashboard.** [Evidence](https://evidence.dev) can read the DuckDB file
  directly.
- **Schedule it.** Run `make update` under Dagster or Prefect.

---

## Testing locally, then moving to a warehouse

`profiles.yml` is the only file tied to DuckDB. The models use standard SQL
plus a few DuckDB features (`count(*) filter (...)`, `unnest` and struct
access). To move to Postgres, Redshift or another warehouse, you change the
profile and rewrite the JSON handling in bronze; silver and gold work as they
are.

That makes this a handy place to develop and test dbt models before running
them against a warehouse.

### Tests

`make build` runs 67 tests, using dbt's built-in generic tests only, so there
are no packages to install:

| Test | Applied to |
|---|---|
| `unique`, `not_null` | Every key in every layer |
| `relationships` | `match_id` on each fact table → `silver_matches` |
| `accepted_values` | `run_type` (10 values), `engagement_type` (5), `position_group` (6) |
| Singular tests | Three SQL assertions in [`transform/tests/`](transform/tests/) |

The `accepted_values` tests are there on purpose: if the provider adds a new
run type, the build fails, instead of a gold number quietly changing.

A row-count check catches what column tests can't. Query 6 in `examples.sql`
compares bronze with silver, and the counts should match exactly:

| `event_type` | bronze | silver |
|---|---|---|
| `off_ball_run` | 5,002 | 5,002 |
| `on_ball_engagement` | 8,911 | 8,911 |
| `passing_option` | 24,374 | 24,374 |

---

## Design notes

Why the models are built the way they are. If you add models, these are worth
following too.

### The real key is `(match_id, event_id)`

`event_id` restarts every match: 47,853 rows carry only 5,449 distinct
values. Silver builds the pair into a single key, and
[`assert_dynamic_event_grain_is_match_plus_event.sql`](transform/tests/assert_dynamic_event_grain_is_match_plus_event.sql)
checks it, so a data drop that breaks the assumption fails the build instead of
duplicating rows in every join downstream.

### Per 30 minutes of possession, not per 90

Each player has three clocks per match:

| Column | Meaning |
|---|---|
| `minutes_played` | Time on the pitch |
| `minutes_tip` | Time on the pitch with their team in possession |
| `minutes_otip` | Time on the pitch with the opponent in possession |

[`macros/per_30.sql`](transform/macros/per_30.sql) normalises attacking
metrics (runs, passing options) per 30 minutes in possession, and defensive
metrics (engagements) per 30 minutes out of possession. Using minutes played
for defensive numbers would favour players in teams that spend a lot of time
without the ball. Rate columns carry their denominator in the name:
`..._per_30_tip`, `..._per_30_otip`.

### Season rates come from summed counts

Season models add up counts and minutes, then compute the rate. They don't
average per-match rates, because that would weigh a 15-minute cameo the same
as a full match. `matches_in_sample` is kept as a column so you can always see
how much data sits behind a row.

### Same input, same output

Rebuilding on unchanged data must give identical results. When an aggregate
picks one value out of many rows, it uses an explicit rule (`max(...)` or an
ordered `row_number()`), never `any_value(...)`, which can return a different
row on each run.

### One approximation

`gold_team_match_summary` uses the squad's `max(minutes_tip)` and
`max(minutes_otip)` as the team's possession clock, assuming someone played the
whole match. This is noted in the model.

---

## Models

| Layer | Model | One row per |
|---|---|---|
| bronze | `bronze_matches` | match |
| bronze | `bronze_match_players` | match × player (incl. unused subs) |
| bronze | `bronze_dynamic_events` | match × event |
| silver | `silver_matches` | match |
| silver | `silver_player_matches` | match × player who played |
| silver | `silver_off_ball_runs` | run |
| silver | `silver_passing_options` | passing option |
| silver | `silver_on_ball_engagements` | engagement |
| gold | `gold_player_match_metrics` | match × player |
| gold | `gold_team_match_summary` | match × team |
| gold | `gold_team_season_summary` | team, across its matches in the sample |

## Layout

```
ingestion/ingest.py                 download the files
transform/
  dbt_project.yml, profiles.yml     dbt config (DuckDB, local file)
  macros/per_30.sql                 normalisation rule
  models/bronze/                    3 models
  models/silver/                    5 models
  models/gold/                      3 models
  tests/                            3 singular tests
docs/add-a-source.md                tutorial: add a new file type
examples.sql                        example gold-layer queries
data/landing/                       downloaded files (gitignored)
data/warehouse/football.duckdb      the warehouse (gitignored)
```

## Attribution

Data © SkillCorner, MIT licensed; see [NOTICE.md](NOTICE.md). This project is
independent of, and not endorsed by, SkillCorner.
