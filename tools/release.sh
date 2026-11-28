#!/usr/bin/env bash
# Один шаг вместо ручной рутины при выпуске новой версии.
#
#   ./tools/release.sh 4.6.3 "что изменилось"
#
# Делает: проверяет, что всё зелёное → поднимает версию → правит шапку →
# обновляет копии файла (loadstring.lua, /tmp/dl для страницы скачивания) →
# коммит с осмысленным сообщением → push → комментарий в PR со ссылкой на этой версии.
#
# Если проверки не прошли — НИЧЕГО не коммитится (защита от «не работает»).
set -euo pipefail
cd "$(dirname "$0")/.."

VER="${1:?укажи версию, например 4.6.3}"
NOTE="${2:-обновление}"
SCRIPT="Enkaisy_Combined_UI_v4_2.lua"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if ! grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' <<< "$VER"; then
	echo "версия должна быть вида 4.6.3"; exit 1
fi

echo "== проверки перед выпуском =="
if ! ./tools/check_all.sh; then
	echo; echo "ПРОВЕРКИ НЕ ПРОШЛИ — выпуск отменён, ничего не изменено"
	exit 1
fi

OLD=$(sed -n 's/.*GLB\.BUILD = "\([0-9.]*\)".*/\1/p' "$SCRIPT" | head -n 1)
echo "== версия $OLD -> $VER =="
sed -i "s/GLB\.BUILD = \"$OLD\"/GLB.BUILD = \"$VER\"/" "$SCRIPT"
python3 - "$VER" "$NOTE" <<'PY'
import sys
ver, note = sys.argv[1], sys.argv[2]
path = "Enkaisy_Combined_UI_v4_2.lua"
s = open(path, encoding="utf-8").read()
marker = "-- Enkaisy: ESP + Aim Assist"
i = s.index("\n--", s.index(marker))  # конец первых двух строк-заголовков
line = "-- v%s: %s\n" % (ver, note)
s = s[:i + 1] + line + s[i + 1:]
open(path, "w", encoding="utf-8").write(s)
print("шапка обновлена")
PY

cp "$SCRIPT" loadstring.lua
mkdir -p /tmp/dl && cp "$SCRIPT" /tmp/dl/Enkaisy_"$VER".lua 2>/dev/null || true

echo "== проверки после правки версии =="
./tools/check_all.sh > /tmp/release_check.log 2>&1 || { tail -n 20 /tmp/release_check.log; echo "сломалось на обновлении версии"; exit 1; }

git add -A
git commit -q -m "$VER: $NOTE"
git push origin "$BRANCH" > /dev/null
SHA=$(git rev-parse --short HEAD)
echo "запушено: $SHA"

if command -v gh > /dev/null; then
	URL="https://raw.githubusercontent.com/Unicrase/unicrase/$SHA/$SCRIPT"
	gh pr comment 7 -b "## $VER — готово

$(printf '%b' "$NOTE")

**Проверки:** \`LUAU COMPILE OK\`, declared-before-use OK, лимит локалей OK, тесты OK.

Скрипт: $URL" > /dev/null 2>&1 && echo "комментарий в PR добавлен"
	echo "ссылка: $URL"
fi
