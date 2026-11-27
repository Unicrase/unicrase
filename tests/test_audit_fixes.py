"""Regression guards for the audit fixes (v4.3).

Covered here:
  * the access key lives on the server only, and shots without it are rejected;
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
AUTH_SALT = "enkaisy.v4.2:"


def djb2(value):
    h = 5381
    for byte in value.encode():
        h = (h * 33 + byte) % 4294967296
    return h


def between(start, end):
    return TEXT.split(start, 1)[1].split(end, 1)[0]


class AccessKey(unittest.TestCase):
    def test_key_hash_is_checked_on_the_server(self):
        server = TEXT.split("if RS:IsServer() then", 1)[1].split("\n    return\nend", 1)[0]
        self.assertIn("OnServerInvoke", server)
        self.assertIn("AUTH_HASH", server)
        self.assertIn("authorized[plr] = true", server)
        self.assertIn("authTries", server, "нужен лимит попыток ввода")

    def test_client_has_no_key_material(self):
        self.assertNotIn("KEY_HASH", TEXT, "хеш ключа не должен жить в клиенте")
        self.assertNotIn(f'"{ACCESS_KEY}"', TEXT, "ключ не должен лежать в файле текстом")
        self.assertIn("InvokeServer", TEXT, "клиент спрашивает сервер, а не проверяет сам")

    def test_current_key_still_matches_the_hash(self):
        auth_hash = int(re.search(r"local AUTH_HASH = (\d+)", TEXT).group(1))
        self.assertEqual(auth_hash, djb2(AUTH_SALT + ACCESS_KEY))

    def test_shots_require_authorization(self):
        shot = between("local function handleShot(", "-- 1. Типы данных")
        self.assertIn('if not authorized[plr] then return "not activated" end', shot)


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
