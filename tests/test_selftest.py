"""Самопроверка внутри игры: единственное, что доказывает «подсветку видно на экране».

Все остальные проверки статические: они гарантируют, что скрипт загрузится и
настройки доходят до кода. Но если фильтры отсекают цель или Highlight не
создаётся, на экране пусто, а код «правильный». Поэтому в скрипте есть
GLB.selfTest(): создаёт настоящую цель в мире, проводит её через рабочий цикл
подсветки и печатает отчёт на экране.

Тест стережёт:
1) что эта функция вообще есть и вызывается кнопкой из меню (на телефоне нет консоли);
2) что она идёт через настоящий путь (upd / esp / Highlight), а не свою копию;
3) что после прогона ничего не остаётся: модель, подсветка, список NPC.
"""
import re
import unittest
from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua").read_text(encoding="utf-8")


def body_of(name):
    start = SOURCE.index("function GLB.%s()" % name)
    end = SOURCE.index("\nend\n", SOURCE.index("return body", start))
    return SOURCE[start:end]


class SelfTestExists(unittest.TestCase):
    def test_function_defined(self):
        self.assertIn("function GLB.selfTest()", SOURCE)

    def test_reachable_from_menu(self):
        """Без консоли на телефоне единственный вход — кнопка в панели."""
        start = SOURCE.index("Самопроверка: на телефоне консоли нет")
        block = SOURCE[start:start + 700]
        self.assertIn("Skin.setting(pm", block, "кнопка должна быть карточкой настроек")
        self.assertIn("pcall(GLB.selfTest)", block, "нажатие обязано вызывать самопроверку")

    def test_has_bilingual_help(self):
        self.assertIn('["Самопроверка подсветки"]', SOURCE)


class SelfTestIsReal(unittest.TestCase):
    def test_goes_through_real_highlight_path(self):
        body = body_of("selfTest")
        self.assertIn("pcall(upd, probe, nil)", body, "нужен настоящий путь подсветки, не копия")
        self.assertIn("esp[probe]", body, "результат должен читаться из живого списка")
        self.assertIn("Highlight", body + SOURCE[SOURCE.index("local function dohl"):][:600])

    def test_creates_a_real_model_in_world(self):
        body = body_of("selfTest")
        self.assertIn('Instance.new("Model")', body)
        self.assertIn('Instance.new("Humanoid")', body)
        self.assertIn("probe.Parent = Workspace", body)

    def test_cleans_up_after_itself(self):
        body = body_of("selfTest")
        self.assertIn("pcall(unhl, probe)", body, "подсветка должна сниматься")
        self.assertIn("probe:Destroy()", body, "тестовая модель не должна оставаться в мире")
        self.assertIn("npcs[probe] = nil", body, "список NPC должен вернуться в исходное состояние")

    def test_report_is_visible_on_screen(self):
        body = body_of("selfTest")
        self.assertIn("gui:FindFirstChild", body, "отчёт рисуется в интерфейсе, а не только в консоль")
        self.assertIn("TextLabel", body)
        self.assertIn("[OK]", SOURCE[:SOURCE.index("function GLB.selfTest()") * 0] or body)


if __name__ == "__main__":
    unittest.main()
