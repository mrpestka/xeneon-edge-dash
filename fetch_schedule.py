#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["icalendar>=6", "recurring-ical-events>=3", "tzdata"]
# ///
"""Pull every ICS feed listed in the config, expand recurrences, and write
schedule.json next to the dashboard page.

Config: ~/.config/edge-dash/calendars.toml (override with $EDGE_CALENDARS), see
calendars.example.toml. Safe to run from a timer: one failing feed keeps the
others, and if every feed fails the previous schedule.json is left untouched.
URLs are never logged."""
import json, os, sys, tomllib, urllib.request
from datetime import date, datetime, timedelta, time
from pathlib import Path
from zoneinfo import ZoneInfo

import icalendar
import recurring_ical_events

HERE = Path(__file__).resolve().parent
CONFIG = Path(os.environ.get("EDGE_CALENDARS", Path.home() / ".config/edge-dash/calendars.toml"))
OUT = HERE / "schedule.json"


def load_feed(url: str) -> bytes:
    if url.startswith("file://"):
        return Path(url[7:]).read_bytes()
    req = urllib.request.Request(url, headers={"User-Agent": "edge-dash/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def main() -> int:
    if not CONFIG.exists():
        print(f"no config at {CONFIG}; writing empty schedule", file=sys.stderr)
        OUT.write_text(json.dumps({"generated": datetime.now().isoformat(timespec="seconds"),
                                   "calendars": [], "days": {}, "error": f"missing {CONFIG}"}))
        return 0

    cfg = tomllib.loads(CONFIG.read_text())
    tz = ZoneInfo(cfg["timezone"]) if cfg.get("timezone") else datetime.now().astimezone().tzinfo
    today = datetime.now(tz).date()
    start = today - timedelta(days=int(cfg.get("past_days", 45)))
    end = today + timedelta(days=int(cfg.get("future_days", 75)))

    days: dict[str, list] = {}
    cals_out, errors = [], []
    for cal in cfg.get("calendar", []):
        name, url, color = cal["name"], cal["url"], cal.get("color", "#e8457a")
        cals_out.append({"name": name, "color": color})
        try:
            ics = icalendar.Calendar.from_ical(load_feed(url))
        except Exception as e:  # noqa: BLE001
            errors.append(f"{name}: {e}")
            print(f"[{name}] fetch/parse failed: {e}", file=sys.stderr)
            continue
        n = 0
        for ev in recurring_ical_events.of(ics).between(start, end):
            ds, de = ev.get("DTSTART").dt, (ev.get("DTEND").dt if ev.get("DTEND") else None)
            all_day = not isinstance(ds, datetime)
            if all_day:
                s_local = datetime.combine(ds, time.min, tz)
                e_local = datetime.combine(de or ds + timedelta(days=1), time.min, tz)
            else:
                if ds.tzinfo is None:
                    ds = ds.replace(tzinfo=tz)
                s_local = ds.astimezone(tz)
                if de is None:
                    de = ds + timedelta(hours=1)
                if de.tzinfo is None:
                    de = de.replace(tzinfo=tz)
                e_local = de.astimezone(tz)
            status = str(ev.get("STATUS", "")).upper()
            if status == "CANCELLED":
                continue
            item = {
                "title": str(ev.get("SUMMARY", "(untitled)")),
                "location": str(ev.get("LOCATION", "") or ""),
                "allDay": all_day,
                "start": s_local.isoformat(timespec="minutes"),
                "end": e_local.isoformat(timespec="minutes"),
                "calendar": name,
                "color": color,
            }
            # file multi-day events under every day they touch
            d = s_local.date()
            last = (e_local - timedelta(seconds=1)).date() if e_local > s_local else d
            while d <= last:
                days.setdefault(d.isoformat(), []).append(item)
                d += timedelta(days=1)
            n += 1
        print(f"[{name}] {n} events", file=sys.stderr)

    for lst in days.values():
        lst.sort(key=lambda e: (not e["allDay"], e["start"]))

    if errors and len(errors) == len(cals_out) and cals_out:
        print("every feed failed; keeping previous schedule.json", file=sys.stderr)
        return 1
    OUT.write_text(json.dumps({"generated": datetime.now(tz).isoformat(timespec="seconds"),
                               "calendars": cals_out, "days": days, "errors": errors}, ensure_ascii=False))
    OUT.chmod(0o600)  # event titles/locations are personal; keep them owner-only
    print(f"wrote {OUT} ({len(days)} days)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
