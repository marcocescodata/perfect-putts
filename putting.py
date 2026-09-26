"""Putting-stroke detection and tempo analysis. A port of PuttCore (Swift), same thresholds.

A sample is a dict like the ones airpods.stream() yields: t (seconds), gx/gy/gz (gyro,
rad/s). Pure Python, so it runs anywhere and is easy to feed into numpy/pandas later.
"""

import math
from dataclasses import asdict, dataclass, field
from statistics import mean, stdev


def gyro(s):
    return (s["gx"], s["gy"], s["gz"])


def length(v):
    return math.sqrt(sum(c * c for c in v))


@dataclass
class PuttStroke:
    start_time: float  # sensor timestamp at which the backswing began
    backswing: float  # takeaway to top of backswing, seconds
    downswing: float  # top of backswing to impact, seconds
    backswing_angle: float  # how far the putter rotated back, degrees (proxy for length)
    impact_speed: float  # putter rotation speed at impact, degrees/second (proxy for pace)

    @property
    def tempo_ratio(self):
        """Backswing ÷ downswing. Tour players sit close to 2.0."""
        return self.backswing / self.downswing

    @property
    def total(self):
        return self.backswing + self.downswing

    def features(self):
        return {**asdict(self), "tempo_ratio": self.tempo_ratio, "total": self.total}


@dataclass
class AnalyzerConfig:
    bias_window: float = 0.2  # leading window assumed still, used to estimate gyro bias
    trigger_threshold: float = 0.15  # rad/s that is definitely deliberate motion
    onset_threshold: float = 0.05  # rad/s treated as the moment motion began
    min_backswing_angle: float = 2  # degrees; anything smaller is a waggle
    backswing_range: tuple = (0.2, 2.0)
    downswing_range: tuple = (0.08, 1.2)


def _crossing(times, values, i, level):
    """Time at which values crosses level between index i and i+1, linearly interpolated."""
    dv = values[i + 1] - values[i]
    if dv == 0:
        return times[i + 1]
    f = min(max((level - values[i]) / dv, 0), 1)
    return times[i] + f * (times[i + 1] - times[i])


def _interpolate(times, values, i, t):
    dt = times[i + 1] - times[i]
    if dt <= 0:
        return values[i]
    return values[i] + (t - times[i]) / dt * (values[i + 1] - values[i])


def analyze(samples, config=AnalyzerConfig()):
    """Measure tempo from samples holding one stroke after a still pre-roll. None if it isn't a putt.

    From the grip end a putt is nearly a pure rotation about one axis. The AirPod's orientation is
    unknown, so take the axis from the peak rotation, project the gyro onto it, and read the phases
    off that 1-D signal: start = speed rises past onset, top = speed crosses zero, impact =
    integrated angle returns to where it was at address.
    """
    if len(samples) < 5:
        return None
    times = [s["t"] for s in samples]
    t0 = times[0]

    bias_samples = [gyro(s) for s in samples if s["t"] - t0 <= config.bias_window]
    bias = [sum(c) / len(bias_samples) for c in zip(*bias_samples)]
    omega = [tuple(g - b for g, b in zip(gyro(s), bias)) for s in samples]

    peak = max(omega, key=length)
    if length(peak) <= config.trigger_threshold:
        return None
    axis = [c / length(peak) for c in peak]
    p = [sum(w * a for w, a in zip(v, axis)) for v in omega]

    # Orient so the backswing is positive.
    trigger = next(i for i, v in enumerate(p) if abs(v) > config.trigger_threshold)
    if p[trigger] < 0:
        p = [-v for v in p]

    onset = trigger
    while onset > 0 and p[onset - 1] > config.onset_threshold:
        onset -= 1
    start_time = _crossing(times, p, onset - 1, config.onset_threshold) if onset > 0 else times[0]

    top_index = next((i for i in range(trigger + 1, len(p)) if p[i] <= 0), None)
    if top_index is None:
        return None
    top_time = _crossing(times, p, top_index - 1, 0)

    # Integrate angular velocity into angle (trapezoid rule).
    theta = [0.0]
    for i in range(1, len(p)):
        theta.append(theta[-1] + 0.5 * (p[i] + p[i - 1]) * (times[i] - times[i - 1]))
    address = _interpolate(times, theta, onset - 1, start_time) if onset > 0 else theta[0]
    relative = [v - address for v in theta]

    impact_index = next((i for i in range(top_index, len(p)) if relative[i] <= 0), None)
    if impact_index is None:
        return None
    impact_time = _crossing(times, relative, impact_index - 1, 0)
    impact_speed = abs(_interpolate(times, p, impact_index - 1, impact_time))
    back_angle = max(relative[onset:impact_index], default=0)

    stroke = PuttStroke(
        start_time=start_time,
        backswing=top_time - start_time,
        downswing=impact_time - top_time,
        backswing_angle=math.degrees(back_angle),
        impact_speed=math.degrees(impact_speed),
    )
    lo_b, hi_b = config.backswing_range
    lo_d, hi_d = config.downswing_range
    if (
        stroke.backswing_angle < config.min_backswing_angle
        or not lo_b <= stroke.backswing <= hi_b
        or not lo_d <= stroke.downswing <= hi_d
    ):
        return None
    return stroke


@dataclass
class DetectorConfig:
    still_threshold: float = 0.1  # rad/s below which the putter counts as still
    address_duration: float = 0.5  # hold still this long at address to arm
    trigger_threshold: float = 0.2  # rad/s that starts a recording
    settle_duration: float = 0.4  # still this long after the stroke ends the recording
    max_stroke_duration: float = 4
    pre_roll: float = 0.5  # samples kept from before the trigger, so the analyzer sees address


@dataclass
class StrokeDetector:
    """Feed live samples to process(); it returns (stroke, samples) each time a putt completes.

    Flow: hold still over the ball (address) → "ready" → motion starts a recording → once the
    putter settles again the recording is analysed.
    """

    config: DetectorConfig = field(default_factory=DetectorConfig)
    analyzer_config: AnalyzerConfig = field(default_factory=AnalyzerConfig)
    phase: str = "waiting"  # waiting → ready → stroke
    _history: list = field(default_factory=list)
    _recording: list = field(default_factory=list)
    _still_since: float | None = None
    _trigger_time: float = 0

    def process(self, sample):
        c = self.config
        t = sample["t"]
        speed = length(gyro(sample))
        if speed < c.still_threshold:
            if self._still_since is None:
                self._still_since = t
        else:
            self._still_since = None
        still_for = t - self._still_since if self._still_since is not None else 0

        if self.phase in ("waiting", "ready"):
            self._history.append(sample)
            self._history = [s for s in self._history if t - s["t"] <= c.pre_roll]
            if self.phase == "waiting" and still_for >= c.address_duration:
                self.phase = "ready"
            elif self.phase == "ready" and speed > c.trigger_threshold:
                self.phase = "stroke"
                self._recording = list(self._history)
                self._trigger_time = t
            return None

        self._recording.append(sample)
        if still_for < c.settle_duration and t - self._trigger_time <= c.max_stroke_duration:
            return None
        samples = self._recording
        self._recording, self._history, self._still_since = [], [], None
        self.phase = "waiting"
        stroke = analyze(samples, self.analyzer_config)
        return (stroke, samples) if stroke else None


def summarise(strokes):
    """Mean, sample SD and coefficient of variation per metric. Lower spread = more repeatable."""
    if not strokes:
        return None
    out = {"count": len(strokes)}
    for name in ("tempo_ratio", "total", "backswing", "downswing", "backswing_angle"):
        values = [getattr(s, name) for s in strokes]
        m = mean(values)
        sd = stdev(values) if len(values) > 1 else 0
        out[name] = {"mean": m, "sd": sd, "cv": sd / m if m else 0}
    return out
