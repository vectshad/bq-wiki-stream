import json
import re
from pathlib import Path

import collect

HERE = Path(__file__).parent
FAR_FUTURE = collect.parse_ts("2999-01-01T00:00:00Z")
LINES = (HERE / "fixtures" / "sample_events.sse").read_bytes().splitlines()


def events():
    return [json.loads(line[5:]) for line in LINES if line.startswith(b"data:")]


def test_keeps_only_enwiki_edit_and_new():
    rows = list(collect.read_rows(LINES, FAR_FUTURE))
    assert len(rows) == 3  # fixture: 3 enwiki edits; wikidata/commons/uk/nl and 'categorize' are dropped
    assert {r["wiki"] for r in rows} == {"enwiki"}
    assert {r["type"] for r in rows} == {"edit"}


def test_user_name_is_never_stored():
    rows = list(collect.read_rows(LINES, FAR_FUTURE))
    assert all("user" not in r for r in rows)
    assert "ExampleEditor" not in json.dumps(rows)


def test_is_anon_for_ip_and_temporary_account():
    flags = [r["is_anon"] for r in collect.read_rows(LINES, FAR_FUTURE)]
    assert flags == [False, True, True]  # named user, IPv4, temporary account (~...)


def test_new_page_has_no_old_length():
    e = next(e for e in events() if e["wiki"] == "enwiki")
    e = {**e, "type": "new", "length": {"new": 390}}
    row = collect.to_row(e)
    assert row["length_old"] is None and row["length_new"] == 390


def sse(dt, wiki="enwiki", type_="edit"):
    e = {"meta": {"id": f"id-{dt}", "dt": dt}, "wiki": wiki, "type": type_, "id": 1, "user": "u"}
    return b"data: " + json.dumps(e).encode()


def test_stops_after_a_streak_of_recent_events():
    stop_at = collect.parse_ts("2026-11-16T08:00:00Z")
    old = [sse(f"2026-11-16T07:59:{s:02d}.000Z") for s in range(10)]
    live = [sse(f"2026-11-16T08:00:{s:02d}.000Z") for s in range(20)]
    consumed = iter(old + live)
    rows = list(collect.read_rows(consumed, stop_at, caught_up_after=5))
    assert len(rows) == 15  # 10 old + the 5 live events that proved we are caught up
    assert len(list(consumed)) == 15  # the rest of the stream was not read


def test_a_lone_recent_event_does_not_stop_the_replay():
    # replays start with stray out-of-order events: one recent event between old ones must not end the run
    stop_at = collect.parse_ts("2026-11-16T08:00:00Z")
    lines = [sse("2026-11-16T08:00:05.000Z"), sse("2026-11-16T07:59:00.000Z")] * 3 + [sse("2026-11-16T07:59:30.000Z")]
    assert len(list(collect.read_rows(lines, stop_at, caught_up_after=2))) == 7


def test_malformed_and_heartbeat_lines_are_skipped():
    lines = [b": hello", b"data: not json", b'data: {"meta": {}}', b""]
    assert list(collect.read_rows(lines, FAR_FUTURE)) == []


def test_deadline_stops_reading():
    assert list(collect.read_rows(LINES, FAR_FUTURE, deadline=0)) == []


def test_row_fields_match_the_table_ddl():
    ddl = (HERE.parent / "scripts" / "bootstrap.sql").read_text()
    columns = re.findall(r"^\s{2}(\w+)\s+(?:STRING|TIMESTAMP|INT64|BOOL)\b", ddl, flags=re.M)
    row = collect.to_row(next(e for e in events() if e["wiki"] == "enwiki"))
    assert set(columns) == set(row)
