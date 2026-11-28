"""Таблица обязана существовать до того, как ей присваивают метод.

`function CH.apply(...)` при отсутствии `CH = {}` — не синтаксическая ошибка:
Luau компилирует файл, а падение происходит при загрузке с
"attempt to index global 'CH' (a nil value)". Именно так сломалась 4.6.1,
когда при удалении движка Chams вырезалась строка `CH = {}`.

Отсюда правило: удаляя код, проверять, что таблицы, к которым он обращался,
всё ещё создаются.
"""
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "Enkaisy_Combined_UI_v4_2.lua"
TOOL = ROOT / "tools" / "declared_before_use.py"


class DeclaredBeforeUse(unittest.TestCase):
    def test_all_tables_exist_before_methods(self):
        result = subprocess.run(
            [sys.executable, str(TOOL), str(SCRIPT)],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0,
                         "присваивание метода несуществующей таблице — падение при загрузке:\n"
                         + result.stdout)

    def test_tool_catches_the_real_bug(self):
        """Инструмент обязан ловить именно этот случай, иначе тест бесполезен."""
        broken = SCRIPT.read_text(encoding="utf-8").replace("CH = {}\n", "", 1)
        self.assertNotIn("CH = {}\n", broken)
        tmp = ROOT / ".broken_check.lua"
        tmp.write_text(broken, encoding="utf-8")
        try:
            result = subprocess.run([sys.executable, str(TOOL), str(tmp)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, "инструмент не заметил пропавшую таблицу")
            self.assertIn("CH.apply", result.stdout)
        finally:
            tmp.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
