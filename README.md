# Perfect Putts

Measures putting-stroke tempo with an AirPod wedged in the top of the putter grip, and
tracks how consistent it is over time.

## How it works

An AirPod reports gyroscope data through `CMHeadphoneMotionManager` (the API behind
spatial-audio head tracking), at about 25 Hz. From the grip end, a putting stroke is
basically a pendulum: rotation about one axis. For each putt:

1. **Address:** hold the putter still for 0.5 s and the app arms itself.
2. **Record:** the first motion starts a recording, and it ends once the putter settles again.
3. **Analyse** (`PuttCore/StrokeAnalyzer`):
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

Each session stores the mean and standard deviation for these, since consistency is the
goal. Raw samples are saved with every putt, so old strokes can be re-analysed as the
detector improves.

## Layout

- `PuttCore/`: the detection and statistics logic. Pure Swift with no CoreMotion, so it's unit-testable on the Mac.
- `App/`: the SwiftUI iPhone app (motion service, SwiftData models, views).
- `project.yml`: the XcodeGen spec. The `.xcodeproj` is generated from it, not committed.

## Running

Tests (works with just the Command Line Tools):

    ./scripts/test.sh

App (needs full Xcode from the App Store):

    brew install xcodegen
    xcodegen
    open PerfectPutts.xcodeproj

Set your signing team in the target, then run it on your iPhone. The simulator has no
headphone motion.

## Hardware notes / open questions

- **Supported AirPods:** only models with spatial-audio head tracking: AirPods Pro, AirPods
  (3rd gen and later), AirPods Max, and some Beats.
- **Ear detection (to verify first):** motion may only stream while the AirPod thinks it's
  in an ear. If data stops once it's in the grip, turn off *Automatic Ear Detection* in
  Settings › [your AirPods].
- **25 Hz means ~40 ms between samples.** Crossings are interpolated, so timing should be
  good to roughly ±10–20 ms. That's fine for tracking *consistency*, but treat absolute
  times as approximate.
- **Thresholds need tuning on real putts.** They live in `StrokeDetector.Config` and
  `StrokeAnalyzer.Config`.
