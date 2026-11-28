"""Guards for the RCS (Recoil Control System) setting in the Aim folder.

Behaviour covered:
  * the feature is off by default and is a plain boolean flag (so the full reset turns it off);
  * it lives in the Aim page, right after the aim settings, with its own section;
  * its three sub-settings (strength / smoothness / suppress) exist and 0% strength means "off";
  * recoil is cancelled in its own render step (after aim assist) and the shot uses the pre-recoil aim;
  * unloading the menu unbinds that step.
"""
import re
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua"
TEXT = SOURCE.read_text(encoding="utf-8")


def between(start, end):
    return TEXT.split(start, 1)[1].split(end, 1)[0]


class RcsConfig(unittest.TestCase):
    def test_defaults_are_off(self):
        config = between("local AIMCFG = {", "local col = {")
        self.assertIn("Rcs = false", config)
        self.assertIn("RcsSuppress = false", config)
        self.assertIn("RcsStrength = 1", config)
        self.assertRegex(config, r"RcsSmooth = 0\.\d+")

    def test_values_are_sanitised_on_load(self):
        self.assertIn("AIMCFG.RcsStrength = math.clamp(", TEXT)
        self.assertIn("AIMCFG.RcsSmooth = math.clamp(", TEXT)

    def test_full_reset_turns_it_off(self):
        reset = TEXT.split("local function fullReset()", 1)[1].split("\n\tend\n", 1)[0]
        self.assertIn('type(v) == "boolean" then', reset, "флаги, включая Rcs, должны выключаться сбросом")


class RcsLogic(unittest.TestCase):
    def test_core_is_defined_once(self):
        self.assertEqual(TEXT.count("local function rcsStep("), 1)
        self.assertEqual(TEXT.count("local function rcsAimRay("), 1)
        self.assertEqual(TEXT.count("local function rcsPulse("), 1)
        self.assertEqual(TEXT.count("local function rcsReset("), 1)

    def test_strength_zero_means_off(self):
        step = between("local function rcsStep(", "\t\tlocal cf = camera.CFrame\n\t\tlocal changed = false")
        self.assertIn("if not A.Rcs or A.RcsStrength <= 0 then", step)
        self.assertIn("rcsReset()", step)

    def test_recoil_step_runs_after_aim_assist(self):
        self.assertIn('BindToRenderStep("EnkaisyAimAssist", Enum.RenderPriority.Camera.Value + 1', TEXT)
        self.assertIn('BindToRenderStep("EnkaisyRCS", Enum.RenderPriority.Camera.Value + 2', TEXT)
        self.assertEqual(TEXT.count('UnbindFromRenderStep("EnkaisyRCS")'), 3, "шаг снимается при старте, выгрузке и создании")

    def test_shot_uses_pre_recoil_aim(self):
        self.assertIn("local ray = rcsAimRay()", TEXT)
        self.assertIn("rcsRef = {cf = camera.CFrame, t = t}", TEXT, "прицел запоминается при выстреле")
        self.assertIn("rcsPulse(tool)", TEXT)


class RcsUi(unittest.TestCase):
    def setUp(self):
        self.aim_ui = between("-- ===== UI папок Aim / Targets / Trigger / Hitbox / FOV =====", "-- ===== Координаты")

    def test_section_is_in_the_aim_folder_after_aim_settings(self):
        self.assertIn('section("RCS — RECOIL CONTROL")', self.aim_ui)
        self.assertGreater(self.aim_ui.index('section("RCS — RECOIL CONTROL")'),
                           self.aim_ui.index('slider("Aim max distance"'))
        self.assertLess(self.aim_ui.index('section("RCS — RECOIL CONTROL")'),
                        self.aim_ui.index('section("TARGET LOCK")'))

    def test_cards_exist_with_values(self):
        self.assertIn('toggleCard(tgt, "RCS (recoil control)"', self.aim_ui)
        self.assertIn('toggleCard(tgt, "RCS suppress (no kick)"', self.aim_ui)
        self.assertIn('sliderCard(tgt, "RCS strength"', self.aim_ui)
        self.assertIn('sliderCard(tgt, "RCS smoothness"', self.aim_ui)
        self.assertIn('"instant"', self.aim_ui, "плавность 0 показывает instant")

    def test_sub_settings_grey_out_while_master_is_off(self):
        self.assertIn("local function paintRcs()", self.aim_ui)
        self.assertIn("local dim = A.Rcs and 0 or 0.55", self.aim_ui)
        self.assertIn("table.insert(rcsSlaves, suppressCard)", self.aim_ui)

    def test_cards_have_bilingual_help(self):
        self.assertIn('["RCS (recoil control)"] = {', TEXT)
        self.assertIn('["RCS strength"] = {', TEXT)
        self.assertIn('["RCS smoothness"] = {', TEXT)
        self.assertIn('["RCS suppress (no kick)"] = {', TEXT)


if __name__ == "__main__":
    unittest.main()
