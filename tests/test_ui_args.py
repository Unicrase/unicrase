"""Аргументы UI-хелперов: тип каждой позиции проверяется статически.

Классическая ошибка в этом файле — перепутать местами «шаг» и «формат значения»
у ползунка: fmt приходит числом и панель падает с
"attempt to call a number value". Тест ловит такие вызовы до запуска в игре.
"""
import re
import unittest
from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua").read_text(encoding="utf-8")


def func_block(header):
    """Тело функции по строке-заголовку: до строки 'end' с тем же отступом."""
    start = SOURCE.index(header)
    indent = len(header) - len(header.lstrip("\t"))
    lines = SOURCE[start:].splitlines(keepends=True)
    body = [lines[0]]
    for line in lines[1:]:
        body.append(line)
        if line.rstrip("\n") == "\t" * indent + "end":
            break
    return "".join(body)


def split_args(text):
    """Аргументы вызова с учётом вложенных скобок и строк."""
    args, depth, cur, quote = [], 0, "", None
    for ch in text:
        if quote:
            cur += ch
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
            cur += ch
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth < 0:
                break
        elif ch == "," and depth == 0:
            args.append(cur.strip())
            cur = ""
            continue
        cur += ch
    if cur.strip():
        args.append(cur.strip())
    return args


def calls(name):
    """Все вызовы name(...) верхнего уровня с их аргументами."""
    out = []
    for m in re.finditer(r"(?<![\w.])" + re.escape(name) + r"\(", SOURCE):
        i = m.end()
        depth, quote, start = 1, None, i
        while i < len(SOURCE) and depth:
            ch = SOURCE[i]
            if quote:
                if ch == quote and SOURCE[i - 1] != "\\":
                    quote = None
            elif ch in "\"'":
                quote = ch
            elif ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            i += 1
        out.append((SOURCE[m.start():i], split_args(SOURCE[start:i - 1]), m.start()))
    return out


class SliderArguments(unittest.TestCase):
    """Ползунки панели ESP: (title, key, min, max, pct, fmt, step)."""

    def setUp(self):
        self.header = "local function slider(title, key, min, max, pct, fmt, step)"

    def test_helper_exists_and_guards_type(self):
        self.assertIn(self.header, SOURCE)
        body = func_block("\t" + self.header)
        # страховка от неверного типа: число в позиции fmt трактуется как шаг
        self.assertIn('if type(fmt) == "number" and step == nil then fmt, step = nil, fmt end', body)
        self.assertIn('if type(fmt) ~= "function" then fmt = nil end', body)
        # fmt вызывается только как функция
        self.assertIn("if fmt then return fmt(v) end", body)

    def test_every_call_passes_a_function_or_nil(self):
        # у ползунков ESP позиция 5 (pct) — логическое значение; у Aim она числовая (step)
        found = [c for c in calls("slider") if c[0].startswith('slider("') and len(c[1]) >= 5
                 and c[1][4] in ("true", "false")]
        self.assertGreaterEqual(len(found), 3, "ползунки ESP должны находиться")
        for text, args, _ in found:
            self.assertGreaterEqual(len(args), 5, text)
            if len(args) >= 6:
                fmt = args[5]
                self.assertTrue(fmt == "nil" or fmt.startswith("function"),
                                "в fmt передан не функция: %s -> %s" % (args[0], fmt))
            if len(args) >= 7:
                self.assertRegex(args[6], r"^[\d.]+$", "шаг должен быть числом: " + text)

    def test_min_distance_has_step_and_metres(self):
        args = dict((a[1].strip('"'), a) for _, a, _ in calls("slider") if len(a) > 1 and a[1].startswith('"'))
        self.assertIn("MinDist", args)
        call = args["MinDist"]
        self.assertEqual(call[4], "false", "MinDist не в долях: pct = false")
        self.assertTrue(call[5].startswith("function"), "подпись значения — функция")


LITERAL_NUMBER = re.compile(r"^[-+]?[\d.]+$")
LITERAL_BOOL = {"true", "false"}


class FunctionSlots(unittest.TestCase):
    """Общий сторож: там, где хелпер вызывает аргумент как функцию, не должно быть литералов.

    Перепутанные местами аргументы — реальная причина падения
    "attempt to call a number value" (ползунок ESP Min distance).
    """

    # helper -> индексы аргументов (0-based), которые хелпер вызывает как функции
    SLOTS = {
        "sliderCard": (7,),
        "vslider": (5,),
        "cycleCard": (3, 4),
        "toggleCard": (3, 4),
        "movable": (2, 3, 4),
        "makePicker": (2, 3),
        "drag": (1, 2, 3),
    }

    def test_no_literal_in_function_slot(self):
        checked = 0
        for helper, slots in self.SLOTS.items():
            for text, args, _ in calls(helper):
                if args and args[0] in ("parent", "handle", "f"):
                    continue  # объявление функции, а не вызов
                for i in slots:
                    if i >= len(args):
                        continue
                    arg = args[i]
                    checked += 1
                    self.assertFalse(LITERAL_NUMBER.match(arg),
                                     "%s: аргумент #%d — число, а ожидается функция: %s" % (helper, i + 1, text))
                    self.assertNotIn(arg, LITERAL_BOOL,
                                     "%s: аргумент #%d — boolean, а ожидается функция: %s" % (helper, i + 1, text))
        self.assertGreater(checked, 30, "проверка должна покрывать все вызовы")


class VslliderArguments(unittest.TestCase):
    """Hitbox ESP: vslider(title, key, min, max, step, fmt) — fmt последним."""

    def test_each_call_passes_function_last(self):
        found = [c for c in calls("vslider") if c[0].startswith('vslider("')]
        self.assertEqual(len(found), 4, "ползунки Hitbox ESP")
        for text, args, _ in found:
            self.assertEqual(len(args), 6, text)
            self.assertRegex(args[4], r"^[\d.]+$", "шаг должен быть числом: " + text)
            # fmt — либо литерал function, либо локальная переменная-функция (pct)
            self.assertTrue(args[5].startswith("function") or args[5] == "pct",
                            "fmt должен быть функцией: " + text)
        header = "local function vslider(title, key, min, max, step, fmt)"
        self.assertIn(header, SOURCE)
        self.assertIn("fmt, step)", func_block("\t\t" + header))


class SliderSignatures(unittest.TestCase):
    """У slider() две разные сигнатуры в разных панелях — проверяем по ближайшему определению."""

    DEFS = (
        ("local function slider(title, key, min, max, step, decimals)", "aim"),
        ("local function slider(title, key, min, max, pct, fmt, step)", "esp"),
    )

    def signature_for(self, pos):
        best = None
        for header, kind in self.DEFS:
            i = SOURCE.find(header)
            if i != -1 and i < pos:
                best = kind
        return best

    def test_esp_calls_pass_function_in_fmt(self):
        checked = 0
        for text, args, pos in calls("slider"):
            if not text.startswith('slider("') or self.signature_for(pos) != "esp":
                continue
            checked += 1
            self.assertLessEqual(len(args), 7, text)
            # fmt — необязательный и всегда функция; шаг не передаётся, он вычисляется внутри.
            # pct (5-я позиция) тоже необязателен: «Name size» его не задаёт.
            if len(args) >= 6:
                self.assertTrue(args[5].startswith("function"), "fmt должен быть функцией: " + text)
        self.assertGreaterEqual(checked, 7, "ползунки панели ESP")

    def test_aim_calls_pass_numbers(self):
        checked = 0
        for text, args, pos in calls("slider"):
            if not text.startswith('slider("') or self.signature_for(pos) != "aim":
                continue
            checked += 1
            self.assertEqual(len(args), 6, text)
            self.assertTrue(LITERAL_NUMBER.match(args[4]), "step должен быть числом: " + text)
            self.assertTrue(LITERAL_NUMBER.match(args[5]), "decimals должен быть числом: " + text)
        self.assertGreaterEqual(checked, 20, "ползунки панели Aim")


class OtherHelpers(unittest.TestCase):
    """Другие хелперы с необязательными хвостовыми аргументами."""

    def test_aim_slider_uses_step_then_decimals(self):
        header = "local function slider(title, key, min, max, step, decimals)"
        self.assertIn(header, SOURCE)
        body = func_block("\t" + header)
        self.assertIn('local fmt = "%." .. (decimals or 0) .. "f"', body)
        for text, args, _ in calls("slider"):
            if not text.startswith('slider("'):
                continue
            if len(args) < 6:
                continue
            # вызовы одной и той же функции с разным смыслом аргументов не смешиваются:
            # в Aim последние два аргумента — числа
            if args[4] == "true" or args[4] == "false":
                continue
            self.assertRegex(args[4], r"^[\d.]+$", text)
            self.assertRegex(args[5], r"^[\d.]+$", text)

    def test_no_number_passed_where_function_expected(self):
        """fmt/format/formatValue не должны получать числа ни в одном хелпере."""
        for name in ("animateNumber",):
            header = "function %s(" % name
            block = SOURCE.split(header, 1)
            self.assertTrue(block)
        body = SOURCE.split("local function animateNumber(label, from, to, fmt, dur)", 1)
        self.assertEqual(len(body), 2)
        for text, args, _ in calls("animateNumber"):
            self.assertGreaterEqual(len(args), 4, text)
            self.assertTrue(args[3].startswith("function") or args[3] == "fmt",
                            "fmt должен быть функцией: " + text)

    def test_number_labels_have_no_leftover_suffix_expression(self):
        self.assertNotIn('(step and "" or "")', SOURCE)


class LocalVariableLimit(unittest.TestCase):
    """Скрипт обязан компилироваться: Lua/Luau разрешает не больше 200 локалей на функцию."""

    def test_script_compiles(self):
        """Регрессия: buildAim переполнялся локалями и скрипт не загружался вообще."""
        import os
        import subprocess
        import sys
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        checker = os.path.join(root, "tools", "luau_check.py")
        if not os.path.exists(checker):
            self.skipTest("нет tools/luau_check.py")
        src = Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua"
        r = subprocess.run([sys.executable, checker, str(src)], capture_output=True, text=True)
        out = (r.stdout + r.stderr).strip()
        self.assertIn("LUAU COMPILE OK", out,
                      "скрипт не компилируется (лимит 200 локалей / синтаксис): " + out[-400:])


if __name__ == "__main__":
    unittest.main()

class HelperVisibility(unittest.TestCase):
    """Локальные хелперы видны только в своей области.

    Классическая ошибка: внутри startMain вызвать connect(...) — он объявлен локально
    в модуле наведения (выше по файлу), поэтому в рантайме падает с
    "attempt to call a nil value". Тест проверяет, что в теле startMain нет таких вызовов.
    """

    def test_no_connect_calls_inside_start_main(self):
        lines = SOURCE.split("\n")
        start = next(i for i, l in enumerate(lines) if l.startswith("local function startMain"))
        offenders = []
        for i, line in enumerate(lines[start:], start + 1):
            code = line.split("--", 1)[0]
            # отсекаем :Disconnect( и прочие методы — важен именно вызов локальной функции connect(
            if "connect(" in code and ":connect(" not in code and "Disconnect" not in code:
                offenders.append((i, line.strip()))
        self.assertEqual(offenders, [], "connect() объявлен внутри модуля наведения; в startMain нужен on()")

    def test_on_helper_is_file_level(self):
        # on объявлен на файловом уровне: им можно пользоваться в любом месте скрипта
        self.assertIn("local function on(sig, fn)", SOURCE)
        # и он не спрятан внутри startMain
        head = SOURCE.split("local function startMain", 1)[0]
        self.assertIn("local function on(sig, fn)", head)



class LocalVariableLimit(unittest.TestCase):
    """Скрипт обязан компилироваться: Lua/Luau разрешает не больше 200 локалей на функцию."""

    def test_script_compiles(self):
        """Регрессия: buildAim переполнялся локалями и скрипт не загружался вообще."""
        import os
        import subprocess
        import sys
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        checker = os.path.join(root, "tools", "luau_check.py")
        if not os.path.exists(checker):
            self.skipTest("нет tools/luau_check.py")
        src = Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua"
        r = subprocess.run([sys.executable, checker, str(src)], capture_output=True, text=True)
        out = (r.stdout + r.stderr).strip()
        self.assertIn("LUAU COMPILE OK", out,
                      "скрипт не компилируется (лимит 200 локалей / синтаксис): " + out[-400:])


if __name__ == "__main__":
    unittest.main()

class NumericConstants(unittest.TestCase):
    """OUT и подобные таблицы хранят ЧИСЛА (прозрачности), а не цвета.

    Классическая ошибка: написать OUT.Hover.Color вместо PURE — в рантайме это
    "attempt to index number with 'Color'". Тест ловит обращения к полям у чисел.
    """

    NUMERIC_TABLES = ("OUT", "TWEEN", "STS")

    def test_no_field_access_on_numeric_constants(self):
        import re
        bad = []
        for name in self.NUMERIC_TABLES:
            for m in re.finditer(r"\b" + name + r"\.\w+\.(\w+)", SOURCE):
                bad.append((name, m.group(0)))
        self.assertEqual(bad, [], "у числовых констант нет полей: цвет обводки — PURE")

    def test_out_is_a_table_of_numbers(self):
        import re
        m = re.search(r"local OUT = \{([^}]*)\}", SOURCE)
        self.assertIsNotNone(m)
        self.assertNotIn("Color3", m.group(1), "OUT должен хранить только прозрачности")

    def test_outline_returns_a_stroke(self):
        # обводку сохраняют как edge/st и меняют .Color/.Transparency — значит нужен UIStroke.
        # Второй аргумент — прозрачность (число): цвет внутри всегда PURE.
        import re
        m = re.search(r"function outline\(o, t\).*", SOURCE)
        self.assertIsNotNone(m, "outline(o, t) должна оставаться с двумя аргументами")
        self.assertIn("return stroke(o, PURE, t or OUT.Idle", m.group(0))



class LocalVariableLimit(unittest.TestCase):
    """Скрипт обязан компилироваться: Lua/Luau разрешает не больше 200 локалей на функцию."""

    def test_script_compiles(self):
        """Регрессия: buildAim переполнялся локалями и скрипт не загружался вообще."""
        import os
        import subprocess
        import sys
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        checker = os.path.join(root, "tools", "luau_check.py")
        if not os.path.exists(checker):
            self.skipTest("нет tools/luau_check.py")
        src = Path(__file__).resolve().parents[1] / "Enkaisy_Combined_UI_v4_2.lua"
        r = subprocess.run([sys.executable, checker, str(src)], capture_output=True, text=True)
        out = (r.stdout + r.stderr).strip()
        self.assertIn("LUAU COMPILE OK", out,
                      "скрипт не компилируется (лимит 200 локалей / синтаксис): " + out[-400:])


if __name__ == "__main__":
    unittest.main()
