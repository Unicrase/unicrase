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
        self.page = between(SOURCE, "local function buildChamsPage(parent, api)", "\t-- СБРОС")

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

    def test_colors_are_real_palettes(self):
        # Color/Color2/GlowColor/OutlineColor должны иметь палитру, а не только поле в таблице
        for key in ("Color", "Color2", "GlowColor", "OutlineColor"):
            self.assertIn('"%s"' % key, self.page, "нет палитры для " + key)

    def test_settings_are_saved(self):
        self.assertIn("saveNow()", between(SOURCE, "local function buildChamsPage", "\t-- СБРОС"))


if __name__ == "__main__":
    unittest.main()
