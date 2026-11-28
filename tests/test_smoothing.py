"""Наводка после удаления раздела SMOOTHNESS (4.7.0).

Пользователь попросил убрать Smooth curve, Max turn speed, Dead zone, Camera follow
и Shake. Осталась одна настройка плавности — Smoothness (и Sticky рядом с ней).

Эти тесты стерегут две вещи:
1) удалённые настройки не вернулись ни в интерфейс, ни в движок;
2) оставшаяся плавность работает и не превращает наводку в телепорт.
"""
import unittest
from pathlib import Path

TEXT = (Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua").read_text(encoding="utf-8")


def between(start, end):
    return TEXT.split(start, 1)[1].split(end, 1)[0]


class RemovedSmoothingSettings(unittest.TestCase):
    """Удалённые настройки не должны остаться нигде."""

    REMOVED = [
        ("SmoothMode", "выбор кривой (Linear/Ease/Human)"),
        ("SmoothMaxSpeed", "предел скорости поворота"),
        ("SmoothDeadPx", "мёртвая зона"),
        ("SmoothCamFollow", "догон камеры"),
        ("A.Shake", "тряска прицела"),
        ("SMOOTHNESS — ПЛАВНОСТЬ", "раздел целиком"),
    ]

    def test_settings_are_gone(self):
        for key, what in self.REMOVED:
            self.assertNotIn(key, TEXT, "%s (%s) всё ещё в коде" % (key, what))

    def test_help_lines_are_gone(self):
        for title in ("Smooth curve", "Max turn speed, deg/s", "Dead zone, px", "Camera follow, %", "Shake (soft aim), deg"):
            self.assertNotIn('["%s"]' % title, TEXT, "справка описывает удалённую настройку: " + title)


class SmoothnessStillWorks(unittest.TestCase):
    """Оставшаяся плавность: одна формула и одна настройка."""

    def test_single_smoothing_function(self):
        fn = between("\tlocal function smoothAlpha(angle, dt)", "\t-- ===== RCS")
        self.assertIn("A.Smoothness", fn)
        self.assertIn("return math.clamp", fn)
        # никаких ветвлений по удалённым кривым
        self.assertNotIn("SmoothMode", fn)
        self.assertNotIn("math.noise", fn, "шум относился к удалённому Shake")

    def test_slider_and_setting_exist(self):
        self.assertIn('slider("Smoothness (higher = faster)", "Smoothness"', TEXT)
        self.assertIn('slider("Sticky (lower = stickier)", "Sticky"', TEXT)
        self.assertIn("Smoothness = 0.16", TEXT)

    def test_aim_uses_it(self):
        step = TEXT[TEXT.index("local step = angle * smoothAlpha(angle, dt)"):]
        self.assertIn("CFrame.fromAxisAngle", step[:400], "поворот камеры должен применяться сразу")


if __name__ == "__main__":
    unittest.main()
