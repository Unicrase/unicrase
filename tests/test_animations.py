"""Animations: каждый эффект включается флагом и полностью гаснет при CFG.Anim = false."""
import re
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = (HERE.parent / "Enkaisy_Combined_UI_v4_2.lua").read_text(encoding="utf-8")


def between(start, end):
    return start + SOURCE.split(start, 1)[1].split(end, 1)[0]


def func_body(name):
    """Тело функции по имени: от объявления до первого закрывающего end на отдельной строке."""
    start = SOURCE.index("function %s(" % name)
    rest = SOURCE[start:]
    end = re.search(r"\n(end|-- =====)", rest)
    return rest[: end.start() if end else len(rest)]


class TweenCurves(unittest.TestCase):
    def test_curves_defined_once_and_ordered(self):
        block = between("local TWEEN = {", "}")
        curves = re.findall(r"(\w+) = TweenInfo\.new\(([\d.]+), Enum\.EasingStyle\.(\w+)", block)
        self.assertEqual([c[0] for c in curves], ["snap", "ui", "pop", "spring", "smooth"])
        durations = {c[0]: float(c[1]) for c in curves}
        # «щелчок» — самый короткий, пружины заметно длиннее, и ни одна не длится дольше 0.5 с
        self.assertLess(durations["snap"], durations["ui"])
        self.assertGreater(durations["pop"], durations["ui"])
        self.assertGreater(durations["spring"], durations["pop"])
        self.assertLessEqual(max(durations.values()), 0.5)
        self.assertTrue(all(d > 0 for d in durations.values()))
        styles = {c[0]: c[2] for c in curves}
        self.assertEqual(styles["pop"], "Back")
        self.assertEqual(styles["spring"], "Elastic")

    def test_curves_used_in_ui(self):
        for name in ("TWEEN.pop", "TWEEN.ui", "TWEEN.snap"):
            self.assertGreaterEqual(SOURCE.count(name), 3, name)


class ForwardLocals(unittest.TestCase):
    def test_helpers_never_call_globals(self):
        """notify создаёт элементы до объявления new/rr/outline — нужны опережающие локали."""
        self.assertIn("local new, rr, outline, gui", SOURCE)

class AnimHelpers(unittest.TestCase):
    """После чистки остался единственный эффект — уведомления (Toasts).

    Счётчики, пульс, каскад страниц, заставка и «текст из искр» удалены по просьбе
    пользователя, но функции-помощники остались безопасными: их зовут десятки мест.
    """

    def test_helpers_are_plain_writes(self):
        pulse = func_body("pulse")
        self.assertNotIn("task.spawn", pulse, "пульс больше не крутит цикл")
        self.assertNotIn("while", pulse)
        pop = func_body("popIn")
        self.assertNotIn("spring(", pop, "точка включённой функции не «вырастает»")

    def test_number_animation_is_instant(self):
        body = func_body("animateNumber")
        self.assertIn("label.Text = fmt(to)", body)
        self.assertNotIn("task.spawn", body)
        self.assertNotIn("while", body)

    def test_particle_text_removed(self):
        body = func_body("revealText")
        self.assertIn("label.Text = text or", body)
        self.assertNotIn("graphemes", body)
        self.assertNotIn("task.spawn", body)

    def test_page_cascade_removed(self):
        self.assertIn("local function appear(o, delay) end", SOURCE)
        self.assertIn("local function cascade(f) end", SOURCE)

class AnimSettings(unittest.TestCase):
    def test_only_toasts_remain(self):
        block = between("\t-- Единственный эффект анимации", "}")
        self.assertIn("AnimToasts = true", block)
        for key in ("AnimCounters", "AnimPages", "AnimPulse", "AnimIntro", "AnimText"):
            self.assertNotIn(key, source_code(), key + " удалён, но остался в коде")

    def test_performance_page_has_single_effect_card(self):
        page = SOURCE[SOURCE.index('sectionLabel(pv2, "ANIMATION EFFECTS", 3)'):]
        page = page[:page.index("local lowBtn")]
        self.assertIn('toggleCard(pv2, "Toasts"', page)
        for gone in ("Animated numbers", "Page cascade", "Accent pulse", "Intro after key", "Particle text"):
            self.assertNotIn(gone, page, gone + " — эффект удалён")

    def test_toasts_only_check_their_own_flag(self):
        body = SOURCE[SOURCE.index("function notify(title, text, danger)"):]
        body = body[:body.index("local host = gui")]
        self.assertIn("UICFG.AnimToasts", body)
        # именно CFG.Anim, а не подстрока внутри UICFG.AnimToasts
        self.assertIsNone(re.search(r"(?<!UI)CFG\.Anim\b", body), "общего выключателя анимаций больше нет")

    def test_intro_is_a_noop(self):
        body = func_body("playIntro")
        self.assertNotIn("ScreenGui", body, "заставка после ключа удалена")
        self.assertIn("if after then after() end", body)

def source_code():
    """Текст скрипта без комментариев: историю версий в шапке не проверяем."""
    return "\n".join(l for l in SOURCE.split("\n") if not l.lstrip().startswith("--"))

class ChamsAndFov(unittest.TestCase):
    """Папка CHAMS удалена целиком (4.6.0): её место занял базовый Highlight."""

    def test_chams_removed_from_menu(self):
        self.assertNotIn('id = "Chams"', SOURCE)
        self.assertNotIn("CHAMS_PAGE(pages, api)", SOURCE)
        self.assertNotIn("local function buildChamsPage(parent, api)", SOURCE)
        for name in ("CH_MATS", "CH_TEX", "CH_FX", "CH_PAT", "CH_DEF", "CHAMS_BY_KEY"):
            self.assertNotIn(name, SOURCE)

    def test_highlight_remains(self):
        # базовая подсветка: цвет и прозрачности, которые считает refreshHL
        self.assertIn("local function refreshHL()", SOURCE)
        self.assertIn("CH.apply(o, fc, oc)", SOURCE)

class FovCircleStyles(unittest.TestCase):
    """Стили круга FOV удалены: остался один ровный контур.

    Раньше их было четыре (Glow / Gradient / Dashed / Classic), и каждый тащил
    свои объекты в оверлее. Пользователь попросил убрать выбор стиля.
    """

    def test_style_picker_removed(self):
        self.assertNotIn('section("CIRCLE STYLE")', SOURCE)
        self.assertNotIn('A.FovStyle', SOURCE)

    def test_style_objects_removed(self):
        # историю версий в шапке не считаем: там упоминания законны
        code = "\n".join(l for l in SOURCE.split("\n") if not l.lstrip().startswith("--"))
        for name in ("fovGlow", "fovHalo", "AIM.fovDash", "fovStrokeGrad"):
            self.assertNotIn(name, code, name + " остался, хотя стилей нет")

    def test_circle_still_drawn(self):
        self.assertIn("fovStroke.Thickness = thick", SOURCE)
        self.assertIn("fovStroke.Color = line", SOURCE)
        self.assertIn('section("VISIBILITY")', SOURCE)


if __name__ == "__main__":
    unittest.main()