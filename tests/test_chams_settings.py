"""Chams: каждая настройка панели обязана что-то менять.

Правило от пользователя: нельзя создавать настройки, которые ничего не меняют,
и нельзя добавлять названия материалов без визуальной реализации. Статическая
проверка ловит именно это: ключ, который панель пишет в состояние, должен
читаться движком.
"""
import re
import unittest
from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua").read_text(encoding="utf-8")


def between(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


class ChamsSettings(unittest.TestCase):
    """Ни одной «мёртвой» настройки в панели Chams."""

    def setUp(self):
        # движок + refreshHL: часть настроек (плотность заливки) живёт в слое Highlight
        self.engine = between(SOURCE, "local function chState()", "-- ===== ПАНЕЛЬ CHAMS") + \
            between(SOURCE, "local function refreshHL()", "\nlocal function unhl")
        self.page = between(SOURCE, "local function buildChamsPage(parent, api)",
                            "\n-- Единая точка API движка Chams")

    def test_every_slot_is_read_by_the_engine(self):
        written = set(re.findall(r'slot\("[^"]+",\s*"(\w+)"', self.page))
        self.assertGreaterEqual(len(written), 10, "ползунки должны быть")
        dead = sorted(k for k in written if not re.search(r"[\w_]+\.%s\b" % k, self.engine))
        self.assertEqual(dead, [], "ползунки, которые движок не читает: %s" % dead)

    def test_engine_uses_material_and_effects(self):
        # материал тела и каждый слой рисуются настоящими свойствами Roblox
        self.assertIn("part.Material", self.engine)
        self.assertIn("part.Reflectance", self.engine)
        self.assertIn("part.TextureID", self.engine)
        self.assertIn("PointLight", self.engine)
        self.assertIn("BoxHandleAdornment", self.engine)  # толщина обводки
        self.assertIn("UIGridLayout", self.engine)        # узор
        self.assertIn("ParticleEmitter", self.engine)

    def test_no_fake_asset_ids(self):
        # ID нельзя придумывать: в таблице текстур только имена узоров
        tex = between(SOURCE, "CH_TEX = {", "CH_TEX_ORDER")
        self.assertNotIn("rbxassetid", tex)
        self.assertNotIn("rbxassetid://2883", SOURCE)

    def test_every_texture_has_a_real_pattern(self):
        # каждое имя в списке текстур обязано иметь настоящий узор в CH_PAT,
        # иначе пункт «Texture» ничего не рисует (запрет на пустые настройки)
        order = re.findall(r'"([A-Za-z]+)"', between(SOURCE, "CH_TEX_ORDER = {", "-- Текущее состояние Chams"))
        patterns = set(re.findall(r'([A-Za-z]+) = \{(?:shape|lines|wave)', between(SOURCE, "CH_PAT = {", "local function chPattern")))
        self.assertGreaterEqual(len(order), 30, "список текстур должен быть полным")
        self.assertEqual([k for k in order if k != "None" and k not in patterns], [],
                         "текстуры без реализации")

    def test_page_cards_have_layout_order(self):
        # страница использует UIListLayout: карточка без LayoutOrder встаёт в случайном месте
        page = between(SOURCE, "local function buildChamsPage(parent, api)",
                       "\n-- Единая точка API движка Chams")
        cards = re.findall(r'new\("Frame", \{[^}]*BackgroundColor3 = C\.Card[^}]*\}, parent\)', page, re.S)
        self.assertGreaterEqual(len(cards), 3)
        for card in cards:
            self.assertIn("LayoutOrder", card, "карточка панели без LayoutOrder")

    def test_colors_are_real_palettes(self):
        # Color/Color2/GlowColor/OutlineColor должны иметь палитру, а не только поле в таблице
        for key in ("Color", "Color2", "GlowColor", "OutlineColor"):
            self.assertIn('"%s"' % key, self.page, "нет палитры для " + key)

    def test_settings_are_saved(self):
        self.assertIn("saveNow()", between(SOURCE, "local function buildChamsPage", "\t-- СБРОС"))


if __name__ == "__main__":
    unittest.main()


class ChamsDeclarationOrder(unittest.TestCase):
    """Панель собирается при старте меню: всё, что она зовёт, обязано быть объявлено ВЫШЕ.

    Именно из-за нарушения этого правила вкладка CHAMS оказалась пустой: панель звала
    sectionLabel, объявленную ниже, вызов падал на nil, а pcall это молча глотал.
    """

    def test_helpers_used_by_page_are_declared_earlier(self):
        page_at = SOURCE.index("local function buildChamsPage")
        page = SOURCE[page_at:SOURCE.index("\n-- Единая точка API движка Chams", page_at)]
        # sectionLabel вызывается только через шину (CHCTX) — прямых обращений быть не должно
        direct = re.findall(r"(?<![\w.:])sectionLabel\s*\(", page)
        self.assertEqual(direct, [], "sectionLabel объявлена ниже панели: зовём через CHCTX")
        self.assertIn("CHCTX.sectionLabel", page)
        # всё остальное, что панель зовёт напрямую, объявлено раньше
        for name in ("chState", "CH_MAT_KEY", "CH_TEX", "CH_TEX_ORDER", "CH_FX", "CH_PAT"):
            self.assertLess(SOURCE.index(name), page_at, name + " объявлен ниже панели")

    def test_pattern_layer_comes_before_pattern_paint(self):
        # chPattern зовёт chFxLayer: он должен быть объявлен выше, иначе слой не создаётся
        self.assertLess(SOURCE.index("local function chFxLayer"), SOURCE.index("local function chPattern"))

    def test_page_errors_are_not_swallowed(self):
        # пустая вкладка без причины недопустима: ошибка сборки должна быть видна в консоли
        self.assertIn("панель Chams не собралась", SOURCE)

    def test_legacy_mode_really_turns_materials_off(self):
        # выключенные материалы должны возвращать тело к исходному виду и не
        # применять плотность заливки Chams: иначе переключатель «не работает»
        tex = between(SOURCE, "local function chamsTexture", "local base = st.col")
        self.assertIn("cs.MatOn ~= false", tex, "при выключенных материалах движок не запускается")
        self.assertIn("chamsClear(char)", tex, "тело возвращается к исходному виду")
        refresh = between(SOURCE, "local function refreshHL()", "local function unhl")
        self.assertIn("cs.MatOn == false", refresh, "refreshHL обязан видеть выключенный режим")

    def test_failure_is_visible_on_screen(self):
        # на телефоне консоли нет: ошибка сборки панели должна быть видна в самой вкладке
        block = SOURCE[SOURCE.index("local function CHAMS_PAGE"):SOURCE.index("local function startMain")]
        self.assertIn("панель не собралась", block, "нет сообщения об ошибке в интерфейсе")
        self.assertIn("to string", block.replace("tostring", "to string"))
        self.assertIn("DangerBg", block, "сообщение должно быть заметным")
        self.assertIn("ChamsDiag", block, "нужна строка диагностики, что панель построена")

    def test_legacy_switch_persists_and_repaints(self):
        block = SOURCE[SOURCE.index('toggleCard(pm, "Материалы и эффекты Chams"'):]
        block = block[:block.index("CHAMS_PAGE(pages, api)")]
        self.assertIn("chState()", block, "переключатель обязан приводить состояние к таблице")
        self.assertIn("refreshHL", block, "выключение должно сразу перекрашивать цели")
        self.assertIn("saveNow()", block, "значение должно сохраняться")
