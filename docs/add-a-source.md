# Add a source

This guide walks you through adding a new file type to the pipeline, from
download to a gold model you can query. The same five steps work for any
provider, but the example uses a file SkillCorner already publishes and this
project doesn't use yet: **Phases of Play**.

By the end you will have:

- `{id}_phases_of_play.csv` landed for every match
- `bronze_phases_of_play`, the file as delivered
- `silver_phases_of_play`, typed, with a proper key
- `gold_team_phase_summary`, how much time each team spends in each phase

Budget about 30 minutes. You need the project set up (`make setup`) and built
once (`make ingest && make build`).

---

## Step 0: Look at the file before writing any code

Five minutes spent profiling the file saves an hour of debugging later.
Download one match and open it in DuckDB:

```bash
curl -sLO https://raw.githubusercontent.com/SkillCorner/opendata/master/data/matches/2017461/2017461_phases_of_play.csv
duckdb -c "describe select * from '2017461_phases_of_play.csv'"
```

Answer three questions before moving on:

1. **What is one row?** Here it's one *phase*: a stretch of play where the
   team in possession is doing one kind of thing (`build_up`, `create`,
   `finish`, ...) and the other team is defending in one shape
   (`high_block`, `medium_block`, `low_block`, ...).
2. **What is the key?** There's an `index` column that looks like an id.
   Check whether it's unique across matches:

   ```sql
   select count(*), count(distinct index), count(distinct (match_id, index))
   from read_csv('*_phases_of_play.csv', union_by_name = true);
   ```

   Across all ten matches, that returns `4520, 490, 4520`. `index` restarts at 0
   every match, so the real key is `(match_id, index)`, the same trap as
   `event_id` in dynamic events.
3. **How does it join to what you already have?** `match_id` joins to
   `silver_matches`, and `team_in_possession_id` joins to the team ids there.
   The provider is the same, so the ids already agree. A new provider needs an
   id mapping, which is covered at the end of this guide.

---

## Step 1: Land the files (`ingestion/ingest.py`)

Ingestion copies files into `data/landing/`, byte for byte. It doesn't parse
or clean anything; that's dbt's job.

Add the new file to `match_files()`:

```python
def match_files(match_id: int) -> list[tuple[str, Path]]:
    """The (url, destination) pairs that make up one match."""
    return [
        # ... the two existing entries ...
        (
            f"{BASE_URL}/matches/{match_id}/{match_id}_phases_of_play.csv",
            LANDING / "phases_of_play" / f"{match_id}_phases_of_play.csv",
        ),
    ]
```

Then run:

```bash
make ingest
```

Matches you already have are only topped up: the script sees that the new
file is missing for every match and downloads just that file. You don't need
`--force`.

> **One folder per file type.** Each file type gets its own folder under
> `data/landing/`, so the dbt source can read it with a single glob. Don't mix
> file types in one folder.

---

## Step 2: Declare the source (`transform/models/bronze/_sources.yml`)

Tell dbt where the files are. dbt-duckdb reads them straight off disk, so
there's no load step:

```yaml
      - name: phases_of_play
        description: One CSV per match, one row per phase of play.
        meta:
          external_location: "read_csv('../data/landing/phases_of_play/*.csv', union_by_name=true, sample_size=-1, filename=true)"
```

What each option does:

| Option | Why |
|---|---|
| `../data/landing/...` | dbt runs from `transform/`, so paths are relative to it |
| `union_by_name=true` | Columns are matched by name, so a file with an extra or reordered column doesn't break the read |
| `sample_size=-1` | DuckDB reads every row to infer types, instead of guessing from the first few thousand |
| `filename=true` | Adds a `filename` column, which becomes `_source_file` in bronze |

> **Land the files before you build.** If the glob matches no files, DuckDB
> stops with `No files found that match the pattern`. Run `make ingest` first.

---

## Step 3: Bronze, the file as delivered

Create `transform/models/bronze/bronze_phases_of_play.sql`:

```sql
-- Bronze: phases of play, untouched.
-- The only additions are provenance: which file each row came from and when
-- it was loaded.

select
    * exclude (filename),
    filename as _source_file,
    current_localtimestamp() as _loaded_at
from {{ source('skillcorner', 'phases_of_play') }}
```

Bronze has one rule: **don't change values.** Don't rename columns, filter
rows or fix anything here. If a gold number is ever disputed, bronze is what
you compare with the original file.

Add basic tests to `transform/models/bronze/_models.yml`:

```yaml
  - name: bronze_phases_of_play
    description: Every phase of play from every match, exactly as delivered.
    columns:
      - name: match_id
        data_tests: [not_null]
      - name: index
        description: Unique *within a match only*.
        data_tests: [not_null]
      - name: _source_file
        data_tests: [not_null]
```

---

## Step 4: Silver, typed and keyed

Silver is where the file becomes pleasant to use. Pick the columns you need,
cast them, rename them so they read clearly, and build the real key.

Create `transform/models/silver/silver_phases_of_play.sql`:

```sql
-- Silver: one row per phase of play.
--
-- A phase is a stretch of play with one in-possession behaviour (build-up,
-- create, finish, ...) and one out-of-possession shape (high, medium or low
-- block, ...), as detected by SkillCorner from tracking data.

select
    -- `index` restarts at 0 every match, so the real key is the pair.
    match_id || '-' || index as phase_id,
    index as phase_index,
    match_id,
    period,
    minute_start,
    cast(duration as double) as duration_seconds,

    team_in_possession_id,
    team_in_possession_shortname as team_in_possession_name,
    team_in_possession_phase_type as in_possession_phase,
    team_out_of_possession_phase_type as out_of_possession_phase,

    third_start,
    third_end,

    -- outcomes
    cast(team_possession_loss_in_phase as boolean) as lost_possession,
    cast(team_possession_lead_to_shot as boolean) as led_to_shot,
    cast(team_possession_lead_to_goal as boolean) as led_to_goal

from {{ ref('bronze_phases_of_play') }}
```

Add tests to `transform/models/silver/_models.yml`:

```yaml
  - name: silver_phases_of_play
    description: One row per phase of play.
    columns:
      - name: phase_id
        data_tests: [not_null, unique]
      - name: match_id
        data_tests:
          - not_null
          - relationships:
              arguments:
                  to: ref('silver_matches')
                  field: match_id
      - name: in_possession_phase
        data_tests:
          - accepted_values:
              arguments:
                  values: [build_up, create, finish, direct, chaotic, set_play, transition, quick_break]
```

Each test protects you from a different failure:

- `unique` on `phase_id` fails if the grain assumption ever breaks, before a
  join fans out.
- `relationships` fails if a phases file arrives for a match that has no match
  file.
- `accepted_values` fails if SkillCorner adds a new phase type, instead of the
  gold model quietly changing shape. The eight values listed are the ones in
  the current ten matches.

---

## Step 5: Gold, answer a question

A gold model is named after the question it answers. This one answers **"How
does each team spend its time on the ball?"**

Create `transform/models/gold/gold_team_phase_summary.sql`:

```sql
-- Gold: time each team spends in each in-possession phase, per match.
-- Seconds and phase counts are kept alongside the share, so the sample size
-- behind each percentage stays visible.

with phases as (

    select
        match_id,
        team_in_possession_id as team_id,
        team_in_possession_name as team_name,
        in_possession_phase,
        count(*) as phases,
        round(sum(duration_seconds), 1) as seconds,
        count(*) filter (where led_to_shot) as phases_leading_to_shot
    from {{ ref('silver_phases_of_play') }}
    group by all

)

select
    match_id || '-' || team_id || '-' || in_possession_phase as team_phase_id,
    *,
    round(100.0 * seconds / sum(seconds) over (partition by match_id, team_id), 1)
        as pct_of_possession_time
from phases
```

Build it and look at the result:

```bash
make build
```

```sql
-- make query, then:
select team_name, in_possession_phase, phases, pct_of_possession_time
from main_gold.gold_team_phase_summary
where match_id = 2017461
order by team_name, pct_of_possession_time desc;
```

---

## Step 6: Reconcile

Tests check each column. A reconciliation checks that no rows went missing
between layers:

```sql
select
    (select count(*) from main_bronze.bronze_phases_of_play) as bronze_rows,
    (select count(*) from main_silver.silver_phases_of_play) as silver_rows;
```

Both should be 4,520 for the ten current matches. Silver doesn't filter this
file, so any difference means a cast or a join dropped rows.

---

## Checklist

- [ ] Profiled the file: one row = ?, key = ?, joins on = ?
- [ ] Added it to `ingest.py`, in its own landing folder
- [ ] Declared it in `_sources.yml` with `filename=true`
- [ ] Bronze: `* exclude (filename)` plus `_source_file` and `_loaded_at`, nothing else
- [ ] Silver: explicit columns, casts, predicate-style booleans, surrogate key
- [ ] Tests: `unique` + `not_null` on the key, `relationships` on `match_id`, `accepted_values` on categories
- [ ] Gold: named for its question, counts kept next to every rate
- [ ] Row counts reconcile from bronze to silver
- [ ] `make clean && make build` passes from scratch

---

## Adding a different provider

The steps are the same, with three differences:

1. **Ingestion.** If the provider publishes an index file listing what's
   available (like SkillCorner's `matches.json`), always re-fetch it. It's how
   new data is discovered, and caching it caps the pipeline at whatever it held
   on the first run.
2. **The source.** Give the provider its own entry under `sources:` so lineage
   in `make docs` shows where each model comes from.
3. **Ids.** Another provider's match and player ids won't match SkillCorner's.
   Before any cross-provider gold model, build a mapping model in silver that
   links the two sets of ids, and test it: `unique` on each side, and a count
   of rows that failed to map.
