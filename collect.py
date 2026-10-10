"""Collect labelled rest and putt data, to tune what counts as a putt versus normal movement.

Usage: .venv/bin/python collect.py [rests] [putts]      (default 5 of each)

Spoken cues guide each trial, so you don't need to watch the screen:
    rest   hold the putter still over the ball
    putt   "address": settle over the ball; "putt": make one stroke after the beep
Between trials ("between") you can reset the ball; that movement is kept too.

Writes to data/labelled/<session start>/:
    samples.jsonl  every sensor reading plus `label` and `trial`
    trials.csv     one row per trial with its label and start/end times
"""

import csv
import json
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

import airpods

RESTS = int(sys.argv[1]) if len(sys.argv) > 1 else 5
PUTTS = int(sys.argv[2]) if len(sys.argv) > 2 else 5
REST_SECONDS = 6
ADDRESS_SECONDS = 3
PUTT_SECONDS = 6
BETWEEN_SECONDS = 5

session = Path(__file__).parent / "data" / "labelled" / datetime.now().strftime("%Y-%m-%d_%H%M%S")
session.mkdir(parents=True)
state = {"label": "setup", "trial": 0, "t": None}
started = threading.Event()
trials = []


def say(text):
    print(text, flush=True)
    subprocess.run(["say", text])


def beep():
    subprocess.run(["afplay", "/System/Library/Sounds/Tink.aiff"])


def segment(label, trial, seconds):
    state.update(label=label, trial=trial)
    start = state["t"]
    time.sleep(seconds)
    trials.append({"trial": trial, "label": label, "start": start, "end": state["t"]})


def protocol():
    started.wait()
    say(f"Sensor connected. {RESTS} rests, then {PUTTS} putts. Get in position.")
    time.sleep(8)
    for i in range(1, RESTS + 1):
        say(f"Rest {i}. Hold still over the ball.")
        segment("rest", i, REST_SECONDS)
        state.update(label="between")
        say("Relax.")
        time.sleep(BETWEEN_SECONDS)
    for i in range(1, PUTTS + 1):
        say(f"Putt {i}. Address the ball.")
        segment("address", RESTS + i, ADDRESS_SECONDS)
        state.update(label="putt")
        beep()
        segment("putt", RESTS + i, PUTT_SECONDS)
        state.update(label="between")
        say("Stop. Reset the ball.")
        time.sleep(BETWEEN_SECONDS)
    say("All done.")
    airpods.stop()


threading.Thread(target=protocol, daemon=True).start()
print(f"saving to {session}")
with open(session / "samples.jsonl", "w") as raw:
    try:
        for r in airpods.stream():
            if "event" in r:
                print("status:", r)
                continue
            state["t"] = r["t"]
            started.set()
            raw.write(json.dumps({**r, "label": state["label"], "trial": state["trial"]}) + "\n")
    except KeyboardInterrupt:
        airpods.stop()

with open(session / "trials.csv", "w", newline="") as out:
    rows = csv.DictWriter(out, ["trial", "label", "start", "end"])
    rows.writeheader()
    rows.writerows(trials)
print(f"{len(trials)} segments saved to {session}")
