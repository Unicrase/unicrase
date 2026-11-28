"""Regression guards for the audit fixes (v4.3).

Covered here:
  * the access key is checked in the client by hash (KEY_HASH), nothing accepted on the server;
  * head hitbox uses its own size (falls back to the body size when it is 0);
  * weapon cooldowns are tracked per Tool (server + client + triggerbot);
  * the triggerbot reaches as far as the weapon Range, not "Aim max distance";
  * the ESP update-rate slider really throttles, including 60 Hz on faster screens.
"""
import re
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua"
TEXT = SOURCE.read_text(encoding="utf-8")

ACCESS_KEY = "61937"


def djb2(value):
    h = 5381
    for byte in value.encode():
        h = (h * 33 + byte) % 4294967296
    return h


def between(start, end):
    return TEXT.split(start, 1)[1].split(end, 1)[0]


class AccessKey(unittest.TestCase):
    def test_key_is_checked_in_the_client(self):
        screen = between("local function keyScreen(done)", "stop = function()")
        self.assertIn('hashKey((box.Text:gsub("%s", ""))) == KEY_HASH', screen)
        self.assertNotIn("InvokeServer", screen, "окно ключа не должно ходить на сервер")

    def test_server_does_not_know_the_key(self):
        server = TEXT.split("if RS:IsServer() then", 1)[1].split("\n    return\nend", 1)[0]
        self.assertNotIn("AUTH_HASH", server)
        self.assertNotIn("OnServerInvoke", server)
        self.assertNotIn("RemoteFunction", server)

    def test_key_is_not_stored_as_plain_text(self):
        self.assertNotIn(f'"{ACCESS_KEY}"', TEXT, "ключ не должен лежать в файле текстом")

    def test_current_key_still_matches_the_hash(self):
        key_hash = int(re.search(r"local KEY_HASH = (\d+)", TEXT).group(1))
        self.assertEqual(key_hash, djb2(ACCESS_KEY))

    def test_shots_do_not_depend_on_the_key(self):
        shot = between("local function handleShot(", "-- 1. Типы данных")
        self.assertNotIn("not activated", shot)
        self.assertNotIn("authorized", shot)


class HeadHitbox(unittest.TestCase):
    def test_head_uses_its_own_size(self):
        box = between("local function rayModelHitbox(", "local function humanoidModel(")
        self.assertNotIn("math.max(bodyPad, headPad)", box)
        self.assertIn("headPad > 0 and headPad or bodyPad", box)

    def test_visual_matches_the_hit_logic(self):
        self.assertIn("isHead and (h > 0 and h or b) or b", TEXT)


class Cooldowns(unittest.TestCase):
    def test_server_cooldown_is_per_tool(self):
        shot = between("local function handleShot(", "local function")
        self.assertIn("lastShot[tool]", shot)
        self.assertNotIn("lastShot[plr]", shot)
        self.assertIn('setmetatable({}, {__mode = "k"})', between("local lastShot =", "\n"))

    def test_client_and_triggerbot_cooldowns_are_per_tool(self):
        self.assertIn("lastSent[tool]", TEXT)
        self.assertIn("lastTrigger[tool]", TEXT)


class TriggerbotRange(unittest.TestCase):
    def test_range_comes_from_the_weapon(self):
        step = between("local function triggerStep(", "local tolPx =")
        self.assertIn('tool:GetAttribute("Range")', step)
        self.assertNotIn("A.MaxDistance", step)


class EspUpdateRate(unittest.TestCase):
    def test_throttle_applies_to_every_rate(self):
        frame = between("local hz = CFG.EspHz", "lastWork = now")
        self.assertNotIn("hz < 60", frame)
        self.assertIn("1 / hz", frame)


if __name__ == "__main__":
    unittest.main()
