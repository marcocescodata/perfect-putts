"""Read live AirPods motion from Python via the AirpodStream helper app.

    for reading in airpods.stream():
        print(reading)

Each reading is a dict. Sensor samples have t (seconds), gx/gy/gz (gyro, rad/s) and
ax/ay/az (acceleration, g). Status messages have an "event" key instead.
"""

import json
import os
import subprocess
import tempfile
from pathlib import Path

APP = Path(__file__).parent / "bridge" / "AirpodStream.app"


def stream():
    if not APP.exists():
        raise SystemExit("Helper not built yet — run ./bridge/build.sh first.")

    fifo = Path(tempfile.mkdtemp()) / "airpods.fifo"
    os.mkfifo(fifo)
    # `open` launches the helper as its own app, which is what lets macOS grant it motion access.
    subprocess.run(["open", "-g", "-n", str(APP), "--stdout", str(fifo), "--stderr", str(fifo)], check=True)
    try:
        with open(fifo) as lines:
            for line in lines:
                line = line.strip()
                if line.startswith("{"):
                    yield json.loads(line)
    finally:
        stop()
        fifo.unlink(missing_ok=True)


def stop():
    """Quit the helper, which also ends any running stream()."""
    subprocess.run(["pkill", "-f", f"{APP.name}/Contents/MacOS/airpod-stream"])
