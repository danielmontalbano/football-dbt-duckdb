# Everything runs locally. No cloud account, no credentials, no cost.

VENV := .venv
PY   := $(VENV)/bin/python
DBT  := cd transform && DBT_PROFILES_DIR=. ../$(VENV)/bin/dbt

.PHONY: setup ingest update build test docs query clean help

help:
	@echo "make setup    - create the virtualenv and install dbt-duckdb"
	@echo "make ingest   - download SkillCorner open data into data/landing/"
	@echo "make update   - fetch any new matches and rebuild"
	@echo "make build    - run the bronze -> silver -> gold models and their tests"
	@echo "make test     - run the tests only"
	@echo "make docs     - build and serve the dbt docs + lineage graph"
	@echo "make query    - open a DuckDB shell on the warehouse"
	@echo "make clean    - delete the warehouse (landed files are kept)"

setup:
	uv venv $(VENV)
	uv pip install --python $(PY) -r pyproject.toml

ingest:
	$(PY) ingestion/ingest.py

update: ingest build

build:
	$(DBT) build

test:
	$(DBT) test

docs:
	$(DBT) docs generate && DBT_PROFILES_DIR=. ../$(VENV)/bin/dbt docs serve

query:
	duckdb data/warehouse/football.duckdb

clean:
	rm -f data/warehouse/football.duckdb
	rm -rf transform/target transform/logs
