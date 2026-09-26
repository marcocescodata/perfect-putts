"""Tests for putting.py, mirroring PuttCore's Swift tests. Run: .venv/bin/python -m unittest"""

import math
import random
import unittest

import putting


def synthetic_putt(backswing, downswing, follow_through=0.4, amplitude_deg=15, axis=(0.3, -0.8, 0.5),
                   rate=25, lead_in=1.0, tail=1.0, noise=0.01, bias=(0.01, -0.005, 0.008), seed=42, t0=1000.013):
    """Pendulum-like putt: smooth takeaway, putter accelerates through impact, then decelerates."""
    rng = random.Random(seed)
    a = math.radians(amplitude_deg)
    tb, td, tf = backswing, downswing, follow_through
    unit = [c / math.sqrt(sum(x * x for x in axis)) for c in axis]

    def omega(t):
        if t < 0:
            return 0
        if t < tb:
            return a * math.pi / (2 * tb) * math.sin(math.pi * t / tb)
        if t < tb + td:
            return -a * math.pi / (2 * td) * math.sin(math.pi * (t - tb) / (2 * td))
        if t < tb + td + tf:
            return -a * math.pi / (2 * td) * math.cos(math.pi * (t - tb - td) / (2 * tf))
        return 0

    n = int((lead_in + tb + td + tf + tail) * rate)
    samples = []
    for i in range(n):
        t = i / rate
        w = omega(t - lead_in)
        g = [u * w + b + rng.gauss(0, noise) for u, b in zip(unit, bias)]
        samples.append({"t": t0 + t, "gx": g[0], "gy": g[1], "gz": g[2]})
    return samples


class AnalyzeTests(unittest.TestCase):
    def test_measures_tour_tempo(self):
        s = putting.analyze(synthetic_putt(0.66, 0.33))
        self.assertLess(abs(s.backswing - 0.66), 0.04)
        self.assertLess(abs(s.downswing - 0.33), 0.03)
        self.assertLess(abs(s.tempo_ratio - 2.0), 0.2)
        self.assertLess(abs(s.backswing_angle - 15), 1.5)
        self.assertLess(abs(s.start_time - 1001.013), 0.04)

    def test_recovers_ratio(self):
        for tb, td in [(0.6, 0.4), (0.9, 0.3), (0.5, 0.25), (1.0, 0.33)]:
            with self.subTest(tb=tb, td=td):
                s = putting.analyze(synthetic_putt(tb, td, seed=int(tb * 1000)))
                self.assertLess(abs(s.tempo_ratio - tb / td) / (tb / td), 0.1)

    def test_works_regardless_of_axis_and_direction(self):
        s = putting.analyze(synthetic_putt(0.66, 0.33, axis=(-1, 0.1, -0.2)))
        self.assertLess(abs(s.tempo_ratio - 2.0), 0.2)

    def test_ignores_stillness(self):
        self.assertIsNone(putting.analyze(synthetic_putt(0.66, 0.33, amplitude_deg=0)))

    def test_rejects_waggle(self):
        self.assertIsNone(putting.analyze(synthetic_putt(0.15, 0.1, amplitude_deg=1.5)))


class HeadPathTests(unittest.TestCase):
    def path(self, axis, down):
        samples = synthetic_putt(0.66, 0.33, axis=axis)
        for s in samples:
            s.update(grx=down[0], gry=down[1], grz=down[2])
        return putting.head_path(samples, putting.analyze(samples))

    def assert_pendulum(self, path):
        back = 0.85 * math.sin(math.radians(15))
        self.assertLess(abs(min(p[0] for p in path) + back), 0.02)  # backswing goes to −x
        self.assertGreater(path[-1][0], 0)  # finishes toward the target
        self.assertLess(max(abs(p[1]) for p in path), 0.01)  # square stroke: no y drift
        self.assertGreaterEqual(min(p[2] for p in path), -0.005)  # head rises either side

    def test_vertical_shaft(self):
        self.assert_pendulum(self.path(axis=(1, 0, 0), down=(0, -1, 0)))

    def test_any_airpod_orientation(self):
        down = (0.48, 0.6, -0.64)  # unit, and perpendicular to the swing axis
        self.assert_pendulum(self.path(axis=(0, 0.8, 0.6), down=down))


class DetectorTests(unittest.TestCase):
    def test_detects_each_putt_in_a_stream(self):
        first = synthetic_putt(0.66, 0.33, seed=1)
        second = synthetic_putt(0.8, 0.4, seed=2, t0=first[-1]["t"] + 0.013)
        detector = putting.StrokeDetector()
        strokes, saw_ready = [], False
        for s in first + second:
            if result := detector.process(s):
                strokes.append(result[0])
            saw_ready |= detector.phase == "ready"
        self.assertTrue(saw_ready)
        self.assertEqual(len(strokes), 2)
        self.assertTrue(all(abs(s.tempo_ratio - 2.0) < 0.2 for s in strokes))

    def test_requires_address_before_recording(self):
        detector = putting.StrokeDetector()
        samples = synthetic_putt(0.66, 0.33, lead_in=0, tail=0.2)
        self.assertFalse([r for s in samples if (r := detector.process(s))])


class SummariseTests(unittest.TestCase):
    def test_summarises_spread(self):
        def stroke(back, down):
            return putting.PuttStroke(0, back, down, 10, 50)
        stats = putting.summarise([stroke(0.6, 0.3), stroke(0.8, 0.4), stroke(0.66, 0.3)])
        self.assertEqual(stats["count"], 3)
        self.assertAlmostEqual(stats["tempo_ratio"]["mean"], (2 + 2 + 2.2) / 3)
        self.assertAlmostEqual(stats["tempo_ratio"]["sd"], 0.11547, places=4)

    def test_empty_is_none(self):
        self.assertIsNone(putting.summarise([]))


if __name__ == "__main__":
    unittest.main()
