# Perfect Putts

Measures putting-stroke tempo with an AirPod wedged in the top of the putter grip, and
records the data so it can be analysed (and modelled) over time.

## How it works

An AirPod reports gyroscope data through `CMHeadphoneMotionManager` (the API behind
spatial-audio head tracking), at about 25 Hz. From the grip end, a putting stroke is
basically a pendulum: rotation about one axis. For each putt:

1. **Address:** hold the putter still for 0.5 s and the recorder arms itself.
2. **Record:** the first motion starts a recording, and it ends once the putter settles again.
3. **Analyse** (`putting.analyze`):
   - Remove gyro bias.
   - Find the dominant rotation axis, so it doesn't matter which way round the AirPod sits.
   - Integrate the rotation to get the stroke angle.
   - Read off the phases:
     - **Start:** rotation speed rises above threshold.
     - **Top:** rotation reverses direction.
     - **Impact:** the putter angle returns to where it was at address.

Per putt, it records:
- backswing time
- downswing time
- **tempo ratio** (back ÷ through; tour average ≈ 2:1)
- stroke length (degrees)
- speed at impact

## Layout

- `putting.py`: stroke detection, tempo analysis and session stats. Pure Python.
- `putt_view.py`: a window for one putt at a time. Press Run, hold still at address for
  3 s, putt, and it plots the putter head's path from above (XY) and down the target line (YZ).
- `record.py`: runs a longer live session and saves the data.
- `airpods.py`: streams live AirPod motion into Python.
- `probe.py`: prints raw gyro readings, to check the sensor is reaching Python.
- `bridge/`: a tiny Swift helper app that reads the sensor. macOS only grants motion
  access to an app that declares `NSMotionUsageDescription`, which Python can't, so the
  helper reads the AirPod and pipes JSON lines to `airpods.py`.

## Running

Build the helper once (needs the Xcode Command Line Tools):

    ./bridge/build.sh

Install matplotlib for the viewer (once):

    .venv/bin/python -m pip install matplotlib

Check the sensor, then view single putts or record a session:

    .venv/bin/python probe.py 15
    .venv/bin/python putt_view.py
    .venv/bin/python record.py

Tests:

    .venv/bin/python -m unittest

## Data

Each session is saved in `data/<date_time>/`:

- `samples.jsonl`: every sensor reading, including waggles and missed putts. Fields are
  `t` (seconds), `gx/gy/gz` (gyro, rad/s) and `ax/ay/az` (acceleration minus gravity, g) and `grx/gry/grz` (gravity, g).
- `strokes.csv`: one row per detected putt with its features. `rec_start` and `rec_end`
  mark which samples belong to that putt.

`putt_view.py` saves each putt to `data/putts/<date_time>.json`, with its features and raw samples.

**Head path:** the gyro only measures rotation, so the path is rebuilt by rotating an 0.85 m
shaft that hangs along gravity at address. The shape is right; the size is approximate,
because a real shaft leans at its lie angle. The plot axes are not to scale.

## Hardware notes

- **Supported AirPods:** only models with spatial-audio head tracking: AirPods Pro, AirPods
  (3rd gen and later), AirPods Max, and some Beats.
- **Ear detection:** turn off *Automatic Ear Detection* in System Settings › [your AirPods],
  or motion stops once the AirPod is out of your ear.
- **25 Hz means ~40 ms between samples.** Crossings are interpolated, so timing should be
  good to roughly ±10–20 ms. That's fine for tracking *consistency*, but treat absolute
  times as approximate.
- **Thresholds need tuning on real putts.** They live in `DetectorConfig` and
  `AnalyzerConfig` in `putting.py`.
