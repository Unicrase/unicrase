#!/usr/bin/env python3
"""Наблюдатель за изменениями Roblox и Luau — замена «обучению во сне».

Пока меня нет, мир меняется: Roblox добавляет и убирает классы/свойства,
Luau выпускает новые версии. Этот скрипт проверяет, не сломает ли это НАШ
скрипт, и пишет отчёт: что изменилось и где в файле это используется.

    python3 tools/watch_upstream.py            # отчёт в docs/UPSTREAM.md
    python3 tools/watch_upstream.py --quiet    # только код возврата (для CI)

Код возврата 1 — есть изменение, влияющее на скрипт (нужно править код).
Код возврата 0 — всё совместимо.
"""
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "Enkaisy_Combined_UI_v4_2.lua"
CACHE = ROOT / ".cache" / "Mini-API-Dump.json"
REPORT = ROOT / "docs" / "UPSTREAM.md"
LAST = ROOT / ".cache" / "upstream-last.json"


def gh_json(args):
    result = subprocess.run(["gh", "api"] + args, capture_output=True, text=True)
    if result.returncode != 0:
        return None
    return json.loads(result.stdout)


def luau_version():
    data = gh_json(["repos/luau-lang/luau/releases", "--jq", "[.[0].tag_name, .[0].published_at]"])
    return tuple(data) if data else (None, None)


def fetch_dump():
    result = subprocess.run(
        ["gh", "api", "repos/MaximumADHD/Roblox-Client-Tracker/contents/Mini-API-Dump.json?ref=roblox",
         "-H", "Accept: application/vnd.github.raw"],
        capture_output=True)
    if result.returncode != 0 or len(result.stdout) < 100000:
        return None
    return result.stdout


def summary(dump_bytes):
    """Классы и их свойства С УЧЁТОМ НАСЛЕДОВАНИЯ.

    Только собственные свойства класса брать нельзя: `ZIndex` живёт в GuiObject,
    `SortOrder` — в UIGridStyleLayout. Иначе проверка выдаёт ложные «свойство
    исчезло» на каждом запуске, и ей перестают верить.
    """
    dump = json.loads(dump_bytes)
    own, supers = {}, {}
    for c in dump["Classes"]:
        own[c["Name"]] = {m["Name"] for m in c.get("Members", []) if m["MemberType"] == "Property"}
        supers[c["Name"]] = c.get("Superclass")

    def all_props(name):
        seen, cur = set(), name
        while cur and cur in own:
            seen |= own[cur]
            cur = supers.get(cur)
        return seen

    out = {name: sorted(all_props(name)) for name in own}
    enums = {e["Name"]: sorted(i["Name"] for i in e["Items"]) for e in dump["Enums"]}
    return {"classes": out, "enums": enums}


def used_in_script():
    src = SCRIPT.read_text(encoding="utf-8")
    code = "\n".join(l for l in src.split("\n") if not l.lstrip().startswith("--"))
    classes = set(re.findall(r'\bnew\("(\w+)"', code)) | set(re.findall(r':IsA\("(\w+)"\)', code))
    enums = {}
    for m in re.finditer(r"Enum\.(\w+)\.(\w+)", code):
        enums.setdefault(m.group(1), set()).add(m.group(2))
    props = {}
    for cls, body in re.findall(r'\bnew\("(\w+)",\s*\{((?:[^{}]|\{[^{}]*\})*)\}', code):
        props.setdefault(cls, set()).update(re.findall(r"(?:^|[,{\s])([A-Z]\w*)\s*=(?!=)", body))
    return classes, enums, props


def main():
    quiet = "--quiet" in sys.argv
    lines, breaking = [], []

    old_luau, old_api = None, None
    if LAST.exists():
        try:
            prev = json.loads(LAST.read_text(encoding="utf-8"))
            old_luau, old_api = prev.get("luau"), prev.get("api")
        except Exception:
            pass

    tag, published = luau_version()
    dump_bytes = fetch_dump()

    if dump_bytes:
        CACHE.parent.mkdir(exist_ok=True)
        CACHE.write_bytes(dump_bytes)
        current = summary(dump_bytes)
    elif CACHE.exists():
        current = summary(CACHE.read_bytes())
    else:
        print("нет доступа к дампу API и нет кэша — проверка невозможна")
        return 2

    classes_used, enums_used, props_used = used_in_script()

    # 1) не пропало ли что-то, что скрипт использует
    for cls in sorted(classes_used):
        if cls not in current["classes"]:
            breaking.append("класс **%s** исчез из Roblox — скрипт его создаёт" % cls)
        else:
            for prop in sorted(props_used.get(cls, ())):
                if prop not in current["classes"][cls] and prop not in ("Name", "Parent"):
                    breaking.append("у **%s** больше нет свойства `%s`" % (cls, prop))
    for en, items in sorted(enums_used.items()):
        if en not in current["enums"]:
            breaking.append("перечисление **Enum.%s** исчезло" % en)
        else:
            for item in sorted(items):
                if item not in current["enums"][en]:
                    breaking.append("**Enum.%s.%s** больше не существует" % (en, item))

    # 2) что изменилось с прошлого запуска
    changes = []
    if old_api:
        old_classes = {k: set(v) for k, v in old_api.get("classes", {}).items()}
        new_classes = {k: set(v) for k, v in current["classes"].items()}
        added = sorted(set(new_classes) - set(old_classes))
        removed = sorted(set(old_classes) - set(new_classes))
        if added:
            changes.append("новые классы: " + ", ".join(added[:12]) + ("…" if len(added) > 12 else ""))
        if removed:
            changes.append("удалённые классы: " + ", ".join(removed[:12]))
        for cls in sorted(set(old_classes) & set(new_classes)):
            added_props = new_classes[cls] - old_classes[cls]
            if added_props and cls in classes_used:
                changes.append("у %s появились свойства: %s" % (cls, ", ".join(sorted(added_props)[:8])))
    if tag and old_luau and tag != old_luau:
        changes.append("Luau обновился: %s → %s" % (old_luau, tag))

    LAST.parent.mkdir(exist_ok=True)
    LAST.write_text(json.dumps({"luau": tag, "checked_at": datetime.now(timezone.utc).isoformat(),
                                "api": current}, ensure_ascii=False), encoding="utf-8")

    if not quiet:
        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        out = ["# Наблюдение за изменениями Roblox", "",
               "Обновлено: %s · Luau %s · классов в API: %d" % (stamp, tag or "?", len(current["classes"])),
               "", "Файл генерируется `tools/watch_upstream.py` — править руками не нужно.", ""]
        if breaking:
            out += ["## Требует правки в скрипте", ""] + ["- " + b for b in breaking] + [""]
        else:
            out += ["## Совместимость", "", "Всё, что использует скрипт, существует в текущем API Roblox.", ""]
        if changes:
            out += ["## Что изменилось с прошлой проверки", ""] + ["- " + c for c in changes] + [""]
        REPORT.write_text("\n".join(out), encoding="utf-8")
        for line in breaking:
            print("[!] " + line)
        for line in changes:
            print("[~] " + line)
        print("UPSTREAM: %s" % ("требует правки" if breaking else "совместимо"),
              "| Luau", tag, "| классов:", len(current["classes"]))
    return 1 if breaking else 0


if __name__ == "__main__":
    sys.exit(main())
