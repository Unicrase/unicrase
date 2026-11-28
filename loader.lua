-- Enkaisy 4.6.0 — загрузчик: скачивает полный скрипт и запускает его.
-- Нужен интернет и исполнитель с loadstring (вы писали, что loadstring есть).
local URL = "https://raw.githubusercontent.com/Unicrase/unicrase/arena/ee6c5c73-unicrase/loadstring.lua"

local src
local ok = pcall(function()
	src = game:HttpGet(URL)
end)
if not ok or not src or #src < 1000 then
	-- запасные способы запроса, если HttpGet недоступен
	local req = (syn and syn.request) or (http and http.request) or http_request or request
	if req then
		local good, res = pcall(req, {Url = URL, Method = "GET"})
		if good and res then src = res.Body or res.body end
	end
end

if not src or #src < 1000 then
	warn("[Enkaisy] не удалось скачать скрипт: нет интернета или HttpGet заблокирован")
	return
end

local fn, err = loadstring(src)
if not fn then
	warn("[Enkaisy] скрипт скачан, но не компилируется: " .. tostring(err))
	return
end

print("[Enkaisy] скачано " .. tostring(#src) .. " байт, запускаю")
fn()
