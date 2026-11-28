#!/usr/bin/env python3
"""Ловит `function TABLE.method(...)`, где сама таблица TABLE нигде не создана.

Это реальный баг 4.6.1: при удалении движка Chams вырезалась строка `CH = {}`,
а `function CH.apply(...)` осталась — скрипт падал ПРИ ЗАГРУЗКЕ:
"attempt to index global 'CH' (a nil value)". Luau такое не ловит: имя читается
в рантайме, компилятор проверяет только синтаксис.

    python3 tools/declared_before_use.py Enkaisy_Combined_UI_v4_2.lua
"""
import re
import sys


def main(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    problems = []

    # все таблицы, которые где-то создаются: `X = {`, `X = {} `, `local X = {`
    declared = {}
    for i, line in enumerate(lines, 1):
        if line.lstrip().startswith("--"):
            continue
        m = re.match(r"^\s*(?:local\s+)?([A-Za-z_]\w*)\s*=\s*(\{|function|\w)", line)
        if m and m.group(1) not in declared:
            declared[m.group(1)] = i

    for i, line in enumerate(lines, 1):
        if line.lstrip().startswith("--"):
            continue
        m = re.match(r"^\s*function\s+([A-Za-z_]\w*)\.(\w+)\s*\(", line)
        if not m:
            continue
        table = m.group(1)
        if table == "_G":
            continue
        if table not in declared:
            problems.append((i, "%s.%s — таблица %s нигде не создаётся" % (table, m.group(2), table)))
        elif declared[table] > i:
            problems.append((i, "%s.%s — таблица %s создаётся позже (строка %d)"
                             % (table, m.group(2), table, declared[table])))

    for line_no, text in problems:
        print("строка %d: %s" % (line_no, text))
    print("DECLARED BEFORE USE: OK" if not problems
          else "DECLARED BEFORE USE: %d проблем" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "Enkaisy_Combined_UI_v4_2.lua"))
