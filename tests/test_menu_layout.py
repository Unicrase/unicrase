"""Static guards for the folder layout and the full settings reset.

The menu groups settings by task: every folder holds one job, and settings that
influence each other sit next to each other (Aim smoothness next to sticky,
triggerbot next to its delay/tolerance, hitbox next to its sizes and visual).
"""
import re
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua"


def between(start, end):
    text = SOURCE.read_text(encoding="utf-8")
    return text.split(start, 1)[1].split(end, 1)[0]


class MenuLayout(unittest.TestCase):
    def test_folders_follow_player_flow(self):
        folders = re.findall(r'\{id = "(\w+)"', between("local folders = {", "local repaints = {}"))
        self.assertEqual(
            folders,
            ["Main", "Targets", "Aim", "Trigger", "FOV", "Hitbox", "Color", "Players", "Visual", "Appearance"],
        )

    def test_retired_folders_are_gone(self):
        text = SOURCE.read_text(encoding="utf-8")
        self.assertNotIn("pages.Sizes", text)
        self.assertNotIn("pages.Extra", text)

    def test_similar_settings_stay_together(self):
        aim_ui = between("-- ===== UI папок Aim / Targets / Trigger / Hitbox / FOV =====", "-- ===== Координаты")
        smooth = aim_ui.index('"Smoothness (higher = faster)"')
        sticky = aim_ui.index('"Sticky (lower = stickier)"')
        self.assertEqual(aim_ui.count("\n", smooth, sticky), 1, "Smoothness и Sticky должны идти подряд")
        trigger = aim_ui.index('{"Triggerbot"')
        trigger_delay = aim_ui.index('"Trigger delay (sec)"')
        self.assertLess(trigger_delay - trigger, 300, "Triggerbot и его ползунки — рядом")
        hitbox = aim_ui.index('"Hitbox size (studs)"')
        head_hitbox = aim_ui.index('"Head hitbox size (studs)"')
        self.assertEqual(aim_ui.count("\n", hitbox, head_hitbox), 1, "Обычный и головной хитбокс — подряд")

    def test_full_reset_asks_for_confirmation_and_switches_everything_off(self):
        text = SOURCE.read_text(encoding="utf-8")
        self.assertIn('dialog.confirm("Сбросить все настройки?"', text)
        self.assertIn('api.confirm = function', text)
        self.assertIn('danger.Visible = actions.Visible and isDanger and true or false', text)
        reset = text.split("local function fullReset()", 1)[1].split("\n\tend\n", 1)[0]
        for table in ("DEF.CFG", "DEF.AIM"):
            self.assertIn(f"for k, v in {table} do", reset)
        self.assertEqual(reset.count('type(v) == "boolean" then'), 2, "все флаги должны выключаться")


if __name__ == "__main__":
    unittest.main()
