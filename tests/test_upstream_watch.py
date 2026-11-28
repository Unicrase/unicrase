"""Наблюдатель за изменениями Roblox: не должен врать и должен ловить поломку.

Смысл: пока меня нет, Roblox и Luau меняются. Скрипт сам проверяет, что
используемые им классы/свойства/перечисления всё ещё существуют, и пишет
docs/UPSTREAM.md. Врущий сторож хуже отсутствующего — эти тесты про точность.
"""
import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "watch_upstream.py"
sys.path.insert(0, str(ROOT / "tools"))


class SummaryTruth(unittest.TestCase):
    """Свойства считаются С учётом наследования, иначе сплошные ложные тревоги."""

    @classmethod
    def setUpClass(cls):
        try:
            import watch_upstream
        except Exception as exc:  # pragma: no cover
            raise unittest.SkipTest("не импортируется: %s" % exc)
        cls.mod = watch_upstream
        cls.cache = ROOT / ".cache" / "Mini-API-Dump.json"
        if not cls.cache.exists():
            raise unittest.SkipTest("нет дампа API — запустите tools/roblox_api_check.py --fetch")

    def test_inherited_properties_present(self):
        data = self.mod.summary(self.cache.read_bytes())
        # ZIndex живёт в GuiObject, SortOrder — в UIGridStyleLayout
        self.assertIn("ZIndex", data["classes"]["TextLabel"])
        self.assertIn("SortOrder", data["classes"]["UIListLayout"])
        self.assertIn("FillDirection", data["classes"]["UIListLayout"])

    def test_used_classes_are_found(self):
        classes, enums, props = self.mod.used_in_script()
        self.assertIn("Frame", classes)
        self.assertIn("Highlight", classes)
        # Enum.Material ушёл вместе с папкой Chams — проверяем те перечисления,
        # которые скрипт реально использует сейчас
        self.assertTrue(enums, "хотя бы одно перечисление должно находиться")
        found = {name for items in enums.values() for name in items}
        self.assertIn("Sibling", found, "Enum.ZIndexBehavior.Sibling должен находиться")


class WatchReport(unittest.TestCase):
    def test_report_written_and_compatible(self):
        cache = ROOT / ".cache" / "Mini-API-Dump.json"
        if not cache.exists():
            self.skipTest("нет дампа API")
        result = subprocess.run([sys.executable, str(TOOL)], capture_output=True, text=True)
        report = ROOT / "docs" / "UPSTREAM.md"
        self.assertTrue(report.exists(), "отчёт должен создаваться")
        text = report.read_text(encoding="utf-8")
        self.assertIn("Наблюдение за изменениями Roblox", text)
        # наш скрипт обязан быть совместим с текущим API
        self.assertEqual(result.returncode, 0, "найдено несовместимое с Roblox:\n" + result.stdout)


if __name__ == "__main__":
    unittest.main()
