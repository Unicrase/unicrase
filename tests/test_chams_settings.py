"""Chams удалён из скрипта целиком (4.6.0) — эти тесты стерегут, чтобы он не вернулся.

Пользователь попросил удалить всю папку CHAMS: вкладку, панель, движок материалов,
узоров и эффектов, старые стили подсветки и переключатель в ESP. Подсветка ESP
осталась базовой: цвет + прозрачность Highlight.

Тесты проверяют три вещи:
1) ни одна часть движка не осталась в файле (иначе это мёртвый код и путаница);
2) подсветка продолжает работать без него (refreshHL, CH.apply, alphaFor);
3) настройки ESP сохраняются и читаются (базовая подсветка не сломана).
"""
import re
import unittest
from pathlib import Path

FULL = (Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua").read_text(encoding="utf-8")


def strip_comments(text):
    """Код без комментариев: в шапке осталась история версий, где старые имена упомянуты законно."""
    text = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S)
    return "\n".join(l for l in text.split("\n") if not l.lstrip().startswith("--"))


SOURCE = strip_comments(FULL)


class ChamsIsGone(unittest.TestCase):
    """Ни одной части удалённой папки CHAMS."""

    REMOVED = [
        "CH_MATS", "CH_FX", "CH_DEF", "CH_TEX", "CH_PAT", "CH_TEX_ORDER",
        "CHAMS_BY_KEY", "chamsTexture", "chamsClear", "chamsParts", "chamsOrig",
        "chamsLights", "chState", "chApply", "chLayer", "chOutline", "chPattern",
        "chPaintBody", "chPaintFx", "chPaintLight", "chPaintParticles", "chPaintBody",
        "buildChamsPage", "CHAMS_PAGE", "CH_DEF.TexId", "CFG.Chams2",
    ]

    def test_engine_names_are_gone(self):
        for name in self.REMOVED:
            self.assertNotIn(name, SOURCE, name + " всё ещё в файле — движок удалён не полностью")

    def test_no_chams_tab(self):
        self.assertNotIn('id = "Chams"', SOURCE)
        self.assertNotIn('title = "CHAMS"', SOURCE)

    def test_no_chams_switch_in_esp(self):
        self.assertNotIn("Материалы и эффекты Chams", SOURCE)
        self.assertNotIn("chClearVisible", SOURCE)

    def test_no_style_list(self):
        # таблица старых стилей подсветки (Outline / Soft / Solid / Neon / Lava ...)
        self.assertNotIn("CHAMS = {", SOURCE)
        self.assertNotIn("mat = Enum.Material.Neon", SOURCE)


class HighlightStillWorks(unittest.TestCase):
    """Базовая подсветка ESP после удаления Chams."""

    def test_refresh_still_sets_colors(self):
        start = SOURCE.index("local function refreshHL()")
        body = SOURCE[start:SOURCE.index("\nlocal function unhl", start)]
        self.assertIn("CH.apply(o, fc, oc)", body)
        self.assertIn("marks[id] == \"Mark\"", body)
        self.assertIn("CFG.TeamColors", body)

    def test_apply_sets_transparency_from_settings(self):
        start = SOURCE.index("function CH.apply(o, fillColor, outlineColor)")
        body = SOURCE[start:SOURCE.index("\nend", start)]
        self.assertIn("alphaFor(o.plr, \"Fill\", CFG.Fill, 0.45)", body)
        self.assertIn("alphaFor(o.plr, \"Outline\", CFG.Outline, 0.8)", body)
        self.assertIn("FillTransparency", body)
        self.assertIn("OutlineTransparency", body)

    def test_frame_loop_does_not_call_engine(self):
        frame = SOURCE[SOURCE.index("local function render()"):] if "local function render()" in SOURCE else SOURCE
        self.assertNotIn("chApply", frame)
        self.assertNotIn("chamsTexture", frame)

    def test_unhl_clears_only_highlight(self):
        start = SOURCE.index("local function unhl(char, fade)")
        body = SOURCE[start:start + 900]
        self.assertIn("restoreNative(o)", body)
        self.assertNotIn("chamsClear", body)


class EspSettingsStillSaved(unittest.TestCase):
    """Настройки ESP, которые раньше были частью панели Chams."""

    def test_fill_and_outline_sliders_exist(self):
        self.assertIn('slider("Fill strength", "Fill"', SOURCE)
        self.assertIn('slider("Outline opacity", "Outline"', SOURCE)

    def test_settings_are_persisted(self):
        self.assertIn("CFG.Fill", SOURCE)
        self.assertIn("CFG.Outline", SOURCE)
        self.assertIn("saveNow", SOURCE)

    def test_help_does_not_mention_removed_panel(self):
        self.assertNotIn("Материалы и эффекты Chams", SOURCE)

    def test_no_help_entries_for_deleted_controls(self):
        """Справка не должна описывать настройки, которых больше нет в интерфейсе."""
        import re as _re
        info_start = SOURCE.index("helpUI.info = {")
        info_end = SOURCE.index("\n}", info_start)
        block = SOURCE[info_start:info_end]
        rest = SOURCE[:info_start] + SOURCE[info_end:]
        for key in _re.findall(r'^ \["([^"]+)"\]', block, _re.M):
            self.assertIn('"%s"' % key, rest, "справка описывает удалённую настройку: " + key)


if __name__ == "__main__":
    unittest.main()
