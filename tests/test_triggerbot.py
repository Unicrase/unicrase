"""Переработка триггербота (4.7.2).

Триггер стреляет сам, поэтому у него должны быть понятные и проверяемые правила:
режим Automatic/Single, реакция, допуск, своя дальность, проверка видимости и
ожидание наводки. Тесты стерегут, что UI-настройка действительно доходит до кода.
"""
import unittest
from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua").read_text(encoding="utf-8")


def between(start, end):
    return SOURCE.split(start, 1)[1].split(end, 1)[0]


class TriggerSettings(unittest.TestCase):
    def test_defaults(self):
        block = between("local AIMCFG = {", "local col = {")
        self.assertIn('TrigMode = "Auto"', block)
        self.assertIn("TrigRange = 0", block, "0 = дальность оружия")
        self.assertIn("WallCheck = true", block)
        self.assertIn("TrigAimFirst = false", block)

    def test_sanitised_on_load(self):
        self.assertIn('if not table.find({"Auto", "Single"}, AIMCFG.TrigMode) then AIMCFG.TrigMode = "Auto" end', SOURCE)
        self.assertIn("AIMCFG.TrigRange = math.clamp(tonumber(AIMCFG.TrigRange) or 0, 0, 2000)", SOURCE)

    def test_ui_controls_exist(self):
        page = SOURCE[SOURCE.index('tgt, ord = api.triggerPage or scroll, 0'):]
        page = page[:page.index('section("MULTIPOINT")')]
        for control in ('cycle("Fire mode", "TrigMode"', '"Reaction delay (sec)"', '"Aim tolerance (% of screen)"',
                        '"Trigger distance (0 = weapon)"', '{"Line of sight", "WallCheck"', '{"Aim first", "TrigAimFirst"'):
            self.assertIn(control, page, control)

    def test_help_is_bilingual(self):
        info = between("helpUI.info = {", "function helpUI.add")
        for title in ("Fire mode", "Trigger distance (0 = weapon)", "Line of sight", "Aim first"):
            line = next((l for l in info.split("\n") if '["%s"]' % title in l), "")
            self.assertTrue(line.count('"') >= 6, title + " без пары ru/en")


class TriggerEngine(unittest.TestCase):
    def setUp(self):
        self.step = SOURCE[SOURCE.index("local function triggerStep(now)"):]
        self.step = self.step[:self.step.index("-- встроенное оружие: Tool с атрибутом Damage")]

    def test_own_range_wins_over_weapon(self):
        self.assertIn("local range = A.TrigRange", self.step)
        self.assertIn('range = tool:GetAttribute("Range")', self.step)

    def test_wall_check_switch(self):
        self.assertIn("(not A.WallCheck) and charRP or rayParams", self.step)
        self.assertIn("local probe = Workspace:Raycast(", self.step)

    def test_single_mode_fires_once_per_target(self):
        self.assertIn('if A.TrigMode == "Single" and firedFor == model then trigStatus = "already fired" return end', self.step)
        self.assertIn("lastTrigger[tool], firedFor = now, model", self.step)
        self.assertIn("firedFor = nil", self.step, "смена цели сбрасывает отметку выстрела")

    def test_aim_first_waits(self):
        self.assertIn("if A.TrigAimFirst then", self.step)
        self.assertIn('trigStatus = "waiting for aim"', self.step)

    def test_statuses_explained(self):
        for status in ('"no tool (equip weapon)"', '"cooldown"', '"aiming"'):
            self.assertIn(status, self.step, status)


if __name__ == "__main__":
    unittest.main()
