-- Enkaisy: ESP + Aim Assist (всё в одном скрипте) — для собственной Roblox-игры
--
-- УСТАНОВКА: один обычный Script в ServerScriptService (RunContext не трогать).
-- Скрипт создаёт клиентскую копию в PlayerScripts каждого игрока.
--
-- ОРУЖИЕ: любой Tool с атрибутом Damage (number). Необязательно: Range (500), Cooldown (0.15).
-- NPC для Aim: любые модели с Humanoid (их находит ESP) или с тегом AimTarget.
-- КЛЮЧ ДОСТУПА: проверяется в клиенте по хешу (KEY_HASH), сервер ключ не знает и не проверяет.
-- Сменить ключ: пересчитать djb2(ключ без пробелов) и подставить число в KEY_HASH (клиентская часть).
--
-- Интерфейс: только Android / сенсорное управление. Вид (тема, акцент, прозрачность, масштаб) — папка Appearance.
-- Окно: − свернуть в логотип, □ развернуть / вернуть размер, × открыть подтверждение выгрузки.
-- Оформление как на референсе: Appearance → Reset appearance (игровые настройки не сбрасываются).
-- Полный сброс: Appearance → RESET → «Полный сброс — выключить всё». Сначала окно подтверждения,
-- после подтверждения ВСЕ настройки выключаются (все переключатели OFF), цвета и оформление — заводские.
-- Управление: меню Enkaisy (кнопка-логотип), папка Aim, плавающая кнопка AIM, папка FOV для круга.
-- Triggerbot/Multipoint: папка Trigger; Checks и модели целей: папка Targets; Hitbox и части тела: папка Hitbox.
-- Атрибуты Tool: BulletSpeed, BulletGravity. Атрибуты модели: Invulnerable, Flashed, InSmoke; тег SmokeCloud.
--
-- ПАПКИ (порядок = порядок настройки): ESP → Targets → Aim → Trigger → FOV → Hitbox → Color → Players → Performance → Appearance.
-- Правило раскладки: одна папка = одна задача, похожие настройки стоят рядом (Smoothness + Sticky, Triggerbot + delay/tolerance,
-- Hitbox + размеры и Hitbox ESP, Dynamic FOV + размер круга). Пояснения — серым текстом прямо под разделом.

-- Target Lock: раздел TARGET LOCK в Aim, кнопка Switch locked target = сменить цель. Silent Aim: раздел SILENT AIM (лимит угла — на сервере, SILENT_MAX_ANGLE).
-- Aim-координаты: ТОЧКА НАВЕДЕНИЯ (логика, раздел AIM POINT) и КРУГ FOV (визуал, папка FOV) — независимые значения в долях экрана; радиусы — % короткой стороны экрана.
-- Aim: "Edit aim point" (точка наведения), FOV: "Edit circle position" (круг), "Check coordinates" (проверка на устройстве, раздел DIAGNOSTICS).


-- ВЕРСИЯ СБОРКИ: v4.4.0 (константа BUILD). Она видна в шапке меню и на экране ключа —
-- по ней легко понять, какая версия скрипта запущена, и не путать сборки при обновлении.
-- v4.4.1: CHAMS LOOK: заливка Highlight рисуется ПОВЕРХ тела и была почти непрозрачной —
--         материал и свет под ней не видны, поэтому все стили выглядели одинаковым силуэтом.
--         Заливка ограничена 55%, свет ярче (1.5..2.2 вместо 0.3..1.1), добавлена поддержка
--         настоящих текстур Roblox (CHAMS_TEX), исходная текстура возвращается при снятии.
--         Круг FOV: gradient-обводка больше не теряется (fovStrokeGrad объявлен), а анимация
--         (вращение градиента, пунктир, «дыхание») не выключается из-за неполного сохранения.
--         ИСПРАВЛЕНО ГЛАВНОЕ — скрипт снова загружается. В buildAim и в главном блоке файла было
--         больше 200 локальных переменных: Lua/Luau отказывался компилировать файл, и не появлялось
--         даже окно ключа. Редкие константы и ссылки переехали в таблицы GLB / AIM (обращения вида
--         GLB.BUILD), число локалей упало ниже предела. В тесты добавлена проверка компиляции.
-- v4.4.0: CHAMS LOOK стал текстурой: материал частей тела (Neon светится, CrackedLava — лава,
--         ForceField — сетка, Glass/Ice, Foil-хром) + PointLight для светящихся стилей; исходные
--         материалы возвращаются при снятии подсветки и выгрузке.
--         Круг FOV: стили получили настоящую разницу — ореол и «дыхание» у Glow, вращающийся
--         градиент у Gradient, вращающийся пунктир у Dashed; элементы стиля перенесены ВНУТРЬ круга
--         (раньше считались в долях экрана и «улетали»).
-- v4.3.3: стиль Chams теперь РЕАЛЬНО применяется: chamsApply вызывается из refreshHL,
--         прозрачности считаются по таблице стилей, оттенок стиля живёт поверх цвета темы
--         и не стирается цветом по здоровью / радугой. В строке списка — превью стиля.
-- v4.3.2: исправлено падение списка CHAMS LOOK и карточек CIRCLE STYLE
--         (цвет обводки брался из OUT.Hover — это число-прозрачность, а не цвет; теперь PURE).
-- v4.3.1: круг FOV: размер в пикселях и стили Glow / Gradient / Dashed / Classic; список CHAMS LOOK
--         (21 стиль подсветки) в папке ESP; заставка после ключа с защитой от падения.
-- v4.3: Ключ доступа снова проверяется в клиенте по хешу (KEY_HASH), серверной авторизации нет.
--       Кулдаун выстрела и триггера — на каждое оружие отдельно (смена пушки больше не съедает выстрел).
--       Triggerbot стреляет на всю дальность оружия (Range), а не до "Aim max distance".
--       Head hitbox: размер головы берётся из Head hitbox size (0 = как тело), раньше всегда был max(тело, голова).
--       ESP update rate теперь реально ограничивает частоту (в т.ч. 60 Гц на 120-Гц экране).
--       Плавность (папка Aim, раздел SMOOTHNESS): Smooth curve (Linear / Ease / Human), Max turn speed,
--       Dead zone в пикселях, Camera follow %; тряска Shake фильтруется по кадру и не скачет.
--       Качество наводки: Stick time (удержание цели по времени), Predict multiplier, Shake (мягкое дрожание),
--       мёртвая зона в экранных пикселях, плавное догоняние камеры, сплайн-трекер скорости по истории позиций.
--       Silent aim: сначала цель самой наводки, иначе — по реальной точке попадания; Multipoint — ближние точки первыми.
--       ESP: ESP box (рамка по границам модели) и Min distance (ближе — не рисуем).
--       RCS (Recoil Control System) в папке Aim: возврат камеры к прицелу после отдачи, сила 0–100%,
--       плавность и режим «без отдачи» (отдача не отрисовывается). Пуля летит по прицелу ДО отдачи.
--       Настройки видны всегда, но гаснут, пока RCS выключен.
--       Анимации интерфейса: пружины на переключателях/кнопках/иконках, «доезжающие» цифры ползунков,
--       HUD и FPS/пинга, каскад карточек новой страницы, всплывающие карточки вместо системных плашек,
--       пульсация активной вкладки и точек включённых функций, появление круга FOV и «дыхание» маркера цели.
--       После верного ключа — заставка «осколки → UNICRASE» на 3.1 с: Michroma, градиентные осколки,
--       кольца, блик по слову и подпись. Не пропускается — это часть открытия (AnimIntro).
--       Открытие папки: заголовок и названия карточек собираются из частиц-искр, волной слева направо (AnimText).
--       Всё гасится общим переключателем Animations и по отдельности — раздел ANIMATION EFFECTS (Performance).
--       Поиск: крестик очистки в поле и бейдж «сколько совпадений» на каждой папке.
--       ESP: линии и скелет появляются и гаснут фейдом (твин стартует только на смене состояния).
--       Поиск: запрос ищется по словам (порядок не важен), папки без совпадений скрываются;
--       клик по папке прокручивает страницу к ближайшей настройке, дальше — стрелки ▲▼ справа от страницы.
-- v4.2: Aim: исправлен Sticky (раньше не работал — цель обнулялась перед выбором), сглаживание упреждения (меньше дрожи), мёртвая зона и лимит скорости поворота камеры.
-- v4.0: Dynamic FOV (вкладка FOV): радиус круга и выбора цели зависит от дистанции (Linear / Smooth, мин/макс, дистанции, плавность, текущий радиус).
--       Target Animation (вкладка FOV): индикатор цели - появление, переключение, захват, потеря; стили Ring / Square / Dot, скорость, Preview.
--       Hitbox Visual (вкладка Aim, раздел HITBOX VISUAL): Hitbox ESP, цвета тела / головы / обводки / захваченной цели, прозрачность, заливка, толщина обводки,
--       показ головы / тела, только цель / все цели, лимит дистанции, пресеты Minimal / Clean / Neon / Filled / Outline Only. ТОЛЬКО ВИД: размеры хитбоксов и попадания не затрагиваются.
--       Body Part Priority (вкладка Aim): 8 частей тела, очередь, вкл/выкл, основная часть, автопереход к следующей доступной и возврат к основной.
--       Старая настройка Target part теперь = первая включённая часть очереди (TargetPart синхронизируется сам).
-- v3.4: Triggerbot переписан (работает и без включённой наводки: луч / хитбокс / допуск, своя проверка каждый кадр, статус и ответ сервера в HUD).
--       Hitbox и Head hitbox (вкладка Aim): включение и размер в студах, показ боксов; сервер ограничивает размер (HITBOX_MAX_BODY / HITBOX_MAX_HEAD).
--       Фон-картинка из Appearance теперь применяется и к окну ключа.
-- v3.3: триггер (стреляет и при движущейся цели + наводке), Adv predict (без ложного упреждения на время полёта), стекло карточек над фоном-картинкой.
-- v3.2: переписан предикт (скорость по позиции, трекер ускорения), триггер (допуск, Activate-режим, статусы), фон-картинка в Appearance.
-- v3.1: окно меню растягивается за правый нижний угол (значок из точек). Двойное касание угла — вернуть размер.
-- Размер, положение окна и последняя вкладка сохраняются; карточки переходят во вторую колонку только в широком окне.
local GLB = {} -- общие константы и ссылки: вынесены в таблицу, иначе лимит Lua на локали
local Players = game:GetService("Players")
local RS = game:GetService("RunService")
GLB.ReplicatedStorage = game:GetService("ReplicatedStorage")
GLB.BUILD = "4.4.1" -- версия сборки: показывается в меню и на экране ключа
GLB.REMOTE_NAME = "EnkaisyAimFire"
GLB.CLIENT_NAME = "EnkaisyAimClient"

-- ===== Части скрипта (обход лимита 200 локалей) =====
-- Лимит 200 считается на ОДИН загруженный кусок кода. Крупные блоки живут отдельными
-- частями: у каждой свой лимит, поэтому суммарный размер роли не играет.
-- Части кешируются: второй вызов loadstring не нужен.
local PARTS_URL = "https://raw.githubusercontent.com/Unicrase/unicrase/arena/ee6c5c73-unicrase/build/parts/%s.lua"
GLB.PARTS = GLB.PARTS or {}
function GLB.loadPart(name)
	local cached = GLB.PARTS[name]
	if cached then return cached end
	-- 1) часть уже склеена в общий текст (обычный Script), 2) иначе — скачиваем
	local code = GLB.PART_SRC and GLB.PART_SRC[name]
	if not code then
		local url = string.format(PARTS_URL, name)
		local ok, body = pcall(function() return game:HttpGet(url) end)
		if not ok or type(body) ~= "string" or #body == 0 then
			return nil, "не удалось скачать " .. url
		end
		code = body
	end
	local chunk, err = loadstring(code, "Enkaisy:" .. name)
	if not chunk then return nil, tostring(err) end
	local ok, fn = pcall(chunk)
	if not ok or type(fn) ~= "function" then return nil, "часть " .. name .. " не вернула функцию" end
	GLB.PARTS[name] = fn
	return fn
end

-- ===== Виртуальные хитбоксы (Hitbox / Head hitbox): общий код клиента и сервера =====
-- Хитбокс = каждая часть тела цели, раздутая на N студов во все стороны (у головы — свой размер).
-- Настоящие парты не меняются: расширенные боксы проверяются математически (луч против повёрнутого бокса).
-- Сервер сам решает, сколько разрешить (HITBOX_MAX_BODY / HITBOX_MAX_HEAD в серверной части).
local HB_BODY_MAX, HB_HEAD_MAX = 6, 4 -- верхние границы ползунков, студы
local function hbSlab(o, d, h, t0, t1)
	if math.abs(d) < 1e-8 then
		if o < -h or o > h then return nil end
		return t0, t1
	end
	local a, b = (-h - o) / d, (h - o) / d
	if a > b then a, b = b, a end
	if a > t0 then t0 = a end
	if b < t1 then t1 = b end
	if t0 > t1 then return nil end
	return t0, t1
end
-- dir — единичный вектор; возвращает расстояние входа в бокс (0, если origin внутри) или nil
local function rayBox(origin, dir, maxDist, cf, size, pad)
	local o, d = cf:PointToObjectSpace(origin), cf:VectorToObjectSpace(dir)
	local t0, t1 = hbSlab(o.X, d.X, size.X / 2 + pad, 0, maxDist)
	if not t0 then return nil end
	t0, t1 = hbSlab(o.Y, d.Y, size.Y / 2 + pad, t0, t1)
	if not t0 then return nil end
	t0, t1 = hbSlab(o.Z, d.Z, size.Z / 2 + pad, t0, t1)
	return t0
end
-- ближайшее пересечение луча с расширенными хитбоксами модели: расстояние и часть тела
-- Голова получает СВОЙ размер (Head hitbox size). Если Head hitbox выключен (0), голова
-- расширяется как тело — иначе обычный Hitbox перестал бы работать по голове.
local function rayModelHitbox(origin, dir, maxDist, model, bodyPad, headPad)
	local bestT, bestPart
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			local pad = bodyPad
			if p.Name == "Head" then pad = headPad > 0 and headPad or bodyPad end
			if pad > 0 then
				local t = rayBox(origin, dir, bestT or maxDist, p.CFrame, p.Size, pad)
				if t and (not bestT or t < bestT) then bestT, bestPart = t, p end
			end
		end
	end
	return bestT, bestPart
end
-- модель с Humanoid, к которой относится инстанс (поднимаемся по родителям, в т.ч. из вложенных Model: броня, оружие)
local function humanoidModel(inst)
	local m = inst
	while m do
		if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then return m end
		m = m.Parent
	end
	return nil
end

-- ===== Ключ доступа (проверка в клиенте по хешу) =====
-- В файле лежит только хеш ключа, самого ключа нет. Сравнение — djb2 от введённого текста без пробелов.
local KEY_HASH = 200016687 -- djb2(ключ без пробелов); сменить ключ = пересчитать это число
local function hashKey(s)
	local h = 5381
	for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
	return h
end

----------------------------------------------------------------
-- СЕРВЕРНАЯ ЧАСТЬ
----------------------------------------------------------------
if RS:IsServer() then
    local CS = game:GetService("CollectionService")
    local DEFAULT_RANGE = 500
    local DEFAULT_COOLDOWN = 0.15
    local MAX_ORIGIN_OFFSET = 10 -- насколько origin может отличаться от головы
    local TEAM_DAMAGE = false    -- бить своих
    -- Silent Aim как игровая механика: клиент присылает направление "куда целился" (aimDir)
    -- и направление "куда лететь пуле" (direction). Сервер разрешает отклонение не больше этого угла.
    -- У Tool можно задать атрибут SilentAim = false, чтобы запретить механику для конкретного оружия.
    local SILENT_AIM_ALLOWED = true
    local SILENT_MAX_ANGLE = 25  -- градусов
    -- Hitbox / Head hitbox как игровая механика: клиент присылает желаемое расширение (студы), сервер режет его до лимитов.
    -- HITBOX_ALLOWED = false полностью отключает механику; у Tool атрибут Hitbox = false отключает её для конкретного оружия.
    local HITBOX_ALLOWED = true
    local HITBOX_MAX_BODY = HB_BODY_MAX -- максимум расширения тела, студов
    local HITBOX_MAX_HEAD = HB_HEAD_MAX -- максимум расширения головы, студов

    local remote = Instance.new("RemoteEvent")
    remote.Name = GLB.REMOTE_NAME
    remote:SetAttribute("SilentMaxAngle", SILENT_MAX_ANGLE) -- клиент подгоняет свой SilentFOV под этот угол
    remote:SetAttribute("HitboxMaxBody", HITBOX_ALLOWED and HITBOX_MAX_BODY or 0) -- клиент ограничивает ползунки хитбоксов
    remote:SetAttribute("HitboxMaxHead", HITBOX_ALLOWED and HITBOX_MAX_HEAD or 0)
    remote.Parent = GLB.ReplicatedStorage

    -- Client Scripts не запускаются из ReplicatedStorage: выдаём копию каждому PlayerScripts.
    local function installClient(plr)
        task.spawn(function()
            local scripts = plr:WaitForChild("PlayerScripts", 30)
            if not scripts or plr.Parent ~= Players then return end
            local old = scripts:FindFirstChild(GLB.CLIENT_NAME)
            if old then old:Destroy() end
            local copy = script:Clone()
            copy.Name = GLB.CLIENT_NAME
            copy.RunContext = Enum.RunContext.Client
            copy.Parent = scripts
        end)
    end
    Players.PlayerAdded:Connect(installClient)
    for _, plr in Players:GetPlayers() do installClient(plr) end

    -- Кулдаун считается ПО ОРУЖИЮ, а не на игрока: своё оружие = свой таймер.
    -- Слабые ключи: инструмент удалили — запись уходит сама.
    local lastShot = setmetatable({}, {__mode = "k"})

    -- NPC (модели с Humanoid, не игроки) для проверки хитбоксов
    local npcModels = setmetatable({}, { __mode = "k" })
    local function trackHumanoid(h)
        if not h:IsA("Humanoid") then return end
        local m = h.Parent
        if m and m:IsA("Model") then npcModels[m] = true end
    end
    workspace.DescendantAdded:Connect(trackHumanoid)
    task.spawn(function()
        local n = 0
        for _, d in workspace:GetDescendants() do
            trackHumanoid(d)
            n += 1
            if n % 500 == 0 then task.wait() end
        end
    end)

    -- кого проверять хитбоксами: все модели с Humanoid рядом (кроме стреляющего)
    local function candidates(shooterChar, origin, range)
        local list, seen = {}, {}
        local function add(m)
            if seen[m] or m == shooterChar or not m.Parent then return end
            seen[m] = true
            local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
            if root and (root.Position - origin).Magnitude > range + 40 then return end
            table.insert(list, m)
        end
        for _, p in Players:GetPlayers() do
            if p.Character then add(p.Character) end
        end
        for m in npcModels do add(m) end
        for _, m in CS:GetTagged("AimTarget") do
            if m:IsA("Model") then add(m) end
        end
        return list
    end

    -- ближайший расширенный хитбокс на отрезке a -> a + dir * maxDist; хитбокс не должен "торчать" сквозь стену
    local function sweepHitboxes(list, a, dir, maxDist, bodyPad, headPad, params)
        local bestM, bestT, bestP, lim = nil, nil, nil, maxDist
        for _, m in list do
            local hum = m:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local t, part = rayModelHitbox(a, dir, lim, m, bodyPad, headPad)
                if t then bestM, bestT, bestP, lim = m, t, part, t end
            end
        end
        if not bestM then return nil end
        local p = a + dir * bestT
        local toPart = bestP.Position - p
        if toPart.Magnitude > 0.05 then
            local back = workspace:Raycast(p, toPart, params)
            if back and not back.Instance:IsDescendantOf(bestM) then return nil end
        end
        return bestM
    end

    -- обработка выстрела; возвращает короткий код результата (клиент показывает его в HUD)
    local function handleShot(plr, tool, origin, direction, aimDir, hbB, hbH)
        -- 1. Типы данных
        if typeof(tool) ~= "Instance" or not tool:IsA("Tool") then return "bad data" end
        if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return "bad data" end
        if typeof(aimDir) ~= "Vector3" then return "bad data" end

        -- 2. Игрок жив и держит это оружие
        local character = plr.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local head = character and character:FindFirstChild("Head")

        if not humanoid or humanoid.Health <= 0 or not head then return "dead" end
        if tool.Parent ~= character then return "tool not equipped" end

        -- 3. Параметры оружия из атрибутов
        local damage = tool:GetAttribute("Damage")
        if type(damage) ~= "number" then return "no Damage attr" end

        if damage ~= damage or damage == math.huge or damage <= 0 then return "bad Damage attr" end
        local range = tool:GetAttribute("Range")
        if type(range) ~= "number" or range ~= range or range <= 0 or range == math.huge then range = DEFAULT_RANGE end
        range = math.min(range, 5000)

        local cooldown = tool:GetAttribute("Cooldown")
        if type(cooldown) ~= "number" or cooldown ~= cooldown or cooldown < 0 or cooldown == math.huge then cooldown = DEFAULT_COOLDOWN end
        cooldown = math.max(cooldown, 0.03)

        -- 4. Кулдаун (у каждого оружия свой)
        local now = os.clock()
        if now - (lastShot[tool] or 0) < cooldown * 0.9 then return "cooldown" end -- 10% допуск на джиттер сети
        lastShot[tool] = now

        -- 5. Стрелять можно только из района головы
        if not ((origin - head.Position).Magnitude <= MAX_ORIGIN_OFFSET) then return "origin too far" end
        local toO = origin - head.Position
        if toO.Magnitude > 0.1 then -- между головой и origin не должно быть стены
            local wp = RaycastParams.new()
            wp.FilterType = Enum.RaycastFilterType.Exclude
            wp.FilterDescendantsInstances = { character }
            if workspace:Raycast(head.Position, toO, wp) then return "origin behind wall" end
        end

        -- 6. Направление должно быть единичным вектором
        local m = direction.Magnitude
        if not (m > 0.9 and m < 1.1) then return "bad direction" end
        local am = aimDir.Magnitude
        if not (am > 0.9 and am < 1.1) then return "bad direction" end

        -- 6.1 Silent Aim: ограничиваем, насколько направление пули может отличаться от прицела.
        -- Если механика запрещена или угол слишком большой, пуля летит туда, куда игрок реально целился.
        local angle = math.deg(math.acos(math.clamp(direction.Unit:Dot(aimDir.Unit), -1, 1)))
        if angle > 0.5 then
            local allowed = SILENT_AIM_ALLOWED and tool:GetAttribute("SilentAim") ~= false
            if not allowed or angle > SILENT_MAX_ANGLE then
                direction = aimDir
            end
        end

        -- 6.2 Hitbox / Head hitbox: сколько студов расширения разрешено этому выстрелу
        local bodyPad, headPad = 0, 0
        if HITBOX_ALLOWED and tool:GetAttribute("Hitbox") ~= false then
            if type(hbB) == "number" and hbB > 0 then bodyPad = math.min(hbB, HITBOX_MAX_BODY) end
            if type(hbH) == "number" and hbH > 0 then headPad = math.min(hbH, HITBOX_MAX_HEAD) end
        end

        -- 7. Рейкаст на сервере
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { character }

        local dirU = direction.Unit
        local list = (bodyPad > 0 or headPad > 0) and candidates(character, origin, range) or nil
        local hitModel -- модель, пойманная расширенным хитбоксом (раньше любой стены)

        -- Баллистика: если у Tool заданы атрибуты BulletSpeed (стадов/с) и BulletGravity (стадов/с^2),
        -- пуля летит по дуге и падает. Без них это обычный мгновенный луч.
        local result
        local speed, grav = tool:GetAttribute("BulletSpeed"), tool:GetAttribute("BulletGravity")
        if type(speed) == "number" and speed >= 1 and speed < math.huge and type(grav) == "number" and grav > 0 and grav < math.huge then
            -- Ограничиваем число сегментов и не просчитываем траекторию за пределами Range.
            local tMax = math.min(range / speed, 10)
            local segments = math.clamp(math.ceil(tMax / 0.04), 1, 250)
            local step = tMax / segments
            local prev = origin
            for i = 1, segments do
                local t = i * step
                local pos = origin + dirU * speed * t - Vector3.new(0, 0.5 * grav * t * t, 0)
                local seg = pos - prev
                local segLen = seg.Magnitude
                if segLen > 1e-4 then
                    result = workspace:Raycast(prev, seg, params)
                    if list then
                        local lim = result and result.Distance or segLen
                        hitModel = sweepHitboxes(list, prev, seg / segLen, lim, bodyPad, headPad, params)
                        if hitModel then break end
                    end
                    if result then break end
                end
                prev = pos
            end
        else
            result = workspace:Raycast(origin, dirU * range, params)
            if list then
                local lim = result and result.Distance or range
                hitModel = sweepHitboxes(list, origin, dirU, lim, bodyPad, headPad, params)
            end
        end

        local model = hitModel
        if not model then
            if not result then return "miss" end
            model = humanoidModel(result.Instance)
        end
        local targetHum = model and model:FindFirstChildOfClass("Humanoid")
        if not targetHum then return "miss (wall)" end
        if targetHum.Health <= 0 then return "target dead" end
        if model:GetAttribute("Invulnerable") == true then return "invulnerable" end

        if not TEAM_DAMAGE then
            local victim = Players:GetPlayerFromCharacter(model)
            if victim and victim.Team ~= nil and victim.Team == plr.Team then
                return "team"
            end
        end

        targetHum:TakeDamage(damage)
        return hitModel and "hit (hitbox)" or "hit"
    end

    remote.OnServerEvent:Connect(function(plr, tool, origin, direction, aimDir, hbB, hbH)
        local ok, code = pcall(handleShot, plr, tool, origin, direction, aimDir, hbB, hbH)
        if not ok then
            warn("[Enkaisy] shot error: " .. tostring(code))
            code = "server error"
        end
        pcall(function() remote:FireClient(plr, code) end)
    end)

    return
end

----------------------------------------------------------------
-- КЛИЕНТСКАЯ ЧАСТЬ
----------------------------------------------------------------
if _G.TH_Stop then pcall(_G.TH_Stop) end
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local STS = game:GetService("TextService") -- ширина напечатанной части текста: позиция курсора
GLB.Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
GLB.HttpService = game:GetService("HttpService")
GLB.Stats = game:GetService("Stats")
local LP = Players.LocalPlayer
local U, S, O, V2 = UDim2.new, UDim2.fromScale, UDim2.fromOffset, Vector2.new
-- Встроенное семейство с кириллицей; используем настоящие начертания, а не обводку букв.
local GR = Font.fromEnum(Enum.Font.Roboto)
local GB, GM, XL = Font.new(GR.Family, Enum.FontWeight.Bold), Font.new(GR.Family, Enum.FontWeight.Medium), Enum.TextXAlignment.Left

GLB.MODES = {"Players", "NPC", "Both"}
local DIST_MAX = 2000
local CFG = {
	On = true, Mode = "Players",
	Hl = true, Names = false, HP = false, Pct = false,
	TeamCheck = false, HideDead = true, Rainbow = false, Disp = false,
	Fill = 0.45, Outline = 1, NameSize = 16, NameLen = 14,
	Dist = false, HPColor = false, Limit = true, LimitN = 30, MaxDist = DIST_MAX, MinDist = 0, Box = false,
	FriendMode = "Off", NpcFilter = "Off", NpcText = "", ModelNames = "", HideNative = true,
	TeamColors = true, DistScale = true, Anim = true, ShowStats = true,
	FpsUnlock = false, FpsCap = 0, EspHz = 60,
	-- v4.1 Team Colors: включатели сторон, "всё цветом Team", трассы / скелет, имена пресетов
	TcFriend = false, TcEnemy = false, TcNPC = false, TcAll = false, Tracers = false, Skeleton = false,
	TcFP = "Blue", TcEP = "Red", TcPair = "Blue / Red",
}
local col = {
	Fill = {h = 0, s = 0.75, v = 0.92},
	Outline = {h = 0, s = 0, v = 1},
	Name = {h = 0, s = 0, v = 1},
	NPC = {h = 0.12, s = 0.85, v = 1},
	Friend = {h = 0.33, s = 0.8, v = 0.95},
	Mark = {h = 0.55, s = 0.85, v = 1},
}
-- ===== v4.1 TEAM COLORS =====
-- Цвета лежат в col (ключи TC<Side><Elem>), флаги и пресеты - в CFG: сохраняются вместе с остальными настройками.
-- Команды игроков не трогаем: только читаем LP.Team и plr.Team.
local TC = {
	Sides = {"Friend", "Enemy", "NPC"}, Elems = {"Team", "Box", "Skeleton", "Tracer"},
	Label = {Friend = "Friendly", Enemy = "Enemy", NPC = "NPC"},
	FP = {Blue = Color3.fromRGB(60, 130, 255), Green = Color3.fromRGB(70, 220, 110), Cyan = Color3.fromRGB(60, 225, 255)},
	EP = {Red = Color3.fromRGB(240, 70, 70), Orange = Color3.fromRGB(255, 150, 40)},
	Pairs = {["Blue / Red"] = {"Blue", "Red"}, ["Green / Red"] = {"Green", "Red"}, ["Cyan / Orange"] = {"Cyan", "Orange"}},
	PairOrder = {"Blue / Red", "Green / Red", "Cyan / Orange", "Custom"},
	FPOrder = {"Blue", "Green", "Cyan", "Custom"}, EPOrder = {"Red", "Orange", "Custom"},
	NpcCol = Color3.fromRGB(255, 210, 80),
}
function TC.put(side, c3) -- один цвет на все элементы стороны
	local h, s, v = c3:ToHSV()
	for _, e in TC.Elems do col["TC" .. side .. e] = {h = h, s = s, v = v} end
end
function TC.sync() -- имя пары = Custom, если Friendly / Enemy пресеты не образуют готовую пару
	CFG.TcPair = "Custom"
	for n, p in TC.Pairs do
		if p[1] == CFG.TcFP and p[2] == CFG.TcEP then CFG.TcPair = n end
	end
end
function TC.reset() -- только цвета и пресеты; включатели не трогаем
	CFG.TcFP, CFG.TcEP, CFG.TcPair = "Blue", "Red", "Blue / Red"
	TC.put("Friend", TC.FP.Blue) TC.put("Enemy", TC.EP.Red) TC.put("NPC", TC.NpcCol)
end
TC.reset()
local cur = "Fill"
local AIMCFG = {
	Enabled = false, HoldToAim = false, ShowButton = true, AutoPredict = true,
	TargetPlayers = true, TargetNPCs = false, TeamCheck = true, WallCheck = true,
AimMode = "Center", AimX = 0.5, AimY = 0.5,        -- точка наведения (ЛОГИКА): режим + доли экрана 0..1
CircleFollow = true, CircleX = 0.5, CircleY = 0.5, -- круг (ВИЗУАЛ): связан с областью наведения или стоит сам по себе
ShowFOV = true, DebugHUD = true,
Smoothness = 0.16, Prediction = 0.1, MaxDistance = 500, Sticky = 0.7,
-- RCS (Recoil Control System): возвращает камеру к точке прицела после отдачи и (по желанию) гасит её
Rcs = false, RcsStrength = 1, RcsSmooth = 0.35, RcsSuppress = false,
-- Плавность (Smoothness): кривая сглаживания, предел угловой скорости, мёртвая зона и подмешивание камеры
SmoothMode = "Linear", SmoothMaxSpeed = 900, SmoothDeadPx = 0.6, SmoothCamFollow = 65,
-- качество наводки: StickTime — сколько цель остаётся «своей» после выхода из круга (сек),
-- Shake — дрожание прицела в долях градуса, LeadMul — множитель упреждения (%)
StickTime = 0.25, Shake = 0, LeadMul = 100,
	TargetPart = "Head", Priority = "Crosshair", VisFromHead = true,
TargetLock = false, SilentAim = false,
FovR = 18, SilentR = 14, LockR = 28, -- радиусы областей в % короткой стороны экрана (не зависят от разрешения)
FovPx = 240, -- диаметр круга FOV в пикселях (FovR остаётся радиусом в % — им пользуется Dynamic FOV)
FovStyle = "Gradient", -- вид круга: Glow / Gradient / Dashed / Classic
Chams = "Outline", -- вид подсветки ESP (Chams Look): Outline / Soft / Solid / Glow / Shaded / Metallic ...
FovAnim = true, -- круг «дышит» и подсвечивается, когда цель захвачена
	Trigger = false, TriggerDelay = 0.05, Multipoint = false, AdvPredict = false,
	TriggerR = 3, LeadBias = 40, -- TriggerR: допуск триггера при включённой наводке (% короткой стороны); LeadBias: запас авто-предикта, мс
	Hitbox = false, HitboxSize = 1.5, HeadHitbox = false, HeadHitboxSize = 1.5, HitboxShow = false, -- расширение хитбоксов, студы
	MPEdges = true, MPHead = true, MPTorso = true, MPArms = false, MPLegs = false,
	CheckInvuln = true, CheckFlash = false, CheckSmoke = false,
StepPx = 10, CircleThick = 1.5, CircleColor = "White",
FovAlpha = 0.35, FovFill = true, FovFillAlpha = 0.94, FovCol = {h = 0, s = 0, v = 0.94}, FovTarget = true,
-- v4.0 Dynamic FOV: радиусы в % короткой стороны экрана (как FovR), дистанции в студах; DynSmooth: 0 = мгновенно, выше = плавнее
DynFov = false, DynInvert = false, DynMode = "Smooth", DynMin = 8, DynMax = 30, DynNear = 25, DynFar = 250, DynSmooth = 0.9,
-- v4.0 Target Animation
TargetAnim = true, AnimLock = true, AnimLose = true, AnimStyle = "Ring", AnimSpeed = 1,
-- v4.0 Body Part Priority: PartOrder - очередь, PartOn - включены ли части; TargetPart всегда = первая включённая
PartOrder = {"Head", "UpperTorso", "LowerTorso", "HumanoidRootPart", "LeftArm", "RightArm", "LeftLeg", "RightLeg"},
PartOn = {Head = true, UpperTorso = true, LowerTorso = true, HumanoidRootPart = true, LeftArm = true, RightArm = true, LeftLeg = true, RightLeg = true},
PartFallback = true, PartReturn = true,
-- v4.0 Hitbox Visual: ТОЛЬКО вид (HitboxShow - главный переключатель Hitbox ESP). Размеры хитбоксов (HitboxSize / HeadHitboxSize) от этих настроек не зависят
HbvBodyCol = {h = 0.4, s = 0.55, v = 0.92}, HbvHeadCol = {h = 0, s = 0.62, v = 0.95}, HbvOutCol = {h = 0, s = 0, v = 1}, HbvLockCol = {h = 0.12, s = 0.8, v = 1},
HbvOutMatch = false, HbvAlpha = 0.05, HbvFillAlpha = 0.86, HbvThick = 1.5, HbvDist = 300,
HbvShowHead = true, HbvShowBody = true, HbvOnlyTarget = false, HbvAll = true, HbvCapture = true,
}

-- ===== v4.0: общие данные Body Part Priority (нужны и загрузке настроек, и модулю Aim) =====
local V4 = {}
V4.SLOTS = {"Head", "UpperTorso", "LowerTorso", "HumanoidRootPart", "LeftArm", "RightArm", "LeftLeg", "RightLeg"}
V4.NAMES = {
	Head = "Head", UpperTorso = "Upper Torso", LowerTorso = "Lower Torso", HumanoidRootPart = "HumanoidRootPart",
	LeftArm = "Left Arm", RightArm = "Right Arm", LeftLeg = "Left Leg", RightLeg = "Right Leg",
}
-- реальные имена частей: R15 и R6 (у R6 одна часть Torso закрывает обе позиции торса)
V4.ALIAS = {
	Head = {"Head"}, UpperTorso = {"UpperTorso", "Torso"}, LowerTorso = {"LowerTorso", "Torso"}, HumanoidRootPart = {"HumanoidRootPart"},
	LeftArm = {"LeftUpperArm", "Left Arm"}, RightArm = {"RightUpperArm", "Right Arm"},
	LeftLeg = {"LeftUpperLeg", "Left Leg"}, RightLeg = {"RightUpperLeg", "Right Leg"},
}
V4.SLOT = {}
for _, n in ipairs(V4.SLOTS) do V4.SLOT[n] = true end
-- приводит PartOrder / PartOn / TargetPart к согласованному виду (вызывается при загрузке, сбросе и любом изменении очереди).
-- fromLegacy = true: только при загрузке - старый TargetPart (до v4.0) становится первым в очереди.
function V4.normalizeParts(A, fromLegacy)
	if A.TargetPart == "Torso" then A.TargetPart = "UpperTorso" end
	local order, seen = {}, {}
	if type(A.PartOrder) == "table" then
		for _, n in ipairs(A.PartOrder) do
			if V4.SLOT[n] and not seen[n] then
				seen[n] = true
				table.insert(order, n)
			end
		end
	end
	for _, n in ipairs(V4.SLOTS) do
		if not seen[n] then table.insert(order, n) end
	end
	local src = type(A.PartOn) == "table" and A.PartOn or {}
	local on, any = {}, false
	for _, n in ipairs(V4.SLOTS) do
		on[n] = src[n] ~= false
		if on[n] then any = true end
	end
	if not any then on.Head = true end -- хотя бы одна часть всегда включена
	local tp = A.TargetPart
	if fromLegacy and V4.SLOT[tp] and on[tp] then
		local first
		for _, n in ipairs(order) do
			if on[n] then first = n; break end
		end
		if first ~= tp then
			table.remove(order, table.find(order, tp))
			table.insert(order, 1, tp)
		end
	end
	for _, n in ipairs(order) do
		if on[n] then A.TargetPart = n; break end
	end
	A.PartOrder, A.PartOn = order, on
end

-- ===== v4.0: Hitbox Visual - общие данные (пресеты и их сравнение). ТОЛЬКО вид; размеры хитбоксов здесь не задаются и не меняются =====
local HBV = {}
HBV.COLORDER = {"Body", "Head", "Outline", "Locked"}
HBV.COLKEYS = {Body = "HbvBodyCol", Head = "HbvHeadCol", Outline = "HbvOutCol", Locked = "HbvLockCol"}
HBV.PRESET_ORDER = {"Minimal", "Clean", "Neon", "Filled", "Outline Only"}
-- body / head / out = {h, s, v}; match = обводка берёт цвет заливки; alpha = общая прозрачность; fill = прозрачность заливки (1 = без заливки); thick = обводка, px
HBV.PRESETS = {
	Minimal = {body = {0.42, 0.2, 0.9}, head = {0.02, 0.4, 0.95}, out = {0, 0, 0.95}, match = true, alpha = 0.15, fill = 0.94, thick = 1},
	Clean = {body = {0.4, 0.55, 0.92}, head = {0, 0.62, 0.95}, out = {0, 0, 1}, match = false, alpha = 0.05, fill = 0.86, thick = 1.5},
	Neon = {body = {0.5, 0.85, 1}, head = {0.88, 0.85, 1}, out = {0, 0, 1}, match = true, alpha = 0, fill = 0.8, thick = 2.5},
	Filled = {body = {0.38, 0.7, 0.85}, head = {0, 0.75, 0.92}, out = {0, 0, 1}, match = true, alpha = 0.05, fill = 0.45, thick = 1},
	["Outline Only"] = {body = {0.4, 0.6, 1}, head = {0, 0.7, 1}, out = {0, 0, 1}, match = true, alpha = 0, fill = 1, thick = 2},
}
function HBV.near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.006 end
function HBV.nearHSV(c, t)
	return type(c) == "table" and HBV.near(c.h, t[1]) and HBV.near(c.s, t[2]) and HBV.near(c.v, t[3])
end
-- применяет пресет: меняет только цвета, прозрачность и обводку (цвет захваченной цели, режимы показа и дистанция остаются как есть)
function HBV.apply(A, name)
	local p = HBV.PRESETS[name]
	if not p then return false end
	A.HbvBodyCol = {h = p.body[1], s = p.body[2], v = p.body[3]}
	A.HbvHeadCol = {h = p.head[1], s = p.head[2], v = p.head[3]}
	A.HbvOutCol = {h = p.out[1], s = p.out[2], v = p.out[3]}
	A.HbvOutMatch, A.HbvAlpha, A.HbvFillAlpha, A.HbvThick = p.match, p.alpha, p.fill, p.thick
	return true
end
-- имя пресета, которому сейчас равны настройки вида, иначе "Custom"
function HBV.match(A)
	for _, n in HBV.PRESET_ORDER do
		local p = HBV.PRESETS[n]
		if A.HbvOutMatch == p.match and HBV.near(A.HbvAlpha, p.alpha) and HBV.near(A.HbvFillAlpha, p.fill) and HBV.near(A.HbvThick, p.thick)
			and HBV.nearHSV(A.HbvBodyCol, p.body) and HBV.nearHSV(A.HbvHeadCol, p.head)
			and (p.match or HBV.nearHSV(A.HbvOutCol, p.out)) then
			return n
		end
	end
	return "Custom"
end

-- Внешний вид меню (вкладка Appearance). MenuScale/MenuAlpha/BgAlpha — окно; UIScale — плавающие элементы.
local UICFG = {
	MenuScale = 1, MenuAlpha = 0, BgAlpha = 0, UIScale = 1, Corner = 8,
	Theme = "Dark", Accent = {h = 0, s = 0, v = 0.94},
	-- окно: размер (логические px до UIScale), центр в долях экрана (-1 = по умолчанию: справа по центру), вкладка
	PanelW = 672, PanelH = 448, PanelCX = -1, PanelCY = -1, Tab = "Main",
	BgImage = "", BgImgAlpha = 0.25, BgImgFit = "Crop", CardAlpha = 0.5, -- фон окна: ссылка / ID картинки, прозрачность, режим
	-- Анимации: общий выключатель (CFG.Anim) + эффекты, которые можно гасить по отдельности
	AnimCounters = true, AnimToasts = true, AnimPages = true, AnimPulse = true,
	AnimIntro = true, -- заставка «UNICRASE» после верного ключа (можно пропустить касанием)
	AnimText = true, -- появление текста по буквам при открытии папки (заголовок и названия карточек)
}
local WIN_MIN_W, WIN_MIN_H, WIN_MAX_W, WIN_MAX_H = 440, 320, 900, 700

-- Общая геометрия панели, окна ключа и оверлеев (логические px, до UIScale).
-- Цвета поверхностей задаются только в THEMES; цвета мира / палитр игроков независимы.
local Skin = {Header = 54, Rail = 0.125, RailBase = 88, Tab = 30, Gap = 6, Inset = 14, Row = 56, Radius = 11}
local C = {
	On = Color3.fromRGB(120, 225, 155), Off = Color3.fromRGB(215, 85, 85),
	Danger = Color3.fromRGB(226, 159, 159), DangerBg = Color3.fromRGB(70, 43, 46), B = Color3.new(),
}
local PURE = Color3.new(1, 1, 1)
-- Палитры тем (Dark / Midnight / Amoled / Forest / Crimson). Win всегда равен Dark (тёмный текст на акценте).
local THEMES = {
	Dark = {Win = {14, 14, 16}, Side = {12, 12, 14}, Card = {25, 25, 28}, Input = {30, 30, 34}, Line = {33, 33, 37}, Sel = {36, 36, 40}, Hi = {47, 47, 53}, Mut = {158, 158, 167}, W = {240, 240, 243}},
	Midnight = {Win = {8, 11, 20}, Side = {12, 16, 28}, Card = {18, 24, 40}, Input = {24, 32, 52}, Line = {34, 44, 70}, Sel = {30, 40, 66}, Hi = {48, 62, 96}, Mut = {133, 145, 177}, W = {234, 240, 252}},
	Amoled = {Win = {0, 0, 0}, Side = {6, 6, 7}, Card = {13, 13, 15}, Input = {21, 21, 24}, Line = {31, 31, 35}, Sel = {27, 27, 31}, Hi = {46, 46, 52}, Mut = {136, 136, 144}, W = {244, 244, 246}},
	Forest = {Win = {9, 14, 12}, Side = {12, 19, 16}, Card = {18, 28, 23}, Input = {24, 37, 30}, Line = {34, 52, 43}, Sel = {30, 46, 38}, Hi = {48, 72, 60}, Mut = {135, 157, 144}, W = {236, 245, 239}},
	Crimson = {Win = {14, 9, 10}, Side = {20, 12, 14}, Card = {30, 18, 21}, Input = {40, 24, 28}, Line = {58, 34, 40}, Sel = {52, 30, 36}, Hi = {80, 48, 56}, Mut = {160, 137, 146}, W = {247, 238, 240}},
}
local THEME_ORDER = {"Dark", "Midnight", "Amoled", "Forest", "Crimson"}
GLB.PAL = {"Win", "Side", "Card", "Input", "Line", "Sel", "Hi", "Mut", "W"}
local function applyPalette(name)
	local t = THEMES[name] or THEMES.Dark
	for _, k in GLB.PAL do
		C[k] = Color3.fromRGB(t[k][1], t[k][2], t[k][3])
	end
	C.Dark = C.Win
end
local function applyAccent()
	local a = UICFG.Accent
	C.Acc = Color3.fromHSV(a.h, a.s, a.v)
	-- Контраст не только у бегунка, но и у текста основной кнопки на любом пользовательском акценте.
	local function linear(c) return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
	local lum = 0.2126 * linear(C.Acc.R) + 0.7152 * linear(C.Acc.G) + 0.0722 * linear(C.Acc.B)
	C.AccTx = (lum + 0.05) / 0.05 >= 1.05 / (lum + 0.05) and C.B or PURE
	C.AccHover, C.AccDown = C.Acc:Lerp(C.AccTx, 0.05), C.Acc:Lerp(C.AccTx, 0.1)
end
-- Прозрачность тонкой белой обводки (0 = яркая, 1 = нет):
-- Idle — покой, Hover — наведение/нажатие, Active — выбранное, Soft — информационные плашки
local OUT = {Idle = 0.95, Hover = 0.84, Active = 0.74, Soft = 0.96, Window = 0.89, Focus = 0.5}
-- Окно ключа: затемнение и размытие игры под окном.
GLB.KEY_DIM = 0.50
GLB.KEY_BLUR = 10
-- статусы FPS / пинга: белый = хорошо, приглушённые жёлтый и красный = хуже
local GOOD, MID, BAD = Color3.fromRGB(226, 226, 230), Color3.fromRGB(214, 190, 120), Color3.fromRGB(222, 100, 100)

-- FPS unlocker (нужен executor с setfpscap; 0 = без лимита)
GLB.canFps = type(setfpscap) == "function"
GLB.FPS_STEPS = {60, 90, 120, 144, 240, 0}
local function applyFps()
	if not GLB.canFps then return end
	pcall(setfpscap, CFG.FpsUnlock and CFG.FpsCap or 60)
end
local fast = TweenInfo.new(0.16, Enum.EasingStyle.Quad)
local slow = TweenInfo.new(0.3, Enum.EasingStyle.Quint)
-- Анимационные кривые: все «живые» переходы меню берут их отсюда, чтобы движение было единым
local TWEEN = {
	snap = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	ui = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	pop = TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	spring = TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
	smooth = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
}
local esp, pconn, conns, blur = {}, {}, {}, nil
local npcs, npcConn = {}, {}
local counterLbl, statsFps, statsPing, statsCard, plrHook, statusFn
local statFpsVal, statPingVal -- последние показанные значения FPS/пинга: от них считается анимация цифр
local marks = {} -- [UserId] = "Mark" | "Hide" (только на время сессии)
local pset = {}  -- [tostring(UserId)] = {Name/Hl/Fill/Outline/HP/Dist = "On"|"Off", cols = {Fill/Outline/Name = {h,s,v}}}
GLB.PKEYS = {"Name", "Hl", "Fill", "Outline", "HP", "Dist"}
GLB.PCOLS = {"Fill", "Outline", "Name"}
local fps, lastT, lastStat = 60, os.clock(), 0
local alive = true

-- ===== Сохранение настроек =====
local friendCache, NpcWords = {}, {}
GLB.FILE = "TH_Settings.json"
GLB.canFile = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
GLB.lastSaved = ""
local function serialize() return GLB.HttpService:JSONEncode({CFG = CFG, col = col, pset = pset, AIM = AIMCFG, UI = UICFG}) end
local function saveNow()
	if not GLB.canFile then return end
	local ok, s = pcall(serialize)
	if ok and s ~= GLB.lastSaved then
		GLB.lastSaved = s
		pcall(writefile, GLB.FILE, s)
	end
end
local function deepCopy(t)
	local r = {}
	for k, v in t do r[k] = type(v) == "table" and deepCopy(v) or v end
	return r
end
local DEF = {CFG = deepCopy(CFG), col = deepCopy(col), AIM = deepCopy(AIMCFG), UI = deepCopy(UICFG)}
if GLB.canFile then
	pcall(function()
		if not isfile(GLB.FILE) then return end
		local d = GLB.HttpService:JSONDecode(readfile(GLB.FILE))
		if type(d) ~= "table" then return end
		for k, v in d.CFG or {} do
			if CFG[k] ~= nil and type(CFG[k]) == type(v) then CFG[k] = v end
		end
		for n, t in d.col or {} do
			if col[n] and type(t) == "table" then
				for _, k in {"h", "s", "v"} do
					if type(t[k]) == "number" then col[n][k] = math.clamp(t[k], 0, 1) end
				end
			end
		end
		for id, t in d.pset or {} do
			if type(t) == "table" then
				local e = {}
				for _, k in GLB.PKEYS do
					if t[k] == "On" or t[k] == "Off" then e[k] = t[k] end
				end
				if type(t.cols) == "table" then
					local cc = {}
					for _, n in GLB.PCOLS do
						local c = t.cols[n]
						if type(c) == "table" and type(c.h) == "number" and type(c.s) == "number" and type(c.v) == "number" then
							cc[n] = {h = math.clamp(c.h, 0, 1), s = math.clamp(c.s, 0, 1), v = math.clamp(c.v, 0, 1)}
						end
					end
					if next(cc) then e.cols = cc end
				end
				if next(e) then pset[tostring(id)] = e end
			end
		end
		for k, v in d.AIM or {} do
			if AIMCFG[k] ~= nil and type(AIMCFG[k]) == type(v) then AIMCFG[k] = v end
		end
		for k, v in d.UI or {} do
			if UICFG[k] ~= nil and type(UICFG[k]) == type(v) then UICFG[k] = v end
		end
	end)
end
CFG.On = true
AIMCFG.Enabled = false
if AIMCFG.TargetPart ~= "Torso" and not V4.SLOT[AIMCFG.TargetPart] then AIMCFG.TargetPart = "Head" end
V4.normalizeParts(AIMCFG, true)
if not table.find({"Auto", "Center", "Touch", "Custom", "Crosshair"}, AIMCFG.AimMode) then AIMCFG.AimMode = "Center" end
if not table.find({"Crosshair", "Distance", "Lowest HP"}, AIMCFG.Priority) then AIMCFG.Priority = "Crosshair" end
AIMCFG.AimX = math.clamp(AIMCFG.AimX, 0.02, 0.98)
AIMCFG.AimY = math.clamp(AIMCFG.AimY, 0.02, 0.98)
AIMCFG.CircleX = math.clamp(AIMCFG.CircleX, 0.02, 0.98)
AIMCFG.CircleY = math.clamp(AIMCFG.CircleY, 0.02, 0.98)
AIMCFG.FovR = math.clamp(AIMCFG.FovR, 2, 60)
AIMCFG.FovPx = math.clamp(tonumber(AIMCFG.FovPx) or 240, 40, 1400)
AIMCFG.Smoothness = math.clamp(AIMCFG.Smoothness, 0.01, 1)
AIMCFG.Prediction = math.clamp(AIMCFG.Prediction, 0, 0.6)
AIMCFG.TriggerR = math.clamp(AIMCFG.TriggerR, 0.5, 15)
AIMCFG.LeadBias = math.clamp(AIMCFG.LeadBias, 0, 300)
AIMCFG.MaxDistance = math.clamp(AIMCFG.MaxDistance, 50, 2000)
AIMCFG.Sticky = math.clamp(AIMCFG.Sticky, 0.2, 1)
AIMCFG.RcsStrength = math.clamp(tonumber(AIMCFG.RcsStrength) or 1, 0, 1)
AIMCFG.RcsSmooth = math.clamp(tonumber(AIMCFG.RcsSmooth) or 0.35, 0, 1)
if not table.find({"Linear", "Ease", "Human"}, AIMCFG.SmoothMode) then AIMCFG.SmoothMode = "Linear" end
AIMCFG.SmoothMaxSpeed = math.clamp(tonumber(AIMCFG.SmoothMaxSpeed) or 900, 100, 3600)
AIMCFG.SmoothDeadPx = math.clamp(tonumber(AIMCFG.SmoothDeadPx) or 0.6, 0, 6)
AIMCFG.SmoothCamFollow = math.clamp(tonumber(AIMCFG.SmoothCamFollow) or 65, 0, 100)
AIMCFG.StickTime = math.clamp(tonumber(AIMCFG.StickTime) or 0.25, 0, 2)
AIMCFG.Shake = math.clamp(tonumber(AIMCFG.Shake) or 0, 0, 3)
AIMCFG.LeadMul = math.clamp(tonumber(AIMCFG.LeadMul) or 100, 0, 200)
AIMCFG.SilentR = math.clamp(AIMCFG.SilentR, 2, 60)
AIMCFG.LockR = math.clamp(AIMCFG.LockR, 5, 90)
AIMCFG.TriggerDelay = math.clamp(AIMCFG.TriggerDelay, 0, 0.5)
AIMCFG.HitboxSize = math.clamp(AIMCFG.HitboxSize, 0, HB_BODY_MAX)
AIMCFG.HeadHitboxSize = math.clamp(AIMCFG.HeadHitboxSize, 0, HB_HEAD_MAX)
AIMCFG.StepPx = math.clamp(AIMCFG.StepPx, 0.5, 500)
AIMCFG.CircleThick = math.clamp(AIMCFG.CircleThick, 0.5, 6)
AIMCFG.DynMin = math.clamp(AIMCFG.DynMin, 2, 60)
AIMCFG.DynMax = math.clamp(AIMCFG.DynMax, 2, 60)
AIMCFG.DynNear = math.clamp(AIMCFG.DynNear, 0, 2000)
AIMCFG.DynFar = math.clamp(AIMCFG.DynFar, 5, 2000)
AIMCFG.DynSmooth = math.clamp(AIMCFG.DynSmooth, 0, 0.95)
AIMCFG.AnimSpeed = math.clamp(AIMCFG.AnimSpeed, 0.25, 3)
if not table.find({"Linear", "Smooth"}, AIMCFG.DynMode) then AIMCFG.DynMode = "Smooth" end
if not table.find({"Ring", "Square", "Dot"}, AIMCFG.AnimStyle) then AIMCFG.AnimStyle = "Ring" end
if not table.find(GLB.MODES, CFG.Mode) then CFG.Mode = "Players" end
if not table.find({"Off", "Color", "Hide"}, CFG.FriendMode) then CFG.FriendMode = "Off" end
if not TC.FP[CFG.TcFP] then CFG.TcFP = "Custom" end
if not TC.EP[CFG.TcEP] then CFG.TcEP = "Custom" end
TC.sync()
if not table.find({"Off", "Only", "Hide"}, CFG.NpcFilter) then CFG.NpcFilter = "Off" end
CFG.MaxDist = math.clamp(CFG.MaxDist, 50, DIST_MAX)
CFG.LimitN = math.clamp(math.floor(CFG.LimitN), 1, 31)
CFG.NameSize = math.clamp(CFG.NameSize, 10, 30)
CFG.NameLen = math.clamp(CFG.NameLen, 3, 20)
CFG.Fill = math.clamp(CFG.Fill, 0, 1)
CFG.Outline = math.clamp(CFG.Outline, 0, 1)
if not table.find(GLB.FPS_STEPS, CFG.FpsCap) then CFG.FpsCap = 0 end
if not table.find({60, 30, 20, 10}, CFG.EspHz) then CFG.EspHz = 60 end
AIMCFG.HoldToAim = false -- только сенсорное управление
AIMCFG.FovAlpha = math.clamp(AIMCFG.FovAlpha, 0, 1)
AIMCFG.FovFillAlpha = math.clamp(AIMCFG.FovFillAlpha, 0, 1)
local function cleanHSV(t, d)
	if type(t) ~= "table" or type(t.h) ~= "number" or type(t.s) ~= "number" or type(t.v) ~= "number" then
		return {h = d.h, s = d.s, v = d.v}
	end
	return {h = math.clamp(t.h, 0, 1), s = math.clamp(t.s, 0, 1), v = math.clamp(t.v, 0, 1)}
end
AIMCFG.FovCol = cleanHSV(AIMCFG.FovCol, DEF.AIM.FovCol)
for _, k in HBV.COLKEYS do AIMCFG[k] = cleanHSV(AIMCFG[k], DEF.AIM[k]) end
CFG.MinDist = math.clamp(tonumber(CFG.MinDist) or 0, 0, DIST_MAX)
CFG.MaxDist = math.clamp(tonumber(CFG.MaxDist) or DIST_MAX, 0, DIST_MAX)
if CFG.MaxDist > 0 and CFG.MinDist > CFG.MaxDist then CFG.MinDist = CFG.MaxDist end
AIMCFG.HbvAlpha = math.clamp(AIMCFG.HbvAlpha, 0, 0.95)
AIMCFG.HbvFillAlpha = math.clamp(AIMCFG.HbvFillAlpha, 0, 1)
AIMCFG.HbvThick = math.clamp(AIMCFG.HbvThick, 0, 4)
AIMCFG.HbvDist = math.clamp(AIMCFG.HbvDist, 25, 1000)
AIMCFG.HbvAll = not AIMCFG.HbvOnlyTarget -- режимы показа взаимоисключающие: ровно один включён
UICFG.Accent = cleanHSV(UICFG.Accent, DEF.UI.Accent)
UICFG.MenuScale = math.clamp(UICFG.MenuScale, 0.7, 1.2)
UICFG.MenuAlpha = math.clamp(UICFG.MenuAlpha, 0, 0.6)
UICFG.BgAlpha = math.clamp(UICFG.BgAlpha, 0, 0.8)
UICFG.UIScale = math.clamp(UICFG.UIScale, 0.8, 1.3)
UICFG.Corner = math.clamp(math.floor(UICFG.Corner), 0, 16)
if type(UICFG.BgImage) ~= "string" or #UICFG.BgImage > 600 then UICFG.BgImage = "" end
-- нет файла настроек (writefile) — берём картинку, выбранную в этой сессии (чтобы окно ключа тоже её показало)
if UICFG.BgImage == "" and type(_G.TH_BgImage) == "string" and #_G.TH_BgImage <= 600 then UICFG.BgImage = _G.TH_BgImage end
UICFG.BgImgAlpha = math.clamp(UICFG.BgImgAlpha, 0, 0.95)
UICFG.CardAlpha = math.clamp(UICFG.CardAlpha, 0, 0.9)
if not table.find({"Crop", "Fit", "Stretch"}, UICFG.BgImgFit) then UICFG.BgImgFit = "Crop" end
UICFG.PanelW = math.clamp(math.floor(UICFG.PanelW), WIN_MIN_W, WIN_MAX_W)
UICFG.PanelH = math.clamp(math.floor(UICFG.PanelH), WIN_MIN_H, WIN_MAX_H)
if not (UICFG.PanelCX >= 0 and UICFG.PanelCX <= 1 and UICFG.PanelCY >= 0 and UICFG.PanelCY <= 1) then
	UICFG.PanelCX, UICFG.PanelCY = -1, -1
end
if not THEMES[UICFG.Theme] then UICFG.Theme = "Dark" end
applyPalette(UICFG.Theme)
applyAccent()
local function parseWords()
	NpcWords = {}
	for w in tostring(CFG.NpcText):gmatch("[^,]+") do
		w = w:lower():match("^%s*(.-)%s*$")
		if w ~= "" then table.insert(NpcWords, w) end
	end
end
parseWords()
pcall(function() GLB.lastSaved = serialize() end)

-- ===== Хелперы =====
local function hsv(t) return Color3.fromHSV(t.h, t.s, t.v) end
-- при выключенных анимациях свойства ставятся мгновенно
local function tween(o, i, g)
	if not CFG.Anim then
		for k, v in g do o[k] = v end
		return
	end
	TS:Create(o, i, g):Play()
end
-- Опережающие локали: анимационные хелперы (pulse/popIn/notify) создают элементы и обводки,
-- а фабрики new/rr/outline объявлены ниже — без этих строк обращения ушли бы в глобалы (nil).
local new, rr, outline, gui
-- Пружина: короткий «доезд» с перелётом — так оживают переключатели и кнопки
local function spring(o, goal, info)
	if not CFG.Anim then
		for k, v in goal do o[k] = v end
		return
	end
	TS:Create(o, info or TWEEN.pop, goal):Play()
end
-- Тряска элемента (ошибка ввода, неверный ключ): амплитуда гаснет к концу
local shaking = setmetatable({}, {__mode = "k"})
local function shake(o, amp, times)
	if not CFG.Anim or shaking[o] then return end
	shaking[o] = true
	task.spawn(function()
		local base = o.Position
		for i = 1, times or 5 do
			local k = (times or 5) - i + 1
			local t = TS:Create(o, TweenInfo.new(0.05, Enum.EasingStyle.Sine), {
				Position = U(base.X.Scale, base.X.Offset + (i % 2 == 0 and 1 or -1) * amp * k / (times or 5), base.Y.Scale, base.Y.Offset),
			})
			t:Play()
			t.Completed:Wait()
		end
		o.Position = base
		shaking[o] = nil
	end)
end
-- Мягкая пульсация: элемент «дышит» масштабом, пока pulse(o, nil) не остановит.
-- Так подсвечивается то, на что игроку стоит нажать (кнопка активации, активная вкладка).
-- Состояние анимаций живёт в слабых таблицах, а не в свойствах Instance:
-- Roblox не разрешает записывать неизвестные поля в объекты («X is not a valid member of Frame»).
local pulseState = setmetatable({}, {__mode = "k"})
local function isPulsing(o) return pulseState[o] ~= nil end
local function pulse(o, amp)
	if pulseState[o] == amp then return end
	pulseState[o] = amp or nil
	local sc = o:FindFirstChild("PulseScale")
	if not amp or not (UICFG.AnimPulse and CFG.Anim) then
		-- Не удаляем UIScale: он принадлежит элементу и может использоваться другими эффектами
		-- (у кнопок это масштаб нажатия/наведения). Просто возвращаем его к обычному размеру.
		if sc then tween(sc, TWEEN.ui, {Scale = 1}) end
		return
	end
	sc = sc or new("UIScale", {Name = "PulseScale", Scale = 1}, o)
	local info = TweenInfo.new(0.75, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	task.spawn(function()
		while pulseState[o] == amp and o.Parent and sc.Parent do
			local up = TS:Create(sc, info, {Scale = 1 + amp})
			up:Play()
			up.Completed:Wait()
			if pulseState[o] ~= amp or not sc.Parent then break end
			local down = TS:Create(sc, info, {Scale = 1})
			down:Play()
			down.Completed:Wait()
		end
		if sc.Parent and not pulseState[o] then tween(sc, TWEEN.ui, {Scale = 1}) end
	end)
end
-- Появление «точки включённой функции»: вырастает из нуля, при выключении схлопывается
local function popIn(o, on)
	local sc = o:FindFirstChild("PopScale")
	if not (UICFG.AnimPulse and CFG.Anim) then
		if sc then sc.Scale = 1 end
		return
	end
	sc = sc or new("UIScale", {Name = "PopScale", Scale = 1}, o)
	if on then
		sc.Scale = 0
		spring(sc, {Scale = 1}, TWEEN.pop)
	else
		tween(sc, TWEEN.snap, {Scale = 0})
	end
end
-- Появление текста из частиц: у каждой буквы вспыхивают искры и слетаются к её месту,
-- буква проявляется в момент, когда они долетели. Читается как «текст собирается из пыли».
-- Один твин на искру и на букву, без кадровых циклов; волна идёт слева направо.
-- Ширина букв меряется TextService, поэтому волна ровная и на пропорциональном шрифте.
-- Сам текст никуда не сдвигается: анимируются только прозрачность и масштаб на месте.
local revealers = setmetatable({}, {__mode = "k"})
local function revealText(label, text, opt)
	opt = opt or {}
	local gen = (revealers[label] or 0) + 1
	revealers[label] = gen
	local layer = label:FindFirstChild("Reveal")
	if not (CFG.Anim and UICFG.AnimText) or text == "" then
		label.Text, label.TextTransparency = text, 0
		if layer then layer:Destroy() end
		return
	end
	if layer then layer:Destroy() end
	label.Text = "" -- исходная строка пуста: видно только собирающиеся буквы

	-- utf8.graphemes отдаёт ДВА значения — начало и конец диапазона, а не символ
	local glyphs, total = {}, 0
	local font = label.FontFace
	local size = label.TextSize
	for first, last in utf8.graphemes(text) do
		local ch = string.sub(text, first, last)
		local ok, m = pcall(STS.GetTextSize, STS, ch, size, font, V2(4000, 400))
		local w = math.max(1, (ok and m and m.X) or (size * 0.58))
		table.insert(glyphs, {ch = ch, w = w, x = total})
		total += w
	end

	-- слой ровно по строке: строки идут вплотную друг к другу, и слой побольше залез бы
	-- на соседнюю настройку. Искры рождаются внутри слоя и слетаются к буквам изнутри.
	local pad = math.max(2, math.floor(size * 0.12))
	local h = math.max(12, label.AbsoluteSize.Y)
	layer = new("Frame", {Name = "Reveal", Size = S(1, 1), BackgroundTransparency = 1, Active = false,
		ZIndex = (label.ZIndex or 1) + 1}, label)

	local dur = opt.dur or 0.34        -- сколько летит искра / проявляется буква
	local stepDelay = opt.step or 0.028 -- волна слева направо
	local per = opt.particles or 2      -- искр на букву
	local sparks, items = {}, {}
	local rnd = Random.new(#glyphs * 7 + math.floor(total))

	-- длинную строку не разбираем на буквы: искры летят к её краям, текст проявляется целиком
	local dense = #glyphs > 24

	for i, g in ipairs(glyphs) do
		local cx = g.x + g.w * 0.5
		local cy = h * 0.5
		local delay = dense and (i / #glyphs) * 0.12 or (i - 1) * stepDelay
		if not dense then
			local lbl = new("TextLabel", {Size = O(g.w + 2, h), Position = O(math.floor(g.x), 0),
				BackgroundTransparency = 1, Text = g.ch, TextColor3 = label.TextColor3, FontFace = font,
				TextSize = size, TextXAlignment = XL, TextYAlignment = label.TextYAlignment,
				TextTransparency = 1, TextScaled = false, ZIndex = label.ZIndex + 2, Active = false}, layer)
			local sc = new("UIScale", {Scale = 1.22}, lbl)
			table.insert(items, {lbl = lbl, sc = sc, delay = delay})
		end
		if not dense or i % 3 == 1 then
			for k = 1, (dense and 2 or per) do
				local s = rnd:NextNumber(2, 3.4)
				-- искра рождается прямо в контуре буквы: разлёт — доли её ширины и высоты,
				-- поэтому частицы вспыхивают на самом тексте, а не влетают сбоку
				local a = rnd:NextNumber(0, math.pi * 2)
				local rx = math.max(2, g.w * 0.46)
				local ry = math.max(2, math.min(h * 0.46, size * 0.55))
				local dist = rnd:NextNumber(0.25, 1)
				-- искра-«звезда»: светлый блик по диагонали, вращается, слегка пульсирует
				local spark = new("Frame", {Name = "Spark", Size = O(s, s), AnchorPoint = V2(0.5, 0.5),
					BackgroundColor3 = C.W, BackgroundTransparency = 0.05,
					ZIndex = label.ZIndex + 3, Active = false,
					Position = O(cx + math.cos(a) * rx * dist, cy + math.sin(a) * ry * dist)}, layer)
				rr(spark, math.ceil(s))
				new("UIGradient", {Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(226, 232, 244)),
					ColorSequenceKeypoint.new(1, (k % 2 == 0) and C.AccTx or Color3.fromRGB(160, 168, 182)),
				}), Rotation = rnd:NextInteger(0, 180)}, spark)
				-- тонкий ореол: свечение вокруг искры
				local halo2 = new("Frame", {Name = "SparkGlow", Size = O(s * 2.4, s * 2.4), AnchorPoint = V2(0.5, 0.5),
					Position = O(s * 0.5, s * 0.5), BackgroundColor3 = C.W, BackgroundTransparency = 0.6,
					ZIndex = label.ZIndex + 2, Active = false}, spark)
				rr(halo2, math.ceil(s))
				table.insert(sparks, {f = spark, g = spark:FindFirstChildOfClass("UIGradient"),
					x = cx, y = cy, delay = delay + (k - 1) * 0.02, size = s,
					spin = rnd:NextInteger(-540, 540),
					dur = dur * rnd:NextNumber(0.8, 1.15)})
			end
		end
	end

	task.spawn(function()
		-- искры: летят к центру буквы, по дороге уменьшаются и гаснут
		for _, sp in sparks do
			if revealers[label] ~= gen then return end
			task.delay(sp.delay, function()
				if revealers[label] ~= gen or not sp.f.Parent then return end
				local info = TweenInfo.new(sp.dur, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
				tween(sp.f, info, {Position = O(sp.x, sp.y), BackgroundTransparency = 0.85,
					Size = O(math.max(1, sp.size * 0.4), math.max(1, sp.size * 0.4)), Rotation = sp.spin})
				-- блик пробегает по искре, пока она летит: градиент поворачивается
				if sp.g then tween(sp.g, info, {Rotation = sp.g.Rotation + 240}) end
				task.delay(sp.dur, function() if sp.f.Parent then sp.f:Destroy() end end)
			end)
		end
		-- буквы: проявляются, когда искры почти долетели; масштаб «садится» с 1.22 до 1
		for _, it in items do
			if revealers[label] ~= gen then return end
			task.delay(it.delay + dur * 0.45, function()
				if revealers[label] ~= gen or not it.lbl.Parent then return end
				tween(it.lbl, TweenInfo.new(dur * 0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {TextTransparency = 0})
				spring(it.sc, {Scale = 1}, TWEEN.pop)
			end)
		end
		local wave = dense and 0.12 or math.max(0, #items - 1) * stepDelay
		local wait = wave + dur * 1.3 + 0.12
		task.wait(wait)
		if revealers[label] ~= gen then return end
		-- финал: возвращаем обычный текст (цвета темы и обрезка работают как раньше)
		label.Text, label.TextTransparency = text, 0
		if layer.Parent then layer:Destroy() end
		if opt.onDone then opt.onDone() end
	end)
	return function() return revealers[label] == gen end
end
-- Анимация цифры: значение «доезжает» до нового числа, а не прыгает
local counters = setmetatable({}, {__mode = "k"})
local function animateNumber(label, from, to, fmt, dur)
	if not (UICFG.AnimCounters and CFG.Anim) or math.abs(to - from) < 1e-6 then
		label.Text = fmt(to)
		return
	end
	local gen = (counters[label] or 0) + 1
	counters[label] = gen
	local t0 = os.clock()
	task.spawn(function()
		while true do
			local k = math.clamp((os.clock() - t0) / (dur or 0.28), 0, 1)
			if counters[label] ~= gen then return end -- значение поменяли снова: старая анимация уступает
			local e = 1 - (1 - k) ^ 3
			label.Text = fmt(from + (to - from) * e)
			if k >= 1 then return end
			task.wait()
		end
	end)
end
-- Всплывающее уведомление в углу экрана (вместо системных Roblox-плашек): появление с пружиной
local toastLayer
function notify(title, text, danger)
	if not (UICFG.AnimToasts and CFG.Anim) then return end
	local host = gui
	if not host then return end
	if not (toastLayer and toastLayer.Parent) then
		toastLayer = new("Frame", {Name = "Toasts", Size = O(320, 1), AnchorPoint = V2(1, 0), Position = U(1, -14, 0, 86),
			BackgroundTransparency = 1, ZIndex = 60}, host)
		new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right}, toastLayer)
	end
	local card = new("Frame", {Size = U(1, 0, 0, 46), BackgroundColor3 = danger and C.DangerBg or C.Card, BackgroundTransparency = 1, ZIndex = 60}, toastLayer)
	-- новая карточка «подъезжает» снизу и мягко толкает старые вверх
	card.Position = O(0, 10)
	tween(card, TWEEN.ui, {Position = O(0, 0)})
	rr(card, 9)
	outline(card, OUT.Soft)
	new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 6)}, card)
	new("TextLabel", {Size = U(1, 0, 0, 14), BackgroundTransparency = 1, Text = title, TextColor3 = danger and C.Danger or C.W,
		FontFace = GB, TextSize = 12, TextXAlignment = XL, TextTransparency = 1, ZIndex = 61}, card)
	local body = new("TextLabel", {Size = U(1, 0, 0, 16), Position = O(0, 20), BackgroundTransparency = 1, Text = text or "",
		TextColor3 = C.Mut, FontFace = GM, TextSize = 11, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd,
		TextTransparency = 1, ZIndex = 61}, card)
	local sc = new("UIScale", {Scale = 0.9}, card)
	-- появление: прозрачность + лёгкий масштаб, затем уход
	tween(card, TWEEN.pop, {BackgroundTransparency = 0.05})
	tween(sc, TWEEN.pop, {Scale = 1})
	local kids = card:GetDescendants()
	for _, d in kids do if d:IsA("TextLabel") then tween(d, TWEEN.ui, {TextTransparency = 0}) end end
	task.delay(2.6, function()
		if not card.Parent then return end
		tween(card, TWEEN.ui, {BackgroundTransparency = 1, Position = O(0, -6)})
		for _, d in card:GetDescendants() do if d:IsA("TextLabel") then tween(d, TWEEN.ui, {TextTransparency = 1}) end end
		tween(sc, TWEEN.ui, {Scale = 0.92})
		task.delay(0.3, function() if card.Parent then card:Destroy() end end)
	end)
	return card, body
end
-- свойства сразу (anim = false) или плавно (anim = true)
local function put(o, g, anim)
	if anim then
		tween(o, fast, g)
	else
		for k, v in g do o[k] = v end
	end
end
-- карточки / поля / кнопки меню регистрируются, чтобы фон-картинка просвечивала сквозь них (Appearance > Card Transparency)
local glass, glassNow = setmetatable({}, {__mode = "k"}), 0
function new(class, props, parent)
	local o = Instance.new(class)
	if o:IsA("GuiObject") then o.BorderSizePixel = 0 end
	for k, v in props do
		-- UIOffset у UIGradient ограничен диапазоном [-1, 1]: всё, что больше, падает с ошибкой
		if k == "Offset" and typeof(v) == "Vector2" then
			v = V2(math.clamp(v.X, -1, 1), math.clamp(v.Y, -1, 1))
		end
		o[k] = v
	end
	if props.BackgroundTransparency == nil and (class == "Frame" or class == "TextButton" or class == "TextBox") then
		local bc = props.BackgroundColor3
		if bc ~= nil and (bc == C.Card or bc == C.Input or bc == C.Sel) then
			glass[o] = true
			if glassNow > 0 then o.BackgroundTransparency = glassNow end
		end
	end
	o.Parent = parent
	return o
end
local function round(o, r) return new("UICorner", {CornerRadius = UDim.new(0, r)}, o) end
-- реестры для живой настройки вида: скругления, акцентные элементы, плавающие элементы (UI Scale)
GLB.corners = setmetatable({}, {__mode = "k"})
local function cornerPx(r, cap)
	return math.clamp(r + UICFG.Corner - DEF.UI.Corner, 0, cap or math.huge)
end
function rr(o, r, cap)
	local c = round(o, cornerPx(r, cap))
	GLB.corners[c] = {r, cap}
	return c
end
local function applyRadius()
	for c, d in GLB.corners do
		if c.Parent then
			c.CornerRadius = UDim.new(0, cornerPx(d[1], d[2]))
		else
			GLB.corners[c] = nil
		end
	end
end
GLB.accents = setmetatable({}, {__mode = "k"})
local function accent(inst, prop, token)
	token = token or "Acc"
	GLB.accents[inst] = GLB.accents[inst] or {}
	GLB.accents[inst][prop] = token
	inst[prop] = C[token]
	return inst
end
GLB.floatScales = setmetatable({}, {__mode = "k"})
-- цвета палитры хранятся по имени, чтобы смена темы доезжала до hover-состояний
local function nameOf(c)
	if typeof(c) ~= "Color3" then return c end
	for _, k in GLB.PAL do
		if C[k] == c then return k end
	end
	return c
end
local function val(x)
	if type(x) == "string" then return C[x] end
	return x
end
-- Обводка ВСЕГДА по границе элемента (Border). В режиме по умолчанию у TextButton / TextLabel / TextBox
-- UIStroke рисуется вокруг букв, а не по краю кнопки — из-за этого контуры на кнопках не были видны.
local function stroke(o, c, t, w)
	return new("UIStroke", {
		Color = c, Transparency = t, Thickness = w,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Round,
	}, o)
end
-- тонкая белая обводка: единый стиль кнопок, меню и карточек.
-- Возвращает сам UIStroke, поэтому результат можно менять (.Color / .Transparency / .Thickness).
-- ВАЖНО: второй аргумент — ПРОЗРАЧНОСТЬ (число), а не цвет. Цвет обводки всегда PURE.
function outline(o, t) return stroke(o, PURE, t or OUT.Idle, 1) end
local function on(sig, fn) local c = sig:Connect(fn); table.insert(conns, c); return c end
-- Надёжное подключение для кода, которому не видно локальные хелперы других модулей:
-- берём файловый on, при его отсутствии — прямой Connect. Вызов никогда не падает.
local function bind(sig, fn)
	if not (sig and fn) then return nil end
	local ok, c = pcall(function() return on(sig, fn) end)
	if not ok or not c then
		local ok2, c2 = pcall(function() return sig:Connect(fn) end)
		if ok2 then return c2 end
		return nil
	end
	return c
end
local UT = Enum.UserInputType
local function press(i) return i.UserInputType == UT.Touch or i.UserInputType == UT.MouseButton1 end
local function move(i) return i.UserInputType == UT.Touch or i.UserInputType == UT.MouseMovement end

-- Наведение / нажатие: плавно меняется только прозрачность обводки (и при желании цвет фона).
-- Лёгкий эффект без свечения и теней — не просаживает FPS. h.base можно менять (выбранное состояние).
local function hoverable(btn, st, o)
	o = o or {}
	local h = {
		base = o.base or OUT.Idle, hover = o.hover or OUT.Hover, down = o.down or OUT.Active,
		bg = nameOf(o.bg), bgHover = nameOf(o.bgHover), bgDown = nameOf(o.bgDown),
		over = false, pressed = false, locked = false,
	}
	function h.apply()
		if h.locked then return end
		local t = h.pressed and h.down or h.over and h.hover or h.base
		tween(st, fast, {Transparency = t})
		if h.bg then
			tween(btn, fast, {
				BackgroundColor3 = val(h.pressed and (h.bgDown or h.bgHover or h.bg) or h.over and (h.bgHover or h.bg) or h.bg),
			})
		end
	end
	on(btn.MouseEnter, function() h.over = true; h.apply() end)
	on(btn.MouseLeave, function() h.over, h.pressed = false, false; h.apply() end)
	on(btn.InputBegan, function(i) if press(i) then h.pressed = true; h.apply() end end)
	on(btn.InputEnded, function(i) if press(i) then h.pressed = false; h.apply() end end)
	return h
end

-- Кнопки действий, в том числе внутри редактора/диалогов. Primary использует ту же
-- пару акцент/контрастный текст, что инвертированная иконка выбранной папки.
local function button(parent, text, props, opt)
	opt = opt or {}
	props.Text, props.FontFace, props.AutoButtonColor = text, GM, false
	props.TextSize = props.TextSize or 13
	props.TextColor3 = props.TextColor3 or (opt.danger and C.Danger or C.W)
	props.BackgroundColor3 = props.BackgroundColor3 or C.Input
	local b = new("TextButton", props, parent)
	rr(b, 8)
	if opt.primary then
		accent(b, "BackgroundColor3")
		accent(b, "TextColor3", "AccTx")
		b.FontFace = GB
	end
	hoverable(b, outline(b), opt.primary and {bg = "Acc", bgHover = "AccHover", bgDown = "AccDown"} or nil)
	-- нажатие: кнопка чуть «вдавливается» и возвращается пружиной — отклик чувствуется без звука.
	-- UIScale назван PulseScale, чтобы пульсация (pulse) переиспользовала его, а не создавала второй:
	-- при двух UIScale на одном объекте Roblox учитывает только первый.
	local bs = new("UIScale", {Name = "PulseScale", Scale = 1}, b)
	local function pressScale(k, info, hard)
		if isPulsing(b) and not hard then return end -- во время пульсации масштабом владеет она
		tween(bs, info, {Scale = k})
	end
	on(b.InputBegan, function(i) if press(i) then pressScale(0.96, TWEEN.snap, true) end end)
	on(b.InputEnded, function(i) if press(i) then spring(bs, {Scale = 1}, TWEEN.pop) end end)
	on(b.MouseEnter, function() pressScale(1.02, TWEEN.ui) end)
	on(b.MouseLeave, function() if not isPulsing(b) then spring(bs, {Scale = 1}, TWEEN.pop) end end)
	return b
end

function Skin.field(box)
	rr(box, 7)
	local edge = outline(box)
	on(box.Focused, function() tween(edge, fast, {Transparency = OUT.Focus}) end)
	on(box.FocusLost, function() tween(edge, fast, {Transparency = OUT.Idle}) end)
end
local function row(parent, h, pad, order)
	local f = new("Frame", {Size = U(1, 0, 0, h), BackgroundTransparency = 1, LayoutOrder = order or 0}, parent)
	new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, pad), SortOrder = Enum.SortOrder.LayoutOrder}, f)
	return f
end
local function getPing()
	local ok, v = pcall(function() return GLB.Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
	if ok and type(v) == "number" then return v end
	return LP:GetNetworkPing() * 2000
end

-- Переключатель ON / OFF (под палец): ON = дорожка акцентного цвета, бегунок справа; OFF = тёмная дорожка, бегунок слева
local function makeSwitch(parent)
	local track = new("Frame", {Name = "Switch", Size = O(40, 22), BackgroundColor3 = C.Hi, Active = false}, parent)
	round(track, 11)
	local knob = new("Frame", {
		Name = "Thumb", Size = O(16, 16), AnchorPoint = V2(0, 0.5), Position = U(0, 3, 0.5, 0),
		BackgroundColor3 = C.Mut, Active = false,
	}, track)
	round(knob, 8)
	local function paint(enabled, anim)
		put(track, {BackgroundColor3 = enabled and C.Acc or C.Hi}, anim)
		if anim then
			-- бегунок доезжает с перелётом и чуть «сплющивается»: переключатель отзывается на палец
			spring(knob, {Position = enabled and U(1, -19, 0.5, 0) or U(0, 3, 0.5, 0)}, TWEEN.pop)
			tween(knob, TWEEN.snap, {BackgroundColor3 = enabled and C.AccTx or C.Mut})
		else
			knob.Position = enabled and U(1, -19, 0.5, 0) or U(0, 3, 0.5, 0)
			knob.BackgroundColor3 = enabled and C.AccTx or C.Mut
		end
	end
	return track, paint
end

gui = new("ScreenGui", {
	Name = "EnkaisyGui", ResetOnSpawn = false, DisplayOrder = 100,
	IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, LP:WaitForChild("PlayerGui"))
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)

-- Один рисунок для кнопки запуска и обеих шапок. Источник: assets/unicrase-crown.png.
-- Данные вшиты tools/embed_crown.py, чтобы для установки по-прежнему хватало одного Script.
local Brand = {}
-- BEGIN UNICRASE ICON DATA
Brand.side = 144
Brand.rgb = "fefefef4f4f5e3e3e4d0cfd1bebcbeacaaac9d9b9d918f918685877d7b7d7473746a696a6160615857595150514a4a4a4443443d3c3d3737373131312c2c2c2827282423232020201c1c1c1a1a191717171515151313131111110f0f0f0e0d0d0c0c0c0b0b0b0a0a0a090909080808080707070707060606060505050505050404040504040404040403040303030304030303030302020302030202020203020202020201020101010201010102010101010100010000000100000001000000"
Brand.pixels = [=[
rqooooppoooopoprqpttttttmhhfacz~zyy{yyy{{yyyyyzyyyzykfh]\aceda`[Y]XXajhkkkottyyyyyl]ahtyyy~t]_~zyyttttoophb^\YVYQHS~YHOatUGLPN^y~~~~~~~~~~~~~~}l
tpoootrttrooprppptttrtttooskkhm||yy{zyy{zyyyyyyyyytqha[TW`eebbbb^ZUWaeefefgotvvyyseZ`oyr~~^[c~yzyytttroohc_[YWSSLTkaXTcedPOOOf~{~~~~~~~~~~~~~oeg
tpoorronollkkooolmmkkkiokotokiktyzyyyyyyyvuuttututkca\TRY`cfcbfc`\Z\Z]`c_^chltrvkjioktt~eW[t~yyyyvvtopogb^]ZUEDMSbfW`o~]\f\Y~~y~~{~~~~~~~~~u]_l~
tvhhrokkkkliihhfhir~~~~~~tttoooopt|yyyyyvutrookkkeb^_^XYZ^htohlhf`abYZ^XPV`bfimiffhkh~~TQ\~~yvyyyvppoohb`]WWFAJVejt][^j[]~y~tzz|~{~~{~{y~~a[^x~~
ttkfmkkhfhmt~~~~~oc[VRPLT~kyztoppoyyvvyutqokhffec^]_ac_hc`ehokkfhfe``]\PERY]`efddfkl~^OQk~txyyytutptnfb^^OP[GOPZqkt~ocu\ezttyy{{{{z{{~~~hWXk~~~~
rtogjhi~~~f^XSPNLJIHHHHHP~kv{|uloqrtwupookfeba_][\`ciptkdfefhfebbba^]YUMBMUY\^^`efpzUNW~yrvuytttrppne_^\UOYTSeSScs~fc~Y^~uyyyzzy~{||~~t\X]~~{~{{
ttofjfrUMJIHGFFGGHHHIIKJO~mtzzzytoonlpkhfc`^`ZVW[ekoqoihhhgb`_^]\][[XTMOADQUVY\_ckeTSh~otttutoopooke_\QS\W]PR~yW[yaWVLRryyyyyyyy{|{~~eY[y~{~~~{{
ttrhke~PGGGGGHHHIJJJJKKKNytwz{y|ytlhgeeb`]ZUOQVaooomihecb`][ZYZYYWYZXOHOA@HPSX[]`ZU\~khroprroooomkea]XRYXXlYV~`__obSIOyytyyyyyyyyy~t^\s~~~~~~~z|
ttthhhyVJJIGHIIJJKKKKLLKNkyy{~yyytiec][[ZYVPP^oohhffc`]]\][YUROLLKMOPGFNB@AIOTY_b`~~fcbehkkkkjkkheb_[Wb][abkbUVf~bUKR~tvyywyvyyyyytcf~~y~~~~{zyz
uttkfho]LLKKKKKKKKKKLLLMM^~t{{yyojfe]WSRY_`e~fceea^]^_\VQLIFDDCDFIKMNFLMFB?ELOOLLORV^~~~vb`abbbbac_[W]hPSav\PPSZaLKl~otvvyutryyyvtr|~{{~~|z~ywy~
tttofikfNLLLLLMMNNQPMMMNLV~oyyulhea``XRTflhe_`_]]^_ZSMIGFGIKNQTW[]ZWQJGNJC?FQUVUTPLIGGHMW~~c\[^_c\OPV\Z[VcUMQ[YZ\Xhkhytyvttootvtty{{{{{~~|yytt~~
yttohok}PLMMMMYbo~~oNMNNMT~oytlkfca_cceka]a^\Z[ZUNIHHKNSX^ba_][ZYXVTMGAOID@DPTY^g{~~[RKFCDHQ[ZSROHJQSU]~bMJS_afklyeetttvttomkrtqyyzzz~~~~yuqho~~
yuuthok~SMNMNOk~{yytPNOONR~otkhkfehklicaZSWWXTMHFGKR[fja^^]]^^^][YWQNC@EDHCBQTY\^`acn~~~[NFCDEBBBDLNPVkVGGV`_bfhhgfkopttqmkhhrtvyyyyy{{{yyofbl~~
yyyykol~WMNNNM[~y~y~SNOONPttpkgihoqkfc_]XTQKFDEKS\c`^_bceeccba_][XUPK@@ACIIBLUX\^befhfb^d~~VB???BMLQQSUKITa_cfikkhhkltttokhcaorttyyyyzyyuofcat}y
zyyyoom~\NNNONXytyt~UNOOOOaylrplolhb`]YXVNEACLW^]]^cffhhhhfeca_]ZWSPD??BEILFGVV[]`cgkogyZKLHB@BFHCFUTQSSRVabehkkmhityuooojk\Wtitttvyyyywkhe__yyy
{yyyoorvePOOONU~~~~~WNOOOMY~hoohhea^ZWWPGDGMQWY\`cfhhkkkjifeb_^[YWRNA??BGINLFRVY[^bfkhtYFBBCEFM^UJLOOWYTQZ`bchkkppwyturoohoVQtenorvyyywkkf_Y_~vo
~{{zoltryQOPPOQXWUTQOOOOOMV~ffffb_[XXQHDIRXYYZ]aehjkpttlohea`^]ZXUTG???AIKNQIMWUX\_efo]MGHHIMN_^R]~YQTQSV\^aehkottwytvhfhekRMhbhkrtxyylkj^Z[whht
{~~{tlto~TPPPPOMONOOOPPPPNS~ceea]YXSIDGRYY[]_a`cehlorttoof`a_][YWTRB?@?@JMPSOIUTWY[_b^SNLNLMOKS^SRUVQSFFV`\_ehkopovutohhf`cOIb^ehkoptokkcaaycb|~
~~z{ykto~WPQQQQRQQQQQQQPPORqbb`[XUMDEOYXY^bcdfhhlikkttoooea^[[ZWUTK?@A?AKOSTSIPVVSSY^TPOPRMMNKJQZWTPRWVMGM_a_efkkotrokhe`\^KE[[befhkkhheebe_h~~~
~y{~yfto~\QRRRRQQQRRRRQQQOQc`^[WSFCKYZYX]bdfhnroecachqoohcb][ZYWRRD?B@?AMQSXVLKSQLMRROTQUSQSQPSWMTUOZ[Y]UMKUh_chklpojfc`\X^GBXZ\`bekkffh^]_t~{~~
~~~~yott~eRRSSRRRRRRQQQPQQQ^]XYMCER[Y\^WYacfkoto__^`afhffca^[YWVPM@AB??ANST[[SISPOPQQPSUWUYYUTXWUbbe]YYVYcTKRfaeggkhfea]XRMB?IQV]ac`afv]]f~{y~~~
{~~{ztqytoTSSSSRSSSTUVY[]``]XUKCHW[[^_`VU^_cgmkgc__cbcdefca][YWQOF?DA??AOSXZ^YJLLORVUPRVXZ^YVUST`deb][VQSW__OPecbeeb\SPKFC????AEIMQVboX]~~tuy~{z
{~~~zuryt~WTVWX[^bjt~~uoga]WVHDP[Y^abb_YJS`^bckfb`acccefec`^\WYIHBDD?@?AQUXZaXJGMORUVUWY[a^]XUWX_aha[YQGMV\`wTP]cbeea^[WSNHA?EMRVY^ccW]~hoyyyz~{
~~z|{}wyy{fel~~fj~vrokhea]WVGFVZZ^bffe^_IFUaWZc``acffcehhb_^]YSEEBFBA@@BRXX[ZRNGKPTUXZYX]abaZ\]ZY[\[ZYHAOY]a`~WQ]ebeeeca_Y_GBVZ]acff^ky`gvvyyy~~
~~z|~{yyyty~~XRXkttpokhc^ZPEIZ[]`cghhf`]NBHRTTUZ]acfhhkhgea^[`MFCCDBB@BCR[YZZLQLHOUUV[Z\c]elbheYVUWOPPBBT[`bbc~[R\cbeecb_[_KD[Z^aeeh~][kytvyyy|~
~~~~~{ytr~~VLMYyvtttoie_[UEI][^bcgikhf`]PAGPLLQW[`cfjklkkec^]YGC@CABBCFDWa\WVMNSMGPUY\^]]^kttkeaSPPHIK@DY[_cdhey]R[ebfeea^cNHc]acekeRVtsptttvu|~
~~~~zyx~~XMIR~~vyyytlhb]WGL_[_bcfklkkf`]ODCUUKMU[\_eikookhcc]KA?@@@CEFHG[a[UPGKUPCG^Y^c]Wajtooh^RNKKWG@G\\cfeekfw\Q\eceec`eRLe^abebRVthhmsstttyy
~~{z~~~[JIQ~~y|~~{wojc]\HMc\`_bfkkookh][OM@FqZNPWX\acekolhhZNF?@BDBCGIIJ^k[VNMXXPJBLa[a]Zackq][_QKO~OAEL^]bhkffket]R]aaccafUOc^beb^`tcfffhkottxy
~y~~tZMLNY~yt{zzz{toh__KNh]baZbe\b^fkf[[OYDAI~`ONX[`bceoohhQPNENIGGCGIIHZa[ZW_f[`pVKW^`beb]^^RSSMR~TBBMMUZeehkhhkekZT``abbcWS`a\U_``_`bbccfhooty
~~o]SLLX~~vzy{yyywokacPPl^cc`ce_UVUZkbbNK~IABIudOP[]`ehloo_[fXMT[HLIFIFG[XU]]hZc~aet\^ahfc]\WSNJS~SDAIULPPT_khhh_a_eZT_^``_[Y^VOS][[[\]^^`acfksy
`XRRROT~mt||zyyyytldbURlaee]bdb[STUV]WSML~O@ACJb~SPY_cefhhe^fcSVlMMLFIEKTRUchc`~hUa]]]bjhca\VKFPfRDCAQWJNPU`pZ[TNXhfWJM[\]]][TPRVVVVVVWXY\]_bekq
SRNMST_yryzzzzyutofcZSfefh`ab`a[WWVXWUMMMeYA@BCG]oYW]^acfffdkvSY~PJJGIMPUW[cr``~a[~ecacf`]a[OFIWLDDBD`XKOSW^ybYPJKRTPMKQ`\WRPPSRQRQQRTUWWWWZ]afl
SQNOS[yyy~{yyztttne`Tahfh]b`f_\[YTSWSRPPM[kDADDPe`~~]\^`bkhfyhQ]~OHHIKPCV[]`h]_~_V~kecee^^[TWUXUCCCBG~UMQRVXU]SKMJMQTTNIKMPONMJGEDCCDDEGKOUXX]bh
OQQZi~~}{~yyyyttmfhY]ohka_a^PX]VWSQTTTTSNV~IDFL~b_yk_^^_kYWo~TSlcJHGKTBBYX\^b^Y~hRi~mffcfWRY~~orWFDDM~TPTTQNNOMLQPQTSOJIGHGDB@????@@ABB@?ACJUY]c
NWk~~|~~|yyyyvtohk\[yhke_`]`QDJSSRRUUVVWLQ~NEGNyeh~mfdZUSRb~ZPa~SFHHOI?DUX\[^bUf~WT~yobfUS`eh{khoLGFTbURVTSPPNOPRSSQQNKFBA@BDGJMPPPMHGIHECA?DTY^
h~~y{~|zyyyyytoiffYhkoh[\\^\fMBDHRSRUWWZMV~QGJJbtYY~~yc[W~~[R`fhGGHLO@AUSVRZZ^US~zSW~zfUScbl~]\t[MLG_VQRWVUSPPQQLPSNHCABEJPW]^]][\]\[LGIJIEA?EXZ
~{~~~~z{|yyyytthfaepkk^\^_`^Z\LEGEOQSXYZc`tUIMHM~ZRS]k~~~t_Xf~~JHKGQB@M~_PTSWVYRZ~tW[y~k~t~tWR^~PLMKu^PTZWUQPOKFIOFCCGOW`^\[ZZ[[[[[YYSHHJLGD?@P[
~~{z~~zz|yyxthb]Xaokoeadccb_]XZGIPEQXVZ\hiyXLOMGJeTPPT]`__^t~]JIJHQG@H~c~UGMSRV^QX~~effyrcWSR\~QFNSN~gWWYTPPLFECFCFO\o`\[[\]^^^]]\[Y\OFHKLKGA?N\
~{{~~{zzyyytr`XUSa`fojjeffc`^[XWDJUPaf^^ya`VMRMIAFOMPTVX]f~`OHIIFKhLDG[t[INR]ZWXXOSh~~oeb_WQQWLCJUTQ~acWURULFKCELTmc]\]^^^^]_^]]\ZXWXGFIKLLHDAS\
~~|zzyz{yyuttt~c\~lolokghfeb_^YYUBI\Wl~t~WcRNSLIC?AEKNOQQMIEEFFEKMQ~HEM~HJU]~^VUVWRORZt~~_WRLCBHOVVTcZ~[Ze^RSEL^^\[]____^^_]\^]\YWUXIEHHJNLHDF[]
~~~~{yyyvvuvtolcbrpomonkhghca_[W_L@I^b[y^S~MSSPHE????@AA@@ABCBDGJLP\[LGGLSWzfWVTTRRSNMKLNKJHGDEMR[[TaTy~~h\TEIbXZ]`a_`a`_^^^[[[YWSPHEHHILQJFGX[b
{~~~{yyyyyyyttokktnmomokghieda^[WtDAJYaXS_TM\UTGE@????????@@ACFLPV`a~TCCTU~~y_YUQPOOMIEGGJMPNHFOX\bS^UYeX_RGF[[]Y^ecbbb`^^[]\XXVSGCDHGHMOOIHYc^f
{~~z{yyyyyvtttotttooojkkffhfeea^X[T@DLUh^]KZ]WSIC@?????????@BDINORRUY~JCWd`ZY[\YTRNIGCFJLPQNMIKR```XSbOUaRIDQb[`]_cfecba^]XUXTSTI?CFGGKOMKK[m`ck
~~~{{yzwuuotytottqookqhheceffeb_^R~F?MPRVKSf^YRLD@????????ACEINPQSTV\hhK_~]VRPNKJHFDBBKMNPONOLNYab_eRYYhQLDHpW_beaafeba^\YVNPQQJCBDEGJMKINcoeefo
~~{z{yzttrtlffmttooij]ef^bceffcbhTVWACWSPOW]^ZSOF@??@?@ADJPUTTSRRT[^b]|~vgpth`YRNIECAACEJNRSSPP^cfb_XMQNQHBT\[feceacb`^\YVTMHJECCBBDIKJIToya]fho
~zzzyyytttk`[Xfoolkhf\acU\bceeccc\RtFAJYUMT[a`SLFDFECCDFEEFEEHJMQSUWZQQ[T]_bcfhtqpbZRMHECBDINMP~he`^QIGOPBGfYcfhec`_^][YVSPHB@@A@@DIHGN[~~WT`kot
{yyyyyytvtffe^ejokjece^]OV^`ccdecgY]PFDPTCJWVPKMQRMEBA@???@BEILPSUWWUXMIWccovto_XWWUSWWQQNJIHGLT]o_YJCI]GBQ]]khfea^[ZXWTRQHA??@?@CEFJTf~[NRcfkry
~~~~~yyythfeYafeohfdb`^^JTa`bbcffffbVMJDWIESSRTQKFA????????BEFIKLNOONMKLUTXYXXWWYVTUWULJLKORRPPPRVVPCCVQEIX]ckifc^[YVTRPMFA?????BDGQ]eaNIRkchoy{
UNU__~vvkcPHHO[khk_V\VPIAFORYacheffb_KWDFSXhc_PKGDB?????@BDHKOQTX]_`a`^^bbb]YTROLJJJGBGJJNLKQ]T[[WVI@OTONH]afhge`]YUROJFB???@??@EOZZ[OEI\obiot{{
PJJHPhy~~ZPEHT]oh`^Y][UQDKUW\abcefkehNMKG~TWb[JLGBB??@DKRYh~~~~~~~~~~~~~~~~~~~~~f\WPKFFFILLORTSXaa]aMUGTHLhbfec`]YTRKCA???@A@?BLX[]QDBMzabhmrw{~
OSPLM]hYYWOGHOU]~QQe]^^fMV`^__afoa^ca[HHTOLa^VPJEEHIEIRY]^`ccfhotvvz{{{~|~||yvtt~~~~~~`WOKILJOZQeoXS~OBNE[^ccb_[WTQHA???@AAADKOV`REAEWh]cimquy{~
NSTJFQRMKPGFJNOUQLLUZZ^\RW[[]cbZUW]a^uKBLDJ^^RMLSa[URTVZ^ek{~~~~~~~~~~{y|~z{~~{yyvtpkhv~~~`RKKTWkkjRTTGINe_b`^ZVUOE@??@AABGOWY[QFBDMf^^chortvy|~
\YQFHLPHDFJMPLHIJPOQV[\YUW[]XTSU[cb]]]XHEDIUTU\~r_][]cuye`^]]^][[[^eu~}y~~{{zytttttwzyytloo~~YRSYk_VONGGa]`_[YYTJB??@@@CHQ[`[QGCGSd_[]ehkorvyy~~
^SOOOVRHHMNPTOMKMRRWWXVVWWROPU^fc]]YUXfKDAET]~lb`[XTPMKJJKNOPSTUWY]fuz{yy{{yurroikor{{z}~~yfbv~cVTTPKMIRb^\[]UKC@???@CKT]bZQIHKN_^[]_Uehkptwxy~~
TOOPUWYQMUVWWSRQNNPTVRSQLJNWkob][[TNQW[QDBO~pjchaYVUTTUX[_g~~~~~~~~{ywwywtutolkepthovyz~~{~ofiet~bPEIJK~Z^^ULDA@??AEMX^^YRLLR^\OXaaacefhkoooxy{~
`XSRTVRRPOW[ZZURQQOLJGEFMY~~c]ZWVUOCEXW\DO~ceitlmtifpt~ytoggklotttttutrptttoofefSSmiowy{zzz~~yymfe~OFFRbaVKECBA@BHR^^\XTQRYhb[\YWabccbccdfioty|~
tebZPNKMRTY][^WSRQPHAAHVlphXWUVURPCAFYY[M^eyb^bcb_]W^^_ffeoihrtttrqlkihjrpojee^QMQbhotwyyytmuphefc_~NFtVMGGECBDM[h`[XUUW`ja]^^^XV```__`___bjpx|~
~|fRQJLMNRUWRSRTQKIIKKL[[ZNOUXXTJF@DKb]\[^a\fc`_]_OO[U]hceUYokottomgcbtkfhcef\TOP[[hgmotwrqol^]c__aZSMPKIHEDKTyy_[\WTXjkcaba_]YUR[`^ZWUSTXX^tv{~
~~_SZRSNOQTQPSOMMR^_QB@Rz_QPX[YRBBDBEQ^_]_aZV[b^ZRCDPP`a`WQRuhkjhhc`h]RQ^e~\URLHJVXkfckklrrfc^`ZVX\eQPMHHIO_~o^^`bZTV]cefea_\\XNTTUTUSQMJGM`otz~
~~bXZYYVVVUUSQQXZPHD@??CQtcUWU]HCCBBEUWa^hhcWT]_QCACGQ[[]LLP_hhfeba]OIPS^]OOQHEGHMKQWccefffh]RIKPT~KPQSOVu~h``ah`UTV~~fdfffa^VHDLOPOKHDA@FW]kw{~
fhZTX[\ZYXYZW]~cPE??@???E~`\UWWCBACBM~oX_fjxtb\^LBCCDHN~NBNTTtdec`VPLJZfWNPOKJKJIHGNTT]ccf`XQNNQ[iQARWb~~hffbbcWSUHRQLSa[XSQSDCFJIFDCA@@CQ]ekyy~
ZaY[^`^]\\[[XV\hZyC@B??@R[mcU]J@@ABB\^Mb\akkof_[HBBBCQ[L@AM~Wf_`YTSOJF^lXOIGKKIFDCBAFRW\c]XWXX[\~GA?JS[kdcfef\SQNCACBFY~VYRLIFJMIFDDCBACQ~yfoty~
]^[bbba^^^][Y]VWtLAC@??F\[kbWUC@@A?G~OAW\^Zfhe[QBA@@DXF??BBMW]cUTOFDGFRVJFEGHGFCABA@?BLbUVY]`fh~M??ACM`XcbiaVOHDA?AADEMVYKFFHJIGEDEEDEDEOckfpxy{
\bfcbcb^^[[eVQU^`CCBABASWoea[K@??@BQyE@FSWZ`cbUI?@@ALQ??@?BRUTYVKBDJNIMkXHGOKDIGC@?????Kk[otpk]UA?@BACPX\cZTNB???@ADDEDEURFDHFEDBDEHKPYo~hhotyyy
`ephfe^]\XWONWchLCDBDCG]]tf`WD??@?CfRBAAALf]_]RC??@ATtE?@DT~akVHHJKKJIHVYSfSECG]VIC?????K[]ee_WE?@@@?CMW\XSSB????@?CCAG]~WIEDDEHMU]\avlfcekotyy|
toohhc_]pQKQhy[RDEDCDDS[rlgaO@????HWFAA@@MXc]ZP@???C_xHDR~~c~YECEJJGGIIK~~OBCCAOkTSJA???AU\^cWI@AB@@?BLT[][C?????AHKEKc~t^eFCDEP~~hep{ffcefkvxz~
oomfb^a]ML^~`YRHCFDFEIbbyob|G????@QMA??@BMVkZkH????Hu_UREVly[EEDDJLJEGF]t~F@CCDXtbceB?@?D_Y`XKAAAB@??AMTpXFA@@??EVWNSahxt~RBBCDT~~~~bWbbachquxz~
mhd`[lUIP~pb]QIBCBEIGQ~ttrh\B?@??CPD??@ACGT^^cC???@QeUG@?FfcEACFGKjNDDN~fYB@BBGYg~YC???@KQ^aKAABBCC??@MUTEAA@@AO~k[ykpytk~I@A@F~VOKGEOc`cfortyyz
jc^ZWMHU~ffc^PB@BCFIJhtyyi~M?@A@?HE????ABBRa~R@@@?CbL@???J~HA@CEIYyVBF]z^M@@AAM~lMB????CHVzVD@ABBNF?@?JXQDA@@ACHMVXYcfffe`C?AADFDCCAIk^^cfhkowyy
faZYFGa~fkefXKAABEHIQ~tyyh~E@DB@BMA?@AAAA@K{~IAAA@H~F?@?@ZO@@ABFW]ySFO]nZF?@@ChRE@?@??CBIo[PC@AAD~H?A?IW~N@BCCBBBBDINW\e~Q@?@A@BCDCH_oe^bffkoky~
e\[FH~fehkeaWIBDCGIJ_t|yr~VBBCBAGNBBBBB@A?D~fDBAAAPYA???FcB?ABBQ^u~ROW~aVB?@?DHBA@A?@GFF[cVI@AAAOyKAA@F~t\NGDCCBBA?@AEY[HA@@A@ABDFIPhc\^_acffho|
^oHH~`cfhec^\EDEEJJO~t~~h~JBCCECJLBCDCDA@AAXTCCABC^K?@@AQH?@@?Hhf~~f`~tkP???@A@@AABCMQNXl[SBAA@F~~NDBADJIN[bNFBAA@AA@?CPA?@BCDHNSWpt\X[\]^^_ekty
~MH~_ekkf`][PDFFGKJ[~y~ytcDCDDFDPHCDDDPF@AAMLCCCBG~D?A@BRA?A@AWf~yyy~qa~G?@@AAABBDLWW[ca]`H?AAAJKGFDCCCCCEPtYSPLGA?AAA?AEBCBDQ~~yfc[UUSRSV_bghpy
QItfkkkf`_TXGFFGJJO~t~~o~PCFFFGIYFDDEE]LBCCFHEDEDOUBBA?ENAAC@H~k{oz~h~~TB?@ABABCI~~^oitkUP@?ABCCBCDDDDDDGOXyt`YW^\MBBA?BLCDDETtfltoUQQQRSSNNYtep
J`thkkfc]WPPCHFGJHT~u~voyGFGGHGNUFFEHH~UDDDDGHFEEoJABBBKIBBCBS~tzkb\eWG@@ABBBBCFGKcyo~]KC@?AABCBCDEEEFEN_fkyot~hf~KBBA?BGEFFJa~~~tYPONJHDAES`[bh
a~oomie`\NSHDGEFHHbo~{h~VGIHIJIVMGHKIM~cIFGGGHHFJ~DBCCCPGDDDEfuweZQLHBBE@CEEEDEDFFJ^ZQHA@ABBBCCEGKHGGHFP~t~ky~X^XHCBAB@IFFJHQoYQMJHHGFDDBEP~SQ[e
~tyvohc^UJUDDDEGFN~k~{~fEILJLML[JJJLJW~aNIJGFGIHSYCDEDESFFGFIy~~YLECCEVGBCFGXIFEFIIHYcNDCDCDFOV_h~NGIJJNhyt~[QROGFEBCAGQHILJLKHJKLKKFCEDDLUky[Zf
wyvtke^`LLLCCCFFEWvpoaYHFMLMOKNUIJLLKh~^RJJIHJJHkNDFGEJSJIHJL~ePIHGEEQQDEGGK~_IFHGFEFZVQEEEEJ~~~ktOELLKLZkhVOKIJIFEFEFaLLKNNKLLOMJJFGGFJZ~~~^Y_f
ywtoke^YLUEBACCBDbffZPGIMMLMOJTOJJLHO~~_RKLKJKIJ~JHFJFQQJIJMJOKIKKHDFWMGGKHOyycIFFDDCDZKFEGFWtt~y~VFLKMKXfWPGHKLHHIFF`YJLLKKKJIIHJJHLJGGJSyv[[`c
yytokc_TWTA@@ABCFc~XLGINLKLMLJ]JJIJEY~|kRLKLLLGP`HJGJFfNHKLMMLLLJGEIb`HJJLHY~t~{KDEDA@CHIGFL~p~~{ycFIJJI_kWFEIKKKKII[~PILKKFFFGFFIIIILPTYb~h\]`e
yxtohc]W_J???AFIGJJFHIKHHLLLKOWGIGHIytw~UIJLJKGbPFHIFH~QIMKLMMKJGELy~QGKMJIyy~yr~HBEDCCBGKG[yyyott~JGFGFjXDDFGJMKKQYcvHGMLECDEFINPRSX`h~~~h]^bht
yvtoie]XaI???@DFIGEGHHFFIJJMH^NDGHEP~ty~\NEIJHI~GEGHCM~\ILKKKJIFGRoc~KIIIEP~ty~{h~HCFDCDCNWvv~optt~PDBIVPCACEKJIOV_k~WGJGBBELR]~~_]bhpy~~gY^eeju
yytoke]aTKA@@ABCDHEEEEDFEFLHM~GDEDE`y~vufWIEHESfFECGEX~~RILJJFDJ\oo~_GHEIHY~|~{g_^~HDGEFGEX~keoyuy~\EDMSABECEFIWhk~o~KBCCJV~~~~yo~~~~|e[aZW\ehoU
wwtpjfoHEOHCBBABCCDDCCCBCIHIo[EBCCJ~o{fp~_WFEI~YGGFPJoyy~SKJFFR^`yy~WFEDT\w{f[[\^_buJHIEGHCV~ckuzst~EFKDJTG@DP~~y~yuaDEPo~~yotywy~~~~y^V[bbh`]hS
uttooaKHTlUCBDBBBCBBA@@BEEG_~UDADC[yyfb|yh~NAM~UFHRcQ~t~y~ZTT^ce~~t~SFEM~vy~WRV_bw~yvJHHFFCCXdty~ae~IGQ\~PBFX~ty~~~~[S~~lhtysy~~~f^]`eyypohfRROI
yvtytUQXW_tHACBBAAA@??@BGMWfyQDEFH~k~]fkloyXBR~NFNoh`lvp~ffohamz~~t~JDL~tru`PTf{kYbyoeKGOECDHVZ~{^]~LL~~SEN~~oy~~kf~~~kmkfh{~~]UTTWaotuho^j[PIEE
yy~c[YYUY]oZCCBBA@@???BMUX_k~OCKIQyyh[_\wt~|IZ~JJY~zbiphore^^ct~feohEOpyy~kbe~~y~eV]kocHM]FGGMRW~bX~SQ~TFS~tt~~a^^b~toibftfXQMPT^o~~yty`TR[QJFDC
|y_XVUV[`_c~SCBAB????ERWYoyo~KG^J`~~\[koyckv]k^HZzorh]bk``b]ci^UUVsPG~uy~VPt~tzzy~fTVuv^GWfNFFPRX~WyfcXHV~oz~cTWe_cvifl\OJGKQ[~~~xvyyv~]LMQPOMGG
{~`[UV^jc`_f~TFAABEGDLU\lkt~oHNbQ~rzekytv]Vfh~PK~ehtZRe_befXRNNORW~HRywz^X[ywz~|~vyhPU~~VIf~SFH[R]~t~aP]~o~z[RY~t^\~~`PGDJUy~~ootvyyy~h\QRUTPOHI
~~ojX\yfea\^d]bOO]XQQU^bfxpyVG[h^citwtoog~RTbtLUkf^XQS`^\UQJJKLOWmXN~~mT^~~y~~{~~}yukRV~~QQy~ZIHeWky~ak~u~h\[o~ty`bbQKKRc~~jotuyzlttv~kb_X\WPPKG
yyrcckjjfb^Z^hTRWVXXZ\aeoh]tOK~z_`rkkmkkfo[Qe[P]^YTV\XRNKIEDJOWht^[a~hRY~otz~~{{~{~yvyQU~~Vbt~mJIyky~~~~~k`h~tott_TPQ[~~eemtyt~t][rot~~~fSbYNJFJ
zygfgkkfb`_[Y`nQNWXZ]][aWW\~KT~w`_fhhhefc``VX[SUVQTSMHFFFBCMYqyt`^~~kQW~t~y{~~{{z~z~zt~SU~~v~vz~KJ~t~~~out~~tokot[We~ofkoptyyy~~^etky|v~[MYSGGGN
occfkkfb_\[]\R]fPRW[\USUYX[]IftyhTcfeca_^\ZWURNONLFCCCCDFJXfbeitkp~kRW~o~~z{~~{~z~~{~}v~UX~~~|~t~ML~ztkotyvttkkkht~okotttttttt~YXyos||zjPORLHKIK
`acffca^[X[SHSoe^NPOMOSWX[hSO~huWTkaa^\ZYWUSPFCDBA??@CIQ[e^`fmrtyutTX~t~~{{{~{{~~{~{{~~y~Y]~ttout~NQh_tzutvpoa`ijooptttttrtpop}JP~ft~~~ZSVPJPTKK
_bbbbb^[WSKBL~kluXPORNP[^thRYyhb^a_^\ZXUTQMGC?????@DMY`^]`fjmtwyyy\\~oy~~~zz~{{~~{~~{{~{y~bh{ygf~v~SVlytttrhqXWkhlotuttttrolhzTLRZ]o~o~YRVURPTOM
a`bbca[WSE?L~ek~kYOPPLTqof]Wck_`a^\YWVTPIDA?????AFP\^[]`chkoruyzykk~tyy{~~zz|~~~{{{~~z~~~y~ff{~yht~thyqtookepTShfhmtyopyolkhckQSKO_][WWOR\]YPQPO
^`bcb^YTE?H~aky[QPKLOWyfhc^cb^[^[YWVSKEC@?????AGQZYY[_behjmtttyyttvouutvytyyyzyz{{z~~yyz~~yyoyy~t^bhh~hokgfakOOh`ckompprhhhftbSTLHOQXRLRW\cYRUTT
^`aa`ZYL?BhbekfPMOKKhkaee^_^^X[[ZVPIDBA@????AEOVWWY]_behikoppoooikmltooohkotvtuxwty~yyyz|~~yy|~|yt[ebofgfc`[`KJ^[_chjkkkeefkfQRQLFEIVUQY][]Y[^[Y
^ac`[YPA@L~^c`WROKUyk^]_][]]_a\RKECCDDA???BFMTVVX[\^bcfhhkkjihhhhhhknfpQTkeroooosotxuryyyyyyytWhyyykachfhhc][DD_\_cffgffa^c~SJSOHKILU^][[]_ea\][
aca]YSB@DTb]^VUPQVkca^XZY[^ZRLIFDEFGC@?@CIOTVVYYY\^`bceeeecba`__^`afceTMPYbeheecceefghkpqxyy|t[o~yy~f^he[UOIC??CIOTX`ce_Z]^^MSTLLSQU\_[X]flh`ehc
eb_Y[D?EDOkXWSPMY\[^ae]SNMLHDEFEHKHB?ADKRVWWWYST]^ckot|~~~~~~~~~~~~ht^IKMLeoq~b^~~~~~~~~~~~~~y~~ytttofkf]WRMHA@GMRUY`f`[U\fNIVSKSZX_bhd^fkehkkfe
ea[]I?CHDEQWWRPU[[\VPLKHGIGGFEFKJFDEJNRVVWXYY[STa]ZWWVTRQPNMLJIIGHKTUIFWYHKWTNMLLMOPQSUWY\^achtpmlkolklkfcb^fFE^[a_]^^YWT^WEJQLL[]^^ftz{{lhtrfff
b^[RADJGEA@CFFHHFECCEGJMKHGECFHHIMTYWWWXXXZ[\]_`^]WTSSRPONMKIHFEBCFRODFufFDPQGIFDEFHIKLOQRTUX]fkkkkklkloec_\^KKa[^_]Z[WUX`GDSFFPc`bf~|yu{~|yyhbc
a[ZFDPLFD@????????AFKONJHFBBDHLT_a[YYYXY[[]^^^^`acky~~~~~~~~~~~~by~h|S@IH@Rth~[V~~~~~~~~~~~{tlikkfftkokpkfc_cNNc^`_]VUSUYMCIIDIX_]`~y~~{~zywlee^
^\ODOVNHC@?@@???@DHKMMJFDABIP]ze]]\[[ZY]]^^^_^__beeeffhffeccbaa_bcbf^~M@@N~_ecefcb`_eefhfeeeffedk~~]hhkkqkf`_QSc`b_\SPRURBBDCFVYa`f~{{z{~ythba\N
\[FHWVTE@?????@BFLOPLHEFFM]~~f__`]YXZ]\]_`_```^]ehhklooooookmmolkookf]~CD~^imorotmhkokkhfffecez~bRJFXtfholk]\UT^a_YSQLT^FADCBM^Y`hhcy~~~yoh`_YPJ
\WINWVULEAACDGJNRONLJJOW~~hbdeab_\YU\]]\`aaaa^\[]hhmooroqsooottttttokbyNPydmtuuzykkhhhffheck~yVMGEEDL~bfhph^aZY]^ZVOINYJACBBG^\_hhcftyuttob][RNP
[]TM^XNJEBDIJLJLLLNQZy~yef^^`bbba]YY]]]^`caca][WZkkoorrookooqttuuvvtqookkoptwz~uhhgffhfdf~~]PIFEEFEEF_ffhkeca]Z\[VSHJWM@BB?C[`acohhyyqY^lb\\WQIJ
`_hOLLGDBCFFGHKPT`|~yfkkac[Vhfgcc][WW\]^ab`ba^]Zekkpplookhoosttyyyvtwvroryuy{{keffhfeem~mTKFEEFFFEEEDP~befhfb[Y[UVKGROABAAANb_dhrytohb[Z^][[YKDL
ieebNLIHILMOV^w~~ofoyf^U[ekWU~ehe`\UVY[_]aa``\akhfhkjhhlkoottttvyytyyvzyyyy{~offhgefy~^PIEEFGGFFFFFEDGhbbbhc_ZWUQHDMOB?B@?JY[`eoyyvtc__^`[W[XHHZ
olho^W_etltytfecfty\WZ[[aefo]Ztjfe\VTU^YY`\\ZX]bdcfie^^bkpttowrpttstzyz|y{~~rfgffm~oWMHFFGGGGGGGGGFDDCSo__bb[ZRNGAJPB?A??E]\`cjltttme_teOLPVPGPj
wtpjt[VY[]_accbecWRRYcffcahk~TT~chcWSPRMU\XXV\Y[ce^[Z[`akotoowklturtzyy{}~~offfehaSKHFGHHHGGGHHHHGFEDCI~]]\_]VPE?ENC?@??BRY^cfikpthbf~VFACQVKFSV
zyuwotfa`aba]^`VPPXilfihfb`kryWW~efYPOMPUXVPMUW[`aWVSU`\^koghutvyy{{y{~~~~tffheihLIIIHHHHHIIIHHIJHFEDCDY^\Y]WSI@CMC?@??BPV[achhkphckoMB??GaWIGUJ
|yytwtttog`bfULMWkvhkookkkf^io~RRt]\ONPPOSSRIJTQYSOSOW^a^[b\_vyxyyy{z~~~~thhfiko~PKLJJJJJJJIIKO[XHFEDCBLeYXUYKBCMC????BPXZ`behjkkj~WF@?@H^~WMNSF
yyyuwutmhf~RFGOc}hjoooqtokkbZkoyPMYYYMMPLOOOJHFGONGEN[d[WUY]]qytzzy~{{~~tfhhhkyo~\LLLKKKKKKNUf~~zKGEDCBD[XTRNFJIB????APYY^befikhupPC??AK]fu\TW[R
yyyyypo~wUJDI]~hhmotrrprtoffeXftyNGKXPHMGGLQMHABHFBBITSNQXVYytyyzz{~~{~ohfhhhyyww~PLMLLLKQ^~~yro~SHGEDCALTPLLPLB????AMYY^acfhkko]KA?@DP^_c|k\atp
yyyyo~~TJFIX~kehlortttoorofopcR[|yQBCNLDDEIPJDDHDAACIHHGKX_^tisyyyz{~~rhfkhky{vyt~XMNMMMLR~lq~{uvbIFEDCAESLKaMA????BOWY]`cegkhoZIAACHT]]ct~~eatz
yyyk~VHEKX~uckj`ootvttqoook`khXNWovUB?DDBCEFGH`K@AADLLHBIU]atmrt~~y|kkhihhtv~~vuyykONNMMMNc~yeetk~NFFECBAMPQI@????BNXY]_bejkko^ODFKNV[]e~~~{yhfc
{ut~NBFU~~ejpqlotttvvttpu~[eSYhXKQoc_F?AA@ADT[bD@ADIPPJMOWejmpo|ickthwkfhh~~^h~yyt~UNONNNMW~k^aektYHGEDBAHQC?????ERVY]_behkkkaTLLRTWY^k~~{~{|~yo
w~~JDO~~imtttoktttuttto{tWar\c]UWKMa^`K@?@CS~]VAA@CJVJDMOSbfekocPS~uRMRVkwyVQk}yyu~bPPPPOOQtteehu~~MFEEDCCB?@@?@GZWY]`beekgeg[PFKWXY`y~~~~~~~z~~
~]KJi~ootttttqutttttto~kQZte^_bf]SMJU]^QCI[[Y~J?@BBDFKLDO~ffcocWQJJNIEOZXbaRYm~yyyw~UQQPPPO[yoy~tYRLHHIGB???@?BNWZ]^acehufcf_[LCM]\ay~~~~~~~{~~z
_QU~~iuttttttqtttttur~fOWyf`X[Z^]W\LGQ[Y^fWR~K@@AABA?CIKNRPNZhwZHHJLPMKS`qXb~y~~~yt~]QRRQQPT~~eWQNMLMLFA??@??EU[Z^`bdefcUbbc`^NLY^eheim~~{~~~zu~
cy~mxyutvvttttttttyt~dNV~ek`[\WYZZRNOIM^^b^cM??@@@AABABJKHFGWUPJBEQTRLEMPQYXp~v|zyyytTSSRRQR]UQQONPQKB?AA??ADT[X]`cefghc[bfl]TJNV]~zha]k~{~~tego
~~v{yywyyywtttttttt~`NW~flfefccVROLPRRVhheebND???@?BDCCNOIKLKOGCFNMMJECEKPVWSY~~{xyt~[SSSSSRQQQQQRLD@?AA?@DKJM][\`hhhhecfiYPJC@BK]etb[[\k~yec`\f
{{{zwyyyyyxytuywyt~`OY~folhfhcmVKIKNPTzof`l^[[MD???ABCFNUPLRJNMIMPPLHMKDITX]MUkZoyyyyiUTTSSRQQSTMDA@?A@?BLSPLMZ^^^elfccflQDABA@CM\]ovaa[_ta]]VZP
~{vvyyyyyyyyyvyyu~bR]~cophkhfa]QMQQRakok]hLMV\^\OEA@ABCHPLLQKIKONOQOOSOKFL\fVRMTh~yth~ZUUSQRTRKC@BC@??BIRSRSSWY]_aeocck[IA??EJNSX[]h~pe_^fb[UVKC
{{{{yyyyvyyyyyyvzhWa~_eyptoohkYSPV]pzt{^\TPMKMU^ffRHCBCDFGIGGILMKPTRTSQMKNV~[LKQ]Y\eeybUXWSNGB@CGD??BISUTWYWZ[]^]^]]``OD??@HT]eccfdfyZRV\h`XWLCI
zy{yyyyzyyyxyyt|r^k~]a~tttookca\WY`eik~UZXY_PKMMR[eoYNHEDDEEFGHKKPUTUTRONIHMKOY^[Y\w~~~YNHDA@CIHB?CJSWVYYZ[]^^``^]ZZSGA??BL[a`ckv~yt~MELX^\]QJOz
zzy{yyywwyyyhSoyhp~][~uvttptkobPZ~efh~VTkc`[Te\PLLQV`~y[PJGEEGHJLRONTTSRQLHKOU^b`~~e[RNIDDCEHIEBDMVXWZ^\[]`aabb`__YOD??@ES^YYZ]w~{ytVECLX]\TQX~~
~{yyyyyzyvr~VO~mr~\V{ttttttm~bOWechyhRPba^[cyh`bfWQNNRYe~~^TOLJJMONNRTUONQOOLPVNLMMOPRTOEEGIHFIPYZY]_^^`abccbbbbeXMD@ABJ[YVX[XSV~~mVKGKV_SMQ`~y~
~~{{yyy{{vryMN~k~aUovwttuypt^LTyhkyy[Ta^]VT]bogdaff\UQPQW[f~~~f[TRTRQPQROQNNMLOOTUVYcPLJIJLMQV\[\^bbabccddeeekleXPHFFGPYWWYbk[QS]aZQMOX\LEL^~vz~
{~{yyyyyyq~YLT~ycVh~tyutxvr~KVyrot`bbyea`aW]kmoffobcoh\URSTV[b~~~~~~~xy~~~~~~~~]SNJGIJPXYTY[\]_eeccffghghkttttrZTQPRPUWUX^iy~f[\RNNNRZVIBH^~y~~~
~~{yyyywut{XQS~mR]~ryyuuyo~OLb[ryfa]bfffegchfkolfX^fca]ZX[OOPORQQRVXW][XTRONIFEDGGJJPa~t~c\`fjfefhhhikooyyzytyeXSQY[WVV[boyzz{mfVPPSVRKFKc~v~~~~
~~{~yyvt~~tWNS~\`~tyyyukt~NIS~]qf`[]tkkkgfhkgkk~VR_fha[W[WOVUSQHCEJLJJHHHIIKIKNRZX^~~~tytoookkkllkkkry~{yzzytyaWJKW[VW^puvyzyy~hY\_ZUQPV~~wzz~~~
|{vutvt~aYSPNVZZ~tyuvt~~yPLceTYhXY]yooonkkookkpkXfhkc^[UWOMQQUVMHJQQLMMQYZj~ytw_ckyvpvy{~uomtrtpooyyzzz~yt{~thbOEK]\Yayyyyzy{~oRSht_^at~{y~~~~~~
{{yttt~]PSQOOR]ytywwp~\NQP~~MLY[T]~oqtoookooki{Y^ohhbc_X]SS[SUY]WNONNOQUWXWVX^_al{yy{yy{fytqttwtv{yyyzzvy~t\Y[\MHTk]^t}yyzyyylUILhvft~~y|~~{~~~~
~yyvo~cTUYSTSW~tvywr~YQPYffKKXPS]~tttrqtttrokyaVthjfcfe^bhaaYXWWYORRTZ[_fbZW]ci~~yz~~zyU[~vvyy{{y{yyyyt~~XMNVZULOfh^a_`o~{~yc[SOV~ffy{~~{{~z~{z~
~trt}fW[]^TZ`{yyyyr~TM[eh_HJe~~~~txyvttttttts~T^thfhgfhktofeteXTRMTUW]_^_fahuu~{~~~~z~]Y~yy~{z{{{zzyvy~^OICGWeRHP{ff^TRYl~vaYWW_~fet~{~~{~~~|z~~
wpo~hXZ[Y[UXbpyyyt~WNWc[WJKe~lrrouwyyttyuttt~ZU~fhgihffoolkothcPJMV]`_ccbkkw~~z{{~{~~tb~ywyzzzz~~{yy~qTHCEKTfbPIQ~iwXNPV]k_XVY^a^ak~~||~~~~~zz~~
okykZZZWRVUX\tytt~[Q]c~oQO^]yptvtyvvyttyyyvyyUekhhhhjijoosrtum[PNTY_bcehkt~~~~zz{~y|e]ttttzzz~~~zy~~^NEBDOe~^ULLToz~lWXYWXWVY^]Z^t~~{yz~{~~{{z~~
othZ][ZVSVYXYtyxqyVYb~y~~jW`~uvvtyttuvvvyyt~Y[yffhkkloptttvwy`WTVXX^acfky~~~~~~{{{tt^avry{z{z}~{{~oWJDCHSh`]ZYQQYb~{~yhZTUX[^\[`w~~~~~{y~{~{~{z~
xr[Y][UVTV[W_ytyt~\MQY}oVW[yuuyvttyuuuvyyyycShfhfkkktptutuyytb^c_b_b`fky~~~~~~~~~ttktyoy|{yzyyyzy`TMGGN\bYX^gycZ`k~~{odVRVbc][b~~~~~{~~yz~~~~zz~
m\]][XTYYX\_|vvv~bMMbZ]VTYtyvyyyvvwyyyyy{~~[^tfhkokouvx{y~yyohehlh_ack|~~~~~~~~~wtpotoy~~yzzyz~t\ROONTe\WYax~~yffdba_hZOPW_^_h~|~~~~{~~{{~~~~{~~
^\^e[Y[Y[\]t~vv{]KPV`oTTXwyvyyyyvvvyyyyyy~cZpffhknootuy~~ytyy~wrohcek{z|~~~~~~~tptputy~~~~{~|~{`RNQV]eYUXh~~~~~~l^ZX[XLIRYZ`l~}{~~~~~~~{~~~~~{~~
]=]
Brand.bands = [=[
?~A~BvCkFkG~J~KkLpM~U~VkWWX\YkZc[_\Y]_^~
?~@kB~DcE~F~GcI~L~NcPPQRRZSTT_UNVSW~]~^k
?~@kA~G~HcI_J~K~LvM~S~UcV_WWX_YkZk\_]_^Y
?U@kCkD~E\FZGkH~L~NWOGPNQ~RcS~T_V~[~]c^~
?~AkB\CTENFMHJILJkK~P~RcS\T\UcW~Xk[~]c^N
?G@\BgCkDWEWFkG~I~KkNROTQ~SWTkU~Y~[_]~^~
?~A~CGEGFIGIILJcK~M~Q\RSTkV~WkYV[O\Q]P^J
?BAWC\DkE~G~IkJ~K_LVNcOZP_Q\RPT~X~Zh[~^~
?~A~CLDLGPHMIMJZK~NcPVQcS~TcWNYKZK\Q]L^K
?D@DATBRDPEPFRG\H~I~JUKUL_NUOSP\QUR_S~^~
?~A~BZCMDNEYF~GkHOINK~PkQ\SMTLUNWWZk\\^C
?F@EAWBcD\FPGKHFIDJHKQLYMMNROkQ~T~VkW~^~
?~BcCODNEYG~HQINK~OkPTQJRFTYUkW~Z_\V]D^?
?H@IB_D~E~FPHBIFJIKRLTMQNkQkT~V\W~[~]c^~
?~B~CQDPFTIOJQK~LcMpNWOKPJR\SkW~[Z\P]@^@
?K@OANBYD~EUFHGHI_JVKTLNMRNkT~VQW~Z~\_^~
?~B~CUDQGPHQJPKcLkMNNHP\QpUeW~ZY[Z\F]?^A
?N@WANBRCQDTEQFSHOJULUMONROcT~VIW~Xc\c^~
?~B~DSEUIWK\LKMINWO~PWR~U_WkY_ZY[O\C]@^@
?P@_BLCQFZHVKkLWOSP_RcSWTNUCV@WJXSY\\~^~
?~C~E\FkI~J\KKLNMkOpPUQJRWTcYcZW[E\D]A^A
?S@_BICSDYGcIZKYLHMLN~PVRkT_ULVFWZYk[r^~
?~BpDRF~I_JLKQL~OkPZQDRNSPTZVkYkZI[@\A^F
?Z@WAMBNCIDZH~JNKNLCMQN~PkQWT~VQW~YZ[~^~
?~@~BPDkHkIPK~L_O~P[QIRFSZTRVkX~YWZG\D^I
?\ATBZCMEkGcHZIRJVKJLFMWNcQ~RYTkVWW\Zc^~
?ZAPB_C~GvHWJ~LcMVO\POQTRATWUUWkYc[Y]G^J
?UA~D_G_HLJMKCLQMNNZO~PURYSPTcUjWUXY\k^q
?P@QAcF~H\I~KZL_OTPOQYRESDTZUvV\Y~[\\J^I
?T@kC\D~F_IQJCKGLYMPOUQMRUTKUKVGXD[F]\^k
?Y@~E~G_H~JcKULHMNOWQWRLSKT~V~WZZ_\H]H^C
?XB_DkFWGcI~JJKMLWOPQRSFTDWLYMZG[E\B]D^Z
?~D~F\GkJ_KkMGNPOYQ~SJUVVYW~Y~ZV[I\L]C^V
?W@OAWDkF~HZJMKVLYNRPFRJTYUkY~ZM[J\K]A^M
?~D~F]G~LcMLNKO~Q_SPTCUCVIWMXLZE[H\S]K^P
?NA\CSEZGPHGIHJVLcNVOHQYR~X[YPZG[K\L]E^U
?~H~IkKkL_M\NEOMPkQURTSTTDU?Y?ZD[M\V]_^E
?R@~CPEGFLGNHGJcKWMkNLONP~U[WZXHYE[M\K^~
?~F~JcMcNNODPVQQRbSYTEU@V@WAXCYHZM[R]c^Y
?c@_BPDCEEFLGPHOJ~LTNGO_RcT\UTWHXBZJ\Z^k
?~C~EcHkIZJZKkN\OGPLQLRUSRTLVBXBYD[P\U^P
?Y@kB_DSFHHLJkKMMHNMO~S\TWVAW?XBZR[W\W^~
?SA~B~DMEbH_IJJKK_N~PIRYSSTIUAV?W@ZO\W^U
?\@_CPEHFLJZKHLMMKNWO~RVSKU?WAXMYSZM\_^~
?P@KASBWDHEVGTHbIRJSKcNcOWPIR\TIVHWUX~^~
?~CkGNHOIZJkKZLIMLNcPkQTRDS?T?WPXMYG[~^~
?V@LAOBICJDPEKFMH_JUOcQCRTTkWSXSZZ[Z]~^~
?~F~HYJYLJMVN~OZPJQAR?SCTLUUVQWJXNY\Zk^~
?V@SAUBPD\GNHJILK\M_NKOPPQQJR~S~WWYc[~^~
?~A~C\D~I~J\KILNMcNMOCP@QDROSZUSWWXk[~^~
?~AMDVGMHEITJ\KSLYMKNBOMP_TcUPW~Y\Z~]k^\
?kAYBNCZD~G~I\JkNFOJPVQ~SZV~WYYj[T\U]~^~
?~BUEUFPHAIDJ_LUMCNBP~ScTPUBWkXNZk\k]P^R
?ZAJBIE~GcHQJWKNMSNkP~RSS_UcWHXN[C\P]~^~
?\E_FSGAH?IDJ~KkM@OSQ~S~U@VHWGXAYQ[Z]H^W
?M@HAJCADCEQFkI_JCKCL\NvOVQCRCTVVHZB\~^~
?cDSEcGCHCJ~KXLBM?OJPAQQSUTAU@VOWBZ[\G^N
?RAEBKD?EAFPH~J?K@MkNVOCQ?SFTWVEWFYR[k^~
?pBRDcFDGDIkJ~L?M@NKP?R~T?UBVkWJY~[D\M^M
?~@CABBYC~DDE?G~IAK?MZO?PBQNT~VAWNX~YW^~
?~AMD\ECFBHVJ~L@NCO?QER~T?VJW?XIZ@\`]F^Z
?O@?BZD?E@FNGYHAJHK?MTN@OAQPT~V?WDYEZY^~
?\@KC~EDFEH~JVKCMGNCQARTTAUNVAXJY@ZB[Y^~
?F@?ACC?FcGKH?JYKAMQNMPAR@SITHU@WDYVZc^~
?OA~C_EEGUI~KDMLNDPJQARHSDULV@WDXDY@[~^V
?B@@BCCQE~FRGAHAJELCMFN]O_QJS@TDUCW~\P^~
?\@~B\DFFIG_I\JIMMNGPWQFSGTMVBWHYDZ\[~^D
?B@EBEDcELFAJILIMcP_QMRBSBTHUHWTZG[C]Z^\
?~AkBUDCECG~IKLPNJPcQLSITQVFWMYJZV[O\E^L
?EAWBGCEEPFEGEHVJYKIMYNcOLRDSNVLYHZE\~^_
?~B_D?FKGPHILPNIO_PkQLSKTPUHWQXJYM\I]Y^K
?IA~BVCEDBGNH~JcKILHMVOGQKRTSUTJVEXL\k^c
?~BVD@FFGEJHLMMDO~P~RFSNTLUDWgXLZG\k]V^F
?J@cB~CSDFEDFGG_J~KIMINBPPR~SGTFWkZ~\\^~
?~@~BMCQDBGCIBK_MBNVO~Q~RGSRTKVZX_YP\~^G
?kAVC~DWEIGEH_J~KOLMMQNGOSP~R_SPT~X_\~^M
?~AVC~EAG?HAILJ_KkLHMLN~Q~RUTNU~Z~\_]L^_
?k@\B~C\DcEUGIHJI\JcLYMPNcP_S~URX_Z~\T^E
?~AZDkEJFFHNI~J~LOMcP~RcSTUkWkYOZM[T]V^k
?Z@kC~DWE`FVG_HNINJkLYN~OZQcRZTMVkZ~]Q^J
?~DcFVGgI\JcKQM~NcPkRYTZUTWIXFYJZW[e\k^Y
?~D~EYF\H~IQJSK~M~NkP~RWT~W~XcY~Z~\V]K^I
?cBcDNE_GQHQJ_KSL~MZOjQ[SFUAVCWJY~[~]Z^~
?~E~F_GkI~JUKYL~N~PcQ~T~UkV~WTY~Z~\P]M^M
?cAkBRCDDTE~GMHPIcK\MkOTPKR@S?TCULV\W~^~
?~F~GkH~J~KbL~N~OYP\Q~T~VkWQXNYZZU[T\\^Q
?_A_BCD~EWFMGQHkKkLZMPODP?Q?RCSMT\Uk]~^_
?_@~G~HkLkMcNcOKPNQcSkTcU~WPXHYMZV\_]\^\
?c@~AFBBCZDkESG~IRJQLGMFOBPEQORYWc[X]_^N
?Q@_BZC_G~J~LkM_NQOCPDQTR\ScUWVOWOYZZk^j
?~ADBGCCDFGGHKIKJEKCMMNNP\T]WUZL[H\M]N^J
?J@NAPBJDPFWHcJ~N~OOPQQkSWTZUKVHWMXk]~^k
?Y@IASC?E?FBGIHKIGJEKMLZNcPZQ_TcV~\~]k^F
?F@kE~I~JWKWL~NkOVQkRTSTTNUCVEWVXj\~]c^T
?V@OAWBFCBDEEIFPGQHPJ~LkNYQcS\T\U~Yk]~^Y
?Z@~DkF~G_JEKIL~O\QZRLSPTCUAVNW~Zc\k]V^L
?~@WALBHCJDPF_H~KZLkMdNYOYPbRcS_V~XkY~^~
?~BkD~EYGGHEJFKELUM~O_PXQJRLSCT?V~[k\\^K
?~@~A\CpE~FZGYJkLZM~N\OQPSQZRVTkUcVZX~^~
?~BkEGFFIHKDLJM~O[PFRDS?TCU\Y~ZW[D\N]L^P
?~CkDQEPGkI~LcMUN\OQPOQSSLTSUOVRWkX\Z~^~
?~B~DIGKIVKDLDMWNYPER?SCTVUcX~YLZ@[E\_^N
?~A~CMDNE_F~J~M\NKPIQIRMSDTEUBVJWMY_Z~^~
?kB~DMFNGcI~KELBNROMPCQ?RBSUTdWcXGYA[~^k
?~@ZAJC\D~I~LYMRNYPAQARISUTBUCVNWGXSY~^c
?pCkDPFNGcI~J\KGLCMDNKOAP?QDRUScVkXIZ~^~
?\@OB~H~IZL_NPOYPJQFR_SMT@VHWIXUZ~[R]M^Q
?~@YB~C~EPFPH~JWKLLGMBN?O@Q_TbV~WKXVY~^~
?c@~G~IYJ~MXOLP_Q~RVS@U@VBWIYLZR[F\K]L^G
?RApDcESGRHWJOKHLAM?NAP~Q_U~WGXZY~Z_\~^~
?~F~HYI~L_MMNOOZPkSPTEUAVAWHXOZK[L\P]M^I
?L@_AQC~GUIJK?LANQOQP\S~TQUCVCWFXWY~]Z^M
?~E~GcI~K~MUNcO~QWRPSQTWUSVJWFXFYE\Q]V^Q
?K@PAPBWD~E\GFJBLSM_QcRYT@V\W~Y~ZM\~]P^L
?~C~DWF~G_I~K~LUN~OYPYRcTUUTWZXUYOZM\P^R
?O@LASDUFEILK~M_PkQVRDSBTMUkWVX~ZI[R\P^~
?~C~DQE_F_H~J~KRLZM~O_PkQ\R`S~UcWVZ\[Z^Y
?VAOCLDMESI~KcO~P_QQRNTcVkXRYPZS[I\R]~^~
?~B~DQE\FkIkJTKRL_N_O~S~TZVkXRYPZR[I\L^M
?OAPBRDcE~JkK~O~PQQNRdS_T~V~WZXWY_ZT\~^~
?~A~CSDREcG~ITJWKPM\N~R~T_U~XZZZ[V\P]Q^W
?c@_A~D~FcG~L~McNPOZPNRkS_T~U~VcWPXZY~^~
?~@~A\CWE~F~HUI_JOKWL~R~SZTkY~Zc[O\S]c^k
?kA~D~EcF~K~LPMFNLOZPLQcRcSRT]U_VYXkY~^~
?~BUCVE~F~GUHcIcJYK~Q~R_S_TkV~Y~Z_[V\\^k
?~C~DkE~I~JkLFMPN~OZPSQkR~SdTVUYV\WbX~^~
?_@^AYC\DkE~FYGQH\IWK~Q~R_SkU~Y~Zk[~\c^~
?~H~IbJQKPLZMcNcO~P~QcRcSUTPU_VkW~\~]~^~
]=]
-- END UNICRASE ICON DATA

-- Готовим одну общую текстуру. Запрет Image API или нехватка памяти не должны мешать окну ключа.
function Brand.release()
	if Brand.image then Brand.image:Destroy() end
	Brand.image, Brand.content, Brand.sequences = nil, nil, nil
end

function Brand.texture()
	if Brand.tried then return Brand.content end
	Brand.tried = true
	local ok, content = pcall(function()
		local dims = V2(Brand.side, Brand.side)
		Brand.image = game:GetService("AssetService"):CreateEditableImage({Size = dims})
		if not Brand.image then return nil end
		local rgba = {}
		for hex in Brand.rgb:gmatch("......") do
			local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
			table.insert(rgba, 0xff000000 + b * 65536 + g * 256 + r)
		end
		local pixels, offset = buffer.create(Brand.side * Brand.side * 4), 0
		for row in Brand.pixels:gmatch("%S+") do
			for x = 1, #row do
				buffer.writeu32(pixels, offset, rgba[row:byte(x) - 62])
				offset += 4
			end
		end
		Brand.image:WritePixelsBuffer(V2(0, 0), dims, pixels)
		return Content.fromObject(Brand.image)
	end)
	if ok then Brand.content = content else Brand.release() end
	return Brand.content
end

-- В обычных опубликованных играх Image API может быть выключен. Тогда показываем
-- уменьшенную копию того же PNG статическими полосами, без HTTP и без ассета-заглушки.
function Brand.paintBands(mark)
	if not Brand.sequences then
		local palette = {}
		for hex in Brand.rgb:gmatch("......") do table.insert(palette, Color3.fromHex(hex)) end
		Brand.sequences = {}
		for band in Brand.bands:gmatch("%S+") do
			local keys = {}
			for i = 1, #band, 2 do
				local x, index = band:byte(i, i + 1)
				table.insert(keys, ColorSequenceKeypoint.new((x - 63) / 31, palette[index - 62]))
			end
			table.insert(Brand.sequences, ColorSequence.new(keys))
		end
	end
	local height = #Brand.sequences / 2
	for i, sequence in ipairs(Brand.sequences) do
		local row, half = math.floor((i - 1) / 2), (i - 1) % 2
		-- Нижний край перекрыт следующей строкой: на дробном UIScale не появляются щели.
		local strip = new("Frame", {Position = S(half / 2, row / height), Size = U(0.5, 0, 1 / height, 1),
			BackgroundColor3 = PURE, ZIndex = row + 1, Active = false}, mark)
		new("UIGradient", {Color = sequence}, strip)
	end
end

local function logo(size, parent)
	local props = {Name = "BrandMark", Size = O(size, size), BackgroundColor3 = C.B, Active = false}
	local mark
	local content = Brand.texture()
	if content then
		local image = new("ImageLabel", props)
		if pcall(function() image.ImageContent = content end) then
			image.ScaleType, image.Parent = Enum.ScaleType.Fit, parent
			mark = image
		else
			image:Destroy()
		end
	end
	if not mark then
		mark = new("CanvasGroup", props, parent) -- скругление обрезает весь рисунок, а не только подложку
		Brand.paintBands(mark)
	end
	rr(mark, 7, 9)
	return mark, outline(mark, OUT.Window)
end

-- Штриховые пиктограммы в единой сетке 16×16. path = ломаные, rings = {x,y,диаметр}.
-- Один и тот же знак используется на плитке папки и в заголовке открытой страницы.
Skin.glyphs = {
	Main = {paths = {{8,1, 14,3.5, 13.5,9.5, 11.5,12.5, 8,15, 4.5,12.5, 2.5,9.5, 2,3.5, 8,1}}}, -- щит
	Aim = {rings = {{8,8,14}, {8,8,9}, {8,8,3}}}, -- концентрическая мишень
	Targets = {rings = {{8,8,11}, {8,8,2}}, paths = {{8,1, 8,4}, {8,12, 8,15}, {1,8, 4,8}, {12,8, 15,8}}}, -- прицел с точкой
	Trigger = {paths = {{9,1, 4,9, 8,9, 6,15, 12,7, 8,7, 9,1}}}, -- молния
	Hitbox = {paths = {{3,3, 13,3, 13,13, 3,13, 3,3}}, rings = {{8,8,2.5}}}, -- рамка хитбокса
	FOV = {rings = {{8,8,12}}, paths = {{8,0.5, 8,4}, {8,12, 8,15.5}, {0.5,8, 4,8}, {12,8, 15.5,8}}},
	Color = {paths = {{2,11, 9,4, 12,7, 5,14, 1.5,14.5, 2,11}, {8,3, 13,8}, {10,4, 13,1, 15,3, 12,6}}}, -- пипетка
	Sizes = {paths = {{1,4, 7,4}, {11,4, 15,4}, {1,11, 4,11}, {8,11, 15,11}}, rings = {{9,4,4}, {6,11,4}}},
	Extra = {paths = {{1,3, 15,3}, {3,6.5, 13,6.5}, {5,10, 11,10}, {7,13.5, 9,13.5}}},
	Players = {rings = {{8,5,6}}, paths = {{2,14, 2.5,12, 5,10, 11,10, 13.5,12, 14,14}}},
	Appearance = {paths = {{2,2, 11,2, 14,5, 14,14, 2,14, 2,2}, {5,2, 5,6, 10,6, 10,2}, {5,14, 5,9, 11,9, 11,14}}}, -- конфигурация
	Visual = {paths = {{1,8, 4,8, 6.5,2.5, 9.5,13.5, 12,8, 15,8}}},
	Search = {rings = {{6.5,6.5,9}}, paths = {{10,10, 14,14}}},
	Key = {rings = {{5,5,6}}, paths = {{7,7, 14,14}, {10,10, 12,8}, {12,12, 14,10}}},
	Info = {rings = {{8,8,13}}, paths = {{8,7, 8,11}, {8,4.5, 8,5}}},
	Min = {paths = {{3,9, 13,9}}}, Max = {paths = {{3,3, 13,3, 13,13, 3,13, 3,3}}},
	Restore = {paths = {{3,6, 10,6, 10,13, 3,13, 3,6}, {6,3, 13,3, 13,10}}},
	Close = {paths = {{3,3, 13,13}, {3,13, 13,3}}},
	Star = {paths = {{8,1, 10,6, 15,6.5, 11.5,10, 12.5,15, 8,12.5, 3.5,15, 4.5,10, 1,6.5, 6,6, 8,1}}},
	Next = {paths = {{5.5,3, 10.5,8, 5.5,13}}},
	Up = {paths = {{3,10.5, 8,5.5, 13,10.5}}},
	Down = {paths = {{3,5.5, 8,10.5, 13,5.5}}},
	Right = {paths = {{5.5,3, 10.5,8, 5.5,13}}},
	Left = {paths = {{10.5,3, 5.5,8, 10.5,13}}},
}
local function icon(name, parent, size, color)
	local box = new("Frame", {Name = name .. "Icon", Size = O(size or 16, size or 16), AnchorPoint = V2(0.5, 0.5),
		Position = S(0.5, 0.5), BackgroundTransparency = 1, Active = false}, parent)
	local glyph, ink = Skin.glyphs[name], {}
	color = color or C.Mut
	for _, p in glyph.paths or {} do
		for i = 1, #p - 3, 2 do
			local x, y, dx, dy = p[i], p[i+1], p[i+2] - p[i], p[i+3] - p[i+1]
			local line = new("Frame", {AnchorPoint = V2(0.5, 0.5), Position = S((x + dx/2)/16, (y + dy/2)/16),
				Size = S((math.sqrt(dx*dx + dy*dy) + 0.7)/16, 1.45/16), Rotation = math.deg(math.atan2(dy, dx)),
				BackgroundColor3 = color, Active = false}, box)
			ink[line] = "BackgroundColor3"
		end
	end
	for _, r in glyph.rings or {} do
		local ring = new("Frame", {Size = S(r[3]/16, r[3]/16), AnchorPoint = V2(0.5, 0.5), Position = S(r[1]/16, r[2]/16),
			BackgroundTransparency = 1, Active = false}, box)
		round(ring, 32)
		ink[stroke(ring, color, 0, 1.4)] = "Color"
	end
	local last = color
	return box, function(c, anim)
		if anim and c == last then return end
		last = c
		for obj, prop in ink do put(obj, {[prop] = c}, anim) end
	end
end

-- Кнопка с пиктограммой на обычной поверхности (стрелки, приоритет, переход к игроку).
function Skin.iconAction(parent, glyph, rotation, props)
	local b = button(parent, "", props)
	local mark, paint = icon(glyph, b, 14, C.W)
	mark.Rotation = rotation
	return b, paint
end

function Skin.iconButton(parent, name, right)
	local b = new("TextButton", {Name = name, Size = O(30, 34), AnchorPoint = V2(1, 0.5), Position = U(1, -right, 0.5, 0),
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false}, parent)
	rr(b, 6)
	hoverable(b, outline(b, 1), {base = 1})
	local glyph = icon(name, b, 14)
	-- иконка отзывается на палец: растёт под курсором и коротко сжимается при нажатии
	local gs = new("UIScale", {Scale = 1}, glyph)
	on(b.MouseEnter, function() tween(gs, TWEEN.ui, {Scale = 1.12}) end)
	on(b.MouseLeave, function() spring(gs, {Scale = 1}, TWEEN.pop) end)
	on(b.InputBegan, function(i) if press(i) then tween(gs, TWEEN.snap, {Scale = 0.9}) end end)
	on(b.InputEnded, function(i) if press(i) then spring(gs, {Scale = 1}, TWEEN.pop) end end)
	return b, glyph
end

function Skin.header(parent)
	local bar = new("Frame", {Name = "TitleBar", Size = U(1, 0, 0, Skin.Header), BackgroundColor3 = C.Side, Active = true}, parent)
	new("Frame", {Size = U(1, 0, 0, 1), Position = U(0, 0, 1, -1), BackgroundColor3 = C.Line}, bar)
	local mark = logo(32, bar)
	mark.AnchorPoint, mark.Position = V2(0, 0.5), U(0, 12, 0.5, 0)
	new("TextLabel", {Size = O(85, 19), Position = O(54, 9), BackgroundTransparency = 1,
		Text = "Enkaisy", FontFace = GB, TextSize = 16, TextColor3 = C.W, TextXAlignment = XL}, bar)
	new("TextLabel", {Size = O(85, 14), Position = O(54, 28), BackgroundTransparency = 1,
		Text = "ESP + AIM", FontFace = GM, TextSize = 10, TextColor3 = C.Mut, TextXAlignment = XL}, bar)
	return bar
end

function Skin.badge(bar, text, x, w, withDot)
	local chip = new("Frame", {Size = O(w, 21), AnchorPoint = V2(0, 0.5), Position = U(0, x, 0.5, 0),
		BackgroundColor3 = withDot and C.Sel or C.Card, Active = false}, bar)
	rr(chip, 5, 7)
	new("TextLabel", {Size = U(1, withDot and -11 or 0, 1, 0), Position = O(withDot and 11 or 0, 0),
		BackgroundTransparency = 1, Text = text, FontFace = GM, TextSize = 11, TextColor3 = C.W}, chip)
	if withDot then
		local dot = new("Frame", {Size = O(5, 5), AnchorPoint = V2(0, 0.5), Position = U(0, 8, 0.5, 0), BackgroundColor3 = C.Mut}, chip)
		round(dot, 3)
		return dot
	end
end

-- ===== Персональные настройки игроков =====
local function psOf(plr) return plr and pset[tostring(plr.UserId)] end
-- On / Off для конкретного игрока, иначе глобальное значение g
local function pv(plr, key, g)
	local s = psOf(plr)
	local v = s and s[key]
	if v == "On" then return true elseif v == "Off" then return false end
	return g
end
local function pcol(plr, n)
	local s = psOf(plr)
	local c = s and s.cols and s.cols[n]
	return c and hsv(c)
end
-- ===== v4.1 TEAM COLORS: логика =====
-- NPC -> "NPC"; игрок с Team у нас и у цели -> "Friend" (та же команда) / "Enemy"; нет Team -> nil (обычные цвета)
function TC.side(plr)
	if not plr then return "NPC" end
	local a, b = LP.Team, plr.Team
	if a and b then return a == b and "Friend" or "Enemy" end
	return nil
end
-- Color3 для элемента (Team / Box / Skeleton / Tracer / Name) или nil, если для этой цели Team Colors не действует
function TC.get(plr, elem)
	local side = TC.side(plr)
	if not side or not CFG["Tc" .. side] then return nil end
	if elem == "Name" then
		if not CFG.TcAll then return nil end
		elem = "Team"
	elseif CFG.TcAll then
		elem = "Team"
	end
	return hsv(col["TC" .. side .. elem])
end
GLB.TC_R15 = {{"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"}, {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"},
	{"LeftLowerArm", "LeftHand"}, {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
	{"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
	{"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"}}
GLB.TC_R6 = {{"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"}, {"Torso", "Left Leg"}, {"Torso", "Right Leg"}}
TC.R15, TC.R6 = GLB.TC_R15, GLB.TC_R6
-- ESP Box: рамка по экранным границам модели. Считаем проекции восьми углов BoundingBox —
-- так рамка остаётся точной при любом повороте камеры и не «плывёт» на наклонных целях.
-- Четыре тонких Frame в том же ScreenGui, что линии: ни одного лишнего объекта на цель.
function TC.box(o, char, vis, cam, color)
	local parts = o.bxParts or {}
	if not o.bxParts then
		-- один раз собираем список видимых частей: их проекции и дают границы
		for _, p in char:GetDescendants() do
			if #parts >= 12 then break end -- тело + крупные аксессуары: дальше точность не растёт, только нагрузка
			if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and p.Name ~= "Handle" then table.insert(parts, p) end
		end
		-- части могли добавиться позже (одежда, аксессуары): обновляем раз в пару секунд
		o.bxParts, o.bxT = parts, os.clock()
	elseif os.clock() - (o.bxT or 0) > 2 then
		o.bxT = os.clock()
	end
	if not (vis and cam and #parts > 0) then
		for _, f in o.bx or {} do TC.fade(f, false) end
		return
	end
	-- частота задаётся кадром ESP (EspHz): отдельный таймер молча съедал бы половину обновлений
	local now = os.clock()
	local minX, minY, maxX, maxY, any = math.huge, math.huge, -math.huge, -math.huge, false
	for _, p in parts do
		if p.Parent then
			local cf, sz = p.CFrame, p.Size
			for i = 0, 7 do
				local corner = cf * Vector3.new((i % 2 == 0) and -sz.X / 2 or sz.X / 2,
					(i % 4 < 2) and -sz.Y / 2 or sz.Y / 2, (i < 4) and -sz.Z / 2 or sz.Z / 2)
				local sp, on = cam:WorldToViewportPoint(corner)
				if on then
					any = true
					minX, minY = math.min(minX, sp.X), math.min(minY, sp.Y)
					maxX, maxY = math.max(maxX, sp.X), math.max(maxY, sp.Y)
				end
			end
		end
	end
	if not any or maxX - minX < 2 or maxY - minY < 2 then
		for _, f in o.bx or {} do TC.fade(f, false) end
		return
	end
	-- поля вокруг модели: узкая рамка не прилипает к силуэту
	local pad = math.clamp((maxY - minY) * 0.06, 2, 8)
	minX, minY, maxX, maxY = minX - pad, minY - pad, maxX + pad, maxY + pad
	o.bx = o.bx or {}
	if not (o.bx[1] and o.bx[1].Parent) then
		for i = 1, 4 do o.bx[i] = TC.bar() end
	end
	local th = math.clamp((maxY - minY) * 0.012, 1, 2) -- толщина растёт с размером цели, но не жирнеет
	TC.rect(o.bx, minX, minY, maxX - minX, maxY - minY, th, color)
end

function TC.frame() -- линия = повёрнутый Frame в отдельном ScreenGui (IgnoreGuiInset: координаты = WorldToViewportPoint)
	if not (TC.gui and TC.gui.Parent) then
		TC.gui = new("ScreenGui", {
			Name = "EnkaisyLines", ResetOnSpawn = false, DisplayOrder = 98, IgnoreGuiInset = true,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}, LP:WaitForChild("PlayerGui"))
	end
	return new("Frame", {AnchorPoint = V2(0.5, 0.5), BorderSizePixel = 0, Visible = false, Active = false}, TC.gui)
end
-- полоса рамки: без AnchorPoint, позиция = левый верхний угол в экранных координатах
function TC.bar()
	if not (TC.gui and TC.gui.Parent) then
		TC.gui = new("ScreenGui", {
			Name = "EnkaisyLines", ResetOnSpawn = false, DisplayOrder = 98, IgnoreGuiInset = true,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}, LP:WaitForChild("PlayerGui"))
	end
	return new("Frame", {BorderSizePixel = 0, Visible = false, Active = false}, TC.gui)
end
-- Появление и исчезновение линии: короткий фейд вместо мгновенного включения.
-- Вызывается только при СМЕНЕ состояния (TC.faded[f]), поэтому в кадре ESP лишних твинов нет.
TC.faded = setmetatable({}, {__mode = "k"})
function TC.fade(f, on)
	if TC.faded[f] == on then return end
	TC.faded[f] = on
	if not CFG.Anim then
		f.Visible, f.BackgroundTransparency = on, 0
		return
	end
	if on then
		-- линия уже могла быть видимой (скелет мигнул на кадр): тогда досвечиваем с текущей прозрачности,
		-- а не начинаем заново с нуля — иначе получится мерцание
		local wasHidden = not f.Visible
		f.Visible = true
		if wasHidden then f.BackgroundTransparency = 1 end
		TS:Create(f, TWEEN.ui, {BackgroundTransparency = 0}):Play()
	else
		TS:Create(f, TWEEN.snap, {BackgroundTransparency = 1}):Play()
		task.delay(0.14, function()
			-- цель могла вернуться: гасим, только если линия всё ещё «выключена»
			if f.Parent and not TC.faded[f] then
				f.Visible, f.BackgroundTransparency = false, 0
			end
		end)
	end
end
function TC.line(f, a, b, c)
	local d = b - a
	f.Position, f.Size, f.Rotation = O((a.X + b.X) / 2, (a.Y + b.Y) / 2), O(d.Magnitude, 1.5), math.deg(math.atan2(d.Y, d.X))
	f.BackgroundColor3 = c
	TC.fade(f, true)
end
-- четыре полосы = периметр рамки; толщина одинаковая, стыки не просвечивают
function TC.rect(bx, x, y, w, h, th, color)
	local bars = {{x, y, w + th, th}, {x, y + h, w + th, th}, {x, y, th, h + th}, {x + w, y, th, h + th}}
	for i, b in bars do
		local f = bx[i]
		TC.fade(f, true)
		f.Position = U(0, b[1], 0, b[2])
		f.Size = O(math.max(1, b[3]), math.max(1, b[4]))
		f.BackgroundColor3 = color
	end
end

function TC.draw(o, char, vis, cam)
	local fill = o.h.FillColor -- если Team Colors для цели не действует, линии берут цвет заливки
	if CFG.Tracers and vis and cam and o.root then
		local p, inView = cam:WorldToViewportPoint(o.root.Position)
		if inView then
			if not (o.tr and o.tr.Parent) then o.tr = TC.frame() end
			local sz = cam.ViewportSize
			TC.line(o.tr, V2(sz.X / 2, sz.Y), V2(p.X, p.Y), TC.get(o.plr, "Tracer") or fill)
		elseif o.tr then
			TC.fade(o.tr, false)
		end
	elseif o.tr then
		TC.fade(o.tr, false)
	end
	if CFG.Skeleton and vis and cam then
		o.sk = o.sk or {}
		local c = TC.get(o.plr, "Skeleton") or fill
		for i, pr in (char:FindFirstChild("UpperTorso") and TC.R15 or TC.R6) do
			local a, b = char:FindFirstChild(pr[1]), char:FindFirstChild(pr[2])
			local f, drawn = o.sk[i], false
			if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
				local pa, ia = cam:WorldToViewportPoint(a.Position)
				local pb, ib = cam:WorldToViewportPoint(b.Position)
				if ia and ib then
					if not (f and f.Parent) then f = TC.frame() o.sk[i] = f end
					TC.line(f, V2(pa.X, pa.Y), V2(pb.X, pb.Y), c)
					drawn = true
				end
			end
			if not drawn and f then TC.fade(f, false) end
		end
	elseif o.sk then
		for _, f in o.sk do TC.fade(f, false) end
	end
end

local function alphaFor(plr, key, base, minOn)
	local s = psOf(plr)
	local v = s and s[key]
	if v == "Off" then return 0 end
	if v == "On" then return math.max(base, minOn) end
	return base
end
local function cleanPs(id)
	local e = pset[id]
	if not e then return end
	if e.cols and not next(e.cols) then e.cols = nil end
	if not next(e) then pset[id] = nil end
end

-- ===== Логика подсветки =====
local function matchNpc(name)
	local l = name:lower()
	for _, w in NpcWords do
		if l:find(w, 1, true) then return true end
	end
	return false
end

-- Нестандартные риги: Humanoid, явно отмеченные AimTarget или похожие на персонажа модели.
-- При выборе имён разрешены также другие модели с деталями; без фильтра декорации не сканируются как цели.
local RIG = {}
function RIG.matches(m)
    if CFG.ModelNames:match("^%s*$") then return true end
    local name, path = string.lower(m.Name), string.lower(m:GetFullName())
    for word in CFG.ModelNames:gmatch("[^,]+") do
        word = string.lower(word:match("^%s*(.-)%s*$"))
        if word ~= "" and (word == name or word == path) then return true end
    end
    return false
end
function RIG.part(m, name)
    local p = m:FindFirstChild(name, true)
    return p and p:IsA("BasePart") and p or nil
end
function RIG.root(m)
    if not m or not m:IsA("Model") then return nil end
    return RIG.part(m, "HumanoidRootPart") or m.PrimaryPart or RIG.part(m, "Torso")
        or RIG.part(m, "UpperTorso") or RIG.part(m, "Head") or m:FindFirstChildWhichIsA("BasePart", true)
end
function RIG.characterLike(m)
    if not m or not m:IsA("Model") then return false end
    if m:FindFirstChildOfClass("Humanoid") or game:GetService("CollectionService"):HasTag(m, "AimTarget") then return true end
    if not CFG.ModelNames:match("^%s*$") and RIG.matches(m) then return RIG.root(m) ~= nil end
    -- Только прямые части: иначе модель карты с вложенным персонажем станет целью.
    local head = m:FindFirstChild("Head")
    local body = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso") or m:FindFirstChild("UpperTorso")
    return head ~= nil and head:IsA("BasePart") and body ~= nil and body:IsA("BasePart")
end
function RIG.alive(m)
    local hum = m:FindFirstChildOfClass("Humanoid")
    if hum then return hum.Health > 0 end
    local health = m:GetAttribute("Health")
    return type(health) ~= "number" or health > 0
end
function RIG.fromPart(inst)
    local m = inst
    while m and m ~= Workspace do
        if m:IsA("Model") and (npcs[m] or Players:GetPlayerFromCharacter(m)) then return m end
        m = m.Parent
    end
    return nil
end

local function allowed(plr, char)
	if not CFG.On then return false end
    if char and not RIG.matches(char) then return false end
	if plr then
		if plr == LP or CFG.Mode == "NPC" then return false end
		if marks[plr.UserId] == "Hide" then return false end
		if CFG.TeamCheck and LP.Team and plr.Team == LP.Team then return false end
		if CFG.FriendMode == "Hide" and friendCache[plr.UserId] then return false end
		return true
	end
	if CFG.Mode == "Players" then return false end
	if CFG.NpcFilter ~= "Off" and #NpcWords > 0 and char then
		local m = matchNpc(char.Name)
		if (CFG.NpcFilter == "Only" and not m) or (CFG.NpcFilter == "Hide" and m) then return false end
	end
	return true
end

-- приоритет цвета: персональный > отметка > друг > цвет команды > обычный
-- CHAMS LOOK: один стиль на все хайлайты. Highlight умеет только заливку и обводку, поэтому
-- «металл», «стекло», «лава» и прочее собраны из цвета и прозрачности: у каждого стиля свой
-- характер — плотный контур, мягкая заливка, свечение, тёмный низ под светлый верх.
CHAMS = {
	-- mat  — текстура тела: материал частей (Neon светится, CrackedLava — лава, Foil — металл…)
	-- col  — цвет материала; nil = цвет берётся из темы (папка Color)
	-- glow — яркость настройки, 0 = без света; light = цвет точечного источника
	-- spin — материал переливается со временем (неон, иридец, вода)
	{key = "Outline", name = "Outline", fill = 0.90, outline = 0.05, thick = 1.0, col = nil},
	{key = "Soft", name = "Soft", fill = 0.80, outline = 0.45, thick = 0.8, col = nil},
	{key = "Solid", name = "Solid", fill = 0.25, outline = 0.10, thick = 0.9, col = nil},
	{key = "Neon", name = "Neon", fill = 0.35, outline = 0.00, thick = 1.8, col = Color3.fromRGB(60, 220, 255),
		mat = Enum.Material.Neon, glow = 1.1, light = Color3.fromRGB(80, 220, 255)},
	{key = "Lava", name = "Lava", fill = 0.40, outline = 0.05, thick = 1.3, col = Color3.fromRGB(255, 96, 24),
		mat = Enum.Material.CrackedLava, glow = 0.9, light = Color3.fromRGB(255, 120, 40)},
	{key = "Ice", name = "Ice", fill = 0.55, outline = 0.20, thick = 1.0, col = Color3.fromRGB(185, 230, 255),
		mat = Enum.Material.Ice, glow = 0.2, light = Color3.fromRGB(200, 235, 255)},
	{key = "Glass", name = "Glass", fill = 0.80, outline = 0.35, thick = 1.0, col = Color3.fromRGB(210, 240, 255),
		mat = Enum.Material.Glass, glow = 0},
	{key = "ForceField", name = "ForceField", fill = 0.55, outline = 0.10, thick = 1.2,
		col = Color3.fromRGB(120, 210, 255), mat = Enum.Material.ForceField, glow = 0.5,
		light = Color3.fromRGB(140, 190, 255)},
	{key = "Metal", name = "Metal", fill = 0.40, outline = 0.06, thick = 1.2, col = Color3.fromRGB(168, 176, 190),
		mat = Enum.Material.Foil, glow = 0},
	{key = "Chrome", name = "Chrome", fill = 0.22, outline = 0.02, thick = 1.6, col = Color3.fromRGB(245, 248, 255),
		mat = Enum.Material.Foil, glow = 0.3, light = Color3.fromRGB(230, 240, 255)},
	{key = "Metallic", name = "Metallic", fill = 0.30, outline = 0.04, thick = 1.4, col = Color3.fromRGB(198, 208, 226),
		mat = Enum.Material.Metal, glow = 0},
	{key = "Diamond", name = "Diamond", fill = 0.45, outline = 0.10, thick = 1.3, col = Color3.fromRGB(170, 240, 255),
		mat = Enum.Material.Glass, glow = 0.4, light = Color3.fromRGB(180, 240, 255)},
	{key = "Ghost", name = "Ghost", fill = 0.86, outline = 0.50, thick = 0.9, col = Color3.fromRGB(220, 225, 235),
		mat = Enum.Material.ForceField, glow = 0},
	{key = "Water Flow", name = "Water Flow", fill = 0.55, outline = 0.18, thick = 1.1, col = Color3.fromRGB(60, 150, 255),
		mat = Enum.Material.Water, glow = 0.2, light = Color3.fromRGB(80, 150, 255), spin = true},
	{key = "Iridescent", name = "Iridescent", fill = 0.45, outline = 0.10, thick = 1.3, col = Color3.fromRGB(225, 190, 255),
		mat = Enum.Material.Foil, glow = 0.5, light = Color3.fromRGB(210, 170, 255), spin = true},
	{key = "Wireframe", name = "Wireframe", fill = 0.97, outline = 0.00, thick = 1.0, col = Color3.fromRGB(90, 220, 140),
		mat = Enum.Material.Neon, glow = 0.3, light = Color3.fromRGB(100, 230, 150), spin = true},
	{key = "Glow", name = "Glow", fill = 0.45, outline = 0.10, thick = 1.6, col = Color3.fromRGB(140, 200, 255),
		mat = Enum.Material.Neon, glow = 0.7, light = Color3.fromRGB(150, 200, 255)},
	{key = "Shaded", name = "Shaded", fill = 0.55, outline = 0.30, thick = 1.1, col = Color3.fromRGB(150, 158, 175)},
	{key = "Glossy", name = "Glossy", fill = 0.25, outline = 0.06, thick = 1.3, col = Color3.fromRGB(235, 245, 255),
		mat = Enum.Material.SmoothPlastic, glow = 0.2, light = Color3.fromRGB(225, 240, 255)},
	{key = "Crystal", name = "Crystal", fill = 0.40, outline = 0.12, thick = 1.2, col = Color3.fromRGB(170, 215, 255),
		mat = Enum.Material.Glass, glow = 0.6, light = Color3.fromRGB(170, 215, 255)},
	{key = "Neon Rim", name = "Neon Rim", fill = 0.88, outline = 0.00, thick = 2.0, col = Color3.fromRGB(90, 255, 200),
		mat = Enum.Material.Neon, glow = 0.6, light = Color3.fromRGB(90, 255, 200)},
	{key = "Gradient", name = "Gradient", fill = 0.50, outline = 0.10, thick = 1.3, col = nil},
}
CHAMS_BY_KEY = {}
for i, c in CHAMS do c.idx, CHAMS_BY_KEY[c.key] = i, c end

-- Текстуры для стилей (необязательно). Одного материала мало: CrackedLava почти не реагирует
-- на Color, Glass/Ice/Foil выглядят как пластик. Если вписать сюда id текстуры, она ляжет
-- на тело, и стиль станет по-настоящему «текстурным».
-- Как взять id: в Studio положить на деталь Texture с нужной картинкой (лава, лёд, сетка),
-- скопировать его свойство Texture и вписать сюда: CHAMS_TEX.Lava = "rbxassetid://<число>".
local CHAMS_TEX = {} -- пусто по умолчанию: выдуманный id текстуры ничего не нарисует


-- Стиль Chams: и ключ для списка, и его параметры в одном месте.
local function chamsStyle()
	return CHAMS_BY_KEY[CFG.Chams or "Outline"] or CHAMS[1]
end

-- Оттенок стиля поверх базового цвета: так «металл», «лёд», «лава» отличаются даже
-- когда у всех целей один цвет темы. Для стилей без своего цвета возвращается база.
local function chamsTint(base, st, mix)
	st = st or chamsStyle()
	if not (base and st.col) then return base end
	return base:Lerp(st.col, mix or 0.6)
end

-- Сила стиля. У Highlight есть только заливка и обводка, поэтому «характер» стиля —
-- это плотность: st.fill / st.outline (0.20..0.97) сдвигают базовую непрозрачность ESP.
local function chamsAlpha(o, key, base, minOn, strength)
	-- strength — «плотность» стиля из таблицы CHAMS: меньше = плотнее.
	-- Заливка: 0.20 → ×1.62, 0.97 → ×0.16 (Wireframe почти прозрачный).
	-- Контур: 0.00 → ×1.35, 0.50 → ×0.80 (мягкие стили контур приглушают).
	-- Обе шкалы умножаются на базу ESP, поэтому ползунки Fill/Outline продолжают работать.
	local k = (key == "Fill") and (2.0 - strength * 1.9) or (1.35 - strength * 1.1)
	local a = alphaFor(o.plr, key, base, minOn) * k
	return math.clamp(a, 0, 1)
end

-- ===== ТЕКСТУРА СТИЛЯ НА ТЕЛЕ =====
-- Highlight в Roblox умеет ТОЛЬКО заливку и контур — настоящую текстуру он не рисует.
-- Поэтому Chams Look меняет ещё и материал частей тела: Neon светится, CrackedLava даёт лаву,
-- ForceField — синеву, Glass/Ice — прозрачность, Foil — металлический блик.
-- Исходные BasePart.Material/Color запоминаются, чтобы при снятии вернуть тело как было.
local chamsOrig = setmetatable({}, {__mode = "k"}) -- part -> {mat = ..., col = ...}
local chamsLights = setmetatable({}, {__mode = "k"}) -- char -> PointLight

local function chamsParts(char)
	local list = {}
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") and not d:FindFirstAncestorOfClass("Accessory") and not d:FindFirstAncestorOfClass("Tool") then
			table.insert(list, d)
		end
	end
	return list
end

-- снимает текстуру со всех частей персонажа (материалы и цвета возвращаются как были)
local function chamsClear(char)
	if not char then return end
	-- chamsOrig хранит запись по КАЖДОЙ части, поэтому идём по частям персонажа,
	-- а не по таблице целиком (иначе у чужих моделей сбрасывались бы материалы)
	local list = (char.Parent and char:IsDescendantOf(Workspace)) and chamsParts(char) or {}
	for _, part in list do
		local orig = chamsOrig[part]
		if orig then
			pcall(function()
				part.Material = orig.mat
				part.Color = orig.col
				part.TextureID = orig.tex or ""
			end)
		end
		chamsOrig[part] = nil
	end
	local light = chamsLights[char]
	if light then
		light:Destroy()
		chamsLights[char] = nil
	end
end

-- накладывает текстуру стиля: tint — цвет темы, чтобы стиль без своего цвета не был белым
local function chamsTexture(char, st, tint, animate)
	st = st or chamsStyle()
	if not char then return end
	if not st.mat then
		-- стиль без материала (Outline/Solid/Gradient): только Highlight, тело не трогаем
		chamsClear(char)
		return
	end
	local base = st.col or tint or Color3.new(1, 1, 1)
	local now = os.clock()
	-- перелив: неон, вода и иридец медленно меняют оттенок; при выключенных анимациях — статично
	local hue = base:ToHSV()
	local col = base
	if st.spin and animate then
		col = Color3.fromHSV((hue + now * 0.08) % 1, (select(2, base:ToHSV()) * 0.85) + 0.15, select(3, base:ToHSV()))
	elseif st.spin then
		col = base
	end
	for _, part in chamsParts(char) do
		if not chamsOrig[part] then
			chamsOrig[part] = {mat = part.Material, col = part.Color}
			chamsOrig[part].tex = part.TextureID or ""
		end
		pcall(function()
			part.Material = st.mat
			part.Color = col
		end)
	end
	-- Настоящая текстура Roblox поверх материала: CrackedLava почти не реагирует на Color,
	-- Glass/Ice/Foil выглядят как пластик. Текстура берётся из CHAMS_TEX (по умолчанию пусто:
	-- id текстур задаются вручную, придуманный id просто ничего не нарисует).
	local tex = CHAMS_TEX[st.key] or CHAMS_TEX[st.mat and st.mat.Name or ""]
	for _, part in chamsParts(char) do
		if tex then
			if part.TextureID ~= tex then pcall(function() part.TextureID = tex end) end
		elseif part.TextureID ~= "" then
			-- стиль без своей текстуры: убираем чужую, чтобы тело выглядело штатно
			pcall(function() part.TextureID = "" end)
		end
	end
	-- свет: стили с glow реально светятся в тёмных местах (Neon/Lava/Chrome и т.п.)
	local light = chamsLights[char]
	if (st.glow or 0) > 0 then
		if not light or not light.Parent then
			local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
			if not root then return end
			-- яркость 1.5 + Range 9: при меньшей свет не виден днём и стили «не светятся»
			light = new("PointLight", {Name = "EnkaisyChamsLight", Range = 9, Brightness = 1.5}, root)
			chamsLights[char] = light
		end
		light.Color = st.light or col
		light.Brightness = math.max(1.5, st.glow * 2.2) * (animate and (0.85 + 0.15 * math.sin(now * 3)) or 1)
	elseif light then
		light:Destroy()
		chamsLights[char] = nil
	end
end

-- Применяет стиль к хайлайту: цвет (с оттенком стиля) и обе прозрачности.
-- tintable = false, когда у цели свой цвет (персональный) — его не перекрашиваем.
local function chamsApply(o, fillColor, outlineColor, tintable)
	local st = chamsStyle()
	if fillColor then
		o.h.FillColor = (tintable == false) and fillColor or chamsTint(fillColor, st)
	end
	if outlineColor then
		o.h.OutlineColor = (tintable == false) and outlineColor or chamsTint(outlineColor, st, 0.7)
	end
	-- Заливка Highlight рисуется ПОВЕРХ тела (DepthMode.AlwaysOnTop), поэтому плотная заливка
	-- прячет материал и свет — снаружи все стили выглядели одинаково серым силуэтом.
	-- Ограничиваем заливку 55%: тело (лава, неон, стекло) остаётся видимым, стиль читается.
	o.h.FillTransparency = 1 - math.min(0.55, chamsAlpha(o, "Fill", CFG.Fill, 0.45, st.fill))
	o.h.OutlineTransparency = 1 - chamsAlpha(o, "Outline", CFG.Outline, 0.8, st.outline)
	return st
end

local function refreshHL()
	local st = chamsStyle()
	for _, o in esp do
		local h = o.h
		-- персональный цвет сильнее стиля: если он задан, оттенок стиля не подмешивается
		local fc = pcol(o.plr, "Fill")
		local ownFill = fc ~= nil
		if not fc then
			local tcf = TC.get(o.plr, "Team")
			if o.plr then
				local id, tm = o.plr.UserId, o.plr.Team
				if marks[id] == "Mark" then
					fc = hsv(col.Mark)
				elseif CFG.FriendMode == "Color" and friendCache[id] then
					fc = hsv(col.Friend)
				elseif tcf then
					fc = tcf
				elseif CFG.TeamColors and tm then
					fc = tm.TeamColor.Color
				else
					fc = hsv(col.Fill)
				end
			else
				fc = tcf or hsv(col.NPC)
			end
		end
		local oc = pcol(o.plr, "Outline") or TC.get(o.plr, "Box") or hsv(col.Outline)
		local ownOutline = pcol(o.plr, "Outline") ~= nil
		chamsApply(o, fc, oc, not (ownFill or ownOutline))
		-- текстура (материал тела) — вторая половина стиля; для Outline/Solid/Gradient это no-op
		if o.char then
			pcall(chamsTexture, o.char, st, fc, CFG.Anim)
		end
	end
	return st
end

local function unhl(char, fade)
	if not char then return end
	local o = esp[char]
	if not o then return end
	esp[char] = nil
	-- тело возвращаем к исходным материалам: иначе скрипт оставит игроков неоновыми
	pcall(chamsClear, char)
	restoreNative(o)
	if o.nb then o.nb:Destroy() end
	if o.hb then o.hb:Destroy() end
	if o.tr then o.tr:Destroy() end
	for _, f in o.sk or {} do f:Destroy() end
	for _, f in o.bx or {} do f:Destroy() end
	if fade and CFG.Anim then
		local t = TS:Create(o.h, TweenInfo.new(0.25), {FillTransparency = 1, OutlineTransparency = 1})
		t.Completed:Once(function() o.h:Destroy() end)
		t:Play()
	else
		o.h:Destroy()
	end
end

local function dohl(char, plr)
	if not char then return end
	unhl(char)
	if not allowed(plr, char) then return end
	local o = {plr = plr, char = char}
	esp[char] = o
	o.h = new("Highlight", {
		Name = "TH", Adornee = char, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		FillTransparency = 1, OutlineTransparency = 1,
	}, char)
	-- refreshHL сам применяет выбранный стиль Chams: берём готовые прозрачности и
	-- проявляем хайлайт фейдом до них (набор стиля считается ровно в одном месте)
	refreshHL()
	local ft, ot = o.h.FillTransparency, o.h.OutlineTransparency
	o.h.FillTransparency, o.h.OutlineTransparency = 1, 1
	tween(o.h, TweenInfo.new(0.25), {FillTransparency = ft, OutlineTransparency = ot})
	local function setup()
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = RIG.root(char)
		local head = RIG.part(char, "Head") or root
		if not (head and root) then return false end
		o.hum = hum
		o.root = root
		o.nb = new("BillboardGui", {
			Adornee = head, Size = O(200, 26), StudsOffset = Vector3.new(0, 2.4, 0),
			AlwaysOnTop = true, Enabled = false,
		}, char)
		o.nl = new("TextLabel", {
			Size = S(1, 1), BackgroundTransparency = 1,
			FontFace = GB, TextStrokeTransparency = 0.3,
		}, o.nb)
		o.hb = new("BillboardGui", {
			Adornee = root, Size = S(2.4, 5.2), StudsOffset = Vector3.new(2.9, 0, 0),
			AlwaysOnTop = true, Enabled = false,
		}, char)
		o.bg = new("Frame", {Size = S(0.12, 1), BackgroundColor3 = C.B, BackgroundTransparency = 0.3, BorderSizePixel = 0}, o.hb)
		o.bar = new("Frame", {AnchorPoint = V2(0, 1), Position = S(0, 1), BorderSizePixel = 0}, o.bg)
		o.pct = new("TextLabel", {
			Size = S(1, 0.3), Position = S(0, 0.35), BackgroundTransparency = 1,
			TextScaled = true, FontFace = GB, TextXAlignment = XL,
			TextStrokeTransparency = 0.3,
		}, o.hb)
		if hum then hum.Died:Once(function()
			if CFG.HideDead and esp[char] == o then unhl(char, true) end
		end) end
		return true
	end
	task.spawn(function()
		for i = 1, 25 do
			if esp[char] ~= o or not char.Parent then return end
			if setup() then return end
			task.wait(i < 10 and 0.2 or 1)
		end
	end)
end

local function upd(char, plr)
	if not char then return end
	if allowed(plr, char) then
		if not esp[char] then dohl(char, plr) end
	else
		unhl(char, true)
	end
end

local function checkFriend(p)
	if friendCache[p.UserId] ~= nil then return end
	task.spawn(function()
		local ok, res = pcall(function() return LP:IsFriendsWith(p.UserId) end)
		friendCache[p.UserId] = ok and res == true
		if CFG.FriendMode ~= "Off" and p.Parent then
			upd(p.Character, p)
			refreshHL()
		end
	end)
end

local function updAll()
	for _, p in Players:GetPlayers() do
		if p ~= LP then
			if CFG.FriendMode ~= "Off" then checkFriend(p) end
			upd(p.Character, p)
		end
	end
	for m in npcs do upd(m, nil) end
	refreshHL()
end

local function track(p)
	if p == LP then return end
	pconn[p] = {
		p.CharacterAdded:Connect(function(c)
            npcs[c] = nil
            if npcConn[c] then npcConn[c]:Disconnect(); npcConn[c] = nil end
            dohl(c, p)
        end),
		p.CharacterRemoving:Connect(function(c) unhl(c) end),
		p:GetPropertyChangedSignal("Team"):Connect(function()
			upd(p.Character, p)
			refreshHL()
			if plrHook then plrHook(p) end
		end),
	}
	if CFG.FriendMode ~= "Off" then checkFriend(p) end
	if p.Character then
        npcs[p.Character] = nil
        if npcConn[p.Character] then npcConn[p.Character]:Disconnect(); npcConn[p.Character] = nil end
        dohl(p.Character, p)
    end
end

local function untrack(p)
	unhl(p.Character)
	for _, c in pconn[p] or {} do c:Disconnect() end
	pconn[p] = nil
end

local function addNpc(inst)
    task.defer(function()
        local m = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
        if not m or npcs[m] or not m:IsDescendantOf(Workspace) or not RIG.characterLike(m) then return end
        if Players:GetPlayerFromCharacter(m) or (LP.Character and (m == LP.Character or m:IsDescendantOf(LP.Character))) then return end
        npcs[m] = true
        npcConn[m] = m.AncestryChanged:Connect(function()
            if not m:IsDescendantOf(Workspace) then
                unhl(m)
                npcs[m] = nil
                if npcConn[m] then npcConn[m]:Disconnect(); npcConn[m] = nil end
            end
        end)
        upd(m, nil)
    end)
end
-- Убираем модели, которые больше не соответствуют явному фильтру или автоматически распознаваемым ригам.
local function pruneModels()
    for m in npcs do
        if not m:IsDescendantOf(Workspace) or not RIG.characterLike(m) or Players:GetPlayerFromCharacter(m) then
            unhl(m)
            npcs[m] = nil
            if npcConn[m] then npcConn[m]:Disconnect(); npcConn[m] = nil end
        end
    end
end
-- Явный фильтр имён позволяет зарегистрировать любой Model с BasePart, даже без Humanoid.
local function scanModels()
    task.spawn(function()
        local count = 0
        for _, d in Workspace:GetDescendants() do
            if not alive then return end
            if d:IsA("Model") then addNpc(d) end
            count += 1
            if count % 400 == 0 then task.wait() end
        end
    end)
end

local lastRank, lastChk, lastLbl, lastWork = 0, 0, 0, 0
local function setp(o, k, v) if o[k] ~= v then o[k] = v end end
local function frame()
	local now = os.clock()
	local dt = now - lastT
	lastT = now
	fps += (1 / math.max(dt, 1e-3) - fps) * 0.08
	local hz = CFG.EspHz
	-- ограничение работает на любой выбранной частоте: на 120-Гц экране "60 Hz" теперь реально 60,
	-- а не полная частота кадров (раньше при hz = 60 условие не срабатывало никогда)
	if hz > 0 and now - lastWork < 1 / hz - 0.004 then return end
	lastWork = now
	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position
	local rb = CFG.Rainbow and Color3.fromHSV(now * 0.25 % 1, math.max(col.Fill.s, 0.6), math.max(col.Fill.v, 0.8))
	local doRank = now - lastRank > 0.25
	local doLbl = now - lastLbl > 0.1
	local list = doRank and {} or nil
	if doRank then lastRank = now end
	if doLbl then lastLbl = now end
	local hideNative = CFG.On and CFG.Names and CFG.HideNative
	local pc, nc = 0, 0
	for char, o in esp do
		if o.plr then pc += 1 else nc += 1 end
		local dist = (camPos and o.root) and (o.root.Position - camPos).Magnitude or 0
		o.dist = dist
		-- MinDist: вплотную к цели рамки/подписи только мешают, их можно скрыть
		local far = (CFG.MaxDist < DIST_MAX and dist > CFG.MaxDist) or (CFG.MinDist > 0 and dist < CFG.MinDist)
		if list and not far then table.insert(list, o) end
		local limited = CFG.Limit and (o.rank or 0) > CFG.LimitN
		local vis = not far and not limited and (not CFG.HideDead or RIG.alive(char))
		setp(o.h, "Enabled", pv(o.plr, "Hl", CFG.Hl) and vis)
		local hum = o.hum
		local f = hum and math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1) or 1
		local marked = o.plr and marks[o.plr.UserId] == "Mark"
		local ps = psOf(o.plr)
		local custom = ps and ps.cols and ps.cols.Fill
		if not marked and not custom then
			if CFG.HPColor and hum then o.h.FillColor = Color3.fromHSV(f * 0.33, 0.85, 0.95) end
			if rb then o.h.FillColor = rb end
			-- HPColor и радуга перекрашивают заливку каждый кадр — оттенок стиля возвращаем обратно,
			-- иначе Chams «пропадает», как только включён цвет по здоровью
			o.h.FillColor = chamsTint(o.h.FillColor)
		end
		-- ESP Box: экранная рамка вокруг цели, цвет как у контура подсветки
		if CFG.Box or o.bx then
			local okB, eB = pcall(TC.box, o, char, vis, cam, o.h.OutlineColor)
			if not okB and not TC.warnB then TC.warnB = true warn("[Enkaisy] box draw error: " .. tostring(eB)) end
		end
		if CFG.Tracers or CFG.Skeleton or o.tr or o.sk then
			local okT, eT = pcall(TC.draw, o, char, vis, cam)
			if not okT and not TC.warned then TC.warned = true warn("[Enkaisy] team colors draw error: " .. tostring(eT)) end
		end
		if hum then
			-- прячем родные ники игры, пока включены наши Names
			if hideNative then
				if not o.hidNative then
					o.origDDT = hum.DisplayDistanceType
					o.hidNative = true
				end
				if hum.DisplayDistanceType ~= NONE then hum.DisplayDistanceType = NONE end
			elseif o.hidNative then
				restoreNative(o)
			end
		end
		if o.nl then
			local showN, showD = pv(o.plr, "Name", CFG.Names), pv(o.plr, "Dist", CFG.Dist)
			local showName = (showN or showD) and vis
			setp(o.nb, "Enabled", showName)
			if showName and doLbl then
				local txt = ""
				if showN then
					local n = o.plr and (CFG.Disp and o.plr.DisplayName or o.plr.Name) or char.Name
					txt = n:sub(1, CFG.NameLen)
				end
				if showD then
					txt = txt .. (txt ~= "" and " " or "") .. "[" .. math.floor(dist + 0.5) .. "m]"
				end
				-- размер надписи зависит от расстояния: ближе — крупнее
				local k = CFG.DistScale and math.clamp(1.15 - dist / 300, 0.5, 1.15) or 1
				local sz = math.floor(CFG.NameSize * k + 0.5)
				setp(o.nl, "Text", txt)
				setp(o.nl, "TextSize", sz)
				setp(o.nl, "TextColor3", pcol(o.plr, "Name") or TC.get(o.plr, "Name") or hsv(col.Name))
				setp(o.nb, "Size", O(200, sz + 10))
			end
			local hpOn = pv(o.plr, "HP", CFG.HP)
			local showHB = hum ~= nil and (hpOn or CFG.Pct) and vis
			setp(o.hb, "Enabled", showHB)
			if showHB and doLbl then
				local c = Color3.fromHSV(f * 0.33, 0.85, 0.95)
				setp(o.bg, "Visible", hpOn and not CFG.Pct)
				setp(o.pct, "Visible", CFG.Pct)
				o.bar.Size = S(1, f)
				setp(o.bar, "BackgroundColor3", c)
				setp(o.pct, "Text", math.floor(f * 100 + 0.5) .. "%")
				setp(o.pct, "TextColor3", c)
			end
		end
	end
	if list then
		table.sort(list, function(a, b) return a.dist < b.dist end)
		for i, o in list do o.rank = i end
	end
	if counterLbl then
		local txt = "Players: " .. pc .. " • NPC: " .. nc
		if counterLbl.Text ~= txt then
			counterLbl.Text = txt
			-- счётчик целей меняется редко, поэтому подсветка вспыхивает: изменение заметно
			if CFG.Anim and UICFG.AnimCounters then
				counterLbl.TextColor3 = C.W
				tween(counterLbl, TWEEN.ui, {TextTransparency = 0})
				task.delay(0.35, function()
					if counterLbl.Parent and CFG.Anim then counterLbl.TextColor3 = C.Mut end
				end)
			end
		end
	end
	if doLbl and statusFn then statusFn() end
	-- FPS и пинг: цифры «доезжают» до новых значений, цвет меняется мягко, а не рывком
	if statsCard and CFG.ShowStats and now - lastStat > 0.5 then
		lastStat = now
		local fr, pg = math.floor(fps + 0.5), math.floor(getPing() + 0.5)
		local fFrom = statFpsVal or fr
		local pFrom = statPingVal or pg
		statFpsVal, statPingVal = fr, pg
		if CFG.Anim and UICFG.AnimCounters then
			animateNumber(statsFps, fFrom, fr, function(v) return math.floor(v + 0.5) .. " FPS" end, 0.4)
			animateNumber(statsPing, pFrom, pg, function(v) return math.floor(v + 0.5) .. " ms" end, 0.4)
		else
			statsFps.Text, statsPing.Text = fr .. " FPS", pg .. " ms"
		end
		tween(statsFps, fast, {TextColor3 = fr >= 50 and GOOD or fr >= 30 and MID or BAD})
		tween(statsPing, fast, {TextColor3 = pg <= 100 and GOOD or pg <= 200 and MID or BAD})
	end
	if now - lastChk > 0.5 then
		lastChk = now
		saveNow()
	end
end

-- ===== Перетаскивание =====
-- один общий обработчик на все ползунки: слушаются только активные касания (без лишней нагрузки)
local dragMoves, dragEnds = {}, {}
on(UIS.InputChanged, function(i) for fn in dragMoves do fn(i) end end)
on(UIS.InputEnded, function(i) for fn in dragEnds do fn(i) end end)
local function drag(f, cb, onStart, onEnd)
	local act
	local function u(pos)
		local a, s = f.AbsolutePosition, f.AbsoluteSize
		cb(math.clamp((pos.X - a.X) / s.X, 0, 1), math.clamp((pos.Y - a.Y) / s.Y, 0, 1))
	end
	local function moved(i)
		if act and move(i) and (i == act or i.UserInputType == UT.MouseMovement) then u(i.Position) end
	end
	local function ended(i)
		if act and (i == act or i.UserInputType == UT.MouseButton1) then
			act = nil
			dragMoves[moved], dragEnds[ended] = nil, nil
			if onEnd then onEnd() end
		end
	end
	on(f.InputBegan, function(i)
		if not press(i) then return end
		act = i
		dragMoves[moved], dragEnds[ended] = true, true
		if onStart then onStart() end
		u(i.Position)
	end)
end

-- держит плавающий элемент целиком на экране (с учётом AnchorPoint и UIScale); положение хранит в долях родителя
local function clampGui(o, m)
	local host = o.Parent
	if not host or not host:IsA("GuiBase2d") then return end
	local gs, sz = host.AbsoluteSize, o.AbsoluteSize
	if gs.X < 50 or gs.Y < 50 then return end
	m = m or 6
	local a, p = o.AnchorPoint, o.Position
	local x, y = p.X.Scale * gs.X + p.X.Offset, p.Y.Scale * gs.Y + p.Y.Offset
	local loX, hiX = m + a.X * sz.X, gs.X - m - (1 - a.X) * sz.X
	local loY, hiY = m + a.Y * sz.Y, gs.Y - m - (1 - a.Y) * sz.Y
	x = hiX < loX and gs.X * a.X or math.clamp(x, loX, hiX)
	y = hiY < loY and gs.Y * a.Y or math.clamp(y, loY, hiY)
	o.Position = U(x / gs.X, 0, y / gs.Y, 0)
end

-- onTap — короткое касание; onEnd — после настоящего перетаскивания (удобно вернуть элемент на экран и сохранить место)
local function movable(handle, target, onTap, onEnd, canDrag)
	local d, m, s0, p0, t = false, false
	on(handle.InputBegan, function(i)
		if press(i) and (not canDrag or canDrag()) then d, m, s0, p0, t = true, false, i.Position, target.Position, i end
	end)
	on(UIS.InputChanged, function(i)
		if not d or not move(i) or not (i == t or i.UserInputType == UT.MouseMovement) then return end
		local dl = i.Position - s0
		if dl.Magnitude > 10 then m = true end
		if m then target.Position = U(p0.X.Scale, p0.X.Offset + dl.X, p0.Y.Scale, p0.Y.Offset + dl.Y) end
	end)
	on(UIS.InputEnded, function(i)
		if d and (i == t or i.UserInputType == UT.MouseButton1) then
			d = false
			if m then
				if onEnd then onEnd() end
			elseif onTap then
				onTap()
			end
		end
	end)
end

-- ===== Общие элементы интерфейса (единый стиль: тёмная карточка + тонкая белая обводка) =====
local function sectionLabel(parent, text, order)
	local l = new("TextLabel", {
		Size = U(1, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Text = string.upper(text),
		TextColor3 = C.Mut, FontFace = GB, TextSize = 10, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Bottom,
		TextWrapped = true, LayoutOrder = order or 0,
	}, parent)
	new("UIPadding", {PaddingLeft = UDim.new(0, 2), PaddingBottom = UDim.new(0, 1)}, l)
	return l
end

-- Карточки в одну колонку на телефоне и в две в широком окне.
-- applyGridCols перестраивает все сетки сразу.
local gridCols, grids = 1, setmetatable({}, {__mode = "k"})
local function applyGridCols(n)
	if n == gridCols then return end
	gridCols = n
	for lay in grids do
		if lay.Parent then
			lay.CellSize = U(1 / n, -Skin.Gap * (n - 1) / n, 0, Skin.Row)
		else
			grids[lay] = nil
		end
	end
end
local function chipGrid(parent, order)
	local g = new("Frame", {Size = U(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order or 0}, parent)
	local lay = new("UIGridLayout", {
		CellSize = U(1 / gridCols, -Skin.Gap * (gridCols - 1) / gridCols, 0, Skin.Row), CellPadding = O(Skin.Gap, Skin.Gap), SortOrder = Enum.SortOrder.LayoutOrder,
	}, g)
	grids[lay] = true
	return g
end

-- Справка общих карточек; окно создаётся главным меню. Реестр также служит поиску.
local helpUI = {items = {}}
helpUI.info = {
 ["Enable ESP"] = {"Включает подсветку игроков и NPC.", "Enables highlights for players and NPCs."},
 ["Aim on"] = {"Включает помощь в наведении.", "Enables aim assistance."},
 ["Auto predict"] = {"Автоматически рассчитывает упреждение движущейся цели.", "Automatically predicts a moving target's position."},
 ["Float button"] = {"Показывает плавающую кнопку AIM.", "Shows the floating AIM button."},
 ["Target lock"] = {"Удерживает выбранную цель.", "Keeps the selected target locked."},
 ["Silent aim"] = {"Направляет выстрел в цель без движения камеры; сервер ограничивает угол.", "Directs shots toward the target without moving the camera; the server limits the angle."},
 ["Highlight"] = {"Подсвечивает цели.", "Highlights targets."},
 ["CHAMS LOOK"] = {"Стиль подсветки целей: Outline, Metal, Chrome, Neon, Lava, Ghost и другие. Цвет берётся из папки Color, стиль меняет характер — контур, заливку, свечение.", "Highlight style: Outline, Metal, Chrome, Neon, Lava, Ghost and more. The color comes from the Color folder; the style changes the character — outline, fill, glow."},
 ["CIRCLE STYLE"] = {"Вид круга FOV: Glow (мягкое свечение), Gradient (градиентная обводка), Dashed (пунктир, вращается), Classic (ровная линия).", "FOV circle look: Glow (soft halo), Gradient (gradient outline), Dashed (rotating dashes), Classic (solid line)."},
 ["Names"] = {"Показывает имена целей.", "Shows target names."},
 ["HP bar"] = {"Показывает полосу здоровья.", "Shows the health bar."},
 ["HP %"] = {"Показывает здоровье в процентах.", "Shows health as a percentage."},
 ["Team check"] = {"Исключает игроков своей команды.", "Excludes players on your team."},
 ["Hide dead"] = {"Скрывает погибшие цели.", "Hides dead targets."},
 ["Rainbow"] = {"Меняет цвет подсветки по радуге.", "Cycles highlight colors through the rainbow."},
 ["Display name"] = {"Показывает отображаемое имя игрока.", "Shows the player's display name."},
 ["Distance"] = {"Показывает расстояние до цели.", "Shows the distance to the target."},
 ["HP color"] = {"Меняет цвет по уровню здоровья.", "Changes color based on health."},
 ["Limit nearest"] = {"Ограничивает отображение ближайшими целями.", "Limits display to the nearest targets."},
 ["Hide native"] = {"Скрывает стандартные метки Roblox.", "Hides Roblox's native labels."},
 ["Friends"] = {"Выбирает, как отображать друзей.", "Chooses how friends are displayed."},
 ["Fill strength"] = {"Настраивает силу заливки подсветки.", "Adjusts highlight fill strength."},
 ["Outline opacity"] = {"Настраивает непрозрачность контура.", "Adjusts outline opacity."},
 ["Name size"] = {"Изменяет размер имени.", "Changes the name text size."},
 ["Name length"] = {"Ограничивает длину имени.", "Limits the length of names."},
 ["Max distance"] = {"Ограничивает расстояние до цели.", "Limits target distance."},
 ["Limit count"] = {"Ограничивает количество целей.", "Limits the number of targets."},
 ["Show Tracers"] = {"Показывает линии к целям.", "Shows lines to targets."},
 ["Show Skeleton"] = {"Показывает скелет целей.", "Shows target skeletons."},
 ["FPS cap"] = {"Ограничивает частоту кадров, если доступно.", "Limits the frame rate when supported."},
 ["ESP update rate"] = {"Изменяет частоту обновления ESP.", "Changes the ESP update rate."},
 ["Image fit"] = {"Выбирает способ размещения фоновой картинки.", "Chooses how the background image fits."},
 ["Triggerbot"] = {"Автоматически стреляет, когда цель попадает в прицел или допуск.", "Automatically fires when a target is in the crosshair or tolerance area."},
 ["Multipoint"] = {"Ищет видимую точку на краях хитбокса.", "Searches for a visible point around the hitbox edges."},
 ["Adv predict"] = {"Учитывает движение цели и падение пули; нужны атрибуты BulletSpeed и BulletGravity.", "Accounts for target motion and bullet drop; requires BulletSpeed and BulletGravity."},
 ["Hitbox"] = {"Расширяет виртуальный хитбокс тела; размер ограничен сервером.", "Expands the virtual body hitbox; the server limits its size."},
 ["Head hitbox"] = {"Расширяет виртуальный хитбокс головы.", "Expands the virtual head hitbox."},
 ["Hitbox size (studs)"] = {"Размер расширения хитбокса тела в студах.", "Body hitbox expansion in studs."},
 ["Head hitbox size (studs)"] = {"Размер расширения хитбокса головы в студах.", "Head hitbox expansion in studs."},
 ["Hitbox ESP"] = {"Рисует расширенные хитбоксы целей.", "Draws expanded target hitboxes."},
 ["Show head"] = {"Показывает хитбокс головы.", "Shows the head hitbox."},
 ["Show body"] = {"Показывает хитбоксы тела.", "Shows body hitboxes."},
 ["Only target"] = {"Показывает хитбокс только выбранной цели.", "Shows only the selected target's hitbox."},
 ["All targets"] = {"Показывает хитбоксы всех целей.", "Shows hitboxes for all targets."},
 ["Invuln check"] = {"Исключает неуязвимые цели.", "Excludes invulnerable targets."},
 ["Flash check"] = {"Проверяет эффект ослепления.", "Checks for the flash effect."},
 ["Smoke check"] = {"Проверяет наличие дыма.", "Checks for smoke."},
 ["Players"] = {"Разрешает выбирать игроков как цели.", "Allows players to be selected as targets."},
 ["NPCs"] = {"Разрешает выбирать NPC как цели.", "Allows NPCs to be selected as targets."},
 ["Wall check"] = {"Проверяет видимость цели через препятствия.", "Checks target visibility through obstacles."},
 ["Target priority"] = {"Выбирает приоритет цели: прицел, расстояние или здоровье.", "Chooses target priority: crosshair, distance or health."},
 ["Aim center"] = {"Выбирает точку отсчёта для наведения.", "Selects the reference point for aiming."},
 ["Auto fallback"] = {"Переходит к следующей доступной части тела.", "Falls back to the next available body part."},
 ["Return to main"] = {"Возвращается к основной части, когда она доступна.", "Returns to the main body part when available."},
 ["Debug HUD"] = {"Показывает диагностическую информацию.", "Shows diagnostic information."},
 ["Trigger delay (sec)"] = {"Задержка автоматического выстрела в секундах.", "Delay before an automatic shot, in seconds."},
 ["RCS (recoil control)"] = {"Возвращает камеру в точку прицела после отдачи и гасит увод ствола.", "Pulls the camera back to the aim point after recoil and cancels the muzzle climb."},
 ["RCS strength"] = {"Насколько сильно RCS гасит отдачу: 100% — полностью, 50% — половину, 0% — RCS выключен.", "How much recoil RCS removes: 100% — all of it, 50% — half, 0% — RCS off."},
 ["RCS smoothness"] = {"Скорость выравнивания: 0 — мгновенно, выше — плавнее и мягче.", "How fast recoil is levelled out: 0 — instantly, higher — smoother."},
 ["RCS suppress (no kick)"] = {"Не даёт камере уходить вверх при выстреле: отдача не отрисовывается, ствол не задран.", "Stops the camera from kicking up while shooting: recoil is not shown and the barrel never climbs."},
 ["Smooth curve"] = {"Форма плавности: Linear — ровно, Ease — мягче ближе к цели, Human — с живой неровностью.", "Smoothing shape: Linear — even, Ease — softer near the target, Human — with a lifelike unevenness."},
 ["Max turn speed, deg/s"] = {"Предел скорости поворота камеры: не даёт резко «щёлкнуть» на далёкую цель.", "Camera turn speed limit: prevents snapping to a distant target."},
 ["Dead zone, px"] = {"Зона, внутри которой прицел не двигается — убирает микро-дрожь на цели.", "Zone where the aim does not move — removes micro-jitter on the target."},
 ["Camera follow, %"] = {"Насколько наводка следует за реальной камерой за кадр: меньше — плавнее, но медленнее реакция.", "How much the aim follows the real camera per frame: lower — smoother but slower to react."},
 ["Stick time (sec)"] = {"Сколько секунд захваченная цель остаётся главной, даже если рядом появилась другая.", "How many seconds the captured target stays primary even if another one appears nearby."},
 ["Predict multiplier, %"] = {"Множитель упреждения: меньше — стрелять ближе к текущей позиции цели, больше — дальше вперёд.", "Prediction multiplier: lower shoots closer to the target's current position, higher shoots further ahead."},
 ["Shake (soft aim), deg"] = {"Небольшое дрожание прицела при наводке, чтобы она не выглядела идеально ровной. 0 — выключено.", "Small aim jitter while aiming so it does not look perfectly linear. 0 — off."},
 ["ESP box"] = {"Рамка вокруг цели по её видимым границам на экране.", "A box around the target along its visible screen bounds."},
 ["Min distance (studs)"] = {"Ближе этого расстояния ESP не рисуется: вплотную рамки и подписи мешают.", "ESP is not drawn closer than this distance: boxes and labels get in the way up close."},
 ["Smoothness (higher = faster)"] = {"Скорость наведения: большее значение означает быстрее.", "Aim speed: a higher value means faster."},
 ["Manual predict (sec)"] = {"Ручное упреждение в секундах.", "Manual prediction time in seconds."},
 ["Auto predict bias (ms)"] = {"Поправка автоматического упреждения в миллисекундах.", "Automatic prediction bias in milliseconds."},
 ["Sticky (lower = stickier)"] = {"Удержание цели: меньшее значение сильнее удерживает цель.", "Target stickiness: lower values hold the target more strongly."},
 ["Aim max distance"] = {"Максимальная дистанция цели для наводки, студы.", "Maximum target distance for aim assist, in studs."},
 ["ESP max distance"] = {"Максимальная дистанция, на которой ESP показывает цели.", "Maximum distance at which ESP shows targets."},
 ["Team check (Aim)"] = {"Не выбирать игроков своей команды целью наводки.", "Never select teammates as aim targets."},
 ["FOV circle"] = {"Показывает круг FOV при включённом Aim.", "Shows the FOV circle while Aim is enabled."},
 ["Fill"] = {"Включает заливку круга.", "Enables the circle fill."},
 ["Fill circle"] = {"Заливка внутри круга FOV.", "Fill inside the FOV circle."},
 ["Highlight on target"] = {"Меняет цвет круга при захвате цели.", "Changes the circle color when a target is acquired."},
 ["Dynamic FOV"] = {"Меняет радиус FOV в зависимости от расстояния до цели.", "Changes the FOV radius based on target distance."},
 ["Target animation"] = {"Показывает анимацию появления, захвата и потери цели.", "Shows animations when a target appears, is acquired or lost."},
 ["Animation style"] = {"Выбирает форму индикатора цели.", "Selects the target indicator shape."},
 ["Animation speed"] = {"Изменяет скорость анимации цели.", "Changes the target animation speed."},
 ["Visual preset"] = {"Выбирает готовый стиль отображения хитбоксов, не меняя их размер.", "Selects a hitbox visual preset without changing hitbox size."},
 ["Outline = fill color"] = {"Использует цвет заливки для обводки хитбокса.", "Uses the hitbox fill color for its outline."},
 ["Capture color"] = {"Окрашивает захваченную цель в цвет Locked.", "Tints the locked target using the Locked color."},
 ["Hitbox transparency"] = {"Общая прозрачность изображения хитбоксов.", "Overall hitbox visual transparency."},
 ["Fill transparency"] = {"Прозрачность заливки хитбоксов; 100% скрывает заливку.", "Hitbox fill transparency; 100% hides the fill."},
 ["Outline thickness (px)"] = {"Толщина обводки хитбоксов в пикселях.", "Hitbox outline thickness in pixels."},
 ["Distance limit (studs)"] = {"Максимальная дистанция отображения хитбоксов в студах.", "Maximum hitbox display distance in studs."},
 ["Edges (края)"] = {"Разрешает Multipoint проверять края выбранной части.", "Allows Multipoint to check the selected part's edges."},
 ["Head"] = {"Разрешает Multipoint искать точку на голове.", "Allows Multipoint to search the head."},
 ["Torso"] = {"Разрешает Multipoint искать точку на туловище.", "Allows Multipoint to search the torso."},
 ["Arms"] = {"Разрешает Multipoint искать точку на руках.", "Allows Multipoint to search the arms."},
 ["Legs"] = {"Разрешает Multipoint искать точку на ногах.", "Allows Multipoint to search the legs."},
 ["Visibility from head"] = {"Проверяет видимость от головы персонажа вместо камеры.", "Checks visibility from the character's head instead of the camera."},
 ["Main part"] = {"Выбирает основную часть тела в очереди приоритетов.", "Selects the primary body part in the priority order."},
 ["Select radius (silent), %"] = {"Радиус поиска Silent Aim в процентах короткой стороны экрана; сервер ограничивает угол.", "Silent Aim search radius as a percentage of the shorter screen side; the server limits the angle."},
 ["Lock release radius, %"] = {"Расстояние от центра наведения, после которого захват отпускается, в процентах короткой стороны экрана.", "Distance from the aim center at which a target lock is released, as a percentage of the shorter screen side."},
 ["Trigger tolerance (% of screen)"] = {"Допуск триггера вокруг прицела в процентах короткой стороны экрана.", "Trigger tolerance around the crosshair as a percentage of the shorter screen side."},
 ["FOV Size (diameter, px)"] = {"Диаметр круга и области выбора цели в пикселях: одинаковый на любом экране.", "Circle and target selection diameter in pixels: the same on any screen."},
 ["FOV Transparency"] = {"Прозрачность контура круга FOV.", "Transparency of the FOV circle outline."},
 ["FOV Thickness"] = {"Толщина контура круга FOV.", "Thickness of the FOV circle outline."},
 ["Fill Transparency"] = {"Прозрачность заливки круга FOV.", "Transparency of the FOV circle fill."},
 ["Invert (far = bigger)"] = {"Меняет направление динамического FOV: дальше — больше радиус.", "Reverses dynamic FOV: greater distance means a larger radius."},
 ["Change mode"] = {"Выбирает линейное или плавное изменение динамического FOV.", "Selects linear or smooth dynamic FOV interpolation."},
 ["Min radius, % of screen"] = {"Минимальный радиус динамического FOV в процентах короткой стороны экрана.", "Minimum dynamic FOV radius as a percentage of the shorter screen side."},
 ["Max radius, % of screen"] = {"Максимальный радиус динамического FOV в процентах короткой стороны экрана.", "Maximum dynamic FOV radius as a percentage of the shorter screen side."},
 ["Start distance (studs)"] = {"Ближняя дистанция, используемая динамическим FOV.", "Near distance used by dynamic FOV."},
 ["Max-change distance (studs)"] = {"Дальняя дистанция, используемая динамическим FOV.", "Far distance used by dynamic FOV."},
 ["Smoothing (higher = smoother)"] = {"Сглаживание изменения радиуса динамического FOV.", "Smooths changes to the dynamic FOV radius."},
 ["Capture effect"] = {"Включает эффект при захвате или смене цели.", "Enables the target acquisition and switching effect."},
 ["Lose effect"] = {"Включает эффект при потере цели.", "Enables the effect when a target is lost."},
 ["Circle = aim area"] = {"Связывает положение круга с точкой наведения; при выключении круг перемещается отдельно.", "Links the circle position to the aim point; when disabled, the circle moves independently."},
 ["Enable Friendly Color"] = {"Применяет цвета команды к союзникам; Team check может скрыть их.", "Applies friendly team colors; Team check may hide teammates."},
 ["Enable Enemy Color"] = {"Применяет цвета команды к противникам.", "Applies enemy team colors."},
 ["Enable NPC Color"] = {"Применяет отдельные цвета к NPC.", "Applies separate colors to NPCs."},
 ["Apply colors to all elements"] = {"Использует общий цвет команды для подсветки, имени, скелета и линий.", "Uses the team color for highlights, names, skeletons and tracers."},
 ["Team color preset"] = {"Выбирает пару цветов союзников и противников.", "Selects a friendly/enemy color pair."},
 ["Friendly color preset"] = {"Выбирает готовый цвет союзников.", "Selects a friendly color preset."},
 ["Enemy color preset"] = {"Выбирает готовый цвет противников.", "Selects an enemy color preset."},
 ["Team colors"] = {"Использует цвет команды в обычной подсветке игроков.", "Uses player team colors in the standard highlight."},
 ["Size by dist"] = {"Меняет размер меток в зависимости от расстояния.", "Changes label size with distance."},
 ["Animations"] = {"Включает анимации интерфейса.", "Enables interface animations."},
 ["Animated numbers"] = {"Плавно меняет цифры ползунков и счётчиков: значение доезжает, а не прыгает.", "Eases slider values and counters to the new number instead of jumping."},
 ["Toasts"] = {"Показывает результаты и ошибки всплывающей карточкой в углу вместо системных плашек.", "Shows results and errors in a corner card instead of system notifications."},
 ["Page cascade"] = {"Карточки только что открытой страницы проявляются сверху вниз.", "Cards of a freshly opened page fade in from top to bottom."},
 ["Accent pulse"] = {"Активная вкладка и точки включённых функций мягко пульсируют.", "The active tab and enabled-feature dots pulse softly."},
 ["Intro after key"] = {"Заставка после верного ключа: осколки слетаются, собирается UNICRASE (шрифт Michroma), кольца и блик. Идёт 3 секунды и не пропускается; выключение — ключ сразу открывает меню.", "Intro after a valid key: shards converge, UNICRASE assembles in Michroma with rings and a shine sweep. Lasts 3 seconds and cannot be skipped; off means the key opens the menu at once."},
 ["Particle text"] = {"Текст в папке собирается из частиц: у каждой буквы вспыхивают искры, слетаются к её месту, и буква проявляется. Выключение — текст появляется целиком.", "Folder text assembles from particles: sparks flash around each letter, converge into it, then the letter fades in. Off means text appears at once."},
 ["FPS / ping"] = {"Показывает частоту кадров и задержку в боковой панели.", "Shows frame rate and ping in the sidebar."},
 ["FPS unlock"] = {"Использует setfpscap, если функция доступна в окружении.", "Uses setfpscap when the environment provides it."},
 ["Menu Scale (zoom)"] = {"Масштабирует главное окно с учётом размера экрана.", "Scales the main window while fitting it to the screen."},
 ["Menu Transparency"] = {"Меняет прозрачность всего окна.", "Changes transparency of the whole window."},
 ["Background Transparency"] = {"Меняет прозрачность фона окна, шапки и боковой панели.", "Changes the transparency of the window, header and sidebar backgrounds."},
 ["Image Transparency"] = {"Меняет прозрачность фонового изображения.", "Changes background image transparency."},
 ["Card Transparency (with image)"] = {"Меняет прозрачность карточек, когда установлено фоновое изображение.", "Changes card transparency when a background image is active."},
 ["UI Scale (buttons, HUD, key)"] = {"Масштабирует плавающие кнопки, HUD и окно ключа.", "Scales floating buttons, HUD and the key window."},
 ["Corner Radius"] = {"Меняет скругление элементов интерфейса.", "Changes interface corner rounding."},
}
function helpUI.add(parent, title, desc, label)
	-- Поиску нужен сам объект настройки: по нему строится точная прокрутка к элементу.
	if not helpUI.cardOwner then
		for _, v in helpUI.items do
			if v.card == parent then helpUI.cardOwner, helpUI.cardTitle = parent, v.title break end
		end
	end
	-- Кнопка справки больше самого знака и не перекрывает переключатель.
	local b = new("TextButton", {Name = "Help", Size = O(28, 28), AnchorPoint = V2(0, 0.5),
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 5}, parent)
	icon("Info", b, 11)
	-- Отдельная колонка перед значением. Не измеряем TextBounds: на смене языка,
	-- при анимации UIScale и у длинного текста значок никогда не наезжает на буквы.
	local function place()
		local x, w = label.Position.X, label.Size.X
		b.Position = U(x.Scale + w.Scale, x.Offset + w.Offset, 0, label.Position.Y.Offset + label.Size.Y.Offset / 2)
	end
	on(label:GetPropertyChangedSignal("Size"), place)
	place()
	table.insert(helpUI.items, {card = parent, title = title, desc = desc})
	on(b.Activated, function() if helpUI.open then helpUI.open(title, desc) end end)
end

function Skin.setting(parent, order, interactive)
	local props = {Size = U(1, 0, 0, Skin.Row), BackgroundColor3 = C.Card, LayoutOrder = order or 0}
	if interactive then props.Text, props.AutoButtonColor = "", false end
	local f = new(interactive and "TextButton" or "Frame", props, parent)
	rr(f, Skin.Radius)
	local h = hoverable(f, outline(f), interactive and {bg = C.Card, bgHover = C.Sel} or nil)
	return f, h
end

function Skin.copy(card, title, desc, reserve)
	local label = new("TextLabel", {Name = "Title", Size = U(1, -reserve - 28, 0, 20), Position = O(Skin.Inset, 8),
		BackgroundTransparency = 1, Text = title, TextColor3 = C.W, FontFace = GM, TextSize = 14, TextXAlignment = XL,
		TextTruncate = Enum.TextTruncate.AtEnd, Active = false}, card)
	local caption = new("TextLabel", {Name = "Caption", Size = U(1, -reserve, 0, 16), Position = O(Skin.Inset, 29),
		BackgroundTransparency = 1, Text = desc or (helpUI.info[title] and helpUI.info[title][1]) or "",
		TextColor3 = C.Mut, FontFace = GR, TextSize = 12, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, Active = false}, card)
	helpUI.add(card, title, desc, label)
	return label, caption
end

local function toggleCard(parent, text, order, getv, setv, desc)
	local b = Skin.setting(parent, order, true)
	Skin.copy(b, text, desc, 80)
	local sw, swPaint = makeSwitch(b)
	sw.AnchorPoint, sw.Position = V2(1, 0.5), U(1, -Skin.Inset, 0.5, 0)
	local function paint(anim) swPaint(getv(), anim) end
	paint(false)
	on(b.Activated, function() setv(not getv()); paint(true) end)
	return b, paint
end

local function cycleCard(parent, text, order, getv, nextv, isOn)
	local b = Skin.setting(parent, order, true)
	local label, caption = Skin.copy(b, text, nil, 120)
	local pill = new("TextLabel", {
		AnchorPoint = V2(1, 0.5), Position = U(1, -Skin.Inset, 0.5, 0), Size = O(0, 24), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Sel, Text = "", TextColor3 = C.W, FontFace = GM, TextSize = 12, Active = false,
	}, b)
	new("UIPadding", {PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9)}, pill)
	rr(pill, 6)
	local function fitLabel()
		if b.AbsoluteSize.X <= 0 then return end
		-- Ширина значения в долях карточки остаётся верной при любом UIScale.
		local frac = 1 - pill.AbsoluteSize.X / b.AbsoluteSize.X
		label.Size = U(frac, -2 * Skin.Inset - 36, 0, 20)
		caption.Size = U(frac, -2 * Skin.Inset - 8, 0, 16)
	end
	on(pill:GetPropertyChangedSignal("AbsoluteSize"), fitLabel)
	on(b:GetPropertyChangedSignal("AbsoluteSize"), fitLabel)
	local function paint(anim)
		local txt = tostring(getv()) .. "  ›"
		local dim = not (isOn == nil or isOn())
		pill.Text, pill.TextColor3 = txt, dim and C.Mut or C.W
		if anim and CFG.Anim and UICFG.AnimCounters then
			-- значение «перещёлкивается»: короткий масштаб и фейд, видно, что нажатие сработало
			local sc = pill:FindFirstChild("PopScale")
			if not sc then sc = new("UIScale", {Name = "PopScale", Scale = 1}, pill) end
			sc.Scale = 0.86
			spring(sc, {Scale = 1}, TWEEN.pop)
			pill.TextTransparency = 0.35
			tween(pill, TWEEN.ui, {TextTransparency = 0})
		end
	end
	paint()
	fitLabel()
	on(b.Activated, function() nextv(); paint(true) end)
	return b, paint
end

-- пока тянем ползунок, список под ним не должен скроллиться
local lockedSF
local function unlockSF()
	if lockedSF then
		lockedSF.ScrollingEnabled = true
		lockedSF = nil
	end
end
-- слайдер: название и значение сверху, дорожка и бегунок акцентного цвета, зона касания 32 px
local function sliderCard(parent, title, order, min, max, getv, setv, fmt, step)
	local f, h = Skin.setting(parent, order, false)
	local label = new("TextLabel", {
		Size = U(1, -112, 0, 20), Position = O(Skin.Inset, 7), BackgroundTransparency = 1, Text = title, TextColor3 = C.W,
		FontFace = GM, TextSize = 14, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, Active = false,
	}, f)
	local val = new("TextLabel", {
		Name = "Value", Size = O(54, 20), AnchorPoint = V2(1, 0), Position = U(1, -Skin.Inset, 0, 7), BackgroundTransparency = 1, Text = "",
		TextColor3 = C.Mut, FontFace = GM, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, Active = false,
	}, f)
	helpUI.add(f, title, nil, label)
	local hit = new("Frame", {Name = "SliderHit", Size = U(1, -2 * Skin.Inset, 0, 32), Position = O(Skin.Inset, 24), BackgroundTransparency = 1, Active = true}, f)
	local track = new("Frame", {
		Name = "Track", Size = U(1, 0, 0, 5), AnchorPoint = V2(0, 0.5), Position = U(0, 0, 0.5, 0), BackgroundColor3 = C.Hi, Active = false,
	}, hit)
	round(track, 3)
	local bar = new("Frame", {Name = "ValueFill", Size = U(0, 0, 1, 0), Active = false}, track)
	accent(bar, "BackgroundColor3")
	round(bar, 3)
	local knob = new("Frame", {Name = "Thumb", Size = O(13, 13), AnchorPoint = V2(0.5, 0.5), ZIndex = 3, Active = false}, track)
	accent(knob, "BackgroundColor3")
	round(knob, 7)
	local shownValue -- последнее показанное число: нужно для анимации цифры
	local function paint(anim)
		if anim == nil then anim = CFG.Anim end -- внешние вызовы (сброс, пресет) анимируются, перетаскивание — нет
		local v = getv()
		local x = math.clamp((v - min) / (max - min), 0, 1)
		if anim and shownValue and math.abs(v - shownValue) > 1e-6 then
			-- при сбросе/смене пресета число «доезжает», а не прыгает
			local a, b = shownValue, v
			animateNumber(val, a, b, fmt)
		else
			val.Text = fmt(v)
		end
		shownValue = v
		if anim then
			-- бегунок и заполнение двигаются мягко, дорожка подскакивает под палец
			spring(knob, {Position = U(x, 0, 0.5, 0)}, TWEEN.ui)
			tween(bar, TWEEN.ui, {Size = U(x, 0, 1, 0)})
			tween(knob, TWEEN.snap, {Size = O(15, 15)})
			task.delay(0.12, function() if knob.Parent then tween(knob, TWEEN.ui, {Size = O(13, 13)}) end end)
		else
			bar.Size, knob.Position = U(x, 0, 1, 0), U(x, 0, 0.5, 0)
		end
	end
	drag(hit, function(x)
		local v = min + (max - min) * x
		if step then v = math.floor(v / step + 0.5) * step end
		setv(math.clamp(v, min, max))
		paint(false)
	end, function()
		h.pressed = true
		h.apply()
		local sf = hit:FindFirstAncestorWhichIsA("ScrollingFrame")
		if sf then
			sf.ScrollingEnabled = false
			lockedSF = sf
		end
	end, function()
		h.pressed = false
		h.apply()
		unlockSF()
	end)
	paint()
	return f, paint
end

-- вкладка выбора цвета: точка с текущим цветом + название, выбранная подсвечена яркой обводкой
local function colorTab(parent, name, size, order, onClick)
	local b = new("TextButton", {Size = size, BackgroundColor3 = C.Card, Text = "", AutoButtonColor = false, LayoutOrder = order}, parent)
	rr(b, 8)
	local h = hoverable(b, outline(b), {bg = C.Card, bgHover = C.Sel})
	local dot = new("Frame", {Size = O(10, 10), AnchorPoint = V2(0, 0.5), Position = U(0, 8, 0.5, 0), Active = false}, b)
	round(dot, 5)
	stroke(dot, PURE, OUT.Hover, 1)
	new("TextLabel", {
		Size = U(1, -22, 1, 0), Position = O(22, 0), BackgroundTransparency = 1, Text = name, TextColor3 = C.W,
		FontFace = GM, TextSize = 11, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, Active = false,
	}, b)
	on(b.Activated, onClick)
	return {btn = b, dot = dot, h = h}
end
local function colorTabSel(t, sel)
	if t.sel == sel then return end
	t.sel = sel
	t.h.bg = sel and "Sel" or "Card"
	t.h.base = sel and OUT.Active or OUT.Idle
	t.h.apply()
end

-- Цветной здесь только образец, а не вся кнопка. Ряд помещается и в узкую страницу.
function Skin.swatch(parent, i, count, color)
	local b = button(parent, "", {Size = U(1 / count, -8 * (count - 1) / count, 1, 0), BackgroundColor3 = C.Card, LayoutOrder = i})
	local sample = new("Frame", {Size = O(18, 18), AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), BackgroundColor3 = color, Active = false}, b)
	round(sample, 9)
	outline(sample, OUT.Hover)
	return b
end

-- Палитра (квадрат S/V + полоса оттенка + HEX). getC(edit) отдаёт таблицу {h,s,v}
local function makePicker(parent, order, getC, onEdit, extra)
	local card = new("Frame", {Size = U(1, 0, 0, 170), BackgroundColor3 = C.Card, LayoutOrder = order}, parent)
	rr(card, Skin.Radius)
	outline(card)
	local sv = new("Frame", {Size = U(1, -20, 0, 92), Position = O(10, 10)}, card)
	rr(sv, 6)
	outline(sv, OUT.Hover)
	for _, d in {{PURE, 0, NumberSequence.new(0, 1)}, {C.B, 90, NumberSequence.new(1, 0)}} do
		local f = new("Frame", {Size = S(1, 1), BackgroundColor3 = d[1], Active = false}, sv)
		rr(f, 6)
		new("UIGradient", {Rotation = d[2], Transparency = d[3]}, f)
	end
	local svCur = new("Frame", {Size = O(14, 14), AnchorPoint = V2(0.5, 0.5), BackgroundColor3 = PURE, ZIndex = 3, Active = false}, sv)
	round(svCur, 7) stroke(svCur, C.B, 0, 2)
	local hueBar = new("Frame", {Size = U(1, -20, 0, 14), Position = O(10, 110), BackgroundColor3 = PURE}, card)
	round(hueBar, 7)
	local keys = {}
	for i = 0, 6 do table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6 % 1, 1, 1))) end
	new("UIGradient", {Color = ColorSequence.new(keys)}, hueBar)
	local hueCur = new("Frame", {Size = O(8, 20), AnchorPoint = V2(0.5, 0.5), BackgroundColor3 = PURE, ZIndex = 3, Active = false}, hueBar)
	round(hueCur, 3) stroke(hueCur, C.B, 0, 1.5)
	local hex = new("TextBox", {
		Size = U(1, -20, 0, 26), Position = O(10, 134), BackgroundColor3 = C.Input,
		Text = "", PlaceholderText = "HEX #RRGGBB", TextColor3 = C.W, PlaceholderColor3 = C.Mut,
		FontFace = GB, TextSize = 13, ClearTextOnFocus = false,
	}, card)
	Skin.field(hex)
	local function refresh()
		local c = getC(false)
		sv.BackgroundColor3 = Color3.fromHSV(c.h, 1, 1)
		svCur.Position = S(c.s, 1 - c.v)
		hueCur.Position = S(c.h, 0.5)
		if not hex:IsFocused() then hex.Text = "#" .. hsv(c):ToHex():upper() end
		if extra then extra() end
	end
	drag(sv, function(x, y) local c = getC(true); c.s, c.v = x, 1 - y; onEdit(); refresh() end)
	drag(hueBar, function(x) getC(true).h = x; onEdit(); refresh() end)
	on(hex.FocusLost, function()
		local ok, c3 = pcall(Color3.fromHex, hex.Text)
		if ok then
			local h, s, v = c3:ToHSV()
			local c = getC(true)
			if s > 0.001 and v > 0.001 then c.h = h end
			c.s, c.v = s, v
			onEdit()
		end
		refresh()
	end)
	return card, refresh
end

-- ===== Aim assist (встроен в меню: папки Aim / Targets / Trigger / Hitbox / FOV) =====
local aim
	-- buildAim вынесен отдельной частью: её локали не входят в лимит 200 этого куска.
	local function buildAim(page, api)
		local fn, err = GLB.loadPart and GLB.loadPart("aim")
		if not fn then
			warn("[Enkaisy] часть aim не загрузилась: " .. tostring(err))
			return
		end
		return fn(page, api)
	end

-- ===== Загрузка фона-картинки (общая для окна меню и окна ключа) =====
-- ID / rbxassetid:// / ссылка roblox.com работают везде. Прямая ссылка (png/jpg) скачивается через request/HttpGet,
-- сохраняется writefile и показывается через getcustomasset — это есть только в окружениях, где эти функции доступны.
GLB.CP = game:GetService("ContentProvider")
local function trimS(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function bgHttp(url)
	local req = (type(request) == "function" and request) or (type(http_request) == "function" and http_request)
		or (type(syn) == "table" and type(syn.request) == "function" and syn.request) or nil
	if req then
		local ok, res = pcall(req, {Url = url, Method = "GET"})
		if ok and type(res) == "table" then
			local code = tonumber(res.StatusCode)
			if (code == nil or code == 200) and type(res.Body) == "string" and #res.Body > 0 then return res.Body end
			return nil, "HTTP " .. tostring(res.StatusCode or "?")
		end
		return nil, "запрос не удался"
	end
	local ok, body = pcall(function() return game:HttpGet(url) end)
	if ok and type(body) == "string" and #body > 0 then return body end
	return nil, "нет http-функций"
end
local function bgFetch(src)
	local id = src:match("^rbxassetid://(%d+)$") or src:match("^(%d+)$")
	if id then return "rbxassetid://" .. id end
	if src:match("^rbxasset://") or src:match("^rbxthumb://") or src:match("^rbxassetid://") then return src end
	if src:find("roblox%.com") and not src:find("rbxcdn", 1, true) then
		local rid = src:match("[?&]id=(%d+)") or src:match("/(%d+)")
		if rid then return "rbxassetid://" .. rid end
	end
	if not src:match("^https?://") then return nil, "Не похоже на ссылку или ID" end
	local getAsset = (type(getcustomasset) == "function" and getcustomasset) or (type(getsynasset) == "function" and getsynasset)
	if not (GLB.canFile and getAsset) then
		return nil, "Прямые ссылки работают только где есть writefile и getcustomasset. Используй ID: rbxassetid://12345 или просто число."
	end
	local base = "TH_bg_" .. hashKey(src)
	for _, ext in {"png", "jpg"} do -- уже скачивали эту ссылку — берём файл с диска
		local p = base .. "." .. ext
		local okF, has = pcall(isfile, p)
		if okF and has then
			local okA, a = pcall(getAsset, p)
			if okA and type(a) == "string" and a ~= "" then return a end
		end
	end
	local body, err = bgHttp(src)
	if not body then return nil, "Не удалось скачать: " .. tostring(err) end
	if #body > 12 * 1024 * 1024 then return nil, "Файл больше 12 МБ" end
	local ext = body:sub(1, 8) == "\137PNG\r\n\26\n" and "png" or body:sub(1, 3) == "\255\216\255" and "jpg" or nil
	if not ext then return nil, "Это не PNG/JPG: нужна прямая ссылка на файл картинки" end
	local p = base .. "." .. ext
	if not pcall(writefile, p, body) then return nil, "Не удалось сохранить файл" end
	local okA, a = pcall(getAsset, p)
	if not okA or type(a) ~= "string" or a == "" then return nil, "getcustomasset не сработал" end
	return a
end

-- ===== Экран ключа и запуск интерфейса =====
-- Эта часть — отдельный кусок кода. Отдельный файл нужен, чтобы её локали не считались
-- в лимите 200 вместе с сервером и ключом.
local mainPart = nil
local function startMain()
	local ok, e = pcall(function()
		mainPart = mainPart or GLB.loadPart("main")
		if not mainPart then error(e or "часть main не загрузилась") end
		mainPart.run({gui = gui, stop = stop, startMain = startMain, keyScreen = keyScreen})
	end)
	if not ok then
		pcall(function()
			game:GetService("StarterGui"):SetCore("SendNotification",
				{Title = "Enkaisy error", Text = tostring(e):sub(1, 120), Duration = 15})
		end)
	end
end

keyScreen(function() startMain() end)
