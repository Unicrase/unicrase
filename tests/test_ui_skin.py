"""Skin invariants and an optional headless test of the real Luau widget factories."""
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = (HERE.parent / "Enkaisy_Combined_UI_v4_2.lua").read_text(encoding="utf-8")


def between(start, end):
    return start + SOURCE.split(start, 1)[1].split(end, 1)[0]


def luminance(rgb):
    channels = (int(n) / 255 for n in rgb.split(","))
    return sum(w * (c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
               for w, c in zip((0.2126, 0.7152, 0.0722), channels))


class SkinTests(unittest.TestCase):
    def test_every_folder_has_a_drawable_glyph(self):
        folders = re.findall(r'\bid = "(\w+)"', between("local folders = {", "local repaints"))
        glyphs = between("Skin.glyphs = {", "local function icon(")
        names = set(re.findall(r'\b(\w+) = \{(?:paths|rings) =', glyphs))
        self.assertTrue(folders)
        self.assertEqual(len(folders), len(set(folders)))
        self.assertFalse(set(folders) - names)
        for kind, groups in re.findall(r'(paths|rings) = \{((?:\{[\d., ]+\}(?:, )?)+)\}', glyphs):
            for group in re.findall(r'\{([^}]+)\}', groups):
                points = [float(n) for n in group.split(",")]
                if kind == "rings":
                    self.assertEqual(len(points), 3)
                    self.assertGreater(points[2], 0)
                else:
                    self.assertGreaterEqual(len(points), 4)
                    self.assertEqual(len(points) % 2, 0)
                self.assertTrue(all(0 <= n <= 16 for n in points), group)

    def test_captions_remain_legible_on_card_and_hover_surfaces(self):
        palettes = re.findall(r'(\w+) = \{(Win = .*?)\},\n', between("local THEMES = {", "local THEME_ORDER"))
        self.assertIn("Dark", dict(palettes))
        for theme, palette in palettes:
            colors = {k: luminance(v) for k, v in re.findall(r'(\w+) = \{([\d, ]+)\}', palette)}
            for surface in ("Win", "Side", "Card", "Sel"):
                self.assertGreaterEqual((colors["Mut"] + 0.05) / (colors[surface] + 0.05), 4.5,
                                        f"{theme}: muted text on {surface}")

    def test_text_fields_share_focus_treatment(self):
        fields = set(re.findall(r'local (\w+) = new\("TextBox",', SOURCE))
        styled = set(re.findall(r'Skin\.field\((\w+)\)', SOURCE.split("local function row(", 1)[1]))
        self.assertFalse(fields - styled, fields - styled)

    @unittest.skipUnless(shutil.which("luau"), "Luau CLI not on PATH")
    def test_widget_states_and_slider_drag(self):
        # Run only UI factories. No game services, authentication, network or renderer required.
        factories = "\n".join((between("local function makeSwitch(", "local gui ="),
                               between("local function toggleCard(", "local function cycleCard("),
                               between("local lockedSF\n", "-- вкладка выбора цвета")))
        fixture = (HERE / "widget_smoke.luau").read_text(encoding="utf-8")
        with tempfile.TemporaryDirectory() as folder:
            script = Path(folder) / "widgets.luau"
            script.write_text(fixture.replace("-- INSERT_FACTORIES", factories), encoding="utf-8")
            result = subprocess.run([shutil.which("luau"), str(script)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
