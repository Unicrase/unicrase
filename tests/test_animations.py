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
        """pulse/popIn/notify создают элементы до объявления new/rr/outline — нужны опережающие локали."""
        forward = SOURCE.split("local new, rr, outline", 1)
        self.assertEqual(len(forward), 2, "нет строки опережающих локалей")
        for decl in ("function new(class, props, parent)", "function rr(o, r, cap)",
                     "function outline(o, t) return stroke(o, PURE, t or OUT.Idle, 1) end"):
            self.assertIn(decl, SOURCE, decl)
            self.assertNotIn("local " + decl, SOURCE, "повторный local перекрывает опережающую локаль")

    def test_pulse_scale_names_are_unique_per_element(self):
        """Второй UIScale на объекте Roblox игнорирует: helper обязан переиспользовать существующий."""
        body = func_body("pulse")
        self.assertIn('o:FindFirstChild("PulseScale")', body)
        self.assertIn('new("UIScale", {Name = "PulseScale"', body)


class AnimHelpers(unittest.TestCase):
    def test_every_helper_respects_master_switch(self):
        for name in ("spring", "shake", "pulse", "popIn", "animateNumber", "notify"):
            self.assertIn("CFG.Anim", func_body(name), name)

    def test_spring_sets_goal_without_animation(self):
        body = func_body("spring")
        self.assertIn("if not CFG.Anim then", body)
        self.assertRegex(body, r"for k, v in goal do o\[k\] = v end")

    def test_number_animation_keeps_format_and_last_value(self):
        body = func_body("animateNumber")
        self.assertIn("label.Text = fmt(to)", body)  # выключено — сразу конечное значение
        self.assertIn("label.Text = fmt(from + (to - from) * e)", body)  # включено — интерполяция
        self.assertIn("counters[label] ~= gen", body)  # новая анимация отменяет старую

    def test_toast_layer_is_above_menu(self):
        body = func_body("notify")
        z = re.search(r"toastLayer = new\(\"Frame\".*?ZIndex = (\d+)", body, re.S)
        self.assertIsNotNone(z)
        self.assertGreater(int(z.group(1)), 20)  # окно меню живёт на ZIndex 20
        self.assertIn("UICFG.AnimToasts", body)
        self.assertIn("card:Destroy()", body)  # карточка убирается сама

    def test_pulse_is_single_scale_per_element(self):
        body = func_body("pulse")
        self.assertIn('o:FindFirstChild("PulseScale")', body)
        self.assertIn("o.pulseOn == amp", body)  # остановка без «двойного» запуска
        self.assertIn("UICFG.AnimPulse", body)

    def test_pop_in_removes_scale_when_off(self):
        body = func_body("popIn")
        self.assertIn('"PopScale"', body)
        self.assertIn("UICFG.AnimPulse", body)


class AnimWiring(unittest.TestCase):
    def test_settings_exist_in_defaults_and_ui_config(self):
        defaults = between("local DEF = {", "local CFG = ")
        ui = between("local UICFG = {", "local WIN_MIN_W")
        for key in ("AnimCounters", "AnimToasts", "AnimPages", "AnimPulse"):
            self.assertIn(key, ui, key)
            self.assertIn("UICFG.AnimCounters", ui + defaults)  # значения по умолчанию — включены
            self.assertRegex(ui, key + r" = true")

    def test_effect_toggles_bound_to_ui(self):
        for key in ("AnimCounters", "AnimToasts", "AnimPages", "AnimPulse"):
            self.assertRegex(SOURCE, r'\{"[A-Z][^\n]*", "' + key + r'",')

    def test_master_switch_disables_effects_list(self):
        body = between("on(lowBtn.Activated, function()", "end)")
        for key in ("CFG.Anim", "UICFG.AnimCounters", "UICFG.AnimToasts", "UICFG.AnimPages", "UICFG.AnimPulse"):
            self.assertIn(key, body, key)

    def test_switch_knob_moves_with_spring(self):
        body = between("local function paint(enabled, anim)", "end")
        self.assertIn("spring(knob", body)
        self.assertIn("knob.Position = enabled and U(1, -19", body)  # без анимаций — сразу на место

    def test_slider_animates_value_but_not_while_dragging(self):
        body = between("local shownValue", "drag(hit, function(x)")
        self.assertIn("animateNumber(val", body)
        self.assertIn("shownValue = v", body)
        drag = SOURCE.split("drag(hit, function(x)", 1)[1].split("end, function()", 1)[0]
        self.assertIn("paint(false)", drag)  # при перетаскивании число следует за пальцем

    def test_page_switch_runs_cascade(self):
        body = between("local function cascade(f)", "local function paintTab")
        self.assertIn("GroupTransparency", body)  # гасит и фон, и текст
        self.assertIn("UICFG.AnimPages", body)
        show = between("local function show(n)", "for i, folder in folders do")
        self.assertIn("cascade(f)", show)
        self.assertIn("pTitle", show)  # заголовок меняется с фейдом

    def test_key_screen_uses_helpers(self):
        screen = between("local function keyScreen(done)", "stop = function()")
        self.assertIn("shake(form", screen)  # неверный ключ
        self.assertIn("pulse(btn", screen)
        self.assertNotIn('for _, dx in {-12, 12', screen)  # старый ручной цикл тряски убран

    def test_dialog_opens_and_closes_with_animation(self):
        dialog = between("function helpUI.mount", "local function startMain")
        self.assertIn("dialogIn", dialog)
        self.assertIn("spring(dscale", dialog)
        self.assertIn("hiding", dialog)
        complete = dialog.split("local function complete()", 1)[1].split("end\n", 1)[0]
        self.assertIn("hide()", complete)

    def test_esp_lines_fade_without_per_frame_tweens(self):
        body = SOURCE.split("function TC.fade(", 1)[1].split("\nfunction TC.line", 1)[0]
        self.assertIn("f.fadeOn == on", body)  # твин стартует только на смене состояния
        self.assertIn("if not CFG.Anim then", body)
        line = SOURCE.split("function TC.line(", 1)[1].split("\nend", 1)[0]
        self.assertIn("TC.fade(f, true)", line)
        self.assertNotIn("Visible, f.BackgroundColor3", line)
        # выключение линий/скелета тоже проходит через фейд
        self.assertNotIn("f.Visible = false", SOURCE.split("function TC.draw(", 1)[1].split("\nlocal function alphaFor", 1)[0])

    def test_search_clear_button_and_hit_badges(self):
        self.assertIn("Name = \"SearchClear\"", SOURCE)
        self.assertIn('Name = "Hits"', SOURCE)
        changed = SOURCE.split("local function onQueryChanged()", 1)[1].split("on(search:GetPropertyChangedSignal", 1)[0]
        self.assertLess(changed.index("refreshSearch()"), changed.index("filterTabs()"), "бейджи считаются после совпадений")
        self.assertIn("clearBtn.Visible", changed)

    def test_overlay_circle_pops_in_and_mark_reacts_to_target(self):
        body = between("local function drawOverlay(now)", "runSelfTest = function")
        self.assertIn("fovSc", body)
        self.assertIn("markHot", body)
        self.assertIn("UICFG.AnimPulse", body)
        self.assertIn("currentTarget", body)


if __name__ == "__main__":
    unittest.main()
