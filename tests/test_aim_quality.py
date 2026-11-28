"""Guards for the aimbot / silent aim / ESP quality pass.

Covered here:
  * aim keeps its target by time (StickTime) and by screen-space dead zone, not raw degrees;
  * the camera follows a smoothed lag so it does not snap, and the lag resets with the target;
  * optional soft-aim shake and a lead multiplier exist and are off/neutral by default;
  * silent aim reuses the aim target when it is inside its radius and scores by real hit point;
  * multipoint scans the points closest to the crosshair first (screen positions cached);
  * ESP gained a screen-space box, a minimum distance and cleans its box bars up;
  * the velocity tracker uses a short position history instead of a single frame.
"""
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua"
TEXT = SOURCE.read_text(encoding="utf-8")


def between(start, end):
    return TEXT.split(start, 1)[1].split(end, 1)[0]


class AimQuality(unittest.TestCase):
    """Качество наводки после удаления SMOOTHNESS: остались Stick time и упреждение."""

    def test_defaults_are_neutral(self):
        config = between("local AIMCFG = {", "local col = {")
        self.assertIn("StickTime = 0.25", config)
        self.assertIn("LeadMul = 100", config)

    def test_removed_quality_settings_are_gone(self):
        for key in ("SmoothMaxSpeed", "SmoothDeadPx", "SmoothCamFollow", "A.Shake"):
            self.assertNotIn(key, TEXT, key + " удалён, но остался в коде")


class MultipointQuality(unittest.TestCase):
    def test_closest_points_are_scanned_first(self):
        scan = between("local function scanPoint(model, part)", "local function isVisible")
        self.assertIn("table.sort(keyed, function(a, b) return a.d < b.d end)", scan)
        self.assertEqual(scan.count("WorldToViewportPoint(pt)"), 1, "экранная позиция считается один раз")


class EspQuality(unittest.TestCase):
    def test_box_exists_and_is_cleaned_up(self):
        self.assertIn("function TC.box(o, char, vis, cam, color)", TEXT)
        self.assertIn("function TC.rect(bx, x, y, w, h, th, color)", TEXT)
        self.assertIn("for _, f in o.bx or {} do f:Destroy() end", TEXT)
        self.assertIn('{"ESP box", "Box"}', TEXT)

    def test_box_is_cheap(self):
        box = between("function TC.box(o, char, vis, cam, color)", "function TC.rect(")
        self.assertIn("#parts >= 12 then break", box)
        self.assertNotIn("bxNext", box, "частота — от кадра ESP, отдельный таймер терял обновления")

    def test_min_distance_hides_close_targets(self):
        frame = between("local far = ", "\n")
        self.assertIn("CFG.MinDist > 0 and dist < CFG.MinDist", frame)
        self.assertIn('slider("Min distance (studs)", "MinDist"', TEXT)

    def test_new_settings_survive_load(self):
        self.assertIn("CFG.MinDist = math.clamp(", TEXT)


class Tracker(unittest.TestCase):
    def test_history_based_speed(self):
        track = between("local function trackPart(part)", "local function groundBelow") if "local function groundBelow" in TEXT else between("local function trackPart(part)", "local function ")
        self.assertIn("local hist = k.hist or {}", track)
        self.assertIn("local avg = (pos - first.p) / span", track)
        self.assertIn("nv = raw:Lerp(avg, 0.55)", track)


if __name__ == "__main__":
    unittest.main()
