# Add a source

A source is a set of raw files from a provider. There are two ways to add one,
and this guide covers both:

- **[Part 1](#part-1-a-new-file-from-a-provider-you-already-have)**: a new
  file from a provider the pipeline already uses. A worked example, start to
  finish, with SkillCorner's Phases of Play file.
- **[Part 2](#part-2-a-new-provider)**: a new provider. The same steps, plus
  the few things that are new: a script, folders, a licence check and ids.

## What adding a source touches

Every source goes through the same six places. Nothing else in the project
needs to change.

| # | What | Where | New file, same provider | New provider |
|---|---|---|---|---|
| 1 | Download | `ingestion/<provider>.py` | add the file to the existing script | new script |
| 2 | Raw files | `data/raw/<provider>/<file_type>/` | new folder for the file type | new provider folder |
| 3 | Source | `transform/models/staging/<provider>/_<provider>__sources.yml` | add a table | new file |
| 4 | Staging | `transform/models/staging/<provider>/stg_<provider>__<entity>.sql` | new model | new folder and model |
| 5 | Intermediate | `transform/models/intermediate/<provider>/int_<provider>__<entity>.sql` | new model | new folder and model |
| 6 | Mart | `transform/models/marts/<provider>/<what_it_answers>.sql` | new model | new folder and model |

Each model also gets tests in the `.yml` file next to it. The schema and
materialisation come from the layer folder (`staging/`, `intermediate/`,
`marts/`) in `dbt_project.yml`, so a new model or a new provider folder needs
no configuration.

---

# Part 1: a new file from a provider you already have

The example uses a file SkillCorner already publishes and this project doesn't
use yet: **Phases of Play**.

By the end you will have:

- `{id}_phases_of_play.csv` downloaded for every match
- `stg_skillcorner__phases_of_play`, the file as delivered
- `int_skillcorner__phases_of_play`, typed, with a proper key
- `team_phase_summary`, how much time each team spends in each phase

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

   Across all twenty matches, that returns `8834, 490, 8834`. `index` restarts at 0
   every match, so the real key is `(match_id, index)`, the same trap as
   `event_id` in dynamic events.
3. **How does it join to what you already have?** `match_id` joins to
   `stg_skillcorner__matches`, and `team_in_possession_id` joins to the team
   ids there. The provider is the same, so the ids already agree. A new
   provider needs an id mapping, which is covered in Part 2.

---

## Step 1: Download the files (`ingestion/skillcorner.py`)

Ingestion copies files into `data/raw/skillcorner/`, byte for byte. It doesn't
parse or clean anything; that's dbt's job.

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
> `data/raw/<provider>/`, so the dbt source can read it with a single glob.
> Don't mix file types in one folder.

---

## Step 2: Declare the source (`transform/models/staging/skillcorner/_skillcorner__sources.yml`)

Tell dbt where the files are. dbt-duckdb reads them straight off disk, so
there's no load step:

```yaml
      - name: phases_of_play
        description: One CSV per match, one row per phase of play.
        meta:
          external_location: "read_csv('../data/raw/skillcorner/phases_of_play/*.csv', union_by_name=true, sample_size=-1, filename=true)"
```

What each option does:

| Option | Why |
|---|---|
| `../data/raw/...` | dbt runs from `transform/`, so paths are relative to it |
| `union_by_name=true` | Columns are matched by name, so a file with an extra or reordered column doesn't break the read |
| `sample_size=-1` | DuckDB reads every row to infer types, instead of guessing from the first few thousand |
| `filename=true` | Adds a `filename` column, which becomes `_source_file` in staging |

> **Download the files before you build.** If the glob matches no files,
> DuckDB stops with `No files found that match the pattern`. Run `make ingest`
> first.

---

## Step 3: Staging, the file as delivered

A staging model has exactly one source and is named
`stg_<provider>__<entity>`, with two underscores between provider and entity.

Create `transform/models/staging/skillcorner/stg_skillcorner__phases_of_play.sql`:

```sql
-- Staging: phases of play, as delivered.
-- The provider's column names are already snake_case, so nothing is renamed.
-- The only additions are provenance: which file each row came from and when
-- it was loaded.

select
    * exclude (filename),
    filename as _source_file,
    current_localtimestamp() as _loaded_at
from {{ source('skillcorner', 'phases_of_play') }}
```

Staging has one rule: **no business logic.** It may rename, cast and flatten,
but it doesn't filter rows, join other models or fix values. If a mart number
is ever disputed, staging is what you compare with the original file.

Add basic tests to `transform/models/staging/skillcorner/_skillcorner__models.yml`:

```yaml
  - name: stg_skillcorner__phases_of_play
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

## Step 4: Intermediate, typed and keyed

Intermediate is where the file becomes pleasant to use. Pick the columns you
need, cast them, rename them so they read clearly, and build the real key.

Create `transform/models/intermediate/skillcorner/int_skillcorner__phases_of_play.sql`:

```sql
-- Intermediate: one row per phase of play.
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

from {{ ref('stg_skillcorner__phases_of_play') }}
```

Add tests to `transform/models/intermediate/skillcorner/_int_skillcorner__models.yml`:

```yaml
  - name: int_skillcorner__phases_of_play
    description: One row per phase of play.
    columns:
      - name: phase_id
        data_tests: [not_null, unique]
      - name: match_id
        data_tests:
          - not_null
          - relationships:
              arguments:
                  to: ref('stg_skillcorner__matches')
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
  mart quietly changing shape. The eight values listed are the ones in the
  current twenty matches.

---

## Step 5: Mart, answer a question

A mart is named after the question it answers, with no prefix. This one
answers **"How does each team spend its time on the ball?"**

Create `transform/models/marts/skillcorner/team_phase_summary.sql`:

```sql
-- Mart: time each team spends in each in-possession phase, per match.
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
    from {{ ref('int_skillcorner__phases_of_play') }}
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
from main_marts.team_phase_summary
where match_id = 2017461
order by team_name, pct_of_possession_time desc;
```

---

## Step 6: Reconcile

Tests check each column. A reconciliation checks that no rows went missing
between layers:

```sql
select
    (select count(*) from main_staging.stg_skillcorner__phases_of_play) as staging_rows,
    (select count(*) from main_intermediate.int_skillcorner__phases_of_play) as intermediate_rows;
```

Both should be 8,834 for the twenty current matches. The intermediate model
doesn't filter this file, so any difference means a cast or a join dropped
rows.

---

## Checklist for a new file

- [ ] Profiled the file: one row = ?, key = ?, joins on = ?
- [ ] Added it to `ingestion/skillcorner.py`, in its own folder under `data/raw/skillcorner/`
- [ ] Declared it in `_skillcorner__sources.yml` with `filename=true`
- [ ] Staging: one source, `_source_file` and `_loaded_at` added, no filters or joins
- [ ] Intermediate: explicit columns, casts, predicate-style booleans, surrogate key
- [ ] Tests: `unique` + `not_null` on the key, `relationships` on `match_id`, `accepted_values` on categories
- [ ] Mart: named for its question, counts kept next to every rate
- [ ] Row counts reconcile from staging to intermediate
- [ ] `make clean && make build` passes from scratch

---

# Part 2: a new provider

Do Part 1 once first: the six places are the same. This part lists only what
is different. `<provider>` stands for a short lowercase name, such as
`skillcorner`.

## Before you start: read the licence

Open data isn't always MIT. Some releases forbid redistribution or commercial
use, or require attribution. Read the terms before you download anything, then:

- add the provider and its licence to `NOTICE.md`;
- never commit the files: everything under `data/raw/` is gitignored;
- if the terms are stricter than the rest of the project, keep that provider's
  models off unless asked for, by adding this under each layer in
  `dbt_project.yml`:

  ```yaml
      staging:
        +schema: staging
        <provider>:
          +enabled: "{{ var('<provider>', false) }}"
  ```

  and building it with `dbt build --vars '{<provider>: true}'`.

## 1. Ingestion: a script of its own

Copy `ingestion/skillcorner.py` to `ingestion/<provider>.py` and change three
things:

| In the script | Change it to |
|---|---|
| `BASE_URL` | where the provider publishes its files |
| `LANDING` | `data/raw/<provider>` |
| `match_files()` and the index it loops over | the provider's own file list |

Keep the two rules the existing script follows:

- **Don't transform anything.** Files land exactly as published.
- **Always re-fetch the index.** If the provider publishes a file listing what
  is available, that is how new data gets discovered. If the index also says
  when each item last changed, store that and download the item again when it
  moves.

Then add the script to the `ingest` target in the `Makefile`, so `make ingest`
and `make update` run both:

```make
ingest:
	$(PY) ingestion/skillcorner.py
	$(PY) ingestion/<provider>.py
```

## 2. The source: its own file and folders

Create one folder per layer, and declare the source in the staging folder:

```
transform/models/staging/<provider>/_<provider>__sources.yml
transform/models/staging/<provider>/_<provider>__models.yml
transform/models/intermediate/<provider>/_int_<provider>__models.yml
transform/models/marts/<provider>/_<provider>__models.yml
```

```yaml
version: 2

sources:
  - name: <provider>
    description: Files downloaded by ingestion/<provider>.py into data/raw/<provider>/.
    tables:
      - name: <file_type>
        meta:
          external_location: "read_json('../data/raw/<provider>/<file_type>/*.json', union_by_name=true, filename=true)"
```

Use `read_csv` or `read_json` to match the files. Giving the provider its own
`sources:` entry is what makes lineage in `make docs` show where each model
comes from.

## 3. Staging, intermediate, marts: same rules, provider in the name

Follow Steps 3 to 5 of Part 1. The provider goes in the model name for staging
and intermediate, with two underscores before the entity:

- `stg_<provider>__<entity>`: one source each, renamed to snake_case, cast,
  flattened, plus `_source_file` and `_loaded_at`. No joins, no filters.
- `int_<provider>__<entity>`: the grain you want to work with, a real key,
  joins to names.
- marts: named for what they answer. Model names must be unique across the
  project, so check a name isn't already taken by another provider's mart.

Profile the files first, as in Step 0. Every provider has its own version of
the `event_id` trap: find the real key before you write the first model, and
pin it with a `unique` test.

## 4. Ids: don't join providers until they map

Another provider's match, team and player ids won't match SkillCorner's. Two
marts from two providers can sit side by side with no mapping. Before a mart
that *combines* them, build a mapping model in intermediate, for example
`int_<provider>__skillcorner_match_ids`, and test it:

- `unique` on each side, so one match never maps to two;
- a count of rows that failed to map, so a gap is visible instead of silently
  dropping matches from the join.

Some providers publish the other provider's ids themselves. Use those when they
exist; otherwise match on date and team names, and review what doesn't match
by hand.

## Checklist for a new provider

- [ ] Licence read; provider added to `NOTICE.md`
- [ ] `ingestion/<provider>.py` writes to `data/raw/<provider>/`, one folder per file type
- [ ] Script added to the `ingest` target in the `Makefile`
- [ ] `_<provider>__sources.yml` declares each file type with `filename=true`
- [ ] A `<provider>/` folder in `staging/`, `intermediate/` and `marts/`
- [ ] Models named `stg_<provider>__…` and `int_<provider>__…`; mart names unique
- [ ] The real key found, built and tested with `unique`
- [ ] No cross-provider mart without a tested id mapping
- [ ] `make clean && make build` passes from scratch
