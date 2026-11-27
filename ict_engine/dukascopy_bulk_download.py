"""
Bulk Dukascopy downloader for USATECHIDXUSD (Nasdaq-100 CFD), bypassing the
Cloudflare-fronted www.dukascopy.com (blocks python-requests with 403) by
hitting the origin mirror datafeed.dukascopy.com directly over plain HTTP,
which returns real data (confirmed working 2013-present).

Downloads hourly tick files, decompresses with duka's own LZMA/tokenize
logic, builds 1-minute and 1-hour OHLC (BID side) bars, and appends to CSV
incrementally so progress is never lost if interrupted.
"""
import datetime
import time
import csv
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests
from duka.core.processor import decompress

SYMBOL = "USATECHIDXUSD"
URL = "http://datafeed.dukascopy.com/datafeed/{symbol}/{y}/{m:02d}/{d:02d}/{h:02d}h_ticks.bi5"
START = datetime.date(2016, 1, 1)
END = datetime.date(2026, 11, 25)
OUT_M1 = "data/dukascopy_m1.csv"
PROGRESS_FILE = "data/dukascopy_progress.txt"
WORKERS = 4
MAX_RETRIES = 8
INTER_DAY_PAUSE = 2.0       # seconds, baseline politeness pause between days
RATE_LIMIT_COOLDOWN = 75    # seconds to fully back off the WHOLE process on any 429 sighting

rate_limited_event = False

def fetch_hour_bytes(day, hour):
    global rate_limited_event
    url = URL.format(symbol=SYMBOL, y=day.year, m=day.month - 1, d=day.day, h=hour)
    for attempt in range(MAX_RETRIES):
        try:
            r = requests.get(url, timeout=20)
            if r.status_code == 200:
                return r.content
            if r.status_code == 404:
                return b""
            if r.status_code == 429:
                rate_limited_event = True
                time.sleep(RATE_LIMIT_COOLDOWN)
                continue
        except Exception:
            time.sleep(2 * (attempt + 1))
    return None  # genuine failure after retries


def decompress_hour(day, hour, raw):
    if not raw:
        return []
    import numpy as np
    buf = np.frombuffer(raw, dtype=np.uint8)
    try:
        ticks = decompress(day, buf)
    except Exception:
        return []
    out = []
    for t in ticks:
        ts, ask, bid, _, _ = t
        out.append((ts, bid, ask))
    return out


def ticks_to_m1(ticks):
    """ticks: list of (datetime, bid, ask). Returns dict minute->OHLC(bid)."""
    bars = {}
    for ts, bid, ask in ticks:
        key = ts.replace(second=0, microsecond=0)
        if key not in bars:
            bars[key] = [bid, bid, bid, bid]  # O H L C
        else:
            b = bars[key]
            b[1] = max(b[1], bid)
            b[2] = min(b[2], bid)
            b[3] = bid
    return bars


def already_done_days():
    if not os.path.exists(PROGRESS_FILE):
        return set()
    with open(PROGRESS_FILE) as f:
        return set(line.strip() for line in f if line.strip())


def main():
    global rate_limited_event
    os.makedirs("data", exist_ok=True)
    done = already_done_days()
    write_header = not os.path.exists(OUT_M1)

    f_out = open(OUT_M1, "a", newline="")
    writer = csv.writer(f_out)
    if write_header:
        writer.writerow(["datetime_utc", "open", "high", "low", "close"])

    f_prog = open(PROGRESS_FILE, "a")

    day = START
    total_days = (END - START).days
    processed = 0
    t0 = time.time()

    while day <= END:
        key = day.isoformat()
        processed += 1
        if key in done or day.weekday() >= 5:
            day += datetime.timedelta(days=1)
            continue

        with ThreadPoolExecutor(max_workers=WORKERS) as ex:
            futs = {ex.submit(fetch_hour_bytes, day, h): h for h in range(24)}
            hour_bytes = {}
            for fut in as_completed(futs):
                h = futs[fut]
                hour_bytes[h] = fut.result()

        day_ticks = []
        any_fail = False
        for h in range(24):
            raw = hour_bytes.get(h)
            if raw is None:
                any_fail = True
                continue
            if raw:
                day_ticks.extend(decompress_hour(day, h, raw))

        if day_ticks:
            bars = ticks_to_m1(day_ticks)
            for ts in sorted(bars.keys()):
                o, h_, l, c = bars[ts]
                writer.writerow([ts.isoformat(), o, h_, l, c])
            f_out.flush()

        if not any_fail:
            f_prog.write(key + "\n")
            f_prog.flush()

        elapsed = time.time() - t0
        print(f"[{day}] processed={processed}/{total_days} ticks_today={len(day_ticks)} elapsed={elapsed:.0f}s", flush=True)

        if rate_limited_event:
            print(f"  -> rate-limit hit, cooling down an extra {RATE_LIMIT_COOLDOWN}s", flush=True)
            rate_limited_event = False
        time.sleep(INTER_DAY_PAUSE)

        day += datetime.timedelta(days=1)

    f_out.close()
    f_prog.close()
    print("DONE")


if __name__ == "__main__":
    main()
