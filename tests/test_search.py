"""Static guards for the sidebar search (jump to the exact card + Telegram-style arrows).

Behaviour covered:
  * a query is split into words, and every word must be found (any order);
  * a click on a result row opens the page and scrolls it to that exact card;
  * a click on a folder with hits jumps to its first hit instead of the page top;
  * when a query matches several settings, rows get prev/next arrows that cycle;
  * a single hit is opened automatically, and the search panel takes space from the folder list.
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
        self.search = between("-- ===== Результаты поиска: точный переход к элементу =====", "-- ===== События =====")

    def test_query_is_matched_word_by_word(self):
        terms = between("local function searchTerms()", "local SEARCH_BOTTOM")
        self.assertIn('gmatch("%S+")', terms)
        self.assertIn("for _, w in terms do", self.search, "каждое слово запроса проверяется отдельно")
        self.assertIn("if not string.find(hay, w, 1, true) then all = false break end", self.search)

    def test_result_row_jumps_to_the_exact_card(self):
        self.assertIn("local function scrollPage(pg, card)", self.search)
        self.assertIn("CanvasPosition = V2(0, math.max(0, y", self.search)
        self.assertIn("on(rowBtn.Activated, function() goTo(folder, card, indexOf(card)) end)", self.search)
        self.assertIn("local function flash(card)", self.search, "найденная карточка подсвечивается")

    def test_folder_click_goes_to_the_first_hit(self):
        self.assertIn("folderHook = function(n)", self.search)
        self.assertIn("if folderHook and folderHook(n) then return end", TEXT)

    def test_arrows_cycle_through_matches(self):
        self.assertIn("local function stepResult(dir)", self.search)
        self.assertIn("matchStep = (matchStep - 1 + (dir or 1)) % #resultSigs + 1", self.search)
        self.assertIn('arrow("Down", "NextMatch", 3)', self.search)
        self.assertIn('arrow("Up", "PrevMatch", 26)', self.search)
        self.assertIn("if #resultSigs > 1 then", self.search, "стрелки только когда совпадений несколько")

    def test_single_hit_opens_itself_and_panel_shrinks_the_folder_list(self):
        self.assertIn("if #terms > 0 and #resultSigs == 1 then", self.search)
        self.assertIn("tabsHolder.Size = U(1, -10, 1, -(SEARCH_BOTTOM", self.search)
        self.assertIn("SEARCH_BOTTOM = 83", self.search)


class HelpRegistry(unittest.TestCase):
    def test_card_owner_lookup_exists(self):
        self.assertIn("helpUI.cardOwner", TEXT, "поиску нужен объект карточки для прокрутки")


if __name__ == "__main__":
    unittest.main()
