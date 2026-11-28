"""Guards for the smoothness (плавность) system in the Aim folder.

Covered here:
  * three smoothing curves (Linear / Ease / Human) with sane defaults and load-time validation;
  * the turn speed limit, dead zone and camera follow are real settings used by the aim step;
  * the shake noise is filtered per frame instead of jumping between samples;
  * the settings live in the Aim page next to Smoothness/Sticky and have bilingual help.
"""
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua"
TEXT = SOURCE.read_text(encoding="utf-8")


def between(start, end):
    return TEXT.split(start, 1)[1].split(end, 1)[0]


class SmoothingConfig(unittest.TestCase):
    def test_defaults(self):
        config = between("local AIMCFG = {", "local col = {")
        self.assertIn('SmoothMode = "Linear"', config)
        self.assertIn("SmoothMaxSpeed = 900", config)
        self.assertIn("SmoothDeadPx = 0.6", config)
        self.assertIn("SmoothCamFollow = 65", config)

    def test_values_are_sanitised(self):
        self.assertIn('if not table.find({"Linear", "Ease", "Human"}, AIMCFG.SmoothMode)', TEXT)
        self.assertIn("AIMCFG.SmoothMaxSpeed = math.clamp(", TEXT)
        self.assertIn("AIMCFG.SmoothDeadPx = math.clamp(", TEXT)
        self.assertIn("AIMCFG.SmoothCamFollow = math.clamp(", TEXT)

    def test_linear_is_the_default_look(self):
        fn = between("\tlocal function smoothAlpha(angle, dt)", "\tlocal function clampStep")
        self.assertIn('if A.SmoothMode == "Ease" then', fn)
        self.assertIn('elseif A.SmoothMode == "Human" then', fn)
        self.assertIn("return math.clamp(alpha, 0, 1)", fn)


class SmoothingLogic(unittest.TestCase):
    def test_speed_limit_is_per_second(self):
        fn = between("local function clampStep(step, dt)", "local function camFollow")
        self.assertIn("math.rad(maxDeg) * math.clamp(dt, 0, 0.1)", fn)

    def test_aim_step_uses_the_core(self):
        step = between("\t\tlocal smooth = math.clamp(A.Smoothness, 0.01, 1)\n\t\tlocal step", "end)")
        self.assertIn("smoothAlpha(angle, dt)", step)
        self.assertIn("clampStep(step, dt)", step)
        self.assertIn("A.SmoothDeadPx", step)

    def test_camera_follow_is_a_setting(self):
        self.assertIn("local follow = smooth < 1 and camFollow() or 1", TEXT)
        self.assertIn("local function camFollow()", TEXT)

    def test_shake_is_filtered(self):
        step = between("if A.Shake > 0 then", "camera.CFrame = stepCF * shakeOff")
        self.assertIn("shakePrev = shakePrev + (", step)
        self.assertIn("1 - math.exp(-math.clamp(dt, 0, 0.1) / 0.12)", step)


class SmoothingUi(unittest.TestCase):
    def setUp(self):
        self.aim_ui = between("-- ===== UI папок Aim / Targets / Trigger / Hitbox / FOV =====", "-- ===== Координаты")

    def test_section_and_cards(self):
        self.assertIn('section("SMOOTHNESS — ПЛАВНОСТЬ")', self.aim_ui)
        self.assertIn('cycleKeep("Smooth curve", "SmoothMode", {"Linear", "Ease", "Human"})', self.aim_ui)
        self.assertIn('slider("Max turn speed, deg/s", "SmoothMaxSpeed"', self.aim_ui)
        self.assertIn('slider("Dead zone, px", "SmoothDeadPx"', self.aim_ui)
        self.assertIn('slider("Camera follow, %", "SmoothCamFollow"', self.aim_ui)

    def test_sticky_still_follows_smoothness(self):
        smooth = self.aim_ui.index('"Smoothness (higher = faster)"')
        sticky = self.aim_ui.index('"Sticky (lower = stickier)"')
        self.assertEqual(self.aim_ui.count("\n", smooth, sticky), 1)

    def test_help_is_bilingual(self):
        for name in ("Smooth curve", "Max turn speed, deg/s", "Dead zone, px", "Camera follow, %"):
            self.assertIn(f'["{name}"] = {{', TEXT)


if __name__ == "__main__":
    unittest.main()
