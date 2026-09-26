"""Record a putting session: prints each putt's tempo live and saves the data for later analysis.

Usage: .venv/bin/python record.py        (Ctrl-C to finish)

Writes to data/<session start>/:
    samples.jsonl  every sensor reading, including waggles and missed putts
    strokes.csv    one row per detected putt; rec_start/rec_end bound its samples
"""

import csv
import json
from datetime import datetime
from pathlib import Path

import airpods
import putting

FIELDS = ["putt", "rec_start", "rec_end", "start_time", "backswing", "downswing",
          "tempo_ratio", "total", "backswing_angle", "impact_speed"]

session = Path(__file__).parent / "data" / datetime.now().strftime("%Y-%m-%d_%H%M%S")
session.mkdir(parents=True)
detector = putting.StrokeDetector()
strokes = []
phase = None

print(f"saving to {session}\nhold the putter still over the ball to arm, then putt (Ctrl-C to finish)")
with open(session / "samples.jsonl", "w") as raw, open(session / "strokes.csv", "w", newline="") as out:
    rows = csv.DictWriter(out, FIELDS)
    rows.writeheader()
    try:
        for r in airpods.stream():
            if "event" in r:
                print("status:", r)
                continue
            raw.write(json.dumps(r) + "\n")
            result = detector.process(r)
            if detector.phase != phase:
                phase = detector.phase
                if phase == "ready":
                    print("ready")
            if result:
                stroke, samples = result
                strokes.append(stroke)
                rows.writerow({"putt": len(strokes), "rec_start": samples[0]["t"],
                               "rec_end": samples[-1]["t"], **stroke.features()})
                out.flush()
                print(f"putt {len(strokes)}: {stroke.tempo_ratio:.2f}:1  back {stroke.backswing:.2f}s  "
                      f"through {stroke.downswing:.2f}s  {stroke.backswing_angle:.1f}°")
    except KeyboardInterrupt:
        airpods.stop()

stats = putting.summarise(strokes)
if stats:
    t = stats["tempo_ratio"]
    print(f"\n{stats['count']} putts, tempo {t['mean']:.2f}:1 ± {t['sd']:.2f} (CV {t['cv']:.0%})")
