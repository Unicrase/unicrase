"""Каждое поле настроек, которое читает нормализация, должно существовать.

Повод: в 4.7.0 удалили поле SilentR, но оставили строку
`AIMCFG.SilentR = math.clamp(AIMCFG.SilentR, 2, 60)` — скрипт падал на загрузке
(`attempt to compare nil with number`), и меню не открывалось вообще.
Эта проверка ловит такой класс ошибок без запуска игры.
"""
import re
import unittest
from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua").read_text(encoding="utf-8")
LINES = SOURCE.split("\n")


def table_keys(marker):
    """Ключи таблицы, объявленной строкой marker."""
    start = next(n for n, l in enumerate(LINES) if l.startswith(marker))
    keys, depth = set(), 0
    for line in LINES[start:]:
        code = line.split("--", 1)[0]
        for m in re.finditer(r"(\w+)\s*=", code):
            keys.add(m.group(1))
        depth += code.count("{") - code.count("}")
        if depth <= 0 and code.strip() == "}":
            break
    return keys


class SettingsKeysExist(unittest.TestCase):
    def test_every_read_key_is_declared(self):
        tables = {
            "CFG": table_keys("local CFG = {"),
            "AIMCFG": table_keys("local AIMCFG = {"),
            "UICFG": table_keys("local UICFG = {"),
        }
        missing = []
        for name, keys in tables.items():
            for n, line in enumerate(LINES, 1):
                for m in re.finditer(r"(?<![\w.])" + name + r"\.(\w+)\s*=(?!=)", line):
                    key = m.group(1)
                    if key not in keys:
                        missing.append("%s.%s (строка %d)" % (name, key, n))
        self.assertEqual(missing, [], "поля нет в таблице настроек — будет nil и падение:\n" + "\n".join(missing))

    def test_known_removed_fields_stay_removed(self):
        # историю версий и клиентскую механику на серверной стороне (SilentAim как атрибут Tool) не считаем
        code = "\n".join(l for l in LINES if not l.lstrip().startswith("--"))
        for key in ("SilentR", "FovStyle", "SmoothMode", "SmoothMaxSpeed", "SmoothDeadPx",
                    "SmoothCamFollow", "AnimCounters", "AnimPages", "AnimPulse", "AnimIntro", "AnimText"):
            self.assertNotIn(key, code, key + " удалён, но остался в коде")


if __name__ == "__main__":
    unittest.main()
