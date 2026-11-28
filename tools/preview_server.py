#!/usr/bin/env python3
"""Страница для телефона: одна кнопка «Скачать скрипт» + ссылка «открыть текстом».

    python3 tools/preview_server.py [порт]

Отдаёт ВСЕГДА текущий файл из репозитория, поэтому не бывает «скачал, а там
старая версия» — именно на этом мы уже теряли время.
"""
import http.server
import os
import socketserver
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "Enkaisy_Combined_UI_v4_2.lua"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080

PAGE = """<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Enkaisy %(ver)s</title>
<style>
body{margin:0;background:#0c0d12;color:#eef0f8;font-family:system-ui,-apple-system,sans-serif;
display:flex;align-items:center;justify-content:center;min-height:100vh}
.card{width:min(92vw,430px);background:#161820;border:1px solid #262a36;border-radius:16px;padding:22px}
h1{font-size:20px;margin:0 0 4px}.ver{color:#ff8a2e;font-size:13px;font-weight:700;margin-bottom:14px}
p{color:#9aa0b0;font-size:14px;line-height:1.5;margin:0 0 16px}
a.btn{display:block;text-align:center;text-decoration:none;background:#ff8a2e;color:#14161c;
font-weight:700;padding:16px;border-radius:12px;font-size:17px;margin-bottom:10px}
a.alt{display:block;text-align:center;text-decoration:none;background:#22252f;color:#cfd4e2;
font-weight:600;padding:14px;border-radius:12px;font-size:15px}
ol{color:#9aa0b0;font-size:13px;line-height:1.6;padding-left:18px;margin:14px 0 0}
.meta{margin-top:12px;color:#6f7688;font-size:12px;text-align:center}
</style></head><body><div class="card">
<h1>Enkaisy</h1><div class="ver">версия %(ver)s</div>
<p>Нажмите «Скачать скрипт»: телефон сохранит файл, откройте его и скопируйте всё в исполнитель.</p>
<a class="btn" href="/file" download="Enkaisy_%(ver)s.lua">Скачать скрипт (.lua)</a>
<a class="alt" href="/text">Открыть текстом в браузере</a>
<ol><li>Скачать файл</li><li>Открыть и выделить всё</li><li>Вставить в исполнитель</li></ol>
<div class="meta">%(kb)s КБ · %(lines)s строк · %(check)s</div>
</div></body></html>"""


def version_of(text):
    for line in text.split("\n"):
        if "GLB.BUILD" in line and '"' in line:
            return line.split('"')[1]
    return "?"


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        raw = SCRIPT.read_bytes()
        text = raw.decode("utf-8")
        if self.path.startswith("/file"):
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition",
                             'attachment; filename="Enkaisy_%s.lua"' % version_of(text))
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return
        if self.path.startswith("/text"):
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(raw)
            return
        body = (PAGE % {
            "ver": version_of(text),
            "kb": "%.0f" % (len(raw) / 1024),
            "lines": len(text.split("\n")),
            "check": "проверки: ./tools/check_all.sh",
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    print("страница скачивания: http://0.0.0.0:%d" % PORT)
    httpd.serve_forever()
