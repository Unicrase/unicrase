"""Static guard for bilingual descriptions on the standard setting cards."""
import re
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua"


class HelpCoverage(unittest.TestCase):
    def test_standard_cards_have_bilingual_help(self):
        source = SOURCE.read_text(encoding="utf-8")
        help_block = source.split("helpUI.info = {", 1)[1].split("function helpUI.add", 1)[0]
        descriptions = dict(
            (name, (ru, en)) for name, ru, en in re.findall(
                r'\["([^"\n]+)"\]\s*=\s*\{"([^"\n]+)",\s*"([^"\n]+)"\}', help_block
            )
        )
        ui = source.split("local function buildAim", 1)[1]
        titles = set(re.findall(r'\b(?:slider|vslider|aSlider|cycle|cycleKeep|cyc|tog)\("([^"\n]+)"', ui))
        titles.update(re.findall(r'\b(?:cycleCard|sliderCard)\(\w+,\s*"([^"\n]+)"', ui))
        # Lists passed to chips/makeChips; exclude unrelated tables and the custom player-detail rows.
        config = source.split("local CFG =", 1)[1].split("-- ===== v4.0: общие данные", 1)[0]
        for title, key in re.findall(r'\{"([^"\n]+)",\s*"([A-Za-z][A-Za-z0-9]*)"', ui):
            if re.search(r'\b' + re.escape(key) + r'\s*=', config) and title not in {"Nickname", "Outline", "UpperTorso"}:
                titles.add(title)
        self.assertEqual(sorted(titles - descriptions.keys()), [], "Missing bilingual descriptions")
        for title in titles:
            self.assertTrue(all(descriptions[title]), title)


if __name__ == "__main__":
    unittest.main()
