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
        forward = SOURCE.split("local new, rr, outline, gui", 1)
        self.assertEqual(len(forward), 2, "нет строки опережающих локалей")
        for decl in ("function new(class, props, parent)", "function rr(o, r, cap)",
                     "function outline(o, t) return stroke(o, PURE, t or OUT.Idle, 1) end"):
            self.assertIn(decl, SOURCE, decl)
            self.assertNotIn("local " + decl, SOURCE, "повторный local перекрывает опережающую локаль")
        self.assertIn("\ngui = new(\"ScreenGui\"", SOURCE, "gui объявлен как опережающая локаль")

    def test_group_transparency_only_on_canvas_groups(self):
        """GroupTransparency существует только у CanvasGroup: запись в Frame — ошибка рантайма.

        Для каждого упоминания свойства находим объект, к которому его применяют
        (tween(o, ...), TS:Create(o, ...) или props у new("CanvasGroup", ...)),
        и требуем, чтобы это был CanvasGroup.
        """
        canvas_vars = set(re.findall(r'(\w+)\s*=\s*new\("CanvasGroup"', SOURCE))
        self.assertTrue(canvas_vars, "в файле есть CanvasGroup")
        checked = 0
        for m in re.finditer(r"GroupTransparency", SOURCE):
            line_start = SOURCE.rfind("\n", 0, m.start()) + 1
            line = SOURCE[line_start:SOURCE.find("\n", m.start())]
            if line.lstrip().startswith("--"):
                continue
            before = SOURCE[max(0, m.start() - 400):m.start()]
            # сначала props (new("CanvasGroup", {...})): внутри таблицы объект ещё не назван
            if 'new("CanvasGroup"' in before[before.rfind("new(") if "new(" in before else 0:]:
                checked += 1
                continue
            obj = re.findall(r"(?:tween|Create)\(\s*(\w+)\s*,", before)
            if obj:
                checked += 1
                self.assertIn(obj[-1], canvas_vars,
                              "GroupTransparency применён к не-CanvasGroup: " + line.strip())
                continue
            # прямое присваивание: panel.GroupTransparency = ... / o.GroupTransparency = ...
            direct = re.findall(r"(\w+)\.GroupTransparency", line)
            if direct:
                checked += 1
                self.assertIn(direct[0], canvas_vars,
                              "GroupTransparency на не-CanvasGroup: " + line.strip())
                continue
            self.fail("GroupTransparency вне CanvasGroup: " + line.strip())
        self.assertGreaterEqual(checked, 5, "проверка должна находить применения свойства")

    def test_no_state_written_into_instances(self):
        """Roblox бросает ошибку при записи неизвестного поля в Instance — состояние только в таблицах."""
        for pattern in (r"\w+\.pulseOn\s*=", r"\bf\.fadeOn\s*=", r"\w+\.(fadeOn|pulseOn)\b"):
            for hit in re.findall(pattern, SOURCE):
                self.fail("состояние пишется в Instance: " + str(hit))
        self.assertIn('local pulseState = setmetatable({}, {__mode = "k"})', SOURCE)
        self.assertIn('TC.faded = setmetatable({}, {__mode = "k"})', SOURCE)

    def test_shake_never_stacks(self):
        body = SOURCE.split("local function shake(o, amp, times)", 1)[1].split("local function pulse(", 1)[0]
        self.assertIn('setmetatable({}, {__mode = "k"})', SOURCE.split("local function shake(", 1)[0].rsplit("\n", 2)[-2])
        self.assertIn("shaking[o] then return end", body)
        self.assertIn("shaking[o] = nil", body)

    def test_esp_fade_does_not_flash_when_already_visible(self):
        body = SOURCE.split("function TC.fade(f, on)", 1)[1].split("\nend", 1)[0]
        self.assertIn("local wasHidden = not f.Visible", body)
        self.assertIn("if wasHidden then f.BackgroundTransparency = 1 end", body)

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
        self.assertIn("pulseState[o] == amp", body)  # остановка без «двойного» запуска
        self.assertNotIn("sc:Destroy()", body)  # UIScale может делить кнопка: только возврат к 1
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

    def test_effect_cards_dim_labels_only(self):
        """Фон карточек принадлежит прозрачности фона-картинки: гасим только подписи."""
        block = SOURCE.split('sectionLabel(pv2, "ANIMATION EFFECTS", 3)', 1)[1].split("local lowBtn", 1)[0]
        self.assertIn("TextTransparency", block)
        self.assertNotIn("BackgroundTransparency = CFG.Anim", block)

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
        body = between("local function appear(o, delay)", "local folders = {")
        self.assertIn("UIScale", body)  # GroupTransparency есть только у CanvasGroup
        self.assertIn("UICFG.AnimPages", body)
        self.assertIn("cascadeGen[f] ~= my then return end", body)  # старый каскад уступает новому
        show = between("local function show(n)", "for i, folder in folders do")
        self.assertIn("cascade(f)", show)
        self.assertIn("pTitle", show)  # заголовок меняется с фейдом

    def test_intro_plays_after_valid_key(self):
        intro = between("local function playIntro(after)", "-- ===== Экран ключа =====")
        # сцена живёт в своём ScreenGui и удаляется целиком
        self.assertIn('Name = "EnkaisyIntro"', intro)
        self.assertIn("stage:Destroy()", intro)
        # слово собирается по буквам из строки UNICRASE
        self.assertIn('local INTRO_WORD = "UNICRASE"', SOURCE)
        self.assertIn("INTRO_WORD:sub(i, i)", intro)
        # два выключателя: общий и отдельный
        self.assertIn("CFG.Anim and UICFG.AnimIntro", intro)
        # пропуск касанием и страховка по времени
        self.assertIn("UT.Touch", intro)
        self.assertIn("task.delay(INTRO_LEN + 0.5, stop)", intro)
        # вызов ровно один и только в ветке верного ключа
        screen = between("local function keyScreen(done)", "stop = function()")
        valid = screen.split('== KEY_HASH then', 1)[1].split("tries += 1", 1)[0]
        self.assertIn("playIntro(function()", valid)
        self.assertEqual(SOURCE.count("playIntro("), 2)  # объявление + единственный вызов

    def test_letters_reveal_opens_folder_text(self):
        body = SOURCE.split("local function revealText(label, text, opt)", 1)[1].split("-- Анимация цифры", 1)[0]
        self.assertIn("UICFG.AnimText", body)
        # каждая буква — отдельный TextLabel со своим UIScale, а не срез строки
        self.assertIn('new("TextLabel"', body)
        self.assertIn('new("UIScale"', body)
        # буквы стартуют по очереди и «выпрыгивают» снизу
        self.assertIn("task.wait(stepDelay)", body)
        self.assertIn("Position = O(math.floor(g.x), rise)", body)
        self.assertIn("{Position = O(it.x, 0), TextTransparency = 0}", body)
        self.assertIn("spring(it.sc, {Scale = 1}, TWEEN.pop)", body)
        # выключено — текст ставится сразу, слой анимации снимается
        self.assertIn("label.Text, label.TextTransparency = text, 0", body)
        # в конце обычный текст возвращается: цвета темы и обрезка работают как раньше
        self.assertIn("label.Text, label.TextTransparency = text, 0\n", body + "\n")
        self.assertIn("layer:Destroy()", body)
        # поколение отменяет предыдущую анимацию (быстрые клики по папкам)
        self.assertIn("revealers[label] ~= gen", body)
        # заголовок папки и названия карточек используют один хелпер
        show = between("local function show(n)", "for i, folder in folders do")
        self.assertIn("revealText(pTitle, newTitle", show)
        cascade = between("local function cascade(f)", "local folders = {")
        self.assertIn('c:FindFirstChild("Title")', cascade)
        self.assertIn("revealText(title, title.Text", cascade)
        # utf8.graphemes отдаёт диапазон (два числа), а не символ:
        # старый `for _, ch in utf8.graphemes(text)` давал в ch число → «attempt to get length of a number value»
        self.assertIn("for first, last in utf8.graphemes(text) do", body)
        self.assertIn("string.sub(text, first, last)", body)
        self.assertNotIn("for _, ch in utf8.graphemes", SOURCE)

        # очень длинное название — без сотен инстансов
        self.assertIn("if #glyphs > 28 then", body)

        # переключатель и справка
        self.assertIn('{"Letters reveal", "AnimText"', SOURCE)
        self.assertIn('["Letters reveal"]', SOURCE)

    def test_intro_can_be_disabled_and_is_in_effects_list(self):
        self.assertIn('{"Intro after key", "AnimIntro"', SOURCE)
        self.assertIn("UICFG.AnimIntro, UICFG.AnimText = false, false", SOURCE)  # low-end preset
        self.assertIn('["Intro after key"]', SOURCE)  # двуязычная справка
    def test_key_screen_uses_helpers(self):
        screen = between("local function keyScreen(done)", "stop = function()")
        self.assertIn("shake(form", screen)  # неверный ключ
        self.assertIn("pulse(btn", screen)
        self.assertNotIn('for _, dx in {-12, 12', screen)  # старый ручной цикл тряски убран

    def test_players_list_to_detail_slide(self):
        self.assertIn("local function slideIn(o)", SOURCE)
        block = SOURCE.split("closeDetail = function()", 1)[1].split("-- --- список игроков ---", 1)[0]
        self.assertIn("slideOut(detail", block)
        self.assertIn("slideOut(listView", block)
        self.assertIn("UICFG.AnimPages", SOURCE.split("local function slideIn(o)", 1)[1].split("local function slideOut", 1)[0])

    def test_unload_fades_before_destroy(self):
        body = SOURCE.split("stop = function()", 1)[1].split("Brand.release()", 1)[0]
        self.assertIn("BackgroundTransparency = 0.5", body)
        self.assertIn("gui:Destroy()", body)
        self.assertLess(body.index("FadeOut"), body.index("gui:Destroy()"))

    def test_dialog_opens_and_closes_with_animation(self):
        dialog = between("function helpUI.mount", "local function startMain")
        self.assertIn("dialogIn", dialog)
        self.assertIn("spring(dscale", dialog)
        self.assertIn("hiding", dialog)
        complete = dialog.split("local function complete()", 1)[1].split("end\n", 1)[0]
        self.assertIn("hide()", complete)

    def test_esp_lines_fade_without_per_frame_tweens(self):
        body = SOURCE.split("function TC.fade(", 1)[1].split("\nfunction TC.line", 1)[0]
        self.assertIn("TC.faded[f] == on", body)  # твин стартует только на смене состояния
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
