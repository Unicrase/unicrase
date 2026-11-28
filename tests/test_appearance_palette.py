"""Свободная палитра меню (4.7.1).

Пользователь попросил: «любые цвета в любых местах» — палитра RGB + HEX на все
кнопки, плюс размер и контуры кнопок. Эти тесты стерегут, что настройка реально
доходит до кода, а старые сохранения не ломают меню.
"""
import unittest
from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua").read_text(encoding="utf-8")


def between(start, end):
    return SOURCE.split(start, 1)[1].split(end, 1)[0]


class CustomPalette(unittest.TestCase):
    def test_custom_theme_exists(self):
        self.assertIn('GLB.THEME_ORDER = {"Dark", "Midnight", "Amoled", "Forest", "Crimson"}', SOURCE)
        self.assertIn('table.insert(themeList, "Custom")', SOURCE)
        self.assertIn('if name ~= "Custom" and not THEMES[name] then return end', SOURCE)

    def test_every_surface_is_paintable(self):
        pal = between("GLB.PAL = {", "}")
        for key in ("Win", "Side", "Card", "Input", "Line", "Sel", "Hi", "Mut", "W"):
            self.assertIn('"%s"' % key, pal, key)
        extra = between("GLB.EXTRA = {", "GLB.EXTRA_RU")
        for key in ("On", "Off", "Danger", "DangerBg", "Good", "Mid", "Bad"):
            self.assertIn(key, extra, key)

    def test_hex_round_trip_and_bad_input(self):
        self.assertIn("local function palColor(hex, fallback)", SOURCE)
        self.assertIn("pcall(Color3.fromHex", SOURCE, "битый HEX не должен ломать меню")
        self.assertIn('UICFG.Pal[palSel] = "#" .. Color3.fromHSV(', SOURCE, "цвет хранится как HEX")

    def test_old_saves_are_filled_with_defaults(self):
        self.assertIn("for _, k in GLB.PAL_ALL do", SOURCE)
        self.assertIn("if type(UICFG.Pal[k]) ~= \"string\" then", SOURCE)

    def test_picker_writes_palette(self):
        body = SOURCE[SOURCE.index('sectionLabel(pa, "CUSTOM PALETTE / СВОЯ ПАЛИТРА"'):]
        body = body[:body.index('sectionLabel(pa, "OUTLINES / КОНТУРЫ"')]
        self.assertIn("makePicker(", body, "квадрат S/V + полоса оттенка + HEX")
        self.assertIn("UICFG.Theme = \"Custom\"", body)
        self.assertIn("setTheme(\"Custom\")", body, "правка цвета сразу перекрашивает меню")

    def test_new_buttons_can_take_tokens(self):
        """new{colors = true} превращает C = "Card" в текущий цвет палитры."""
        body = SOURCE[SOURCE.index("function new(class, props, parent)"):]
        body = body[:body.index("local function round(o, r)")]
        self.assertIn("if props.colors then", body)
        self.assertIn('C = "BackgroundColor3"', body)
        self.assertIn('TxC = "TextColor3"', body)


class OutlinesAndSizes(unittest.TestCase):
    def test_control_thickness_and_transparency(self):
        for key in ("BtnStroke", "BtnStrokeAlpha", "FieldStroke", "MenuStroke", "MenuStrokeAlpha"):
            self.assertIn(key, SOURCE, key)

    def test_outline_reads_settings(self):
        self.assertIn("local function btnStrokeW()", SOURCE)
        self.assertIn("local function btnStrokeT(t)", SOURCE)
        self.assertIn("GLB.strokes[st] = base", SOURCE, "реестр нужен для живого применения")

    def test_menu_outline_is_separate(self):
        self.assertIn("GLB.menuStroke = panelStroke", SOURCE)
        self.assertIn("GLB.menuStroke.Thickness = UICFG.MenuStroke or 1", SOURCE)

    def test_button_size_and_radius(self):
        self.assertIn('aSlider("UI Scale (buttons, HUD, key)", "UIScale", 0.8, 1.3, 0.05', SOURCE)
        self.assertIn('aSlider("Corner Radius", "Corner", 0, 16, 1', SOURCE)

    def test_help_is_bilingual(self):
        info = between("helpUI.info = {", "function helpUI.add")
        for title in ("Button outline (px)", "Field outline (px)", "Menu outline (px)"):
            line = next((l for l in info.split("\n") if '["%s"]' % title in l), "")
            self.assertTrue(line.count('"') >= 6, title + " без пары ru/en")


if __name__ == "__main__":
    unittest.main()
