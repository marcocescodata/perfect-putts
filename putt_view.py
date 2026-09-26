"""Window for one putt at a time: hit Run, hold still at address, putt, see the head's path.

Usage: .venv/bin/python putt_view.py

Each putt is also saved to data/putts/<time>.json (features + raw samples).
"""

import json
import queue
import threading
from datetime import datetime
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.widgets import Button

import airpods
import putting

ADDRESS_SECONDS = 3.0
MIN_HALF_SPAN_CM = 3
PUTTS = Path(__file__).parent / "data" / "putts"
PHASES = [("backswing", "#2a78d6"), ("downswing", "#d6532a"), ("follow-through", "#8a8a8a")]

readings = queue.Queue()
streaming = False
detector = None  # set by Run; None while idle


def stream():
    try:
        for r in airpods.stream():
            readings.put(r)
    except SystemExit as e:  # helper not built
        readings.put({"event": "error", "message": str(e)})


def run(_):
    global detector, streaming
    with readings.mutex:
        readings.queue.clear()  # drop anything from before Run
    if not streaming:
        threading.Thread(target=stream, daemon=True).start()
        streaming = True
    detector = putting.StrokeDetector(putting.DetectorConfig(address_duration=ADDRESS_SECONDS, pre_roll=2.0))
    status(f"Hold still at address for {ADDRESS_SECONDS:.0f} s…")


def status(text):
    title.set_text(text)
    fig.canvas.draw_idle()


def poll():
    global detector
    while not readings.empty():
        r = readings.get()
        if "event" in r:
            if r["event"] in ("error", "disconnected"):
                status(f"AirPod {r['event']}: {r.get('message', '')}")
            continue
        if detector is None:
            continue
        before = detector.phase
        result = detector.process(r)
        if result:
            stroke, samples = result
            detector = None
            show(stroke, samples)
            save(stroke, samples)
            return
        if detector.phase == "waiting":
            if before == "stroke":
                status("That didn't look like a putt. Hold still to try again.")
            elif detector.still_since is not None:
                left = ADDRESS_SECONDS - (r["t"] - detector.still_since)
                status(f"Hold still at address… {left:.1f} s")
            else:
                status(f"Hold still at address for {ADDRESS_SECONDS:.0f} s…")
        elif detector.phase == "ready" and before != "ready":
            status("Ready: putt when you like")
        elif detector.phase == "stroke" and before != "stroke":
            status("Putting…")


def show(stroke, samples):
    path = [tuple(c * 100 for c in p) for p in putting.head_path(samples, stroke)]  # cm
    top = stroke.start_time + stroke.backswing
    impact = top + stroke.downswing
    bounds = [(stroke.start_time, top), (top, impact), (impact, float("inf"))]

    for ax, (i, j), xlabel, ylabel, view in (
        (xy, (0, 1), "along target line (cm) → target", "toward you (cm)", "XY: from above"),
        (yz, (1, 2), "toward you (cm)", "height (cm)", "YZ: down the target line"),
    ):
        ax.clear()
        for (name, colour), (lo, hi) in zip(PHASES, bounds):
            # Include the neighbouring sample so the phases join up.
            idx = [k for k, s in enumerate(samples) if lo <= s["t"] < hi]
            if idx:
                idx = sorted({max(idx[0] - 1, 0), *idx})
                ax.plot([path[k][i] for k in idx], [path[k][j] for k in idx], color=colour, lw=2, label=name)
        k_impact = min(range(len(samples)), key=lambda k: abs(samples[k]["t"] - impact))
        ax.plot(0, 0, "ko", ms=6, label="address")
        ax.plot(path[k_impact][i], path[k_impact][j], "x", color="#d6532a", ms=10, mew=2, label="impact")
        ax.set(title=view, xlabel=xlabel, ylabel=ylabel)
        ax.grid(alpha=0.3)
        # Axes aren't to scale (sideways movement is tiny next to stroke length), but keep
        # a minimum span so sensor noise isn't blown up into a wobble.
        for axis, dim in ((ax.set_xlim, i), (ax.set_ylim, j)):
            values = [p[dim] for p in path]
            mid, half = (max(values) + min(values)) / 2, max((max(values) - min(values)) / 2 * 1.15, MIN_HALF_SPAN_CM)
            axis(mid - half, mid + half)
    xy.legend(loc="upper left", fontsize=8)
    status(f"Tempo {stroke.tempo_ratio:.2f}:1   back {stroke.backswing:.2f} s   "
           f"through {stroke.downswing:.2f} s   {stroke.backswing_angle:.1f}°   (Run for another)")


def save(stroke, samples):
    PUTTS.mkdir(parents=True, exist_ok=True)
    name = datetime.now().strftime("%Y-%m-%d_%H%M%S") + ".json"
    (PUTTS / name).write_text(json.dumps({"stroke": stroke.features(), "samples": samples}))


fig = plt.figure("Perfect Putts", figsize=(11, 6))
title = fig.suptitle("Press Run, then hold the putter still at address")
xy = fig.add_axes([0.06, 0.12, 0.42, 0.72])
yz = fig.add_axes([0.55, 0.12, 0.42, 0.72])
run_button = Button(fig.add_axes([0.45, 0.9, 0.1, 0.05]), "Run")
run_button.on_clicked(run)
timer = fig.canvas.new_timer(interval=50)
timer.add_callback(poll)
timer.start()
fig.canvas.mpl_connect("close_event", lambda _: airpods.stop())
plt.show()
