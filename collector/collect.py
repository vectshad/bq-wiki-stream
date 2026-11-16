"""Wikimedia recentchange -> BigQuery raw.wiki_edits (micro-batch, at-least-once).

Catch-up mode: replay the stream from the last loaded event up to "now", append one load job, exit.
Run it every 15 minutes (cron / GitHub Actions). The small overlap re-reads a few events; staging dedupes by event_id.
"""
import argparse
import ipaddress
import json
import os
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime

URL = "https://stream.wikimedia.org/v2/stream/recentchange"
USER_AGENT = "bq-wiki-stream-portfolio/0.1 (educational pipeline)"
PROJECT = os.environ.get("GCP_PROJECT", "bq-stream-514812")
TABLE = f"{PROJECT}.raw.wiki_edits"
BUDGET_BYTES = 3 * 2**30  # decisions D7: stop loading when raw passes 3 GiB
OVERLAP = timedelta(minutes=2)
MAX_REPLAY = timedelta(days=6)  # the stream keeps 7-31 days of history


def parse_ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def is_anon(user):
    try:
        ipaddress.ip_address(user)
        return True
    except ValueError:
        return user.startswith("~")  # temporary accounts


def to_row(e):
    """enwiki edit/new event -> raw row, or None. The user name is never kept (decisions D5)."""
    if e.get("wiki") != "enwiki" or e.get("type") not in ("edit", "new"):
        return None
    length = e.get("length") or {}
    return {
        "event_id": e["meta"]["id"],
        "event_ts": e["meta"]["dt"],
        "rc_id": e.get("id"),
        "wiki": e["wiki"],
        "type": e["type"],
        "namespace": e.get("namespace"),
        "title": e.get("title"),
        "bot": bool(e.get("bot")),
        "minor": bool(e.get("minor")),
        "is_anon": is_anon(e.get("user") or ""),
        "length_old": length.get("old"),
        "length_new": length.get("new"),
    }


def read_rows(lines, stop_at, deadline=float("inf"), caught_up_after=25):
    """Yield rows from SSE lines until the replay has caught up with the live stream, or past the deadline.

    Caught up = `caught_up_after` events in a row at/after stop_at. A single event is not enough: a replay
    starts with a few out-of-order events (stale ones and heartbeats), so one recent event proves nothing.
    """
    streak = 0
    for line in lines:
        if time.monotonic() > deadline:
            return
        if not line.startswith(b"data:"):
            continue
        try:
            event = json.loads(line[5:])
            streak = streak + 1 if parse_ts(event["meta"]["dt"]) >= stop_at else 0
            row = to_row(event)
        except (ValueError, KeyError):
            continue  # malformed event: skip, do not fail the batch
        if row:
            yield row
        if streak >= caught_up_after:
            return


def last_loaded(client):
    from google.cloud import bigquery

    sql = f"SELECT MAX(event_ts) FROM `{TABLE}` WHERE DATE(event_ts) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)"
    job = client.query(sql, job_config=bigquery.QueryJobConfig(maximum_bytes_billed=10**9))
    return next(iter(job.result()))[0]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--bootstrap-minutes", type=int, default=60, help="window for the very first run")
    ap.add_argument("--max-seconds", type=int, default=600, help="stop reading after this long and load what we have")
    ap.add_argument("--dry-run", action="store_true", help="read the stream and print stats; no BigQuery access at all")
    args = ap.parse_args()

    now = datetime.now(timezone.utc)
    client = None
    if args.dry_run:
        last = None
    else:
        from google.cloud import bigquery

        client = bigquery.Client(project=PROJECT)
        if client.get_table(TABLE).num_bytes > BUDGET_BYTES:
            sys.exit(f"{TABLE} is over the {BUDGET_BYTES} byte budget; not loading (decisions D7)")
        last = last_loaded(client)

    start = last - OVERLAP if last else now - timedelta(minutes=args.bootstrap_minutes)
    if start < now - MAX_REPLAY:
        print("WARNING: checkpoint older than the replay window; there will be a gap", file=sys.stderr)
        start = now - MAX_REPLAY
    url = f"{URL}?since={urllib.parse.quote(start.strftime('%Y-%m-%dT%H:%M:%SZ'))}"

    n = 0
    with tempfile.NamedTemporaryFile("w", suffix=".ndjson", delete=False) as f:
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=60) as stream:
            # "now" comes from the server's clock: this PC's clock can be ~1 minute off the event times
            date = stream.headers.get("Date")
            server_now = parsedate_to_datetime(date) if date else now
            stop_at = server_now - timedelta(seconds=5)
            print(f"reading {start:%Y-%m-%d %H:%M:%S}Z -> {stop_at:%Y-%m-%d %H:%M:%S}Z (server time)")
            for row in read_rows(stream, stop_at, time.monotonic() + args.max_seconds):
                f.write(json.dumps(row) + "\n")
                n += 1
                if n == 1 and args.dry_run:
                    print("first row:", json.dumps(row))
    size = os.path.getsize(f.name)
    print(f"{n} rows, {size} bytes of NDJSON")

    if args.dry_run or n == 0:
        if args.dry_run:
            print(f"dry run: not loaded ({f.name})")
        os.unlink(f.name)
        return
    from google.cloud import bigquery

    cfg = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
    )
    with open(f.name, "rb") as fh:
        client.load_table_from_file(fh, TABLE, job_config=cfg).result()
    os.unlink(f.name)
    print(f"loaded {n} rows into {TABLE}")


if __name__ == "__main__":
    main()
