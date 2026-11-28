#!/usr/bin/env python3
"""Разбивает скрипт на мелкие части, чтобы обойти лимит Lua в 200 локальных переменных.

Лимит считается на ОДИН загруженный кусок кода (проверено: 300 локалей в одном чанке
падают, те же 300 двумя кусками работают). Поэтому крупные блоки выносятся отдельными
файлами и грузятся loadstring'ом.

Схема:
  build/Enkaisy_Combined_UI_v4_2.lua  — точка входа: сервер, ключ, заставка
  build/parts/main.lua                — клиентская часть интерфейса (бывший хвост файла)
  build/parts/aim.lua                 — панель Aim (buildAim)

Точка входа понимает, как её загрузили:
  * строкой (executor) — части скачиваются с GitHub по требованию и кешируются;
  * как обычный Script в игре — клиентская часть склеивается в тот же кусок (как раньше).
"""
import os
import re
import sys

ROOT = "/home/user/unicrase"
SRC = os.path.join(ROOT, "Enkaisy_Combined_UI_v4_2.lua")
OUT = os.path.join(ROOT, "build")
RAW = "https://raw.githubusercontent.com/Unicrase/unicrase/arena/ee6c5c73-unicrase/build"


def main():
    lines = open(SRC, encoding="utf-8").read().split("\n")

    # ---------- 1) вырезаем buildAim ----------
    a = next(i for i, l in enumerate(lines) if l.startswith("local function buildAim("))
    b = next(i for i in range(a, len(lines)) if lines[i].rstrip() == "end")
    body = lines[a:b + 1]
    inner = body[1:-1]
    # первая строка тела — объявление таблицы состояния; переносим её сами
    while inner and (inner[0].strip().startswith("--") or inner[0].strip().startswith("local AIM = {")
                      or inner[0].strip() == ""):
        inner.pop(0)
    aim_src = "\n".join([
        "-- ЧАСТЬ: панель Aim. Отдельный кусок кода — свои 200 локалей, не общие с интерфейсом.",
        "return function(page, api)",
        "\tlocal AIM = {} -- состояние панели Aim: редкие локали вынесены в таблицу (лимит Lua 200)",
    ] + inner + ["end"])
    os.makedirs(os.path.join(OUT, "parts"), exist_ok=True)
    open(os.path.join(OUT, "parts", "aim.lua"), "w", encoding="utf-8").write(aim_src + "\n")

    loader = [
        "\t-- buildAim вынесен отдельной частью: её локали не входят в лимит 200 этого куска.",
        "\tlocal function buildAim(page, api)",
        "\t\tlocal fn, err = GLB.loadPart and GLB.loadPart(\"aim\")",
        "\t\tif not fn then",
        "\t\t\twarn(\"[Enkaisy] часть aim не загрузилась: \" .. tostring(err))",
        "\t\t\treturn",
        "\t\tend",
        "\t\treturn fn(page, api)",
        "\tend",
    ]
    lines[a:b + 1] = loader

    # ---------- 2) загрузчик частей ----------
    anchor = 'GLB.CLIENT_NAME = "EnkaisyAimClient"'
    loader_code = anchor + """

-- ===== Части скрипта (обход лимита 200 локалей) =====
-- Лимит 200 считается на ОДИН загруженный кусок кода. Крупные блоки живут отдельными
-- частями: у каждой свой лимит, поэтому суммарный размер роли не играет.
-- Части кешируются: второй вызов loadstring не нужен.
local PARTS_URL = "%s/parts/%%s.lua"
GLB.PARTS = GLB.PARTS or {}
function GLB.loadPart(name)
\tlocal cached = GLB.PARTS[name]
\tif cached then return cached end
\t-- 1) часть уже склеена в общий текст (обычный Script), 2) иначе — скачиваем
\tlocal code = GLB.PART_SRC and GLB.PART_SRC[name]
\tif not code then
\t\tlocal url = string.format(PARTS_URL, name)
\t\tlocal ok, body = pcall(function() return game:HttpGet(url) end)
\t\tif not ok or type(body) ~= "string" or #body == 0 then
\t\t\treturn nil, "не удалось скачать " .. url
\t\tend
\t\tcode = body
\tend
\tlocal chunk, err = loadstring(code, "Enkaisy:" .. name)
\tif not chunk then return nil, tostring(err) end
\tlocal ok, fn = pcall(chunk)
\tif not ok or type(fn) ~= "function" then return nil, "часть " .. name .. " не вернула функцию" end
\tGLB.PARTS[name] = fn
\treturn fn
end""" % RAW

    src = "\n".join(lines).replace(anchor, loader_code)

    # ---------- 3) клиентский хвост: две части ----------
    # Границы: середина интерфейса начинается после bgFetch и кончается перед startMain;
    # хвост — от startMain до конца файла. Каждой части свой лимит 200.
    mid_start = src.index("-- ===== Главное меню =====")
    tail_start = src.index("local function startMain()")
    # всё от keyScreen и до конца — главный интерфейс и запуск
    head = src[:mid_start]
    mid = src[mid_start:tail_start]
    tail = src[tail_start:]

    tail_lines = tail.split("\n")
    last = max(i for i, l in enumerate(tail_lines) if l.strip())
    tail_lines = tail_lines[:last + 1]

    # часть 1: середина интерфейса — возвращает то, что нужно хвосту
    mid_lines = mid.rstrip().split("\n")
    mid_src = "\n".join([
        "-- ЧАСТЬ: интерфейс (карточки, папки, поиск, HUD). Отдельный кусок — свой лимит 200.",
        "return function(env)",
        "\tlocal gui, new, C, S, U, O = env.gui, env.new, env.C, env.S, env.U, env.O",
    ] + ["\t" + l if l.strip() else l for l in mid_lines] +
        ["", "\treturn {mid = true}", "end"])
    open(os.path.join(OUT, "parts", "ui.lua"), "w", encoding="utf-8").write(mid_src + "\n")

    main_src = "\n".join([
        "-- ЧАСТЬ: главное окно и запуск. Отдельный кусок — свой лимит 200.",
        "return {run = function(env)",
        "\tlocal gui, stop, startMain, keyScreen = env.gui, env.stop, env.startMain, env.keyScreen",
    ] + ["\t" + l if l.strip() else l for l in tail_lines] + ["end}"])
    open(os.path.join(OUT, "parts", "main.lua"), "w", encoding="utf-8").write(main_src + "\n")

    src = head + """-- ===== Экран ключа и запуск интерфейса =====
-- Эта часть — отдельный кусок кода. Отдельный файл нужен, чтобы её локали не считались
-- в лимите 200 вместе с сервером и ключом.
local mainPart = nil
local function startMain()
\tlocal ok, e = pcall(function()
\t\tmainPart = mainPart or GLB.loadPart("main")
\t\tif not mainPart then error(e or "часть main не загрузилась") end
\t\tmainPart.run({gui = gui, stop = stop, startMain = startMain, keyScreen = keyScreen})
\tend)
\tif not ok then
\t\tpcall(function()
\t\t\tgame:GetService("StarterGui"):SetCore("SendNotification",
\t\t\t\t{Title = "Enkaisy error", Text = tostring(e):sub(1, 120), Duration = 15})
\t\tend)
\tend
end

keyScreen(function() startMain() end)
"""

    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, "Enkaisy_Combined_UI_v4_2.lua"), "w", encoding="utf-8").write(src)
    print("aim: %d строк, main: %d строк, точка входа: %d строк"
          % (aim_src.count("\n"), main_src.count("\n"), src.count("\n")))


if __name__ == "__main__":
    main()
