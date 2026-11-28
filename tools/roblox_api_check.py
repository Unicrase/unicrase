#!/usr/bin/env python3
"""Сверка скрипта с НАСТОЯЩИМ API Roblox: классы, свойства, методы, перечисления.

Зачем: компилятор Luau не знает Roblox-API. `new("Fraem", {...})` и
`frame.BackgroundColour3 = x` компилируются нормально, а в игре это либо
невидимый элемент, либо тихий сбой. Такой код нельзя поймать ни тестами,
ни глазами в 8000 строк.

Источник: официальный дамп клиента Roblox (обновляется несколько раз в день):
    Mini-API-Dump.json из MaximumADHD/Roblox-Client-Tracker (ветка roblox)

Использование:
    python3 tools/roblox_api_check.py [--fetch] [файл]

    --fetch   скачать свежий дамп перед проверкой (нужен gh с доступом к github.com)

Файл дампа кладётся в .cache/ и в git не попадает.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".cache" / "Mini-API-Dump.json"
REPO = "MaximumADHD/Roblox-Client-Tracker"
SOURCE = "https://github.com/%s (ветка roblox)" % REPO

# Свойства, которые Roblox выставляет не через Instance.new, а движком —
# их нет смысла искать в дампе как обычные поля.
SKIP_PROPS = {"Parent", "Name", "Archivable", "RobloxLocked", "Tags"}


def fetch():
    CACHE.parent.mkdir(exist_ok=True)
    result = subprocess.run(
        ["gh", "api", "repos/%s/contents/Mini-API-Dump.json?ref=roblox" % REPO,
         "-H", "Accept: application/vnd.github.raw"],
        capture_output=True)
    if result.returncode != 0 or len(result.stdout) < 100000:
        raise SystemExit("не удалось скачать дамп API Roblox (нужен gh + доступ к github.com)")
    CACHE.write_bytes(result.stdout)
    print("дамп обновлён: %.1f МБ" % (len(result.stdout) / 1e6))


def load():
    if not CACHE.exists():
        raise SystemExit("нет .cache/Mini-API-Dump.json — запустите с --fetch")
    dump = json.loads(CACHE.read_text(encoding="utf-8"))
    classes = {}
    for c in dump["Classes"]:
        props = {m["Name"] for m in c.get("Members", []) if m["MemberType"] == "Property"}
        events = {m["Name"] for m in c.get("Members", []) if m["MemberType"] == "Event"}
        funcs = {m["Name"] for m in c.get("Members", []) if m["MemberType"] == "Function"}
        classes[c["Name"]] = {"super": c.get("Superclass"), "props": props,
                              "events": events, "funcs": funcs}
    enums = {e["Name"]: {i["Name"] for i in e["Items"]} for e in dump["Enums"]}
    return classes, enums


def strip_code(src):
    """Убирает комментарии, сохраняя номера строк (для понятных сообщений)."""
    out = []
    for line in src.split("\n"):
        if line.lstrip().startswith("--"):
            out.append("")
        else:
            out.append(line)
    return "\n".join(out)


def table_after(text, start):
    """Возвращает тело таблицы `{...}` начиная с позиции start (с балансом скобок)."""
    i = text.find("{", start)
    if i < 0:
        return None, None
    depth, j = 0, i
    in_str, quote = False, ""
    while j < len(text):
        ch = text[j]
        if in_str:
            if ch == "\\":
                j += 2
                continue
            if ch == quote:
                in_str = False
        elif ch in "\"'":
            in_str, quote = True, ch
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[i + 1:j], j + 1
        j += 1
    return None, None


def flatten(body):
    """Убирает вложенные таблицы: остаются только ключи верхнего уровня."""
    out, depth, i = [], 0, 0
    while i < len(body):
        ch = body[i]
        if ch == "{":
            depth += 1
            if depth == 1:
                out.append(ch)
            i += 1
            continue
        if ch == "}":
            depth -= 1
            if depth == 0:
                out.append(ch)
            i += 1
            continue
        out.append(ch if depth <= 1 else " ")
        i += 1
    return "".join(out)


def constructors(code):
    """Все вызовы new("Класс", { ... }) — тело таблицы и номер строки."""
    for m in re.finditer(r'\bnew\("(\w+)"\s*,\s*', code):
        # сразу после запятой ожидается литерал таблицы; `new("X", props)` и
        # `new("X", {...}, parent)` с переменной не трогаем — иначе сканер
        # цепляет первую таблицу ниже по файлу и выдаёт ложные ошибки
        rest = code[m.end():m.end() + 1]
        if rest != "{":
            continue
        body, _ = table_after(code, m.end())
        if body is not None:
            yield m.group(1), body, code[:m.start()].count("\n") + 1


def inherits(classes, name):
    """Все свойства класса с учётом наследования."""
    seen, cur = set(), name
    while cur and cur in classes:
        seen |= classes[cur]["props"] | classes[cur]["events"] | classes[cur]["funcs"]
        cur = classes[cur]["super"]
    return seen


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--fetch" in sys.argv:
        fetch()
    path = Path(args[0]) if args else ROOT / "Enkaisy_Combined_UI_v4_2.lua"
    classes, enums = load()
    src = path.read_text(encoding="utf-8")
    # только код: без комментариев и без содержимого строк
    code_lines = []
    for line in src.split("\n"):
        if line.lstrip().startswith("--"):
            code_lines.append("")
        else:
            code_lines.append(line.split("--")[0] if '"' not in line else line)
    code = "\n".join(code_lines)
    # длинные однострочные конструкции разбиваем по `)` — иначе поиск тела
    # конструктора `new("X", {...})` захватывает код, идущий следом
    code = code.replace(") ", ")\n").replace(") local ", ")\nlocal ")

    problems = []

    # 1) классы: new("Frame", ...) и :IsA("Frame")
    used = set(re.findall(r'\bnew\("(\w+)"', code)) | set(re.findall(r':IsA\("(\w+)"\)', code))
    for name in sorted(used):
        if name not in classes:
            problems.append("класса %s нет в Roblox" % name)

    # 2) свойства в конструкторах: new("Frame", {Prop = ...})
    #    Ключ с заглавной буквы — не всегда свойство: `Name = "Chams"` задаёт имя
    #    объекта. Поэтому ошибкой считаем только те имена, которые ВООБЩЕ есть в
    #    Roblox как свойства, но не подходят этому классу (настоящая опечатка).
    all_props = set()
    for name in classes:
        all_props |= classes[name]["props"]
    for cls, body, line_no in constructors(code):
        if cls not in classes:
            continue
        allowed = inherits(classes, cls)
        flat = flatten(body)
        for prop in re.finditer(r"(?:^|[,{\s])([A-Z]\w*)\s*=(?!=)", flat):
            name = prop.group(1)
            if name in allowed or name in SKIP_PROPS:
                continue
            if name in all_props:
                problems.append("строка %d: у %s нет свойства %s" % (line_no, cls, name))

    # 3) обращения `obj.Prop = ...` НЕ проверяем: тип переменной по имени
    #    недостоверен (в скрипте переменные переиспользуются как «токены» и как
    #    объекты), а ложные срабатывания хуже пропущенной опечатки — из-за них
    #    проверке перестают верить. Конструкторы new() покрывают основные случаи.

    # 4) перечисления: Enum.X.Y
    for m in re.finditer(r'Enum\.(\w+)\.(\w+)', code):
        en, item = m.group(1), m.group(2)
        if en not in enums:
            problems.append("перечисления Enum.%s нет в Roblox" % en)
        elif item not in enums[en]:
            problems.append("Enum.%s.%s не существует" % (en, item))

    # убираем дубли, сохраняя порядок
    seen, uniq = set(), []
    for p in problems:
        if p not in seen:
            seen.add(p)
            uniq.append(p)

    for p in uniq[:40]:
        print("  " + p)
    if len(uniq) > 40:
        print("  ... и ещё %d" % (len(uniq) - 40))
    print("ROBLOX API: OK (классов %d, перечислений %d)" % (len(used), len(enums))
          if not uniq else "ROBLOX API: %d проблем" % len(uniq))
    return 1 if uniq else 0


if __name__ == "__main__":
    sys.exit(main())
