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
        # состояние тряски живёт в таблице ANIM (лимит локалей верхнего уровня)
        self.assertIn('shaking = setmetatable({}, {__mode = "k"})', SOURCE.split("local function shake(", 1)[0])
        self.assertIn("ANIM.shaking[o] then return end", body)
        self.assertIn("ANIM.shaking[o] = nil", body)

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
        self.assertIn('GLB.INTRO_WORD = "UNICRASE"', SOURCE)
        self.assertIn("INTRO_WORD:sub(i, i)", intro)
        # два выключателя: общий и отдельный
        self.assertIn("CFG.Anim and UICFG.AnimIntro", intro)
        # заставку НЕЛЬЗЯ пропустить: нет обработчика касаний, фон держит ввод до конца сцены
        self.assertNotIn("UT.Touch", intro)
        self.assertNotIn("InputBegan", intro)
        self.assertIn('Name = "IntroBg", Size = S(1, 1)', intro)
        self.assertIn("Active = true, ZIndex = 1", intro)
        # страховка по времени — единственный ранний выход
        self.assertIn("task.delay(GLB.INTRO_LEN + 0.5, stop)", intro)
        # шрифт логотипа и сцена: Michroma с фолбэком, осколки с градиентом, кольца, блик, подпись
        self.assertIn('Font.new("rbxasset://fonts/families/Michroma.json"', SOURCE)
        # шрифт выбирается безопасно: Michroma через семейство, потом Enum, в конце Gotham
        self.assertIn("GLB.INTRO_FONT = Font.fromEnum(Enum.Font.GothamBlack)", SOURCE)
        self.assertIn("typeof(f) == \"Font\"", SOURCE)
        self.assertIn("NumberSequenceKeypoint", intro)
        self.assertIn('Name = "Ring"', intro)
        self.assertIn('Name = "Shine"', intro)
        self.assertIn("INTRO_SUB", intro)
        # ширину букв не угадываем: каждая буква меряет себя сама (AutomaticSize),
        # иначе слово «плывёт» вправо, когда рендерится не тот шрифт, что меряли
        self.assertIn("AutomaticSize = Enum.AutomaticSize.XY", intro)
        self.assertNotIn("STS.GetTextSize, STS, INTRO_WORD", intro)
        self.assertIn("l.lbl.AbsoluteSize.X", intro)
        # серебро + свет из глубины + искры с блеском
        # хром: металлическая голова + глянцевая грань + подложки-толщина
        self.assertIn("ColorSequenceKeypoint.new(0.00, CHROME_HI)", intro)
        self.assertIn("ColorSequenceKeypoint.new(0.34, FACE_FLASH)", intro)
        self.assertIn("for d = 4, 1, -1 do", intro)
        # холодный белый свет и кристаллы-осколки из глубины
        self.assertIn("LIGHT_W, LIGHT_COLD", intro)
        self.assertIn('Name = "Crystal"', intro)
        self.assertIn('Name = "Dust"', intro)
        self.assertIn('Name = "Ray"', intro)
        self.assertIn('Name = "Haze"', intro)
        self.assertIn('Name = "SparkGlow"', SOURCE)  # искры в тексте папок
        self.assertIn('Name = "Ray"', intro)
        self.assertIn('Name = "Haze"', intro)
        self.assertIn("sh.g.Offset = V2(0, math.clamp(math.sin(t * 1.15 + sh.shift) * 0.9, -1, 1))", intro)
        # UIOffset у градиента ограничен [-1, 1] — значение за пределами роняет кадр
        self.assertIn('if k == "Offset" and typeof(v) == "Vector2"', SOURCE)
        # и потолок по ширине экрана: если слово шире — кегль уменьшается
        self.assertIn("local maxW = math.clamp(a.X * 0.84, 140, 820)", intro)
        # кадровые эффекты не накапливают размеры
        self.assertIn("baseHal", intro)
        self.assertIn("baseWordW", intro)
        # вызов ровно один и только в ветке верного ключа
        screen = between("local function keyScreen(done)", "stop = function()")
        valid = screen.split('== KEY_HASH then', 1)[1].split("tries += 1", 1)[0]
        # запуск защищён: ошибка заставки не мешает открыть меню
        self.assertIn("local okIntro = pcall(playIntro, safeAfter)", valid)
        self.assertIn("if not okIntro then", valid)
        # двойная страховка: таймер откроет меню, даже если сцена не позвала callback
        self.assertIn("task.delay(GLB.INTRO_LEN + 1.2, function() pcall(safeAfter) end)", valid)
        self.assertIn("if opened then return end", valid)
        self.assertEqual(SOURCE.count("playIntro"), 2)  # объявление + единственный вызов (через pcall)

    def test_particle_text_opens_folder(self):
        body = SOURCE.split("local function revealText(label, text, opt)", 1)[1].split("-- Анимация цифры", 1)[0]
        self.assertIn("UICFG.AnimText", body)
        # каждая буква — отдельный TextLabel, искры — отдельные фреймы, всё на твинах
        self.assertIn('new("TextLabel"', body)
        self.assertIn('Name = "Spark"', body)
        self.assertIn("tween(sp.f, info, {Position = O(sp.x, sp.y)", body)
        self.assertIn("spring(it.sc, {Scale = 1}, TWEEN.pop)", body)
        # выключено — текст ставится сразу, слой анимации снимается
        self.assertIn("label.Text, label.TextTransparency = text, 0", body)
        self.assertIn("layer:Destroy()", body)
        # поколение отменяет предыдущую анимацию (быстрые клики по папкам)
        self.assertIn("revealers[label] ~= gen", body)
        # utf8.graphemes отдаёт диапазон (два числа), а не символ:
        # старый `for _, ch in utf8.graphemes(text)` давал в ch число → «attempt to get length of a number value»
        self.assertIn("for first, last in utf8.graphemes(text) do", body)
        self.assertIn("string.sub(text, first, last)", body)
        self.assertNotIn("for _, ch in utf8.graphemes", SOURCE)
        # искры рождаются в контуре буквы, а не разлетаются по всей строке
        self.assertIn("local rx = math.max(2, g.w * 0.46)", body)
        self.assertIn("local ry = math.max(2, math.min(h * 0.46, size * 0.55))", body)
        self.assertIn("rnd:NextNumber(0.25, 1)", body)
        # слой ровно по строке: искры не залезают на соседние настройки и текст не сдвигается
        self.assertIn('Size = S(1, 1), BackgroundTransparency = 1, Active = false,', body)
        self.assertIn("Position = O(math.floor(g.x), 0)", body)
        # длинную строку не дробим на сотни инстансов
        self.assertIn("local dense = #glyphs > 24", body)
        # заголовок папки и названия карточек используют один хелпер
        show = between("local function show(n)", "for i, folder in folders do")
        self.assertIn("revealText(pTitle, newTitle", show)
        cascade = between("local function cascade(f)", "local folders = {")
        self.assertIn('c:FindFirstChild("Title")', cascade)
        self.assertIn("revealText(title, title.Text", cascade)
        # переключатель и справка
        self.assertIn('{"Particle text", "AnimText"', SOURCE)
        self.assertIn('["Particle text"]', SOURCE)

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

class ChamsAndFov(unittest.TestCase):
    def test_chams_look_list(self):
        # 4.5.0: плоский список из 22 «стилей» заменён полноценной системой Chams —
        # материал тела + настоящий узор + свет + эффекты, всё комбинируется.
        for key in ["Outline", "Soft", "Solid", "Glow", "Shaded", "Metallic", "Metal", "Chrome",
                    "Glossy", "Glass", "Crystal", "Ice", "Lava", "Water Flow", "Neon Rim"]:
            self.assertIn('key = "%s"' % key, SOURCE, "старые стили должны остаться в таблице CHAMS")
        self.assertIn('Chams = "Outline"', SOURCE)
        # панель собрана из данных и подключена к отдельной вкладке
        self.assertIn("local function buildChamsPage(parent, api)", SOURCE)
        self.assertIn("CHAMS_PAGE(pages, api)", SOURCE)
        self.assertIn("CHCTX.buildChamsPage, pages.Chams, api", SOURCE)
        for table in ("CH_MATS", "CH_TEX", "CH_TEX_ORDER", "CH_FX", "CH_PAT", "CH_DEF"):
            self.assertIn(table, SOURCE)
        # каждый слой движка настоящий: материал, узор, свет, обводка, частицы
        for fn in ("chPaintBody", "chPattern", "chPaintLight", "chOutline", "chPaintFx", "chPaintParticles"):
            self.assertIn("local function " + fn, SOURCE)
        self.assertIn("local function chApply(char, tint, now)", SOURCE)
        # старые сейвы не ломаются
        self.assertIn("for k, v in CH_DEF do if c[k] == nil then c[k] = v end end", SOURCE)
        # выдуманных ID текстур быть не должно: только настоящий ассет, который вводит пользователь
        tex = SOURCE.split("CH_TEX = {", 1)[1].split("CH_TEX_ORDER", 1)[0]
        self.assertNotIn("rbxassetid", tex, "ID текстур нельзя выдумывать")
        self.assertIn("CUSTOM TEXTURE ID", SOURCE)
        # длинные списки — в своих прокрутках
        self.assertIn("ScrollingFrame", SOURCE)
        self.assertIn("AutomaticCanvasSize = Enum.AutomaticSize.Y", SOURCE)

    def test_fov_style_cards(self):
        for key in ["Glow", "Gradient", "Dashed", "Classic"]:
            self.assertIn('key = "%s"' % key, SOURCE)
        self.assertIn("A.FovStyle = st.key", SOURCE)
        # пунктир рисуется сегментами по кругу и вращается
        self.assertIn("local DASH_N = 24", SOURCE)
        self.assertIn("seg.Rotation = math.deg(ang) + 90", SOURCE)

    def test_fov_size_in_pixels(self):
        self.assertIn("FovPx = 240", SOURCE)
        self.assertIn("FOV Size (diameter, px)", SOURCE)
        # радиус на экране берётся из пикселей, а не из процента короткой стороны
        self.assertIn("local rPx = (A.DynFov or NX.dynBack) and (NX.dynR * 0.01 * short) or math.max(2, A.FovPx * 0.5)", SOURCE)
        # согласование со старым полем, которым живёт Dynamic FOV
        self.assertIn("A.FovR = math.clamp(A.FovPx * 0.5 / short * 100, 2, 60)", SOURCE)
        # подпись текущего радиуса — в пикселях
        self.assertIn("%d px (diameter %d px)", SOURCE)


if __name__ == "__main__":
    unittest.main()

class ChamsActuallyApplies(unittest.TestCase):
    """Стиль Chams должен реально менять хайлайты, а не просто существовать в таблице.

    Первая версия ловила падение, но выбор стиля ничего не менял: chamsApply была
    объявлена и ни разу не вызвана, а refreshHL перезаписывал цвета базовыми.
    """

    def test_chams_apply_is_called(self):
        # применение стиля к Highlight — через таблицу CH (одна точка входа)
        self.assertGreaterEqual(SOURCE.count("CH.apply(o, fc, oc"), 1, "применение стиля не вызывается")
        self.assertIn("function CH.apply(o, fillColor, outlineColor, tintable)", SOURCE)

    def test_refresh_uses_style(self):
        body = between("local function refreshHL()", "local function unhl(")
        # стиль берётся по ключу прямо из CHAMS_BY_KEY (функция chamsStyle убрана ради лимита локалей)
        self.assertIn("CHAMS_BY_KEY[CFG.Chams or", body)
        self.assertIn("CH.apply(o, fc, oc", body)
        # базовые прозрачности больше не выставляются напрямую мимо стиля
        self.assertNotIn("h.FillTransparency = 1 - alphaFor", body)

    def test_styles_differ_visibly(self):
        import re
        table = between("CHAMS = {", "}\nCHAMS_BY_KEY")
        rows = re.findall(r"fill = ([\d.]+), outline = ([\d.]+)", table)
        self.assertEqual(len(rows), 22)
        fills = [float(f) for f, _ in rows]
        outlines = [float(o) for _, o in rows]
        # Solid и Soft (0.25 против 0.80 по заливке) обязаны отличаться заметно,
        # иначе пользователь их не различит на экране
        self.assertGreater(max(fills) - min(fills), 0.5)
        self.assertGreater(max(outlines) - min(outlines), 0.4)

    def test_style_alphas_are_distinguishable(self):
        # Коэффициенты берём ИЗ КОДА (chamsAlpha), а не дублируем в тесте:
        # иначе ослабление формулы в скрипте тест не заметит.
        import re
        m = re.search(r'local k = \(key == "Fill"\) and \(([\d.]+) - strength \* ([\d.]+)\)'
                      r" or \(([\d.]+) - strength \* ([\d.]+)\)", SOURCE)
        self.assertIsNotNone(m, "формула chamsAlpha не найдена или переписана")
        f_a, f_b, o_a, o_b = (float(v) for v in m.groups())
        table = between("CHAMS = {", "}\nCHAMS_BY_KEY")
        rows = re.findall(r"fill = ([\d.]+), outline = ([\d.]+)", table)
        self.assertEqual(len(rows), 22)

        def fill_alpha(f):
            return min(1.0, 0.45 * (f_a - f * f_b))

        def edge_alpha(o):
            return min(1.0, 1.0 * (o_a - o * o_b))

        fills = [fill_alpha(float(f)) for f, _ in rows]
        edges = [edge_alpha(float(o)) for _, o in rows]
        self.assertGreater(max(fills) - min(fills), 0.5,
                           "по формулe из кода стили дают одинаковую заливку — разницы не видно")
        self.assertGreater(max(edges) - min(edges), 0.15,
                           "по формуле из кода контур у всех стилей одинаковый")
        # Solid (fill 0.25) обязан быть плотнее Soft (0.80) не меньше чем на 0.4
        self.assertGreater(fill_alpha(0.25) - fill_alpha(0.80), 0.4)

    def test_style_tint_survives_hp_color(self):
        # цвет по здоровью и радуга перекрашивают заливку каждый кадр — оттенок стиля
        # должен возвращаться, иначе Chams «исчезает» при включённом HPColor
        body = between("if CFG.HPColor and hum then", "local far =")
        self.assertIn("CH.tint(", SOURCE)
        self.assertIn("-- HPColor и радуга перекрашивают заливку каждый кадр", SOURCE)

    def test_style_choice_is_saved(self):
        # выбор материала, текстуры и эффекта обязан сохраняться между запусками
        start = SOURCE.index("local function buildChamsPage(parent, api)")
        body = SOURCE[start:start + 9000]
        self.assertIn("saveNow()", body, "настройки Chams должны сохраняться")
        # ...и сразу применяться к целям, а не только писаться в состояние
        self.assertIn("refreshHL()", body)


class ChamsTextures(unittest.TestCase):
    """Chams Look — это ТЕКСТУРА тела, а не только плотность подсветки.

    Highlight умеет только заливку и контур, поэтому стиль дополнительно меняет
    материал частей тела: Neon светится, CrackedLava — лава, ForceField — сетка и т.д.
    """

    TEX = {
        "Neon": "Enum.Material.Neon", "Lava": "Enum.Material.CrackedLava",
        "Ice": "Enum.Material.Ice", "Glass": "Enum.Material.Glass",
        "ForceField": "Enum.Material.ForceField", "Metal": "Enum.Material.Foil",
        "Chrome": "Enum.Material.Foil", "Water Flow": "Enum.Material.Water",
    }

    def test_styles_carry_materials(self):
        from pathlib import Path
        import re
        table = between("CHAMS = {", "}\nCHAMS_BY_KEY")
        # запись стиля может занимать две строки: берём блок от "{key" до "}," включительно
        blocks = re.findall(r'\{key = "([^"]+)"(.*?)\},(?=\n)', table, re.S)
        self.assertGreater(len(blocks), 15, "не удалось разобрать таблицу стилей")
        by_key = dict(blocks)
        for key, mat in self.TEX.items():
            self.assertIn(key, by_key, "%s нет в таблице стилей" % key)
            self.assertIn(mat, by_key[key], "%s должен ставить материал %s" % (key, mat))

    def test_texture_is_applied_and_restored(self):
        self.assertIn("local function chamsTexture(", SOURCE)
        self.assertIn("local function chamsClear(", SOURCE)
        # texture вызывается из refreshHL
        body = between("local function refreshHL()", "local function unhl(")
        self.assertIn("chamsTexture", body)
        # и снимается при снятии подсветки/выгрузке, иначе игроки останутся неоновыми
        unhl = between("local function unhl(", "local function dohl(")
        self.assertIn("chamsClear", unhl)
        stop = SOURCE[SOURCE.index("stop = function()"):]
        self.assertIn("chamsClear", stop[:1500])

    def test_original_material_is_remembered(self):
        self.assertIn("chamsOrig[part] = {mat = part.Material, col = part.Color}", SOURCE)
        self.assertIn("part.Material = orig.mat", SOURCE)
        self.assertIn("part.Color = orig.col", SOURCE)

    def test_light_for_glowing_styles(self):
        self.assertIn("PointLight", SOURCE)
        self.assertIn("st.glow", SOURCE)


class FovCircleStyles(unittest.TestCase):
    """Стили круга FOV должны быть детьми самого круга, а не оверлея.

    Первая версия создавала сегменты пунктира в оверлее и считала позицию в долях ЭКРАНА —
    пунктир уезжал от круга, и все стили выглядели одинаково.
    """

    def test_style_objects_are_children_of_circle(self):
        import re
        m = re.search(r'local fovGlow = new\("Frame", \{[^}]*\}, (\w+)\)', SOURCE)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(1), "fov", "ореол должен быть ребёнком круга")
        m2 = re.search(r'local d = new\("Frame", \{[^}]*\}, (\w+)\)', SOURCE)
        self.assertIsNotNone(m2)
        self.assertEqual(m2.group(1), "fov", "сегменты пунктира должны быть детьми круга")

    def test_dashed_positions_are_circle_relative(self):
        body = between('elseif style == "Dashed" then', "elseif style == \"Gradient\"")
        self.assertIn("seg.Position = U(0.5 + math.cos(ang) * 0.5, 0.5 + math.sin(ang) * 0.5)", body)
        # вращение включается только при Animation
        self.assertIn("local spin = animate and (now * 0.6) or 0", body)

    def test_gradient_actually_animates(self):
        body = between('elseif style == "Gradient" then', "else\n\t\t\t\t-- Classic")
        self.assertIn("fovGrad.Rotation = animate and ((now * 125) % 360) or 45", body)
        # градиент из трёх и более цветов, иначе «перелива» не видно
        self.assertIn("ColorSequenceKeypoint.new(0.35", SOURCE)

    def test_glow_has_halo(self):
        self.assertIn("local fovHalo = {}", SOURCE)
        body = between('if style == "Glow" then', 'elseif style == "Dashed" then')
        self.assertIn("math.sin(now * 2.2)", body, "у свечения должно быть «дыхание»")


if __name__ == "__main__":
    unittest.main()