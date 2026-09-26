"""Print raw AirPods gyro readings, to check the sensor reaches Python.

Usage: .venv/bin/python probe.py [seconds]
"""

import sys
import threading

import airpods

duration = float(sys.argv[1]) if len(sys.argv) > 1 else 15
count = 0
threading.Timer(duration, airpods.stop).start()  # ends the stream even if no data arrives

print(f"listening for {duration:.0f}s — wiggle the AirPod (Ctrl-C to stop)...")
try:
    for r in airpods.stream():
        if "event" in r:
            print("status:", r)
        else:
            count += 1
            print(f"{r['t']:.3f}  gyro x={r['gx']:+.3f} y={r['gy']:+.3f} z={r['gz']:+.3f} rad/s")
except KeyboardInterrupt:
    airpods.stop()
print(f"received {count} samples (~{count / duration:.1f} Hz)")
