"""Static guards for the sidebar search (jump to the nearest card + arrows beside the page).

Behaviour covered:
  * a query is split into words and every word must be found, in any order;
  * folders without a match disappear from the folder list (folders with a match stay);
  * clicking a folder jumps to its nearest match, not to the top of the page;
  * arrows ▲▼ + "3/12" counter stand in a strip on the right of the page and cycle matches;
  * the page narrows to leave room for the arrows, so they never cover switches;
  * typing only filters folders (no jumping), Enter goes to the nearest match, the old panel is gone.
"""
import re
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua"
TEXT = SOURCE.read_text(encoding="utf-8")


def between(start, end):
    return TEXT.split(start, 1)[1].split(end, 1)[0]


class Search(unittest.TestCase):
    def setUp(self):
        self.search = between("-- ===== Переход к совпадению и стрелки справа от страницы =====", "-- ===== События =====")

    def test_query_is_matched_word_by_word(self):
        terms = between("function searchTerms()", "local function matchAll")
        self.assertIn('gmatch("%S+")', terms)
        self.assertIn("local function matchAll(hay, terms)", TEXT)
        self.assertIn("if not string.find(hay, w, 1, true) then return false end", TEXT)

    def test_folders_without_matches_disappear(self):
        folders = between("local function filterTabs()", "local function onQueryChanged")
        self.assertIn("tab.Visible = visible", folders)
        self.assertIn("for _, w in terms do", folders)
        self.assertIn("empty.Visible = y == 0", folders)

    def test_folder_click_goes_to_the_nearest_hit(self):
        self.assertIn("function nearestIn(folder)", self.search)
        self.assertIn("local i = nearestIn(n)", TEXT)
        self.assertIn("if i then showHit(i) end", TEXT)
        self.assertNotIn("folderHook", TEXT)

    def test_arrows_and_counter_sit_beside_the_page(self):
        self.assertIn('navBtn("Up", "SearchPrev", 0)', self.search)
        self.assertIn('navBtn("Down", "SearchNext", 1)', self.search)
        self.assertIn('Name = "SearchCount"', self.search)
        self.assertIn('navCount.Text = hitStep .. "/" .. #hits', self.search)
        self.assertIn("Position = U(1, -5, 0, CY + 4 + order * 28)", self.search, "стрелки у правого края страницы")

    def test_page_narrows_to_make_room(self):
        self.assertIn("local NAV_GUTTER = 32", self.search)
        self.assertIn("setNavOpen(any)", self.search)
        self.assertIn("pg.Size = U(1 - RAIL, -Skin.RailBase - 26 - (on_ and NAV_GUTTER or 0)", self.search)

    def test_matches_cycle_wraps_around(self):
        self.assertIn("hitStep = (i - 1) % #hits + 1", self.search)
        self.assertIn("showHit(hitStep + 1)", self.search)
        self.assertIn("showHit(hitStep - 1)", self.search)
        self.assertIn("showHit(hitStep > 1 and hitStep + 1 or 1)", self.search, "Enter ведёт к первому совпадению")

    def test_found_card_is_scrolled_to_and_flashed(self):
        self.assertIn("local function scrollPage(pg, card)", self.search)
        self.assertIn("local function flash(card)", self.search)
        self.assertIn("flash(sig[2])", self.search)

    def test_old_result_panel_is_gone(self):
        self.assertNotIn("SearchResults", TEXT)
        self.assertNotIn("paintResults(", TEXT)
        self.assertNotIn("resultSigs", TEXT)


class HelpRegistry(unittest.TestCase):
    def test_card_owner_lookup_exists(self):
        self.assertIn("helpUI.cardOwner", TEXT, "поиску нужен объект карточки для прокрутки")


if __name__ == "__main__":
    unittest.main()
