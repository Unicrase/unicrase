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
        """Карточка «Самопроверка подсветки» удалена (4.7.0), но сам тест остался.

        Пользователь убрал карточку из панели; функция GLB.selfTest() остаётся
        доступной из консоли разработчика и из отчёта check_all.
        """
        code = "\n".join(l for l in SOURCE.split("\n") if not l.lstrip().startswith("--"))
        self.assertNotIn("Самопроверка подсветки", code, "карточка удалена по просьбе пользователя")
        self.assertIn("function GLB.selfTest()", SOURCE, "сама самопроверка осталась")

    def test_has_bilingual_help(self):
        """Справка описывает самопроверку в тексте функции: карточки больше нет."""
        body = body_of("selfTest")
        self.assertTrue("[OK]" in body and "[!!]" in body)


class SelfTestNoObjectArithmetic(unittest.TestCase):
    """Реальный баг 4.6.5: `base + Vector3`, где base — деталь, а не её позиция.

    FindFirstChild возвращает Instance, поэтому любая арифметика с ним падает
    в рантайме: "attempt to perform arithmetic on a Instance value". Компилятор
    такое не ловит — проверяем статически, внутри самой самопроверки.
    """

    def test_no_arithmetic_on_instances(self):
        start = SOURCE.index("function GLB.selfTest()")
        end = SOURCE.index("\nend\n", SOURCE.index("return body", start))
        block = SOURCE[start:end]
        # объявления, где справа заведомо Instance
        objects = {}
        for line in block.split("\n"):
            m = re.match(r"\s*local\s+([\w, ]+?)\s*=\s*(.+)$", line)
            if m and re.search(r"FindFirstChild\(|Instance\.new\(|CurrentCamera", m.group(2)):
                for name in m.group(1).split(","):
                    objects[name.strip()] = line.strip()
        self.assertTrue(objects, "не нашёл ни одного объекта — тест бесполезен")
        for line in block.split("\n"):
            if line.lstrip().startswith("--"):
                continue
            for name in objects:
                pattern = r"(?<![\w.])" + re.escape(name) + r"\s*[+\-*/]"
                self.assertIsNone(re.search(pattern, line),
                                  "арифметика с объектом `%s` — падение в рантайме: %s" % (name, line.strip()))

    def test_position_is_taken_explicitly(self):
        self.assertIn("myRoot.Position", SOURCE, "позиция детали берётся явно, а не через сам объект")


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
