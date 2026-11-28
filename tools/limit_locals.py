#!/usr/bin/env python3
"""Снимает предел Lua/Luau в 200 локальных переменных: переносит локали в таблицу.

Зачем: функция с ~190+ локалями не компилируется («too many local variables
(limit is 200)»), и скрипт не загружается вообще. Объявление `local x = v`
превращается в `ST.x = v`, обращения к `x` — в `ST.x`. Строки и комментарии
не трогаются, иначе поедут подписи интерфейса.

Безопасность: имя переносится только если оно объявлено РОВНО ОДИН РАЗ во всей
области (нет одноимённых локалей внутри вложенных функций и параметров) и стоит
в объявлении одно.

    python3 tools/limit_locals.py FILE --target buildAim --report
    python3 tools/limit_locals.py FILE --target buildAim --auto 60
    python3 tools/limit_locals.py FILE --top --auto 8
    python3 tools/limit_locals.py FILE --target buildAim --names fov,aimMark
"""
import argparse
import os
import re
import sys


TESTS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests"))


def mask(line):
    """Строка без содержимого литералов и комментариев (длина сохраняется)."""
    out = list(line)
    i, n, quote = 0, len(line), None
    while i < n:
        c = line[i]
        if quote:
            if c == "\\":
                out[i] = "_"
                if i + 1 < n:
                    out[i + 1] = "_"
                i += 2
                continue
            if c == quote:
                quote = None
            else:
                out[i] = "_"
            i += 1
            continue
        if c in "\"'":
            quote = c
            i += 1
            continue
        if line.startswith("[[", i):
            j = line.find("]]", i)
            j = n if j < 0 else j
            for k in range(i, min(j + 2, n)):
                out[k] = "_"
            i = min(j + 2, n)
            continue
        if line.startswith("--", i):
            for k in range(i, n):
                out[k] = " "
            break
        i += 1
    return "".join(out)


def region(lines, target):
    if not target:
        return 0, len(lines), ""
    start = next((i for i, l in enumerate(lines) if l.startswith("local function %s(" % target)), None)
    if start is None:
        sys.exit("функция %s не найдена" % target)
    end = next(i for i in range(start, len(lines)) if lines[i].rstrip() == "end")
    indent = re.match(r"^(\t*)", lines[start + 1]).group(1)
    return start, end + 1, indent


def single_decls(lines, lo, hi, indent):
    """Одиночные объявления на верхнем уровне области: [(строка, имя)]."""
    out = []
    pat = re.compile(r"^" + indent + r"local\s+([A-Za-z_]\w*)\s*=(?!=)\s*\S")
    for i in range(lo, hi):
        m = pat.match(mask(lines[i]))
        if m:
            out.append((i, m.group(1)))
    return out


def shadows(lines, lo, hi, name):
    """Сколько РАЗ имя объявляется в области (local x / local function x / параметр x)."""
    pat_local = re.compile(r"\blocal\s+(?:function\s+)?" + re.escape(name) + r"\b")
    pat_par = re.compile(r"function\s*[\w.:]*\s*\(([^)]*)\)")
    pat_for = re.compile(r"\bfor\s+([\w, ]+?)\s*(?:=|in)\b")
    hits = 0
    for i in range(lo, hi):
        text = mask(lines[i])
        hits += len(pat_local.findall(text))
        for m in pat_par.finditer(text):
            if re.search(r"(?<![\w.:])" + re.escape(name) + r"\b", m.group(1)):
                hits += 1
        for m in pat_for.finditer(text):
            if name in [t.strip() for t in m.group(1).split(",")]:
                hits += 1
    return hits


def uses(lines, lo, hi, name):
    pat = re.compile(r"(?<![\w.:])" + re.escape(name) + r"\b")
    return sum(len(pat.findall(mask(lines[i]))) for i in range(lo, hi))


def apply(lines, lo, hi, name, table):
    """`local x = v` -> `ST.x = v`; обращения x -> ST.x.

    Ключи таблиц (`{x = 1}`) и поля (`t.x`) не трогаем: внутри конструктора таблицы
    имя перед `=` — это имя поля, а не переменная.
    """
    decl = re.compile(r"^(\t*)local(\s+)" + re.escape(name) + r"(\s*=(?!=))")
    pat = re.compile(r"(?<!\w|[\.:])\b" + re.escape(name) + r"\b")
    done = False

    for i in range(lo, hi):
        m = decl.match(mask(lines[i]))
        if m and not done:
            line = lines[i]
            cut = [m.start(1) + len(m.group(1)), m.end(2)]  # убрать слово "local" и пробелы
            lines[i] = line[: cut[0]] + line[cut[1]:]
            done = True

    for i in range(lo, hi):
        masked = mask(lines[i])
        line = lines[i]
        spans = []
        for m in pat.finditer(masked):
            s, e = m.span()
            after = masked[e:e + 8]
            before = masked[:s].rstrip()
            # {name = ...} и {a, name = ...} — это имена полей таблицы, их не трогаем;
            # name = ... в начале инструкции — обычное присваивание, его переименовываем
            is_key = bool(re.match(r"\s*=(?!=)", after)) and before.endswith(("{", ","))
            if is_key:
                continue
            spans.append((s, e))
        if not spans:
            continue
        for s, e in reversed(spans):
            line = line[:s] + table + "." + name + line[e:]
        lines[i] = line
    return done


def test_locked_names():
    """Имена, которые тесты ищут в исходнике: их нельзя переименовывать."""
    locked = set()
    for name in os.listdir(TESTS):
        if not name.endswith(".py"):
            continue
        text = open(os.path.join(TESTS, name), encoding="utf-8").read()
        locked.update(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", text))
    return locked


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--target", default=None)
    ap.add_argument("--top", action="store_true")
    ap.add_argument("--names", default="")
    ap.add_argument("--auto", type=int, default=0)
    ap.add_argument("--table", default="ST")
    ap.add_argument("--max-uses", type=int, default=4, help="брать только редкие имена")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--ignore-tests", action="store_true", help="не трогать имена из тестов")
    a = ap.parse_args()

    lines = open(a.path, encoding="utf-8").read().split("\n")
    lo, hi, indent = region(lines, a.target)
    decls = single_decls(lines, lo, hi, indent)
    if a.top:
        decls = [(i, n) for i, n in decls if lines[i].startswith("local")]

    locked = test_locked_names() if a.ignore_tests else set()
    rows = []
    for i, n in decls:
        if n in locked:
            continue
        if shadows(lines, lo, hi, n) != 1:
            continue  # имя встречается в других объявлениях/параметрах — трогать нельзя
        rows.append((uses(lines, lo, hi, n), n))
    rows.sort()

    if a.report or (not a.names and not a.auto):
        print("безопасных одиночных локалей: %d" % len(rows))
        for c, n in rows:
            print("  %2d  %s" % (c, n))
        return

    if a.names:
        picked = [n.strip() for n in a.names.split(",") if n.strip()]
    else:
        picked = [n for c, n in rows if c <= a.max_uses][: a.auto]
    safe = {n for _, n in rows}
    bad = [n for n in picked if n not in safe]
    if bad:
        sys.exit("нельзя переносить (объявлены не один раз): %r" % bad)

    if picked:
        has_table = any(re.match(r"^" + indent + r"local\s+" + a.table + r"\s*=\s*\{\s*\}\s*$", mask(l))
                        for l in lines[lo:hi])
        if not has_table:
            at = lo + 1
            if not a.target:  # верхний уровень: после шапки-комментария, перед первым кодом
                at = next(i for i in range(len(lines)) if lines[i].strip() and not lines[i].lstrip().startswith("--"))
            lines.insert(at, indent + "local %s = {} -- состояние: редкие локали вынесены в таблицу (лимит Lua 200)" % a.table)

    for n in picked:
        if not apply(lines, lo, hi, n, a.table):
            sys.exit("объявление %s не найдено" % n)
    open(a.path, "w", encoding="utf-8").write("\n".join(lines))
    print("перенесено: %d" % len(picked))


if __name__ == "__main__":
    main()
