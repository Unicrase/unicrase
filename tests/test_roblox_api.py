"""Сверка с настоящим API Roblox: опечатка в имени класса/свойства/перечисления.

Компилятор Luau не знает Roblox-API: `new("Fraem", ...)` и `Enum.Material.Neonn`
компилируются, а в игре элемент просто не появляется. Этот тест ловит такое
до запуска — по официальному дампу клиента Roblox.

Дамп лежит в .cache/ (в git не попадает). Обновить: 
    python3 tools/roblox_api_check.py --fetch
Если дампа нет, тест пропускается, а не падает: среда без доступа к GitHub
не должна выглядеть «сломанной».
"""
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DUMP = ROOT / ".cache" / "Mini-API-Dump.json"
TOOL = ROOT / "tools" / "roblox_api_check.py"


class RobloxApiNames(unittest.TestCase):
    def test_names_exist_in_real_api(self):
        if not DUMP.exists():
            self.skipTest("нет .cache/Mini-API-Dump.json — запустите tools/roblox_api_check.py --fetch")
        result = subprocess.run([sys.executable, str(TOOL)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0,
                         "имена не совпадают с API Roblox (в игре это тихий сбой):\n" + result.stdout)

    def test_checker_catches_typo(self):
        """Проверка обязана ловить реальную опечатку, иначе она бесполезна."""
        if not DUMP.exists():
            self.skipTest("нет дампа API")
        broken = ROOT / ".broken_api_check.lua"
        broken.write_text(
            'local a = Instance.new("Fraem", {Size = UDim2.new(0, 1, 0, 1)})\n'
            'local b = Instance.new("Frame", {BackGroundColor3 = Color3.new(1, 1, 1)})\n'
            'local c = Enum.Material.Neonn\n', encoding="utf-8")
        try:
            result = subprocess.run([sys.executable, str(TOOL), str(broken)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, "опечатки не найдены:\n" + result.stdout)
            self.assertIn("Fraem", result.stdout)
        finally:
            broken.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
