#!/usr/bin/env bash
# Единая проверка проекта: ровно то, что должно быть зелёным перед каждым коммитом.
# Шаг 7 — настоящий запуск в эмуляции Roblox: ловит падения, которых не видит статический анализ.
# Используется и человеком, и CI (.github/workflows/checks.yml), и pre-commit хуком.
set -uo pipefail
cd "$(dirname "$0")/.."

SCRIPT="Enkaisy_Combined_UI_v4_2.lua"
fail=0

step() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

step "1/7 компиляция Luau (настоящий компилятор Roblox)"
if python3 tools/luau_check.py "$SCRIPT" | grep -q "LUAU COMPILE OK"; then
	echo "OK"
else
	echo "ПРОВАЛ: скрипт не компилируется — он не запустится в игре"
	fail=1
fi

step "2/7 таблицы объявлены до использования (падение при загрузке)"
python3 tools/declared_before_use.py "$SCRIPT" || fail=1

step "3/7 сверка с API Roblox (классы, свойства, перечисления)"
if [ -f .cache/Mini-API-Dump.json ]; then
	python3 tools/roblox_api_check.py "$SCRIPT" || fail=1
else
	echo "пропущено: нет .cache/Mini-API-Dump.json (обновить: python3 tools/roblox_api_check.py --fetch)"
fi

step "4/7 лимит локалей (Lua: не больше 200 на функцию)"
python3 tools/limit_locals.py "$SCRIPT" > /tmp/locals.txt 2>&1 || true
if grep -qi "превыш\|too many" /tmp/locals.txt; then
	echo "ПРОВАЛ: превышен лимит локальных переменных"
	grep -i "превыш\|too many" /tmp/locals.txt | head -n 3
	fail=1
else
	echo "OK"
fi

step "5/7 тесты"
if python3 -m unittest discover -s tests -p "test_*.py" 2>&1 | tail -n 3 | grep -qE "^OK"; then
	echo "OK"
else
	echo "ПРОВАЛ: тесты"
	python3 -m unittest discover -s tests -p "test_*.py" 2>&1 | grep -E "^(FAIL|ERROR):" | head -n 20
	fail=1
fi

step "6/7 версия в шапке и в файле совпадают"
build=$(sed -n 's/.*GLB\.BUILD = "\([0-9.]*\)".*/\1/p' "$SCRIPT" | head -n 1)
head_ver=$(sed -n '1,40p' "$SCRIPT" | sed -n 's/.*\bv\([0-9][0-9.]*\):.*/\1/p' | head -n 1)
if [ -n "$head_ver" ] && [ "$head_ver" != "$build" ]; then
	echo "ПРОВАЛ: в шапке v$head_ver, а GLB.BUILD = $build"
	fail=1
else
	echo "OK (v$build)"
fi

step "7/7 запуск в эмуляции Roblox (экран ключа → меню → кадровый цикл)"
if python3 -c "import lupa" 2>/dev/null; then
	if python3 tools/emulate.py "$SCRIPT" > /tmp/emulate.txt 2>&1; then
		if grep -q "STARTMAIN OK" /tmp/emulate.txt && grep -q "кадровый цикл (всё включено): OK" /tmp/emulate.txt; then
			echo "OK"
		else
			echo "ПРОВАЛ: скрипт запустился, но меню или кадровый цикл падают"
			tail -n 12 /tmp/emulate.txt
			fail=1
		fi
	else
		echo "ПРОВАЛ: скрипт падает при запуске — в игре не появится даже окно ключа"
		tail -n 12 /tmp/emulate.txt
		fail=1
	fi
else
	echo "пропущено: нет пакета lupa (pip install lupa)"
fi

if [ "$fail" -eq 0 ]; then
	printf '\n\033[32mВСЁ ЗЕЛЁНОЕ: скрипт собирается, запускается и проходит тесты\033[0m\n'
else
	printf '\n\033[31mЕСТЬ ПРОБЛЕМЫ — коммитить нельзя\033[0m\n'
fi
exit "$fail"
