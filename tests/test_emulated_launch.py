"""Настоящий запуск скрипта в эмуляции Roblox (без игры).

Это единственная проверка, которая ловит падения на загрузке и в кадровом цикле:
статический анализ видит текст, а тут скрипт реально исполняется.

Повод: в 4.7.0 удалили настройку SilentR, но оставили `math.clamp(AIMCFG.SilentR, ...)`.
Компиляция проходила, все текстовые тесты были зелёные, а игрок видел только
незапускающееся меню.
"""
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "Enkaisy_Combined_UI_v4_2.lua"
TOOL = ROOT / "tools" / "emulate.py"


@unittest.skipUnless(TOOL.exists(), "нет tools/emulate.py")
class EmulatedLaunch(unittest.TestCase):
    def test_script_reaches_menu_and_survives_frames(self):
        try:
            import lupa  # noqa: F401
        except ImportError:
            self.skipTest("lupa не установлена (pip install lupa)")
        out = subprocess.run(
            ["python3", str(TOOL), str(SCRIPT)],
            capture_output=True, text=True, timeout=180,
        )
        text = out.stdout + out.stderr
        self.assertIn("COMPILE OK", text, text[-2000:])
        self.assertNotIn("COMPILE ERROR", text, text[-2000:])
        self.assertIn("RUN OK", text, text[-2000:])
        self.assertIn("STARTMAIN OK", text, text[-2000:])
        self.assertIn("кадровый цикл (всё включено): OK", text, text[-2000:])


if __name__ == "__main__":
    unittest.main()
