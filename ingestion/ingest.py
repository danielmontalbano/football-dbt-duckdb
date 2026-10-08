"""
Ingestion (the 'EL' of ELT).

Downloads SkillCorner open data from GitHub into a local landing zone.
Nothing is transformed here on purpose: the landing zone holds the files
exactly as the provider published them. All logic lives in dbt.

The script is incremental and safe to re-run. The match index is always
re-fetched, because it is how new matches are discovered; the per-match files
are only downloaded if they are not already on disk.

Usage:
    python ingestion/ingest.py            # fetch the index, download what is missing
    python ingestion/ingest.py --force    # re-download everything
"""

import argparse
import json
import sys
from pathlib import Path

import requests

BASE_URL = "https://raw.githubusercontent.com/SkillCorner/opendata/master/data"
LANDING = Path(__file__).resolve().parents[1] / "data" / "landing"


def download(url: str, dest: Path, force: bool = False) -> bool:
    """Download `url` to `dest`. Returns True if a file was written."""
    if dest.exists() and not force:
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    response = requests.get(url, timeout=60)
    response.raise_for_status()
    dest.write_bytes(response.content)
    print(f"  landed {len(response.content) / 1e6:6.2f} MB  {dest.name}")
    return True


def match_files(match_id: int) -> list[tuple[str, Path]]:
    """The (url, destination) pairs that make up one match."""
    return [
        (
            f"{BASE_URL}/matches/{match_id}/{match_id}_match.json",
            LANDING / "match_info" / f"{match_id}_match.json",
        ),
        (
            f"{BASE_URL}/matches/{match_id}/{match_id}_dynamic_events.csv",
            LANDING / "dynamic_events" / f"{match_id}_dynamic_events.csv",
        ),
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true", help="re-download files that already exist")
    args = parser.parse_args()

    print(f"Landing zone: {LANDING}")

    # The index is ALWAYS re-fetched. It is how a match played since the last
    # run gets discovered - caching it would make the pipeline permanently
    # blind to new data.
    print("\nMatch index (always refreshed)")
    index_path = LANDING / "matches.json"
    download(f"{BASE_URL}/matches.json", index_path, force=True)
    match_ids = [match["id"] for match in json.loads(index_path.read_text())]

    complete = [m for m in match_ids if all(dest.exists() for _, dest in match_files(m))]
    pending = [m for m in match_ids if m not in complete]

    print(f"  {len(match_ids)} matches in the index")
    print(f"  {len(complete)} already landed")
    if args.force:
        pending = match_ids
        print(f"  {len(pending)} to re-download (--force)")
    elif pending:
        print(f"  {len(pending)} to download: {pending}")
    else:
        print("  nothing new")

    downloaded = 0
    for match_id in pending:
        print(f"\nMatch {match_id}")
        for url, dest in match_files(match_id):
            downloaded += download(url, dest, args.force)

    print(f"\nIngestion complete - {downloaded} file(s) written.")
    if downloaded:
        print("Run `make build` to fold the new data into the warehouse.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
