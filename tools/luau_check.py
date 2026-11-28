#!/usr/bin/env python3
"""Проверка скрипта НАСТОЯЩИМ компилятором Luau (тот же, что в Roblox).

Зачем: самодельные проверки (баланс `end`/скобок) не видят того, что валит загрузку:
  * `x += 1` для константной переменной цикла;
  * превышение лимита Lua/Luau на 200 активных локальных переменных в функции;
  * любые другие ошибки компиляции, из-за которых скрипт не запускается вообще.

Требуется npm-пакет luau-web (содержит wasm-сборку Luau):
    npm install luau-web --prefix /tmp/lw
    python3 tools/luau_check.py Enkaisy_Combined_UI_v4_2.lua

Скрипт печатает OK или первую ошибку компиляции с номером строки и кодом возврата 1.
"""
import json
import pathlib
import shutil
import subprocess
import sys

MODULE = "luau-web"
INSTALL_PREFIX = pathlib.Path("/tmp/lw")

JS = r"""
import { LuauState } from '%(mod)s/src/index.js';
import fs from 'fs';

const state = await LuauState.createAsync();
let bad = 0;
for (const path of process.argv.slice(2)) {
  const src = fs.readFileSync(path, 'utf8');
  const name = path.split('/').pop();
  const fn = state.loadstring(src, name);
  if (typeof fn === 'string') {
    bad++;
    const first = String(fn).split('\n')[0];
    console.log(name + ': LUAU ERROR — ' + first);
    const m = first.match(/:(\d+):/);
    if (m) {
      const n = +m[1];
      const lines = src.split('\n');
      for (let i = Math.max(0, n - 3); i < Math.min(lines.length, n + 2); i++) {
        console.log('   ' + (i + 1) + ': ' + lines[i].slice(0, 130));
      }
    }
  } else {
    console.log(name + ': LUAU COMPILE OK');
  }
}
process.exit(bad ? 1 : 0);
"""


def ensure_module():
    """Ставит luau-web, если его нет. Без сети проверка невозможна — сообщаем об этом явно."""
    if (INSTALL_PREFIX / "node_modules" / MODULE / "src" / "index.js").exists():
        return True
    if not shutil.which("npm"):
        print("luau_check: npm не найден — проверка компилятором Luau пропущена")
        return False
    print("luau_check: ставлю luau-web (одноразово)…")
    r = subprocess.run(["npm", "install", MODULE, "--prefix", str(INSTALL_PREFIX),
                        "--no-fund", "--no-audit"], capture_output=True, text=True)
    if r.returncode != 0:
        print("luau_check: не удалось поставить luau-web:\n" + (r.stderr or r.stdout)[-400:])
        return False
    return True


def main():
    files = sys.argv[1:] or ["Enkaisy_Combined_UI_v4_2.lua"]
    if not ensure_module():
        return 0  # нет сети/пакета — не валим сборку, но и не делаем вид, что проверили
    script = pathlib.Path("/tmp/luau_check.mjs")
    script.write_text(JS % {"mod": str(INSTALL_PREFIX / "node_modules" / MODULE)}, encoding="utf-8")
    r = subprocess.run(["node", str(script), *files])
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
