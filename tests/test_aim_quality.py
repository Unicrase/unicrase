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
    def test_defaults_are_neutral(self):
        config = between("local AIMCFG = {", "local col = {")
        self.assertIn("StickTime = 0.25", config)
        self.assertIn("Shake = 0", config, "тряска по умолчанию выключена")
        self.assertIn("LeadMul = 100", config, "множитель упреждения по умолчанию нейтральный")

    def test_sticky_holds_at_least_the_circle(self):
        pick = between("local function pickTarget()", "local function ")
        self.assertIn("bestDistance < SP.fov then bestDistance = SP.fov", pick,
                      "цель у края круга не должна теряться из-за Sticky")
        self.assertIn("os.clock() - targetSince < A.StickTime", pick)

    def test_dead_zone_is_in_screen_pixels(self):
        step = between("local smooth = math.clamp(A.Smoothness, 0.01, 1)\n\t\tlocal step", "end)")
        self.assertIn("local deadPx = smooth < 1 and A.SmoothDeadPx or 0.2", step)
        self.assertIn("WorldToViewportPoint(aimPt)", step)
        self.assertNotIn("math.rad(0.08)", step, "старая угловая мёртвая зона слишком грубая")

    def test_camera_lag_does_not_snap(self):
        step = between("local smooth = math.clamp(A.Smoothness, 0.01, 1)\n\t\tlocal step", "end)")
        self.assertIn("camLag = camLag:Lerp(cf, follow)", step)
        self.assertIn("if not aimPt then camLag = nil end", TEXT, "лаг сбрасывается вместе с целью")

    def test_shake_is_optional_and_applied_over_aim(self):
        step = between("local smooth = math.clamp(A.Smoothness, 0.01, 1)\n\t\tlocal step", "end)")
        self.assertIn("if A.Shake > 0 then", step)
        self.assertIn("camera.CFrame = stepCF * shakeOff", TEXT)

    def test_lead_multiplier_is_used(self):
        self.assertEqual(TEXT.count("getLead() * (A.LeadMul / 100)"), 2, "простое и продвинутое упреждение")


class SilentQuality(unittest.TestCase):
    def test_reuses_aim_target_inside_its_radius(self):
        silent = between("silentTarget = function(rOverride)", "\n\tend")
        self.assertIn("if A.Enabled and currentTarget and currentTarget.Parent then", silent)
        self.assertIn("if cm and evaluate(cm, currentTarget, rad) then return currentTarget end", silent)

    def test_scores_by_real_hit_point(self):
        silent = between("silentTarget = function(rOverride)", "\n\tend")
        self.assertIn("local pos = getAimPoint(part)", silent)
        self.assertIn("local score = d + dist * 0.02", silent)


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
