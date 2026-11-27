-- Enkaisy: ESP + Aim Assist (всё в одном скрипте) — для собственной Roblox-игры
--
-- УСТАНОВКА: один обычный Script в ServerScriptService (RunContext не трогать).
-- Скрипт сам копирует себя в ReplicatedStorage как клиентский, и он запускается у каждого игрока.
--
-- ОРУЖИЕ: любой Tool с атрибутом Damage (number). Необязательно: Range (500), Cooldown (0.15).
-- NPC для Aim: любые модели с Humanoid (их находит ESP) или с тегом AimTarget.
--
-- Интерфейс: только Android / сенсорное управление. Вид (тема, акцент, прозрачность, масштаб) — вкладка Appearance.
-- Управление: меню Enkaisy (кнопка-логотип), вкладка Aim, плавающая кнопка AIM, вкладка FOV для круга.
-- Triggerbot/Multipoint/Adv predict/Checks: вкладка Aim. Атрибуты Tool: BulletSpeed, BulletGravity. Атрибуты модели: Invulnerable, Flashed, InSmoke; тег SmokeCloud.

-- Target Lock: переключатель в Aim, кнопка Switch locked target = сменить цель. Silent Aim: переключатель в Aim (лимит угла — на сервере, SILENT_MAX_ANGLE).
-- Aim-координаты: ТОЧКА НАВЕДЕНИЯ (логика) и КРУГ FOV (визуал) — независимые значения в долях экрана; радиусы областей — % короткой стороны экрана.
-- Вкладка Aim: "Edit FOV / aim position" (что двигать выбирается явно), "Check coordinates" (проверка на устройстве).


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
-- Размер, положение окна и последняя вкладка сохраняются; раскладка (1/2/3 колонки) подстраивается под ширину.
local Players = game:GetService("Players")
local RS = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local REMOTE_NAME = "EnkaisyAimFire"
local CLIENT_NAME = "EnkaisyAimClient"

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
local function rayModelHitbox(origin, dir, maxDist, model, bodyPad, headPad)
	local bestT, bestPart
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			local pad = bodyPad
			if p.Name == "Head" then pad = math.max(bodyPad, headPad) end
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
    remote.Name = REMOTE_NAME
    remote:SetAttribute("SilentMaxAngle", SILENT_MAX_ANGLE) -- клиент подгоняет свой SilentFOV под этот угол
    remote:SetAttribute("HitboxMaxBody", HITBOX_ALLOWED and HITBOX_MAX_BODY or 0) -- клиент ограничивает ползунки хитбоксов
    remote:SetAttribute("HitboxMaxHead", HITBOX_ALLOWED and HITBOX_MAX_HEAD or 0)
    remote.Parent = ReplicatedStorage

    -- Клиентская копия этого же скрипта
    local clientCopy = script:Clone()
    clientCopy.Name = CLIENT_NAME
    clientCopy.RunContext = Enum.RunContext.Client
    clientCopy.Parent = ReplicatedStorage

    local lastShot = {}

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

        local range = tool:GetAttribute("Range")
        if type(range) ~= "number" then range = DEFAULT_RANGE end

        local cooldown = tool:GetAttribute("Cooldown")
        if type(cooldown) ~= "number" then cooldown = DEFAULT_COOLDOWN end

        -- 4. Кулдаун
        local now = os.clock()
        if now - (lastShot[plr] or 0) < cooldown * 0.9 then return "cooldown" end -- 10% допуск на джиттер сети
        lastShot[plr] = now

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
        if type(speed) == "number" and speed > 0 and type(grav) == "number" and grav > 0 then
            local step = 0.04
            local tMax = range / speed
            local prev, t = origin, step
            while t <= tMax + step do
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
                prev, t = pos, t + step
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

    Players.PlayerRemoving:Connect(function(plr)
        lastShot[plr] = nil
    end)

    return
end

----------------------------------------------------------------
-- КЛИЕНТСКАЯ ЧАСТЬ
----------------------------------------------------------------
if _G.TH_Stop then pcall(_G.TH_Stop) end
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local Stats = game:GetService("Stats")
local LP = Players.LocalPlayer
local U, S, O, V2 = UDim2.new, UDim2.fromScale, UDim2.fromOffset, Vector2.new
local GB, GM, XL = Enum.Font.GothamBold, Enum.Font.GothamMedium, Enum.TextXAlignment.Left
local KEY_HASH = 200016687

local MODES = {"Players", "NPC", "Both"}
local DIST_MAX = 2000
local CFG = {
	On = true, Mode = "Players",
	Hl = true, Names = false, HP = false, Pct = false,
	TeamCheck = false, HideDead = true, Rainbow = false, Disp = false,
	Fill = 0.45, Outline = 1, NameSize = 16, NameLen = 14,
	Dist = false, HPColor = false, Limit = true, LimitN = 30, MaxDist = DIST_MAX,
	FriendMode = "Off", NpcFilter = "Off", NpcText = "", HideNative = true,
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
	TargetPart = "Head", Priority = "Crosshair", VisFromHead = true,
TargetLock = false, SilentAim = false,
FovR = 18, SilentR = 14, LockR = 28, -- радиусы областей в % короткой стороны экрана (не зависят от разрешения)
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
	PanelW = 480, PanelH = 392, PanelCX = -1, PanelCY = -1, Tab = "Main",
	BgImage = "", BgImgAlpha = 0.25, BgImgFit = "Crop", CardAlpha = 0.5, -- фон окна: ссылка / ID картинки, прозрачность, режим
}
local WIN_MIN_W, WIN_MIN_H, WIN_MAX_W, WIN_MAX_H = 440, 320, 900, 700

-- ===== ТЕМА: Modern Dark Gaming Dashboard (минималистичный тактический стиль) =====
-- Глубокий чёрный и тёмно-серый фон. Белый — только для тонких контуров, иконок, текста и акцентов.
-- Цвета и яркость белых контуров меняются здесь.
local C = {
	Win = Color3.fromRGB(10, 10, 12),     -- фон окна
	Side = Color3.fromRGB(14, 14, 16),    -- шапка, боковое меню, подвал
	Card = Color3.fromRGB(20, 20, 23),    -- карточки и ряды
	Input = Color3.fromRGB(26, 26, 30),   -- поля, кнопки, дорожки
	Line = Color3.fromRGB(38, 38, 43),    -- разделители
	Sel = Color3.fromRGB(33, 33, 38),     -- выбранный элемент / наведение
	Hi = Color3.fromRGB(50, 50, 57),      -- дорожка слайдера
	Mut = Color3.fromRGB(124, 124, 134),  -- серый текст и неактивные иконки
	W = Color3.fromRGB(240, 240, 242),    -- основной текст / белые элементы
	Dark = Color3.fromRGB(10, 10, 12),    -- тёмный текст на белом
	On = Color3.fromRGB(120, 225, 155), Off = Color3.fromRGB(215, 85, 85),
	Danger = Color3.fromRGB(235, 120, 120), DangerBg = Color3.fromRGB(86, 30, 34),
	B = Color3.new(),
	Acc = Color3.fromRGB(240, 240, 240), AccTx = Color3.fromRGB(10, 10, 12), -- акцент (Appearance)
}
local PURE = Color3.new(1, 1, 1)
-- Палитры тем (Dark / Midnight / Amoled / Forest / Crimson). Win всегда равен Dark (тёмный текст на акценте).
local THEMES = {
	Dark = {Win = {10, 10, 12}, Side = {14, 14, 16}, Card = {20, 20, 23}, Input = {26, 26, 30}, Line = {38, 38, 43}, Sel = {33, 33, 38}, Hi = {50, 50, 57}, Mut = {124, 124, 134}, W = {240, 240, 242}},
	Midnight = {Win = {8, 11, 20}, Side = {12, 16, 28}, Card = {18, 24, 40}, Input = {24, 32, 52}, Line = {34, 44, 70}, Sel = {30, 40, 66}, Hi = {48, 62, 96}, Mut = {118, 130, 162}, W = {234, 240, 252}},
	Amoled = {Win = {0, 0, 0}, Side = {6, 6, 7}, Card = {13, 13, 15}, Input = {21, 21, 24}, Line = {31, 31, 35}, Sel = {27, 27, 31}, Hi = {46, 46, 52}, Mut = {120, 120, 128}, W = {244, 244, 246}},
	Forest = {Win = {9, 14, 12}, Side = {12, 19, 16}, Card = {18, 28, 23}, Input = {24, 37, 30}, Line = {34, 52, 43}, Sel = {30, 46, 38}, Hi = {48, 72, 60}, Mut = {122, 144, 131}, W = {236, 245, 239}},
	Crimson = {Win = {14, 9, 10}, Side = {20, 12, 14}, Card = {30, 18, 21}, Input = {40, 24, 28}, Line = {58, 34, 40}, Sel = {52, 30, 36}, Hi = {80, 48, 56}, Mut = {146, 122, 128}, W = {247, 238, 240}},
}
local THEME_ORDER = {"Dark", "Midnight", "Amoled", "Forest", "Crimson"}
local PAL = {"Win", "Side", "Card", "Input", "Line", "Sel", "Hi", "Mut", "W"}
local function applyPalette(name)
	local t = THEMES[name] or THEMES.Dark
	for _, k in PAL do
		C[k] = Color3.fromRGB(t[k][1], t[k][2], t[k][3])
	end
	C.Dark = C.Win
end
local function applyAccent()
	local a = UICFG.Accent
	C.Acc = Color3.fromHSV(a.h, a.s, a.v)
	local lum = 0.299 * C.Acc.R + 0.587 * C.Acc.G + 0.114 * C.Acc.B
	C.AccTx = lum > 0.55 and Color3.fromRGB(10, 10, 12) or Color3.fromRGB(245, 245, 247)
end
-- Прозрачность тонкой белой обводки (0 = яркая, 1 = нет):
-- Idle — покой, Hover — наведение/нажатие, Active — выбранное, Soft — информационные плашки
local OUT = {Idle = 0.66, Hover = 0.38, Active = 0.1, Soft = 0.84}
-- Окно ключа: KEY_DIM больше = игра просвечивает сильнее (светлее), KEY_BG = цвет карточки
local KEY_BG = Color3.fromRGB(16, 16, 19)
local KEY_DIM = 0.7
local KEY_BLUR = 14
-- статусы FPS / пинга: белый = хорошо, приглушённые жёлтый и красный = хуже
local GOOD, MID, BAD = Color3.fromRGB(226, 226, 230), Color3.fromRGB(214, 190, 120), Color3.fromRGB(222, 100, 100)

-- FPS unlocker (нужен executor с setfpscap; 0 = без лимита)
local canFps = type(setfpscap) == "function"
local FPS_STEPS = {60, 90, 120, 144, 240, 0}
local function applyFps()
	if not canFps then return end
	pcall(setfpscap, CFG.FpsUnlock and CFG.FpsCap or 60)
end
local fast = TweenInfo.new(0.16, Enum.EasingStyle.Quad)
local slow = TweenInfo.new(0.3, Enum.EasingStyle.Quint)
local esp, pconn, conns, blur = {}, {}, {}, nil
local npcs, npcConn = {}, {}
local counterLbl, statsFps, statsPing, statsCard, plrHook, statusFn
local marks = {} -- [UserId] = "Mark" | "Hide" (только на время сессии)
local pset = {}  -- [tostring(UserId)] = {Name/Hl/Fill/Outline/HP/Dist = "On"|"Off", cols = {Fill/Outline/Name = {h,s,v}}}
local PKEYS = {"Name", "Hl", "Fill", "Outline", "HP", "Dist"}
local PCOLS = {"Fill", "Outline", "Name"}
local fps, lastT, lastStat = 60, os.clock(), 0
local alive = true

-- ===== Сохранение настроек =====
local friendCache, NpcWords = {}, {}
local FILE = "TH_Settings.json"
local canFile = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
local lastSaved = ""
local function serialize() return HttpService:JSONEncode({CFG = CFG, col = col, pset = pset, AIM = AIMCFG, UI = UICFG}) end
local function saveNow()
	if not canFile then return end
	local ok, s = pcall(serialize)
	if ok and s ~= lastSaved then
		lastSaved = s
		pcall(writefile, FILE, s)
	end
end
local function deepCopy(t)
	local r = {}
	for k, v in t do r[k] = type(v) == "table" and deepCopy(v) or v end
	return r
end
local DEF = {CFG = deepCopy(CFG), col = deepCopy(col), AIM = deepCopy(AIMCFG), UI = deepCopy(UICFG)}
if canFile then
	pcall(function()
		if not isfile(FILE) then return end
		local d = HttpService:JSONDecode(readfile(FILE))
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
				for _, k in PKEYS do
					if t[k] == "On" or t[k] == "Off" then e[k] = t[k] end
				end
				if type(t.cols) == "table" then
					local cc = {}
					for _, n in PCOLS do
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
AIMCFG.Smoothness = math.clamp(AIMCFG.Smoothness, 0.01, 1)
AIMCFG.Prediction = math.clamp(AIMCFG.Prediction, 0, 0.6)
AIMCFG.TriggerR = math.clamp(AIMCFG.TriggerR, 0.5, 15)
AIMCFG.LeadBias = math.clamp(AIMCFG.LeadBias, 0, 300)
AIMCFG.MaxDistance = math.clamp(AIMCFG.MaxDistance, 50, 2000)
AIMCFG.Sticky = math.clamp(AIMCFG.Sticky, 0.2, 1)
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
if not table.find(MODES, CFG.Mode) then CFG.Mode = "Players" end
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
if not table.find(FPS_STEPS, CFG.FpsCap) then CFG.FpsCap = 0 end
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
pcall(function() lastSaved = serialize() end)

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
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in props do o[k] = v end
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
local corners = setmetatable({}, {__mode = "k"})
local function rr(o, r, cap)
	local c = round(o, r)
	corners[c] = {r, cap}
	return c
end
local function applyRadius()
	local d0 = UICFG.Corner - 8
	for c, d in corners do
		if c.Parent then
			local r = math.max(0, d[1] + d0)
			if d[2] then r = math.min(r, d[2]) end
			c.CornerRadius = UDim.new(0, r)
		else
			corners[c] = nil
		end
	end
end
local accents = setmetatable({}, {__mode = "k"})
local function accent(inst, prop)
	accents[inst] = prop
	inst[prop] = C.Acc
	return inst
end
local floatScales = setmetatable({}, {__mode = "k"})
-- цвета палитры хранятся по имени, чтобы смена темы доезжала до hover-состояний
local function nameOf(c)
	if typeof(c) ~= "Color3" then return c end
	for _, k in PAL do
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
-- тонкая белая обводка: единый стиль кнопок, меню и карточек
local function outline(o, t) return stroke(o, PURE, t or OUT.Idle, 1) end
local function on(sig, fn) local c = sig:Connect(fn); table.insert(conns, c); return c end
local UT = Enum.UserInputType
local function press(i) return i.UserInputType == UT.Touch or i.UserInputType == UT.MouseButton1 end
local function move(i) return i.UserInputType == UT.Touch or i.UserInputType == UT.MouseMovement end
local function hashKey(s)
	local h = 5381
	for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
	return h
end

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

-- Кнопка: тёмная заливка + тонкая белая обводка. opt.primary — главная (ярче обводка), opt.danger — красный текст
local function button(parent, text, props, opt)
	opt = opt or {}
	props.Text, props.Font, props.AutoButtonColor = text, GB, false
	props.TextSize = props.TextSize or 12
	props.TextColor3 = props.TextColor3 or (opt.danger and C.Danger or C.W)
	props.BackgroundColor3 = props.BackgroundColor3 or (opt.primary and C.Sel or C.Input)
	local b = new("TextButton", props, parent)
	rr(b, 8)
	local base = opt.primary and 0.28 or OUT.Idle
	hoverable(b, outline(b, base), {base = base, hover = opt.primary and 0.05 or OUT.Hover, down = 0})
	return b
end
local function row(parent, h, pad, order)
	local f = new("Frame", {Size = U(1, 0, 0, h), BackgroundTransparency = 1, LayoutOrder = order or 0}, parent)
	new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, pad), SortOrder = Enum.SortOrder.LayoutOrder}, f)
	return f
end
local function getPing()
	local ok, v = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
	if ok and type(v) == "number" then return v end
	return LP:GetNetworkPing() * 2000
end

-- Переключатель ON / OFF (под палец): ON = дорожка акцентного цвета, бегунок справа; OFF = тёмная дорожка, бегунок слева
local function makeSwitch(parent)
	local track = new("Frame", {Size = O(52, 28), BackgroundColor3 = C.Input, Active = false}, parent)
	round(track, 14)
	local st = stroke(track, PURE, 0.55, 1)
	local lOn = new("TextLabel", {
		Size = O(27, 28), BackgroundTransparency = 1, Text = "ON", Font = GB, TextSize = 10,
		TextColor3 = C.AccTx, TextTransparency = 1, Active = false,
	}, track)
	local lOff = new("TextLabel", {
		Size = O(27, 28), Position = O(25, 0), BackgroundTransparency = 1, Text = "OFF", Font = GB, TextSize = 10,
		TextColor3 = C.Mut, Active = false,
	}, track)
	local knob = new("Frame", {
		Size = O(22, 22), AnchorPoint = V2(0, 0.5), Position = U(0, 3, 0.5, 0),
		BackgroundColor3 = C.Mut, Active = false, ZIndex = 2,
	}, track)
	round(knob, 11)
	local function paint(o, anim)
		o = o and true or false
		lOn.TextColor3 = C.AccTx
		put(track, {BackgroundColor3 = o and C.Acc or C.Input}, anim)
		put(knob, {Position = o and U(1, -25, 0.5, 0) or U(0, 3, 0.5, 0), BackgroundColor3 = o and C.AccTx or C.Mut}, anim)
		put(st, {Transparency = o and 0.1 or 0.55}, anim)
		put(lOn, {TextTransparency = o and 0 or 1}, anim)
		put(lOff, {TextTransparency = o and 1 or 0}, anim)
	end
	return track, paint
end

local gui = new("ScreenGui", {
	Name = "EnkaisyGui", ResetOnSpawn = false, DisplayOrder = 100,
	IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, LP:WaitForChild("PlayerGui"))
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)

local function logo(size, ts, parent)
	local f = new("Frame", {Size = O(size, size), BackgroundColor3 = C.Input, Active = false}, parent)
	round(f, size / 2)
	local st = outline(f, 0.35)
	new("TextLabel", {
		Size = S(1, 1), BackgroundTransparency = 1, Text = "E",
		TextColor3 = C.W, Font = Enum.Font.GothamBlack, TextSize = ts, Active = false,
	}, f)
	return f, st
end

-- Иконки меню: рисуются из тонких рамок (один стиль линий, без картинок и ассетов).
-- Возвращает контейнер 16x16 и paint(цвет, anim) для смены цвета при выборе вкладки.
local function icon(name, parent)
	local box = new("Frame", {Size = O(16, 16), AnchorPoint = V2(0, 0.5), BackgroundTransparency = 1, Active = false}, parent)
	local strokes, fills = {}, {}
	local function ring(x, y, w, h, r)
		local f = new("Frame", {Size = O(w, h), Position = O(x, y), BackgroundTransparency = 1, Active = false}, box)
		round(f, r)
		table.insert(strokes, stroke(f, C.Mut, 0, 1))
	end
	local function fill(x, y, w, h, r)
		local f = new("Frame", {Size = O(w, h), Position = O(x, y), BackgroundColor3 = C.Mut, BorderSizePixel = 0, Active = false}, box)
		if r then round(f, r) end
		table.insert(fills, f)
	end
	if name == "Main" then            -- сетка 2x2
		ring(1, 1, 6, 6, 2) ring(9, 1, 6, 6, 2) ring(1, 9, 6, 6, 2) ring(9, 9, 6, 6, 2)
	elseif name == "Aim" then         -- прицел
		ring(2, 2, 12, 12, 6)
		fill(7.5, 0, 1, 4) fill(7.5, 12, 1, 4) fill(0, 7.5, 4, 1) fill(12, 7.5, 4, 1)
	elseif name == "FOV" then         -- круг в круге
		ring(0, 0, 16, 16, 8) ring(4, 4, 8, 8, 4) fill(7, 7, 2, 2, 1)
	elseif name == "Color" or name == "Appearance" then       -- палитра
		ring(1, 1, 14, 14, 7)
		fill(4, 5, 2, 2, 1) fill(9, 4, 2, 2, 1) fill(7, 9, 2, 2, 1)
	elseif name == "Sizes" then       -- ползунки
		fill(1, 3, 14, 1) fill(1, 8, 14, 1) fill(1, 13, 14, 1)
		fill(9, 1, 4, 4, 2) fill(3, 6, 4, 4, 2) fill(10, 11, 4, 4, 2)
	elseif name == "Extra" then       -- фильтр
		fill(1, 3, 14, 1.5, 1) fill(3.5, 7.5, 9, 1.5, 1) fill(6, 12, 4, 1.5, 1)
	elseif name == "Visual" then      -- глаз
		ring(0, 3, 16, 10, 5)
		fill(6, 6, 4, 4, 2)
	elseif name == "Players" then     -- человек
		ring(5, 0, 6, 6, 3) ring(2, 9, 12, 6, 3)
	end
	local function paint(c, anim)
		for _, s in strokes do put(s, {Color = c}, anim) end
		for _, f in fills do put(f, {BackgroundColor3 = c}, anim) end
	end
	return box, paint
end

-- крестик закрытия из двух линий
local function xMark(parent, color)
	for _, r in {45, -45} do
		local l = new("Frame", {
			Size = O(12, 2), AnchorPoint = V2(0.5, 0.5), Position = U(0.5, 0, 0.5, 0), Rotation = r,
			BackgroundColor3 = color, BorderSizePixel = 0, Active = false,
		}, parent)
		round(l, 1)
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
local TC_R15 = {{"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"}, {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"},
	{"LeftLowerArm", "LeftHand"}, {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
	{"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
	{"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"}}
local TC_R6 = {{"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"}, {"Torso", "Left Leg"}, {"Torso", "Right Leg"}}
TC.R15, TC.R6 = TC_R15, TC_R6
function TC.frame() -- линия = повёрнутый Frame в отдельном ScreenGui (IgnoreGuiInset: координаты = WorldToViewportPoint)
	if not (TC.gui and TC.gui.Parent) then
		TC.gui = new("ScreenGui", {
			Name = "EnkaisyLines", ResetOnSpawn = false, DisplayOrder = 98, IgnoreGuiInset = true,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}, LP:WaitForChild("PlayerGui"))
	end
	return new("Frame", {AnchorPoint = V2(0.5, 0.5), BorderSizePixel = 0, Visible = false, Active = false}, TC.gui)
end
function TC.line(f, a, b, c)
	local d = b - a
	f.Position, f.Size, f.Rotation = O((a.X + b.X) / 2, (a.Y + b.Y) / 2), O(d.Magnitude, 1.5), math.deg(math.atan2(d.Y, d.X))
	f.BackgroundColor3, f.Visible = c, true
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
			o.tr.Visible = false
		end
	elseif o.tr then
		o.tr.Visible = false
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
			if not drawn and f then f.Visible = false end
		end
	elseif o.sk then
		for _, f in o.sk do f.Visible = false end
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

local function allowed(plr, char)
	if not CFG.On then return false end
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
local function refreshHL()
	for _, o in esp do
		local h = o.h
		local fc = pcol(o.plr, "Fill")
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
		h.FillColor = fc
		h.OutlineColor = pcol(o.plr, "Outline") or TC.get(o.plr, "Box") or hsv(col.Outline)
		h.FillTransparency = 1 - alphaFor(o.plr, "Fill", CFG.Fill, 0.45)
		h.OutlineTransparency = 1 - alphaFor(o.plr, "Outline", CFG.Outline, 0.8)
	end
end

local NONE = Enum.HumanoidDisplayDistanceType.None
local function restoreNative(o)
	if not o.hidNative then return end
	o.hidNative = false
	local hum = o.hum
	if hum and hum.Parent and o.origDDT then
		pcall(function() hum.DisplayDistanceType = o.origDDT end)
	end
end

local function unhl(char, fade)
	if not char then return end
	local o = esp[char]
	if not o then return end
	esp[char] = nil
	restoreNative(o)
	if o.nb then o.nb:Destroy() end
	if o.hb then o.hb:Destroy() end
	if o.tr then o.tr:Destroy() end
	for _, f in o.sk or {} do f:Destroy() end
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
	local o = {plr = plr}
	esp[char] = o
	o.h = new("Highlight", {
		Name = "TH", Adornee = char, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		FillTransparency = 1, OutlineTransparency = 1,
	}, char)
	refreshHL()
	local ft, ot = 1 - alphaFor(plr, "Fill", CFG.Fill, 0.45), 1 - alphaFor(plr, "Outline", CFG.Outline, 0.8)
	o.h.FillTransparency, o.h.OutlineTransparency = 1, 1
	tween(o.h, TweenInfo.new(0.25), {FillTransparency = ft, OutlineTransparency = ot})
	local function setup()
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
		local head = char:FindFirstChild("Head") or root
		if not (hum and head and root) then return false end
		o.hum = hum
		o.root = root
		o.nb = new("BillboardGui", {
			Adornee = head, Size = O(200, 26), StudsOffset = Vector3.new(0, 2.4, 0),
			AlwaysOnTop = true, Enabled = false,
		}, char)
		o.nl = new("TextLabel", {
			Size = S(1, 1), BackgroundTransparency = 1,
			Font = GB, TextStrokeTransparency = 0.3,
		}, o.nb)
		o.hb = new("BillboardGui", {
			Adornee = root, Size = S(2.4, 5.2), StudsOffset = Vector3.new(2.9, 0, 0),
			AlwaysOnTop = true, Enabled = false,
		}, char)
		o.bg = new("Frame", {Size = S(0.12, 1), BackgroundColor3 = C.B, BackgroundTransparency = 0.3, BorderSizePixel = 0}, o.hb)
		o.bar = new("Frame", {AnchorPoint = V2(0, 1), Position = S(0, 1), BorderSizePixel = 0}, o.bg)
		o.pct = new("TextLabel", {
			Size = S(1, 0.3), Position = S(0, 0.35), BackgroundTransparency = 1,
			TextScaled = true, Font = GB, TextXAlignment = XL,
			TextStrokeTransparency = 0.3,
		}, o.hb)
		hum.Died:Once(function()
			if CFG.HideDead and esp[char] == o then unhl(char, true) end
		end)
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
		p.CharacterAdded:Connect(function(c) npcs[c] = nil; dohl(c, p) end),
		p.CharacterRemoving:Connect(function(c) unhl(c) end),
		p:GetPropertyChangedSignal("Team"):Connect(function()
			upd(p.Character, p)
			refreshHL()
			if plrHook then plrHook(p) end
		end),
	}
	if CFG.FriendMode ~= "Off" then checkFriend(p) end
	if p.Character then dohl(p.Character, p) end
end

local function untrack(p)
	unhl(p.Character)
	for _, c in pconn[p] or {} do c:Disconnect() end
	pconn[p] = nil
end

local function addNpc(hum)
	task.defer(function()
		local m = hum.Parent
		if not m or npcs[m] or not m:IsA("Model") then return end
		if Players:GetPlayerFromCharacter(m) or m == LP.Character then return end
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

local lastRank, lastChk, lastLbl, lastWork = 0, 0, 0, 0
local function setp(o, k, v) if o[k] ~= v then o[k] = v end end
local function frame()
	local now = os.clock()
	local dt = now - lastT
	lastT = now
	fps += (1 / math.max(dt, 1e-3) - fps) * 0.08
	local hz = CFG.EspHz
	if hz < 60 and now - lastWork < 1 / hz - 0.004 then return end -- Performance: реже обновляем ESP-подписи
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
		local far = CFG.MaxDist < DIST_MAX and dist > CFG.MaxDist
		if list and not far then table.insert(list, o) end
		local limited = CFG.Limit and (o.rank or 0) > CFG.LimitN
		local vis = not far and not limited
		setp(o.h, "Enabled", pv(o.plr, "Hl", CFG.Hl) and vis)
		local hum = o.hum
		local f = hum and math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1) or 1
		local marked = o.plr and marks[o.plr.UserId] == "Mark"
		local ps = psOf(o.plr)
		local custom = ps and ps.cols and ps.cols.Fill
		if not marked and not custom then
			if CFG.HPColor and hum then o.h.FillColor = Color3.fromHSV(f * 0.33, 0.85, 0.95) end
			if rb then o.h.FillColor = rb end
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
		if hum and o.nl then
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
			local showHB = (hpOn or CFG.Pct) and vis
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
		if counterLbl.Text ~= txt then counterLbl.Text = txt end
	end
	if doLbl and statusFn then statusFn() end
	-- FPS и пинг
	if statsCard and CFG.ShowStats and now - lastStat > 0.5 then
		lastStat = now
		local fr, pg = math.floor(fps + 0.5), math.floor(getPing() + 0.5)
		statsFps.Text = fr .. " FPS"
		statsPing.Text = pg .. " ms"
		statsFps.TextColor3 = fr >= 50 and GOOD or fr >= 30 and MID or BAD
		statsPing.TextColor3 = pg <= 100 and GOOD or pg <= 200 and MID or BAD
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
local function movable(handle, target, onTap, onEnd)
	local d, m, s0, p0, t = false, false
	on(handle.InputBegan, function(i)
		if press(i) then d, m, s0, p0, t = true, false, i.Position, target.Position, i end
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
		Size = U(1, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Text = text,
		TextColor3 = C.Mut, Font = GB, TextSize = 10, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Bottom,
		TextWrapped = true, LayoutOrder = order or 0,
	}, parent)
	new("UIPadding", {PaddingLeft = UDim.new(0, 2), PaddingBottom = UDim.new(0, 1)}, l)
	return l
end

-- сетка 2 колонки для коротких переключателей (высота считается сама; ряды 40 px — под палец)
-- число колонок зависит от ширины окна (1 / 2 / 3); applyGridCols перестраивает все сетки сразу
local gridCols, grids = 2, setmetatable({}, {__mode = "k"})
local function applyGridCols(n)
	if n == gridCols then return end
	gridCols = n
	for lay in grids do
		if lay.Parent then
			lay.CellSize = U(1 / n, -6 * (n - 1) / n, 0, 40)
		else
			grids[lay] = nil
		end
	end
end
local function chipGrid(parent, order)
	local g = new("Frame", {Size = U(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order or 0}, parent)
	local lay = new("UIGridLayout", {
		CellSize = U(1 / gridCols, -6 * (gridCols - 1) / gridCols, 0, 40), CellPadding = O(6, 6), SortOrder = Enum.SortOrder.LayoutOrder,
	}, g)
	grids[lay] = true
	return g
end

-- Справка общих карточек; окно создаётся главным меню. Реестр также служит поиску.
local helpUI = {items = {}}
helpUI.info = {
 ["Aim on"] = {"Включает помощь в наведении.", "Enables aim assistance."},
 ["Auto predict"] = {"Автоматически рассчитывает упреждение движущейся цели.", "Automatically predicts a moving target's position."},
 ["Float button"] = {"Показывает плавающую кнопку AIM.", "Shows the floating AIM button."},
 ["Target lock"] = {"Удерживает выбранную цель.", "Keeps the selected target locked."},
 ["Silent aim"] = {"Направляет выстрел в цель без движения камеры; сервер ограничивает угол.", "Directs shots toward the target without moving the camera; the server limits the angle."},
 ["Highlight"] = {"Подсвечивает цели.", "Highlights targets."},
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
 ["Hitbox size (studs)"] = {"Размер расширения хитбокса тела в стадах.", "Body hitbox expansion in studs."},
 ["Head hitbox size (studs)"] = {"Размер расширения хитбокса головы в стадах.", "Head hitbox expansion in studs."},
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
 ["Smoothness (higher = faster)"] = {"Скорость наведения: большее значение означает быстрее.", "Aim speed: a higher value means faster."},
 ["Manual predict (sec)"] = {"Ручное упреждение в секундах.", "Manual prediction time in seconds."},
 ["Auto predict bias (ms)"] = {"Поправка автоматического упреждения в миллисекундах.", "Automatic prediction bias in milliseconds."},
 ["Sticky (lower = stickier)"] = {"Удержание цели: меньшее значение сильнее удерживает цель.", "Target stickiness: lower values hold the target more strongly."},
 ["FOV circle"] = {"Показывает круг FOV при включённом Aim.", "Shows the FOV circle while Aim is enabled."},
 ["Fill"] = {"Включает заливку круга.", "Enables the circle fill."},
 ["Highlight on target"] = {"Меняет цвет круга при захвате цели.", "Changes the circle color when a target is acquired."},
 ["Dynamic FOV"] = {"Меняет радиус FOV в зависимости от расстояния до цели.", "Changes the FOV radius based on target distance."},
 ["Target animation"] = {"Показывает анимацию появления, захвата и потери цели.", "Shows animations when a target appears, is acquired or lost."},
 ["Animation style"] = {"Выбирает форму индикатора цели.", "Selects the target indicator shape."},
 ["Animation speed"] = {"Изменяет скорость анимации цели.", "Changes the target animation speed."},
}
function helpUI.add(parent, title, desc, x)
 local b = new("TextButton", {Size = O(26, 28), AnchorPoint = V2(1, 0.5), Position = U(1, x, 0, 20),
  BackgroundColor3 = C.Input, Text = "?", TextColor3 = C.Mut, Font = GB, TextSize = 14, AutoButtonColor = false, ZIndex = 5}, parent)
 rr(b, 8)
 outline(b, OUT.Soft)
 table.insert(helpUI.items, {card = parent, title = title, desc = desc})
 on(b.Activated, function() if helpUI.open then helpUI.open(title, desc) end end)
 return b
end

-- ряд-переключатель: название слева (и необязательное описание), ON/OFF справа
local function toggleCard(parent, text, order, getv, setv, desc)
	local b = new("TextButton", {
		Size = U(1, 0, 0, desc and 52 or 40), BackgroundColor3 = C.Card, Text = "", AutoButtonColor = false, LayoutOrder = order or 0,
	}, parent)
	rr(b, 8)
	hoverable(b, outline(b), {bg = C.Card, bgHover = C.Sel})
	new("TextLabel", {
		Size = U(1, -100, 0, desc and 20 or 40), Position = O(10, desc and 6 or 0), BackgroundTransparency = 1, Text = text,
		TextColor3 = C.W, Font = GM, TextSize = 12, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, Active = false,
	}, b)
	if desc then
		new("TextLabel", {
			Size = U(1, -100, 0, 14), Position = O(10, 28), BackgroundTransparency = 1, Text = desc,
			TextColor3 = C.Mut, Font = GM, TextSize = 10, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, Active = false,
		}, b)
	end
	helpUI.add(b, text, desc, -66)
	local sw, swPaint = makeSwitch(b)
	sw.AnchorPoint, sw.Position = V2(1, 0.5), U(1, -10, 0.5, 0)
	local function paint(anim) swPaint(getv(), anim) end
	paint(false)
	on(b.Activated, function()
		setv(not getv())
		paint(true)
	end)
	return b, paint
end

-- ряд-выбор: название слева, текущее значение в рамке справа, тап = следующее значение
local function cycleCard(parent, text, order, getv, nextv, isOn)
	local b = new("TextButton", {
		Size = U(1, 0, 0, 40), BackgroundColor3 = C.Card, Text = "", AutoButtonColor = false, LayoutOrder = order or 0,
	}, parent)
	rr(b, 8)
	hoverable(b, outline(b), {bg = C.Card, bgHover = C.Sel})
	new("TextLabel", {
		Size = U(1, -120, 1, 0), Position = O(10, 0), BackgroundTransparency = 1, Text = text, TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = C.W, Font = GM, TextSize = 12, TextXAlignment = XL, Active = false,
	}, b)
	local pill = new("TextLabel", {
		AnchorPoint = V2(1, 0.5), Position = U(1, -38, 0.5, 0), Size = O(0, 28), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Input, Text = "", TextColor3 = C.W, Font = GB, TextSize = 11, Active = false,
	}, b)
	new("UIPadding", {PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11)}, pill)
	rr(pill, 6)
	outline(pill, 0.55)
	helpUI.add(b, text, nil, -8)
	local function paint()
		pill.Text = tostring(getv())
		pill.TextColor3 = (isOn == nil or isOn()) and C.W or C.Mut
	end
	paint()
	on(b.Activated, function() nextv(); paint() end)
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
	local f = new("Frame", {Size = U(1, 0, 0, 58), BackgroundColor3 = C.Card, LayoutOrder = order or 0}, parent)
	rr(f, 8)
	local h = hoverable(f, outline(f))
	new("TextLabel", {
		Size = U(1, -122, 0, 20), Position = O(10, 6), BackgroundTransparency = 1, Text = title, TextColor3 = C.W,
		Font = GM, TextSize = 12, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, Active = false,
	}, f)
	local val = new("TextLabel", {
		Size = O(76, 20), AnchorPoint = V2(1, 0), Position = U(1, -10, 0, 6), BackgroundTransparency = 1, Text = "",
		TextColor3 = C.W, Font = GB, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Active = false,
	}, f)
	helpUI.add(f, title, nil, -88)
	local hit = new("Frame", {Size = U(1, -20, 0, 32), Position = O(10, 24), BackgroundTransparency = 1, Active = true}, f)
	local track = new("Frame", {
		Size = U(1, 0, 0, 6), AnchorPoint = V2(0, 0.5), Position = U(0, 0, 0.5, 0), BackgroundColor3 = C.Hi, Active = false,
	}, hit)
	round(track, 3)
	local bar = new("Frame", {Size = U(0, 0, 1, 0), BackgroundColor3 = C.Acc, Active = false}, track)
	accent(bar, "BackgroundColor3")
	round(bar, 3)
	local knob = new("Frame", {Size = O(20, 20), AnchorPoint = V2(0.5, 0.5), BackgroundColor3 = C.Acc, ZIndex = 3, Active = false}, track)
	accent(knob, "BackgroundColor3")
	round(knob, 10)
	stroke(knob, C.Card, 0, 2)
	local function paint()
		local v = getv()
		local x = math.clamp((v - min) / (max - min), 0, 1)
		val.Text = fmt(v)
		bar.Size, knob.Position = U(x, 0, 1, 0), U(x, 0, 0.5, 0)
	end
	drag(hit, function(x)
		local v = min + (max - min) * x
		if step then v = math.floor(v / step + 0.5) * step end
		setv(math.clamp(v, min, max))
		paint()
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
	stroke(dot, PURE, 0.45, 1)
	new("TextLabel", {
		Size = U(1, -22, 1, 0), Position = O(22, 0), BackgroundTransparency = 1, Text = name, TextColor3 = C.W,
		Font = GB, TextSize = 10, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, Active = false,
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

-- Палитра (квадрат S/V + полоса оттенка + HEX). getC(edit) отдаёт таблицу {h,s,v}
local function makePicker(parent, order, getC, onEdit, extra)
	local card = new("Frame", {Size = U(1, 0, 0, 170), BackgroundColor3 = C.Card, LayoutOrder = order}, parent)
	rr(card, 8)
	outline(card, OUT.Soft)
	local sv = new("Frame", {Size = U(1, -20, 0, 92), Position = O(10, 10)}, card)
	rr(sv, 6)
	outline(sv, 0.55)
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
		Font = GB, TextSize = 13, ClearTextOnFocus = false,
	}, card)
	rr(hex, 6)
	local hexStroke = outline(hex, OUT.Idle)
	on(hex.Focused, function() tween(hexStroke, fast, {Transparency = OUT.Active}) end)
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
		tween(hexStroke, fast, {Transparency = OUT.Idle})
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

-- ===== Aim assist (встроен в меню как вкладка Aim) =====
local aim
local function buildAim(page, api)
	local A = AIMCFG
	local CS = game:GetService("CollectionService")
	local GuiService = game:GetService("GuiService")
	local camera = Workspace.CurrentCamera
	local fireRemote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)

	local TAG = "AimTarget" -- NPC с этим тегом тоже считаются целями
	local tagged, aconns = {}, {}
	local function connect(sig, fn)
		local c = sig:Connect(fn)
		table.insert(aconns, c)
		return c
	end
	for _, inst in CS:GetTagged(TAG) do tagged[inst] = true end
	connect(CS:GetInstanceAddedSignal(TAG), function(inst) tagged[inst] = true end)
	connect(CS:GetInstanceRemovedSignal(TAG), function(inst) tagged[inst] = nil end)

	-- ответ сервера на выстрел (hit / miss / причина отказа) — показывается в HUD
	local srvCode, srvT, remoteBound = "-", 0, nil
	local function bindRemote()
		fireRemote = fireRemote or ReplicatedStorage:FindFirstChild(REMOTE_NAME)
		if fireRemote and remoteBound ~= fireRemote then
			remoteBound = fireRemote
			connect(fireRemote.OnClientEvent, function(code) srvCode, srvT = tostring(code), os.clock() end)
		end
	end
	bindRemote()

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local function updateRayFilter(ch) rayParams.FilterDescendantsInstances = ch and {ch} or {} end
	updateRayFilter(LP.Character)
	connect(LP.CharacterAdded, updateRayFilter)

	local lastTouchN -- последнее касание в долях экрана (0..1): не зависит от поворота и разрешения
	local function rememberTouch(touch, processed)
		if processed then return end
		local v = camera.ViewportSize
		if v.X < 2 or v.Y < 2 then return end
		-- InputObject.Position отсчитывается от нижней границы верхней панели: добавляем инсет
		local p = V2(touch.Position.X, touch.Position.Y) + GuiService:GetGuiInset()
		lastTouchN = V2(p.X / v.X, p.Y / v.Y)
	end
	connect(UIS.TouchStarted, rememberTouch)
	connect(UIS.TouchMoved, rememberTouch)

	-- оверлей (FOV-круг, HUD) в экранных координатах без отступов
	local og = new("ScreenGui", {
		Name = "EnkaisyAimOverlay", ResetOnSpawn = false, DisplayOrder = 99,
		IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, LP:WaitForChild("PlayerGui"))
	pcall(function() og.ScreenInsets = Enum.ScreenInsets.None end)
	-- КРУГ: чисто визуальный объект. Положение и размер задаются в ДОЛЯХ оверлея (Scale), без пересчётов px,
	-- поэтому он совпадает с экранными координатами при любом разрешении, DPI и соотношении сторон.
	-- Граница заливки = ровно радиус области (SP.fov); обводка — декоративная.
	local fov = new("Frame", {
		Name = "FOV", AnchorPoint = V2(0.5, 0.5), BackgroundColor3 = C.W, BackgroundTransparency = 0.94,
		BorderSizePixel = 0, Visible = false, Active = false,
	}, og)
	new("UICorner", {CornerRadius = UDim.new(0.5, 0)}, fov)
	local fovStroke = stroke(fov, C.W, 0.35, 1.5)
	-- маркер ТОЧКИ НАВЕДЕНИЯ (зелёный крест): виден в редакторе и когда круг отвязан от области
	local aimMark = new("Frame", {
		Name = "AimPoint", AnchorPoint = V2(0.5, 0.5), Size = O(16, 16), BackgroundTransparency = 1,
		Visible = false, Active = false, ZIndex = 7,
	}, og)
	new("Frame", {
		AnchorPoint = V2(0.5, 0.5), Position = U(0.5, 0, 0.5, 0), Size = U(1, 0, 0, 2),
		BackgroundColor3 = C.On, BorderSizePixel = 0, Active = false, ZIndex = 7,
	}, aimMark)
	new("Frame", {
		AnchorPoint = V2(0.5, 0.5), Position = U(0.5, 0, 0.5, 0), Size = U(0, 2, 1, 0),
		BackgroundColor3 = C.On, BorderSizePixel = 0, Active = false, ZIndex = 7,
	}, aimMark)
	-- калибровочный ScreenGui С отступом экрана: нужен только режиму Crosshair (см. crosshairPoint)
	local probeGui = new("ScreenGui", {
		Name = "EnkaisyProbe", ResetOnSpawn = false, DisplayOrder = -1, IgnoreGuiInset = false,
	}, LP:WaitForChild("PlayerGui"))
	local probe = new("Frame", {Size = O(1, 1), BackgroundTransparency = 1, Active = false}, probeGui)
	local hud = new("TextLabel", {
		AnchorPoint = V2(0.5, 0), Position = U(0.5, 0, 0, 44), Size = O(0, 22), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Win, BackgroundTransparency = 0.25,
		TextColor3 = C.W, TextSize = 12, Font = Enum.Font.Gotham, Text = "", Visible = false,
	}, og)
	new("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)}, hud)
	rr(hud, 6) outline(hud, OUT.Soft)
	floatScales[new("UIScale", {Scale = UICFG.UIScale}, hud)] = true

	-- плавающая кнопка AIM: капсула с индикатором (перетаскивается, тап = вкл/выкл)
	local quick = new("TextButton", {
		Size = O(108, 36), AnchorPoint = V2(0, 0.5), Position = U(0, 16, 0.45, 0),
		BackgroundColor3 = C.Card, Text = "", AutoButtonColor = false, ZIndex = 10,
	}, gui)
	round(quick, 18)
	local qStroke = outline(quick, 0.5)
	floatScales[new("UIScale", {Scale = UICFG.UIScale}, quick)] = true
	local qDot = new("Frame", {
		Size = O(8, 8), AnchorPoint = V2(0, 0.5), Position = U(0, 15, 0.5, 0),
		BackgroundColor3 = C.Mut, Active = false,
	}, quick)
	round(qDot, 4)
	new("TextLabel", {
		Size = O(40, 36), Position = O(31, 0), BackgroundTransparency = 1, Text = "AIM",
		TextColor3 = C.W, Font = Enum.Font.GothamBlack, TextSize = 14, TextXAlignment = XL, Active = false,
	}, quick)
	local qState = new("TextLabel", {
		Size = O(32, 36), AnchorPoint = V2(1, 0), Position = U(1, -13, 0, 0), BackgroundTransparency = 1,
		Text = "OFF", TextColor3 = C.Mut, Font = GB, TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right, Active = false,
	}, quick)

	local CIRCLE_COLORS = {
		White = C.W, Green = Color3.fromRGB(80, 220, 120), Red = Color3.fromRGB(240, 80, 80),
		Cyan = Color3.fromRGB(80, 220, 255), Yellow = Color3.fromRGB(255, 220, 80),
	}
	local currentTarget = nil
	local lastPingT, autoLead = 0, 0.1
	local editing = false
	local previewFov = false -- живой предпросмотр круга, пока открыта вкладка FOV
	-- ЭКРАННОЕ ПРОСТРАНСТВО, общее для логики и визуала; заполняется updateSpace() в начале каждого кадра:
	--   vp     — размер экрана в пикселях (camera.ViewportSize)
	--   aim    — ТОЧКА НАВЕДЕНИЯ (px экрана): выбор цели, поворот камеры, triggerbot, выстрел
	--   circle — где РИСУЕТСЯ круг (по умолчанию = aim, но его можно отвязать)
	--   fov / silent / lock — радиусы областей (px экрана); тот же fov использует и отрисовка круга
	local SP = {vp = V2(1920, 1080), aim = V2(960, 540), circle = V2(960, 540), fov = 0, silent = 0, lock = 0}
	local updateSpace, runSelfTest, setEditing -- задаются ниже
	local testUntil = 0

	-- ===== v4.0: состояние новых функций (одна таблица NX - не плодим локальные переменные) =====
	local NX = {
		gen = 0, -- любое изменение очереди частей тела увеличивает счётчик и сбрасывает кэш выбора части
		dynR = A.FovR, wantR = A.FovR, dynBack = false, wasDyn = false, refDist = nil, shownRef = nil, nearT = 0, nearD = nil, radT = 0,
		an = {a = 0, s = 1, r = 0, x = 0, y = 0, lx = 0, ly = 0, col = C.On, glide = 0},
		demoA = {}, demoB = {},
	}
	NX.STYLES = {
		Ring = {corner = 0.5, filled = false, rot = 0, kick = 2.2, scale = 1},
		Square = {corner = 0.12, filled = false, rot = 45, kick = 1.7, scale = 0.9},
		Dot = {corner = 0.5, filled = true, rot = 0, kick = 3.2, scale = 0.42},
	}
	-- индикатор цели и кольцо-импульс (оверлей без отступов, позиции в долях экрана - как у круга FOV)
	NX.mark = new("Frame", {
		Name = "TargetMark", AnchorPoint = V2(0.5, 0.5), Size = O(34, 34), BackgroundTransparency = 1,
		BorderSizePixel = 0, Visible = false, Active = false, ZIndex = 7,
	}, og)
	NX.markCorner = new("UICorner", {CornerRadius = UDim.new(0.5, 0)}, NX.mark)
	NX.markStroke = stroke(NX.mark, C.On, 1, 2)
	NX.pulse = new("Frame", {
		Name = "TargetPulse", AnchorPoint = V2(0.5, 0.5), Size = O(34, 34), BackgroundTransparency = 1,
		BorderSizePixel = 0, Visible = false, Active = false, ZIndex = 7,
	}, og)
	NX.pulseCorner = new("UICorner", {CornerRadius = UDim.new(0.5, 0)}, NX.pulse)
	NX.pulseStroke = stroke(NX.pulse, C.W, 1, 1.5)

	-- ===== Dynamic FOV =====
	-- Радиус считается по дистанции до цели: ближе DynNear - максимум, дальше DynFar - минимум (DynInvert меняет местами).
	-- Опорная дистанция: текущая цель; пока цели нет - ближайшая к прицелу (NX.nearest); никого нет - максимальный радиус.
	-- Фактический радиус сглаживается и сразу пишется в SP.fov: им пользуются и выбор цели, и отрисовка круга (они всегда совпадают).
	function NX.dynTarget(dist)
		local lo, hi = math.min(A.DynMin, A.DynMax), math.max(A.DynMin, A.DynMax)
		if not dist then return hi end
		local d0, d1 = math.min(A.DynNear, A.DynFar), math.max(A.DynNear, A.DynFar)
		if d1 - d0 < 1 then d1 = d0 + 1 end
		local t = math.clamp((dist - d0) / (d1 - d0), 0, 1)
		if A.DynMode == "Smooth" then t = t * t * (3 - 2 * t) end
		if A.DynInvert then t = 1 - t end
		return hi + (lo - hi) * t
	end
	function NX.dynStep(now, dt)
		local short = math.min(SP.vp.X, SP.vp.Y)
		local a = 1 - math.clamp(A.DynSmooth, 0, 0.95) ^ (math.clamp(dt, 0, 0.1) * 60)
		if A.DynFov then
			NX.wasDyn, NX.dynBack = true, false
			local ref = NX.refDist or (NX.nearest and NX.nearest(now))
			local want = NX.dynTarget(ref)
			NX.dynR += (want - NX.dynR) * a
			NX.wantR, NX.shownRef = want, ref
		elseif NX.wasDyn then
			NX.wasDyn, NX.dynBack = false, true -- Dynamic FOV выключили: плавно возвращаемся к обычному FOV
		end
		if NX.dynBack then
			NX.dynR += (A.FovR - NX.dynR) * a
			if math.abs(NX.dynR - A.FovR) < 0.05 then NX.dynBack, NX.dynR = false, A.FovR end
		elseif not A.DynFov then
			NX.dynR = A.FovR -- обычный FOV: без сглаживания, как раньше
		end
		NX.dynR = math.clamp(NX.dynR, 2, 60)
		if A.DynFov or NX.dynBack then SP.fov = NX.dynR * 0.01 * short end
		if NX.radLbl and previewFov and now - NX.radT > 0.1 then
			NX.radT = now
			local info = "normal FOV (Dynamic FOV is off)"
			if A.DynFov then
				info = NX.shownRef
					and string.format("dynamic: target %d st, goal %.1f%%", math.floor(NX.shownRef + 0.5), NX.wantR)
					or string.format("dynamic: no target, goal %.1f%% (max)", NX.wantR)
			end
			local r = (A.DynFov or NX.dynBack) and NX.dynR or A.FovR
			NX.radLbl.Text = string.format("Current radius: %.1f%% (diameter %.1f%%) = %d px\n%s", r, r * 2, math.floor(SP.fov + 0.5), info)
		end
	end

	-- ===== Target Animation =====
	-- Одна процедурная анимация на кадр (без TweenService): новое событие (захват / смена / потеря) не запускает вторую анимацию,
	-- а только меняет цели и "толчок" той же машины состояний - конфликтов быть не может. Нагрузка: ~10 присвоений за кадр.
	function NX.animReset()
		local an = NX.an
		an.a, an.mdl, an.pulse, an.glide = 0, nil, nil, 0
		NX.mark.Visible, NX.pulse.Visible = false, false
	end
	function NX.animStep(now, dt, model, sx, sy)
		local an = NX.an
		if editing then NX.demo = nil; NX.animReset(); return end
		if not model and NX.demo then -- кнопка Preview animation: захват -> смена -> потеря на круге FOV
			local t = now - NX.demo
			local c, s = SP.circle, math.min(SP.vp.X, SP.vp.Y)
			if t < 1 then model, sx, sy = NX.demoA, c.X, c.Y
			elseif t < 2 then model, sx, sy = NX.demoB, c.X + s * 0.12, c.Y - s * 0.06
			elseif t < 3 then model, sx, sy = nil, nil, nil
			else NX.demo = nil end
		end
		if not A.TargetAnim and not NX.demo then
			if an.a > 0 or an.mdl then NX.animReset() end
			return
		end
		if not model and an.a <= 0 and not an.mdl and not an.pulse then return end -- простой: ничего не рисуем и не считаем
		local v = SP.vp
		local st = NX.STYLES[A.AnimStyle] or NX.STYLES.Ring
		local speed = math.clamp(A.AnimSpeed, 0.25, 3)
		dt = math.clamp(dt, 0, 0.1)
		local k = 1 - math.exp(-dt * 9 * speed)
		if not sx then model = nil end
		if model ~= an.mdl then
			if model then
				if an.a > 0.08 then -- смена цели: индикатор плавно переезжает, с небольшим толчком
					an.glide = 0.3 / speed
					if A.AnimLock then an.s, an.pulse, an.col = st.kick * 0.55, 0, C.W end
				else -- новый захват: индикатор появляется в точке цели и "сжимается" на неё
					an.x, an.y, an.a, an.r = sx, sy, 0, st.rot
					if A.AnimLock then an.s, an.pulse, an.col = st.kick, 0, C.W else an.s, an.col = 1, C.On end
				end
			elseif an.mdl then -- цель потеряна
				if A.AnimLose then an.col = C.Off else an.a = 0 end
			end
			an.mdl = model
		end
		local gs, ga, gcol = 1, 1, C.On
		if model then
			an.lx, an.ly = sx, sy
			local kp = an.glide > 0 and (1 - math.exp(-dt * 12 * speed)) or (1 - math.exp(-dt * 30))
			an.x += (sx - an.x) * kp
			an.y += (sy - an.y) * kp
			an.glide = math.max(0, an.glide - dt)
		else
			gs, ga, gcol = 1.9, 0, C.Off -- потеря: красное расширение и затухание на последнем месте
		end
		an.s += (gs - an.s) * k
		an.a += (ga - an.a) * (model and k or k * 1.4)
		an.r += (0 - an.r) * k
		an.col = an.col:Lerp(gcol, k)
		if an.pulse then
			an.pulse += dt * 2.2 * speed
			if an.pulse >= 1 then an.pulse = nil end
		end
		local base = math.clamp(math.min(v.X, v.Y) * 0.055, 28, 60) * st.scale
		local vis = an.a > 0.02
		setp(NX.mark, "Visible", vis)
		if vis then
			local d = base * an.s
			NX.mark.Size = O(d, d)
			NX.mark.Position = S(an.x / v.X, an.y / v.Y)
			NX.mark.Rotation = an.r
			setp(NX.markCorner, "CornerRadius", UDim.new(st.corner, 0))
			if st.filled then
				NX.mark.BackgroundTransparency = 1 - an.a * 0.9
				NX.mark.BackgroundColor3 = an.col
				setp(NX.markStroke, "Transparency", 1)
			else
				NX.mark.BackgroundTransparency = 1
				NX.markStroke.Transparency = 1 - an.a * 0.9
				NX.markStroke.Color = an.col
			end
		elseif an.a ~= 0 and not model then
			an.a = 0
		end
		local pv = an.pulse ~= nil and vis
		setp(NX.pulse, "Visible", pv)
		if pv then
			local pd = base * (1 + 1.8 * (1 - (1 - an.pulse) ^ 2))
			NX.pulse.Size = O(pd, pd)
			NX.pulse.Position = S(an.x / v.X, an.y / v.Y)
			setp(NX.pulseCorner, "CornerRadius", UDim.new(st.corner, 0))
			NX.pulseStroke.Transparency = 0.25 + 0.75 * an.pulse
			NX.pulseStroke.Color = an.col
		end
	end

	-- ===== Редактор позиции =====
	-- Два НЕЗАВИСИМЫХ объекта: КРУГ (визуал: CircleX/CircleY) и ТОЧКА НАВЕДЕНИЯ (логика: AimX/AimY + AimMode).
	-- Что тащить, выбирает кнопка "Двигаю". Ничего не двигается "заодно":
	--   круг  -> меняется только круг (при первом сдвиге он отвязывается от области наведения);
	--   точка -> меняется только точка наведения; отвязанный круг остаётся на месте.
	-- Само открытие редактора настройки не меняет.
	fov.ZIndex, hud.ZIndex = 6, 7
	local editLayer = new("Frame", {
		Size = S(1, 1), BackgroundColor3 = C.B, BackgroundTransparency = 0.7, Active = true, Visible = false, ZIndex = 5,
	}, og)
	local editBar = new("Frame", {
		AnchorPoint = V2(0.5, 0), Position = U(0.5, 0, 0, 80), Size = O(300, 232),
		BackgroundColor3 = C.Win, Active = true, Visible = false, ZIndex = 8,
	}, og)
	rr(editBar, 12) outline(editBar, 0.4)
	new("TextLabel", {
		Size = U(1, -16, 0, 28), Position = O(8, 4), BackgroundTransparency = 1, TextWrapped = true,
		Text = "Тяни по экрану — двигается выбранное (круг или точка aim)", TextColor3 = C.W, Font = GM, TextSize = 12,
	}, editBar)
	local doneBtn = button(editBar, "Готово", {
		Size = O(86, 32), Position = O(8, 36), TextSize = 13,
	}, {primary = true})
	local centerBtn = button(editBar, "В центр", {
		Size = O(86, 32), Position = O(107, 36), TextSize = 13,
	})
	local resetBtn = button(editBar, "Сброс", {
		Size = O(86, 32), Position = O(206, 36), TextSize = 13,
	})
	movable(editBar, editBar, nil, function() clampGui(editBar) end) -- панель можно перетаскивать
	connect(doneBtn.Activated, function() setEditing(false) end)

	-- шаг стрелок в пикселях экрана
	new("TextLabel", {
		Size = O(120, 18), Position = O(160, 74), BackgroundTransparency = 1, Text = "Шаг, px",
		TextColor3 = C.Mut, Font = GM, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
	}, editBar)
	local stepBox = new("TextBox", {
		Size = O(120, 32), Position = O(160, 94), BackgroundColor3 = C.Input, Text = tostring(A.StepPx),
		TextColor3 = C.W, Font = GM, TextSize = 14, ClearTextOnFocus = true, PlaceholderText = "10",
	}, editBar)
	rr(stepBox, 8) outline(stepBox, 0.5)
	local function readStep()
		local n = tonumber(stepBox.Text)
		if n then A.StepPx = math.clamp(n, 0.5, 500) end
		return A.StepPx
	end
	connect(stepBox.FocusLost, function() stepBox.Text = tostring(readStep()) end)

	local targetBtn = button(editBar, "", {Size = O(120, 28), Position = O(160, 130), TextSize = 11})
	local followBtn = button(editBar, "", {Size = O(284, 28), Position = O(8, 166), TextSize = 11})
	local xyLabel = new("TextLabel", {
		Size = O(284, 30), Position = O(8, 198), BackgroundTransparency = 1, Text = "", TextWrapped = true,
		TextColor3 = C.Mut, Font = GM, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, editBar)

	local editTarget = "Circle" -- что двигаем: "Circle" (визуал) или "Aim" (точка наведения)
	local function clampN(x) return math.clamp(x, 0.02, 0.98) end
	local function circleN() return V2(SP.circle.X / SP.vp.X, SP.circle.Y / SP.vp.Y) end
	local function aimN() return V2(SP.aim.X / SP.vp.X, SP.aim.Y / SP.vp.Y) end
	-- отвязать круг от области наведения, оставив его ровно там, где он сейчас (без скачка)
	local function unlinkCircle()
		if not A.CircleFollow then return end
		local n = circleN()
		A.CircleX, A.CircleY, A.CircleFollow = clampN(n.X), clampN(n.Y), false
	end
	local function getTargetN()
		if editTarget == "Aim" then return aimN() end
		return circleN()
	end
	local function setTargetN(x, y)
		x, y = clampN(x), clampN(y)
		if editTarget == "Aim" then
			A.AimX, A.AimY, A.AimMode = x, y, "Custom" -- круг при этом не трогаем
		else
			unlinkCircle()
			A.CircleX, A.CircleY = x, y -- точку наведения не трогаем
		end
	end
	local function paintEdit()
		local t1 = editTarget == "Aim" and "Двигаю: ТОЧКУ AIM" or "Двигаю: КРУГ"
		local t2 = A.CircleFollow and "Связь круга с областью: ВКЛ" or "Связь круга с областью: ВЫКЛ"
		if targetBtn.Text ~= t1 then targetBtn.Text = t1 end
		if followBtn.Text ~= t2 then followBtn.Text = t2 end
	end
	paintEdit()
	connect(targetBtn.Activated, function()
		editTarget = editTarget == "Aim" and "Circle" or "Aim"
		paintEdit()
	end)
	connect(followBtn.Activated, function()
		if A.CircleFollow then unlinkCircle() else A.CircleFollow = true end
		paintEdit()
	end)
	connect(centerBtn.Activated, function()
		if editTarget == "Aim" then
			A.AimMode, A.AimX, A.AimY = "Center", 0.5, 0.5
		else
			-- круг уже связан с точкой, стоящей в центре — менять нечего
			if A.CircleFollow and (SP.aim - V2(SP.vp.X / 2, SP.vp.Y / 2)).Magnitude < 0.5 then return end
			unlinkCircle()
			A.CircleX, A.CircleY = 0.5, 0.5 -- только круг; точка наведения остаётся как была
		end
	end)
	connect(resetBtn.Activated, function()
		A.AimMode, A.AimX, A.AimY = "Center", 0.5, 0.5
		A.CircleFollow, A.CircleX, A.CircleY, A.StepPx = true, 0.5, 0.5, 10
		stepBox.Text = tostring(A.StepPx)
		paintEdit()
	end)

	-- стрелки: точный сдвиг выбранного объекта на N пикселей экрана
	local function nudge(dx, dy)
		local st, v = readStep(), SP.vp
		local n = getTargetN()
		setTargetN(n.X + dx * st / v.X, n.Y + dy * st / v.Y)
	end
	-- удержание стрелки = непрерывный сдвиг
	local holdToken = 0
	local function arrow(txt, x, y, dx, dy)
		local b = button(editBar, txt, {
			Size = O(40, 32), Position = O(x, y), TextSize = 18,
		})
		connect(b.InputBegan, function(i)
			if not press(i) then return end
			holdToken += 1
			local my = holdToken
			nudge(dx, dy)
			task.spawn(function()
				task.wait(0.4)
				while holdToken == my and b.Parent do
					nudge(dx, dy)
					task.wait(0.05)
				end
			end)
		end)
	end
	connect(UIS.InputEnded, function(i) if press(i) then holdToken += 1 end end)
	arrow("▲", 56, 72, 0, -1)
	arrow("◀", 12, 108, -1, 0)
	arrow("▼", 56, 108, 0, 1)
	arrow("▶", 100, 108, 1, 0)

	-- перетаскивание: новая позиция = позиция на старте + сдвиг пальца в ДОЛЯХ экрана (без накопления ошибки)
	local dragInput, dragStart, dragN0
	connect(editLayer.InputBegan, function(i)
		if press(i) then
			dragInput, dragStart, dragN0 = i, V2(i.Position.X, i.Position.Y), getTargetN()
		end
	end)
	connect(UIS.InputChanged, function(i)
		if not dragInput or not move(i) then return end
		if not (i == dragInput or i.UserInputType == Enum.UserInputType.MouseMovement) then return end
		local d = V2(i.Position.X, i.Position.Y) - dragStart
		setTargetN(dragN0.X + d.X / SP.vp.X, dragN0.Y + d.Y / SP.vp.Y)
	end)
	connect(UIS.InputEnded, function(i)
		if i == dragInput or i.UserInputType == Enum.UserInputType.MouseButton1 then dragInput = nil end
	end)
	local refreshers = {}
	local function refreshAll(anim) for _, fn in refreshers do fn(anim) end end
	local function paintQuick(anim)
		local o = A.Enabled
		quick.Visible = A.ShowButton and not editing
		qState.Text = o and "ON" or "OFF"
		local function apply(inst, g)
			if anim then tween(inst, fast, g) else for k, v in g do inst[k] = v end end
		end
		apply(quick, {BackgroundColor3 = o and C.Sel or C.Card})
		apply(qStroke, {Transparency = o and 0.08 or 0.5})
		apply(qDot, {BackgroundColor3 = o and C.W or C.Mut})
		apply(qState, {TextColor3 = o and C.W or C.Mut})
	end
	table.insert(refreshers, paintQuick)
	paintQuick(false)
	local lockedModel, skipModel, skipUntil, switchTarget -- Target Lock
	local function setEnabled(state)
		A.Enabled = state
		if not state then currentTarget = nil; lockedModel = nil end
		refreshAll(true)
	end
	movable(quick, quick, function() setEnabled(not A.Enabled) end, function() clampGui(quick) end)

	-- ===== UI вкладки =====
	local scroll = new("ScrollingFrame", {
		Size = S(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.Mut, ScrollBarImageTransparency = 0.3,
		CanvasSize = U(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, page)
	new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, scroll)
	-- отступы, чтобы тонкие обводки карточек не обрезались краем прокрутки
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 2), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), PaddingRight = UDim.new(0, 8),
	}, scroll)
	local ord = 0
	local function nextOrder() ord += 1 return ord end
	local tgt = scroll -- куда добавляют section / chips / cycle / slider (вкладка Aim или вкладка FOV)

	local function section(text) sectionLabel(tgt, text, nextOrder()) end

	-- список переключателей: {название, ключ, колбэк, описание}
	-- короткие без описаний — в 2 колонки, с описанием (или одиночные) — во всю ширину
	local function chips(list)
		local single = #list == 1
		for _, d in list do
			if d[4] then single = true end
		end
		local parent = tgt
		if not single then parent = chipGrid(tgt, nextOrder()) end
		for i, d in list do
			local key = d[2]
			local _, paint = toggleCard(parent, d[1], single and nextOrder() or i, function() return A[key] end, function(v)
				if d[3] then d[3](v) else A[key] = v end
			end, d[4])
			table.insert(refreshers, paint)
		end
	end

	local function cycle(text, key, options)
		local _, paint = cycleCard(tgt, text, nextOrder(), function() return A[key] end, function()
			local idx = table.find(options, A[key]) or 0
			A[key] = options[idx % #options + 1]
			currentTarget = nil
		end)
		table.insert(refreshers, paint)
	end

	local function slider(title, key, min, max, step, decimals)
		local fmt = "%." .. (decimals or 0) .. "f"
		local _, paint = sliderCard(tgt, title, nextOrder(), min, max,
			function() return A[key] end,
			function(v) A[key] = math.clamp(tonumber(string.format("%.4f", v)), min, max) end,
			function(v) return string.format(fmt, v) end,
			step)
		table.insert(refreshers, paint)
	end

	section("MAIN")
	chips({
		{"Aim on", "Enabled", setEnabled, "Включает наводку (то же, что кнопка AIM)"},
		{"Auto predict", "AutoPredict"},
		{"Float button", "ShowButton", function(v) A.ShowButton = v; paintQuick(true) end, "Плавающая кнопка AIM на экране"},
		{"Target lock", "TargetLock", function(v) A.TargetLock = v; lockedModel = nil end, "Держит цель; смена — кнопкой ниже"},
		{"Silent aim", "SilentAim", nil, "Пуля летит в цель, камера не двигается"},
	})
	local switchBtn = button(scroll, "Switch locked target", {Size = U(1, 0, 0, 40), LayoutOrder = nextOrder()})
	on(switchBtn.Activated, function() if switchTarget then switchTarget() end end)
	section("EXTRA AIM")
	chips({
		{"Triggerbot", "Trigger", nil, "Стреляет сам, когда цель в прицеле, в хитбоксе или рядом с прицелом (Aim не нужен). Статус — в Debug HUD"},
		{"Multipoint", "Multipoint", nil, "Ищет видимую точку по краям хитбокса"},
		{"Adv predict", "AdvPredict", nil, "Скорость, ускорение, прыжок/падение цели и падение пули (нужны BulletSpeed + BulletGravity)"},
	})
	section("HITBOX")
	chips({
		{"Hitbox", "Hitbox", nil, "Расширяет попадание по всему телу цели (сервер ограничивает размер)"},
		{"Head hitbox", "HeadHitbox", nil, "Расширяет попадание по голове цели"},
	})
	slider("Hitbox size (studs)", "HitboxSize", 0, HB_BODY_MAX, 0.25, 2)
	slider("Head hitbox size (studs)", "HeadHitboxSize", 0, HB_HEAD_MAX, 0.25, 2)
	section("HITBOX VISUAL")
	do -- только вид: ни один из этих элементов не трогает HitboxSize / HeadHitboxSize и не влияет на попадания
		local presetPaint = function() end
		local function vslider(title, key, min, max, step, fmt)
			local _, paint = sliderCard(tgt, title, nextOrder(), min, max,
				function() return A[key] end,
				function(v) A[key] = math.clamp(tonumber(string.format("%.4f", v)), min, max); presetPaint() end,
				fmt, step)
			table.insert(refreshers, paint)
		end
		local function pct(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
		chips({
			{"Hitbox ESP", "HitboxShow", nil, "Рисует хитбоксы целей (нужен включённый Hitbox или Head hitbox). Размеры - ползунки выше"},
		})
		local _, pp = cycleCard(tgt, "Visual preset", nextOrder(),
			function() return HBV.match(A) end,
			function()
				local idx = table.find(HBV.PRESET_ORDER, HBV.match(A)) or 0
				HBV.apply(A, HBV.PRESET_ORDER[idx % #HBV.PRESET_ORDER + 1])
				refreshAll(true)
			end)
		presetPaint = pp
		table.insert(refreshers, pp)
		chips({
			{"Show head", "HbvShowHead"},
			{"Show body", "HbvShowBody"},
			{"Only target", "HbvOnlyTarget", function(v) A.HbvOnlyTarget = v; A.HbvAll = not v; refreshAll(true) end},
			{"All targets", "HbvAll", function(v) A.HbvAll = v; A.HbvOnlyTarget = not v; refreshAll(true) end},
		})
		chips({
			{"Outline = fill color", "HbvOutMatch", function(v) A.HbvOutMatch = v; presetPaint() end, "Обводка берёт цвет заливки (голова / тело). Выкл - цвет Outline"},
			{"Capture color", "HbvCapture", nil, "Захваченная цель плавно меняет цвет на Locked (тело сильнее, голова слабее)"},
		})
		vslider("Hitbox transparency", "HbvAlpha", 0, 0.95, 0.05, pct)
		vslider("Fill transparency", "HbvFillAlpha", 0, 1, 0.02, pct)
		vslider("Outline thickness (px)", "HbvThick", 0, 4, 0.25, function(v) return string.format("%.2f", v) end)
		vslider("Distance limit (studs)", "HbvDist", 25, 1000, 25, function(v) return string.format("%d", math.floor(v + 0.5)) end)
		local tabRow = row(tgt, 30, 5, nextOrder())
		local tabs, curC, pickRefresh = {}, "Body", nil
		local function tabsPaint()
			for n, t in tabs do
				t.dot.BackgroundColor3 = hsv(A[HBV.COLKEYS[n]])
				colorTabSel(t, n == curC)
			end
			presetPaint()
		end
		for i, n in HBV.COLORDER do
			tabs[n] = colorTab(tabRow, n, U(1 / 4, -4, 1, 0), i, function() curC = n; pickRefresh() end)
		end
		local _card
		_card, pickRefresh = makePicker(tgt, nextOrder(), function() return A[HBV.COLKEYS[curC]] end, function() end, tabsPaint)
		pickRefresh()
		table.insert(refreshers, function() pickRefresh() end)
		new("TextLabel", {
			Size = U(1, 0, 0, 40), BackgroundTransparency = 1, TextWrapped = true, LayoutOrder = nextOrder(),
			Text = "Только вид: цвета, прозрачность, заливка и обводка не меняют размеры хитбоксов и попадания. Размеры - ползунки Hitbox size / Head hitbox size.",
			TextColor3 = C.Mut, Font = GM, TextSize = 10, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top,
		}, tgt)
	end
	section("MULTIPOINT: ЧАСТИ ТЕЛА, НА КОТОРЫЕ ПЕРЕХОДИТЬ, ЕСЛИ ВЫБРАННАЯ ЗАКРЫТА")
	chips({{"Edges (края)", "MPEdges"}, {"Head", "MPHead"}, {"Torso", "MPTorso"}, {"Arms", "MPArms"}, {"Legs", "MPLegs"}})
	section("CHECKS")
	chips({{"Invuln check", "CheckInvuln"}, {"Flash check", "CheckFlash"}, {"Smoke check", "CheckSmoke"}})
	section("TARGETS")
	chips({
		{"Players", "TargetPlayers"}, {"NPCs", "TargetNPCs"},
		{"Team check", "TeamCheck"}, {"Wall check", "WallCheck"},
	})
	cycle("Target priority", "Priority", {"Crosshair", "Distance", "Lowest HP"})
	chips({{"Visibility from head", "VisFromHead"}})
	cycle("Aim center", "AimMode", {"Auto", "Center", "Touch", "Custom", "Crosshair"})
	section("BODY PART PRIORITY")
	new("TextLabel", {
		Size = U(1, 0, 0, 40), BackgroundTransparency = 1, TextWrapped = true, LayoutOrder = nextOrder(),
		Text = "Первая включённая часть - основная. Кнопки: ★ сделать основной, ▲▼ очередь; переключатель - вкл/выкл. Основная закрыта - цель берётся на следующую доступную часть.",
		TextColor3 = C.Mut, Font = GM, TextSize = 10, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top,
	}, scroll)
	local partPaint = {}
	local function partsChanged()
		V4.normalizeParts(A)
		NX.gen += 1
		for _, fn in partPaint do fn(true) end
	end
	local function partRank(slot)
		for i, s in ipairs(A.PartOrder) do
			if s == slot then return i end
		end
		return #A.PartOrder + 1
	end
	local function partMain(slot) -- в начало очереди и включить
		table.remove(A.PartOrder, partRank(slot))
		table.insert(A.PartOrder, 1, slot)
		A.PartOn[slot] = true
		partsChanged()
	end
	do
		local _, mp = cycleCard(scroll, "Main part", nextOrder(),
			function() return V4.NAMES[A.TargetPart] or A.TargetPart end,
			function()
				local i = table.find(V4.SLOTS, A.TargetPart) or 0
				partMain(V4.SLOTS[i % #V4.SLOTS + 1])
			end)
		table.insert(refreshers, mp)
		table.insert(partPaint, mp)
	end
	chips({
		{"Auto fallback", "PartFallback", function(v) A.PartFallback = v; NX.gen += 1 end, "Основная часть закрыта - цель на следующую доступную"},
		{"Return to main", "PartReturn", function(v) A.PartReturn = v; NX.gen += 1 end, "Основная часть снова доступна - вернуться к ней"},
	})
	local partBase = ord
	ord += 9 -- 8 рядов частей тела: LayoutOrder = partBase + место в очереди
	for _, slot in ipairs(V4.SLOTS) do
		local f = new("Frame", {Size = U(1, 0, 0, 40), BackgroundColor3 = C.Card}, scroll)
		rr(f, 8)
		outline(f)
		local sw, swPaint = makeSwitch(f)
		sw.AnchorPoint, sw.Position = V2(0, 0.5), U(0, 8, 0.5, 0)
		local rankLbl = new("TextLabel", {
			Size = O(18, 40), Position = O(66, 0), BackgroundTransparency = 1, Text = "", TextColor3 = C.Mut,
			Font = GB, TextSize = 11, Active = false,
		}, f)
		local nameLbl = new("TextLabel", {
			Size = U(1, -202, 1, 0), Position = O(86, 0), BackgroundTransparency = 1, Text = V4.NAMES[slot], TextColor3 = C.W,
			Font = GM, TextSize = 12, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, Active = false,
		}, f)
		local hit = new("TextButton", {Size = O(64, 40), BackgroundTransparency = 1, Text = "", AutoButtonColor = false}, f)
		local starBtn = button(f, "★", {Size = O(32, 28), AnchorPoint = V2(1, 0.5), Position = U(1, -80, 0.5, 0), TextSize = 14})
		local upBtn = button(f, "▲", {Size = O(32, 28), AnchorPoint = V2(1, 0.5), Position = U(1, -44, 0.5, 0), TextSize = 12})
		local dnBtn = button(f, "▼", {Size = O(32, 28), AnchorPoint = V2(1, 0.5), Position = U(1, -8, 0.5, 0), TextSize = 12})
		local function paint(anim)
			local isOn = A.PartOn[slot] == true
			local rank = partRank(slot)
			f.LayoutOrder = partBase + rank
			swPaint(isOn, anim)
			local n = 0
			for _, s in ipairs(A.PartOrder) do
				if A.PartOn[s] then n += 1 end
				if s == slot then break end
			end
			local isMain = isOn and A.TargetPart == slot
			rankLbl.Text = not isOn and "·" or (isMain and "★" or tostring(n))
			rankLbl.TextColor3 = isMain and C.On or C.Mut
			nameLbl.TextColor3 = isOn and C.W or C.Mut
			starBtn.TextColor3 = isMain and C.On or C.W
			upBtn.TextTransparency = rank <= 1 and 0.6 or 0
			dnBtn.TextTransparency = rank >= #A.PartOrder and 0.6 or 0
		end
		on(hit.Activated, function()
			local nowOn = not A.PartOn[slot]
			if not nowOn then
				local cnt = 0
				for _, s in ipairs(A.PartOrder) do
					if A.PartOn[s] then cnt += 1 end
				end
				if cnt <= 1 then return end -- хотя бы одна часть должна остаться включённой
			end
			A.PartOn[slot] = nowOn
			partsChanged()
		end)
		on(starBtn.Activated, function() partMain(slot) end)
		on(upBtn.Activated, function()
			local r = partRank(slot)
			if r > 1 then
				A.PartOrder[r], A.PartOrder[r - 1] = A.PartOrder[r - 1], A.PartOrder[r]
				partsChanged()
			end
		end)
		on(dnBtn.Activated, function()
			local r = partRank(slot)
			if r < #A.PartOrder then
				A.PartOrder[r], A.PartOrder[r + 1] = A.PartOrder[r + 1], A.PartOrder[r]
				partsChanged()
			end
		end)
		paint(false)
		table.insert(refreshers, paint)
		table.insert(partPaint, paint)
	end
	local resetParts = button(scroll, "Reset body part priority", {Size = U(1, 0, 0, 40), LayoutOrder = nextOrder()})
	on(resetParts.Activated, function()
		A.PartOrder, A.PartOn, A.TargetPart = deepCopy(DEF.AIM.PartOrder), deepCopy(DEF.AIM.PartOn), DEF.AIM.TargetPart
		partsChanged()
	end)
	section("TUNING")
	chips({{"Debug HUD", "DebugHUD"}})
	local editBtn = button(scroll, "Edit aim point", {Size = U(1, 0, 0, 40), LayoutOrder = nextOrder()})
	on(editBtn.Activated, function() editTarget = "Aim"; paintEdit(); setEditing(true) end)
	slider("Select radius (silent), %", "SilentR", 2, 60, 1, 0)
	slider("Lock release radius, %", "LockR", 5, 90, 1, 0)
	slider("Trigger delay (sec)", "TriggerDelay", 0, 0.5, 0.01, 2)
	slider("Trigger tolerance (% of screen)", "TriggerR", 0.5, 15, 0.5, 1)
	slider("Smoothness (higher = faster)", "Smoothness", 0.01, 1, 0.01, 2)
	slider("Manual predict (sec)", "Prediction", 0, 0.6, 0.01, 2)
	slider("Auto predict bias (ms)", "LeadBias", 0, 300, 5, 0)
	slider("Max distance", "MaxDistance", 50, 2000, 25, 0)
	slider("Sticky (lower = stickier)", "Sticky", 0.2, 1, 0.05, 2)
	section("DIAGNOSTICS")
	local testBtn = button(scroll, "Check coordinates", {Size = U(1, 0, 0, 40), LayoutOrder = nextOrder()})
	local selfLabel = new("TextLabel", {
		Size = U(1, 0, 0, 62), BackgroundTransparency = 1, TextWrapped = true, LayoutOrder = nextOrder(), Text = "",
		TextColor3 = C.Mut, Font = GM, TextSize = 10, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top,
	}, scroll)
	on(testBtn.Activated, function() if runSelfTest then runSelfTest() end end)

	-- ===== Вкладка FOV (визуал круга; живой предпросмотр, пока вкладка открыта) =====
	-- Размер круга = область выбора цели. Позиция круга (CircleX/Y) не связана с точкой наведения (AimX/Y),
	-- пока выключено «Circle = aim area»: двигается только рисунок.
	do
		local pageOrd = ord
		tgt, ord = api.fovPage or scroll, 0
		section("VISIBILITY")
		chips({
			{"FOV circle", "ShowFOV", nil, "Показывать круг, пока Aim включён"},
			{"Fill", "FovFill", nil, "Заливка внутри круга"},
			{"Highlight on target", "FovTarget", nil, "Круг зеленеет, когда цель захвачена"},
		})
		section("SIZE AND LOOK")
		do
			local _, paint = sliderCard(tgt, "FOV Size (diameter, % of screen)", nextOrder(), 4, 120,
				function() return A.FovR * 2 end,
				function(v) A.FovR = math.clamp(v / 2, 2, 60) end,
				function(v) return string.format("%d%%", math.floor(v + 0.5)) end,
				1)
			table.insert(refreshers, paint)
		end
		slider("FOV Transparency", "FovAlpha", 0, 1, 0.05, 2)
		slider("FOV Thickness", "CircleThick", 0.5, 6, 0.5, 1)
		slider("Fill Transparency", "FovFillAlpha", 0, 1, 0.02, 2)

		section("DYNAMIC FOV")
		chips({
			{"Dynamic FOV", "DynFov", nil, "Радиус круга и выбора цели меняется с дистанцией до цели"},
			{"Invert (far = bigger)", "DynInvert", nil, "Выкл: ближе - больше радиус; вкл: дальше - больше"},
		})
		local function cycleKeep(text, key, options) -- как cycle, но не сбрасывает текущую цель
			local _, paint = cycleCard(tgt, text, nextOrder(), function() return A[key] end, function()
				local idx = table.find(options, A[key]) or 0
				A[key] = options[idx % #options + 1]
			end)
			table.insert(refreshers, paint)
		end
		cycleKeep("Change mode", "DynMode", {"Smooth", "Linear"})
		slider("Min radius, % of screen", "DynMin", 2, 60, 1, 0)
		slider("Max radius, % of screen", "DynMax", 2, 60, 1, 0)
		slider("Start distance (studs)", "DynNear", 0, 1000, 5, 0)
		slider("Max-change distance (studs)", "DynFar", 10, 2000, 10, 0)
		slider("Smoothing (higher = smoother)", "DynSmooth", 0, 0.95, 0.05, 2)
		NX.radLbl = new("TextLabel", {
			Size = U(1, 0, 0, 34), BackgroundTransparency = 1, TextWrapped = true, LayoutOrder = nextOrder(), Text = "",
			TextColor3 = C.W, Font = GM, TextSize = 11, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top,
		}, tgt)
		section("TARGET ANIMATION")
		chips({
			{"Target animation", "TargetAnim", function(v) A.TargetAnim = v; if not v then NX.animReset() end end, "Индикатор цели: появление, переключение, захват, потеря"},
			{"Capture effect", "AnimLock", nil, "Вспышка и сжатие при захвате и смене цели"},
			{"Lose effect", "AnimLose", nil, "Красное расширение при потере цели"},
		})
		cycleKeep("Animation style", "AnimStyle", {"Ring", "Square", "Dot"})
		slider("Animation speed", "AnimSpeed", 0.25, 3, 0.05, 2)
		local demoBtn = button(tgt, "Preview animation", {Size = U(1, 0, 0, 40), LayoutOrder = nextOrder()})
		on(demoBtn.Activated, function() NX.demo = os.clock() end)
		section("FOV COLOR")
		local FOVCOL = {{0, 0, 0.94}, {0.33, 0.75, 0.9}, {0, 0.8, 0.95}, {0.52, 0.8, 1}, {0.14, 0.85, 1}, {0.8, 0.6, 1}}
		local srow = row(tgt, 40, 8, nextOrder())
		local fovPicker, fovRefresh
		for i, p in FOVCOL do
			local b = new("TextButton", {
				Size = O(40, 40), BackgroundColor3 = Color3.fromHSV(p[1], p[2], p[3]), Text = "", AutoButtonColor = false, LayoutOrder = i,
			}, srow)
			rr(b, 8)
			outline(b, 0.4)
			connect(b.Activated, function()
				A.FovCol = {h = p[1], s = p[2], v = p[3]}
				fovRefresh()
			end)
		end
		fovPicker, fovRefresh = makePicker(tgt, nextOrder(), function() return A.FovCol end, function() end, nil)
		fovRefresh()
		table.insert(refreshers, function() fovRefresh() end)
		section("POSITION (VISUAL ONLY)")
		chips({{"Circle = aim area", "CircleFollow", function(v)
			if v then A.CircleFollow = true else unlinkCircle() end
		end, "Выкл — круг двигается отдельно, точка наведения не меняется"}})
		local editCircle = button(tgt, "Edit circle position", {Size = U(1, 0, 0, 40), LayoutOrder = nextOrder()})
		connect(editCircle.Activated, function()
			editTarget = "Circle"
			paintEdit()
			setEditing(true)
		end)
		local centerCircle = button(tgt, "Reset circle to center", {Size = U(1, 0, 0, 40), LayoutOrder = nextOrder()})
		connect(centerCircle.Activated, function()
			unlinkCircle()
			A.CircleX, A.CircleY = 0.5, 0.5
		end)
		new("TextLabel", {
			Size = U(1, 0, 0, 40), BackgroundTransparency = 1, TextWrapped = true, LayoutOrder = nextOrder(),
			Text = "Размер круга задаёт и область выбора цели. Позиция круга — только визуал, пока он не связан с точкой наведения.",
			TextColor3 = C.Mut, Font = GM, TextSize = 10, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top,
		}, tgt)
		tgt, ord = scroll, pageOrd
	end

	-- ===== Координаты и точка наведения =====
	-- Всё считается в ОДНОМ пространстве: экран (viewport), пиксели, (0,0) — левый верхний угол экрана.
	-- Это пространство camera.ViewportSize / WorldToViewportPoint / ViewportPointToRay / GetMouseLocation и
	-- AbsolutePosition объектов в ScreenGui с IgnoreGuiInset (наш оверлей). Круг ставится в ДОЛЯХ оверлея (Scale),
	-- поэтому DPI, UIScale, вырез экрана и соотношение сторон его не смещают.
	-- В настройках: позиции — доли экрана (0..1), радиусы — % короткой стороны экрана.
	-- SP.aim (логика) и SP.circle (визуал) независимы: круг идёт за SP.aim только пока CircleFollow = true.

	-- прицел самой игры (только режим Crosshair): GuiObject с именем Crosshair/Reticle или тегом "Crosshair"
	local xhObj, xhT = nil, 0
	local function chainVisible(o)
		local cur = o
		while cur and not cur:IsA("LayerCollector") do
			if cur:IsA("GuiObject") and not cur.Visible then return false end
			cur = cur.Parent
		end
		return cur ~= nil and cur.Enabled
	end
	local function findCrosshair()
		local t = os.clock()
		if xhObj and xhObj.Parent and t - xhT < 1 then
			if chainVisible(xhObj) then return xhObj end
			return nil
		end
		if t - xhT < 1 then return nil end
		xhT, xhObj = t, nil
		for _, o in LP.PlayerGui:GetDescendants() do
			if o:IsA("GuiObject") and o.AbsoluteSize.X > 0 and o.AbsoluteSize.X < 150
				and not o:IsDescendantOf(og) and not o:IsDescendantOf(gui) and not o:IsDescendantOf(probeGui)
				and chainVisible(o) then
				local n = o.Name:lower()
				if n:find("crosshair") or n:find("reticle") or CS:HasTag(o, "Crosshair") then
					xhObj = o
					break
				end
			end
		end
		return xhObj
	end
	-- Центр чужого GuiObject в координатах экрана. Что именно движок кладёт в AbsolutePosition (с инсетом или без)
	-- проверяем на probe: истинный сдвиг начала координат ScreenGui минус то, что показывает probe.
	local function crosshairPoint()
		local o = findCrosshair()
		if not o then return nil end
		local sg = o:FindFirstAncestorWhichIsA("ScreenGui")
		local offset = V2(0, 0)
		if sg and not sg.IgnoreGuiInset then
			offset = GuiService:GetGuiInset() - probe.AbsolutePosition
		end
		return o.AbsolutePosition + o.AbsoluteSize / 2 + offset
	end

	-- ТОЧКА НАВЕДЕНИЯ в пикселях экрана
	local function resolveAimPoint(v)
		local center = V2(v.X / 2, v.Y / 2)
		local mode, p = A.AimMode, nil
		if mode == "Center" then
			p = center
		elseif mode == "Custom" then
			p = V2(v.X * A.AimX, v.Y * A.AimY)
		elseif mode == "Touch" then
			p = lastTouchN and V2(v.X * lastTouchN.X, v.Y * lastTouchN.Y) or center
		elseif mode == "Crosshair" then
			p = crosshairPoint() or center
		else -- Auto: свободная мышь = курсор; тач, Shift Lock, первое лицо = центр экрана
			p = center
			if UIS.MouseEnabled and UIS.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
				local m = UIS:GetMouseLocation()
				if m.X >= 0 and m.Y >= 0 and m.X <= v.X and m.Y <= v.Y then p = m end
			end
		end
		return V2(math.clamp(p.X, 0, v.X), math.clamp(p.Y, 0, v.Y))
	end

	-- единственное место, где считаются экранные координаты и радиусы; вызывается раз в кадр
	updateSpace = function()
		local v = camera.ViewportSize
		if v.X < 2 or v.Y < 2 then return false end
		local short = math.min(v.X, v.Y)
		SP.vp = v
		SP.fov, SP.silent, SP.lock = ((A.DynFov or NX.dynBack) and NX.dynR or A.FovR) * 0.01 * short, A.SilentR * 0.01 * short, A.LockR * 0.01 * short
		SP.aim = resolveAimPoint(v)
		SP.circle = A.CircleFollow and SP.aim or V2(v.X * A.CircleX, v.Y * A.CircleY)
		return true
	end

	-- ВИЗУАЛ: только читает SP, ничего в логике не меняет
	local function drawOverlay(now)
		local v = SP.vp
		local showCircle = editing or (A.Enabled and A.ShowFOV) or now < testUntil or (previewFov and A.ShowFOV)
		setp(fov, "Visible", showCircle)
		if showCircle then
			-- квадрат в пикселях: ширина всегда равна высоте, при любом разрешении и соотношении сторон
			local d = math.max(4, 2 * SP.fov)
			setp(fov, "Size", O(d, d))
			setp(fov, "Position", S(SP.circle.X / v.X, SP.circle.Y / v.Y))
		end
		local showMark = editing or (A.Enabled and A.ShowFOV and not A.CircleFollow) or now < testUntil
		aimMark.Visible = showMark
		if showMark then aimMark.Position = S(SP.aim.X / v.X, SP.aim.Y / v.Y) end
	end

	-- Проверка на устройстве: кнопка Check coordinates (вкладка Aim)
	runSelfTest = function()
		testUntil = os.clock() + 3
		task.spawn(function()
			task.wait(0.3) -- пусть цикл отрисует круг и движок пересчитает AbsolutePosition
			if not updateSpace() then selfLabel.Text = "Экран ещё не готов, повтори" return end
			local v = SP.vp
			local ray = camera:ViewportPointToRay(SP.aim.X, SP.aim.Y)
			local back = camera:WorldToViewportPoint(ray.Origin + ray.Direction.Unit * 100)
			local eProj = (V2(back.X, back.Y) - SP.aim).Magnitude
			local ov = og.AbsoluteSize
			local eOv = (ov - v).Magnitude
			local cc = fov.AbsolutePosition + fov.AbsoluteSize / 2
			local eCenter = (cc - SP.circle).Magnitude
			local eRad = math.abs(fov.AbsoluteSize.X / 2 - SP.fov)
			local ok = eProj < 1.5 and eOv < 1.5 and eCenter < 1.5 and eRad < 1.5
			local text = string.format(
				"%s\nэкран %.0f×%.0f, оверлей %.0f×%.0f (Δ%.1f px), проекция aim Δ%.1f px\nкруг: центр Δ%.1f px, радиус %.1f px (Δ%.1f), aim %.0f,%.0f",
				ok and "OK: круг и область совпадают" or "ОШИБКА: есть расхождение", v.X, v.Y, ov.X, ov.Y, eOv, eProj,
				eCenter, SP.fov, eRad, SP.aim.X, SP.aim.Y)
			selfLabel.Text, selfLabel.TextColor3 = text, ok and C.On or C.Off
			print("[Enkaisy] " .. text:gsub("\n", " | "))
		end)
	end

	setEditing = function(s)
		if s == editing then return end
		editing = s
		editLayer.Visible, editBar.Visible = s, s
		dragInput = nil
		currentTarget = nil
		refreshAll(false)
		if api and api.menu then api.menu(not s) end
	end

	local function isActive()
		if not A.Enabled then return false end
		if A.HoldToAim and not UIS.TouchEnabled then
			return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		end
		return true
	end

	local function isTeammate(plr)
		if not A.TeamCheck then return false end
		return plr.Team ~= nil and LP.Team ~= nil and plr.Team == LP.Team
	end

	-- единый обход целей: игроки (кроме себя и тимейтов) + NPC
	local function eachTarget(fn)
		if A.TargetPlayers then
			for _, plr in Players:GetPlayers() do
				if plr ~= LP and not isTeammate(plr) and plr.Character then fn(plr.Character) end
			end
		end
		if A.TargetNPCs then
			for m in npcs do fn(m) end
			for m in tagged do if not npcs[m] then fn(m) end end
		end
	end

	-- ближайшая к прицелу цель (опорная дистанция для Dynamic FOV, пока цель не выбрана); пересчёт ~8 раз в секунду
	NX.nearest = function(now)
		if now - NX.nearT < 0.12 then return NX.nearD end
		NX.nearT, NX.nearD = now, nil
		local best = math.max(A.DynMin, A.DynMax) * 0.01 * math.min(SP.vp.X, SP.vp.Y)
		local camPos = camera.CFrame.Position
		eachTarget(function(model)
			local hum = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
			if not hum or hum.Health <= 0 or not root or model == LP.Character then return end
			local d = (root.Position - camPos).Magnitude
			if d > A.MaxDistance then return end
			local sp, vis = camera:WorldToViewportPoint(root.Position)
			if not vis then return end
			local sd = (V2(sp.X, sp.Y) - SP.aim).Magnitude
			if sd < best then best, NX.nearD = sd, d end
		end)
		return NX.nearD
	end

	-- ===== Checks: цели, которые нужно игнорировать =====
	-- Invulnerable: ForceField или атрибут Invulnerable = true на модели
	-- Flash: атрибут Flashed = true на модели цели (вашу флеш-механику выставляйте на сервере)
	-- Smoke: атрибут InSmoke = true на модели ИЛИ линия до цели пересекает Part с тегом "SmokeCloud" (CanQuery = true)
	-- точка, из которой реально летит пуля (голова); иначе камера
	local function eyePos()
		if A.VisFromHead then
			local h = LP.Character and LP.Character:FindFirstChild("Head")
			if h then return h.Position end
		end
		return camera.CFrame.Position
	end
	local smokeRP, smokeN, smokeT = RaycastParams.new(), 0, 0
	smokeRP.FilterType = Enum.RaycastFilterType.Include
	local function smokeBlocks(part)
		local t = os.clock()
		if t - smokeT > 0.5 then -- список облаков обновляем раз в 0.5с, а не на каждую цель
			smokeT = t
			local clouds = CS:GetTagged("SmokeCloud")
			smokeN, smokeRP.FilterDescendantsInstances = #clouds, clouds
		end
		if smokeN == 0 then return false end
		local o = eyePos()
		return Workspace:Raycast(o, part.Position - o, smokeRP) ~= nil
	end
	local function passChecks(model, part)
		if A.CheckInvuln and (model:FindFirstChildOfClass("ForceField") or model:GetAttribute("Invulnerable") == true) then return false end
		if A.CheckFlash and model:GetAttribute("Flashed") == true then return false end
		if A.CheckSmoke then
			if model:GetAttribute("InSmoke") == true then return false end
			if part and smokeBlocks(part) then return false end
		end
		return true
	end

	-- (раньше пропускался случай, когда луч попадал во вложенную Model внутри персонажа — триггер считал это «не humanoid»)
	local function humModel(inst)
		return inst and humanoidModel(inst)
	end

	local function getTargetPart(model)
		if not model or not model:IsA("Model") or model == LP.Character then return nil end
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return nil end
		local part = NX.resolve(model) -- v4.0 Body Part Priority: основная часть, затем запасные по очереди
		if not part or not passChecks(model, part) then return nil end
		return part
	end

	local function getLead()
		return A.AutoPredict and autoLead or A.Prediction
	end

	-- ===== Multipoint: ищем видимую точку по краям хитбокса (голова, плечи) =====
	local scanCache = setmetatable({}, {__mode = "k"})
	local GROUPS = {
		Head = {"Head"},
		Torso = {"UpperTorso", "LowerTorso", "Torso", "HumanoidRootPart"},
		Arms = {"LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "Left Arm", "Right Arm"},
		Legs = {"LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot", "Left Leg", "Right Leg"},
	}
	local GROUP_ORDER = {{"Head", "MPHead"}, {"Torso", "MPTorso"}, {"Arms", "MPArms"}, {"Legs", "MPLegs"}}
	local EDGES = {{0, 0, 0}, {0.4, 0, 0}, {-0.4, 0, 0}, {0, 0.4, 0}, {0, -0.4, 0}}
	local CENTER = {{0, 0, 0}}
	-- порядок: выбранная часть (центр + края), затем включённые запасные части тела.
	-- Если выбрана голова, а видны только ноги и включено "MP legs", прицел уйдёт на ноги.
	local function scanPoint(model, part)
		local now = os.clock()
		local c = scanCache[model]
		if c and c.part == part and now - c.t < 0.05 then return c.pos end
		local origin = eyePos()
		local pts = {}
		local function add(p, offsets)
			local cf, sz = p.CFrame, p.Size
			for _, o in offsets do table.insert(pts, cf * Vector3.new(o[1] * sz.X, o[2] * sz.Y, o[3] * sz.Z)) end
		end
		add(part, A.MPEdges and EDGES or CENTER)
		for _, g in GROUP_ORDER do
			if A[g[2]] then
				local offs = (A.MPEdges and (g[1] == "Head" or g[1] == "Torso")) and EDGES or CENTER
				for _, name in GROUPS[g[1]] do
					local p = model:FindFirstChild(name)
					if p and p:IsA("BasePart") and p ~= part then add(p, offs) end
				end
			end
		end
		local found
		for _, pt in pts do
			local r = Workspace:Raycast(origin, pt - origin, rayParams)
			if r and r.Instance:IsDescendantOf(model) then
				found = pt
				break
			end
		end
		scanCache[model] = {t = now, part = part, pos = found}
		return found
	end

	-- ===== v4.0 Body Part Priority =====
	-- Очередь: A.PartOrder + A.PartOn; основная часть = первая включённая (A.TargetPart всегда равен ей).
	-- Часть "доступна", если существует и (при Wall check) видна: тогда при закрытой основной берётся следующая.
	-- Выбор кэшируется на 0.06 с на модель (лучи не летят на каждый вызов); любая смена настроек сбрасывает кэш (NX.gen).
	local partState = setmetatable({}, {__mode = "k"})
	local function slotPart(model, slot)
		for _, n in ipairs(V4.ALIAS[slot]) do
			local p = model:FindFirstChild(n)
			if p and p:IsA("BasePart") then return p end
		end
		return nil
	end
	-- при Multipoint видимость проверяет сам Multipoint (он тоже умеет переходить на запасные группы тела)
	local function partAvailable(model, p)
		if not A.WallCheck then return true end
		if A.Multipoint then return scanPoint(model, p) ~= nil end
		local o = eyePos()
		local r = Workspace:Raycast(o, p.Position - o, rayParams)
		return r ~= nil and r.Instance:IsDescendantOf(model)
	end
	NX.resolve = function(model)
		local now = os.clock()
		local st = partState[model]
		if st and st.gen ~= NX.gen then st = nil end
		if st and now - st.t < 0.06 and st.part and st.part.Parent then return st.part end
		local fb = A.PartFallback
		local chosen, chosenRank, first, firstRank, rank = nil, 0, nil, 0, 0
		for _, s in ipairs(A.PartOrder) do
			if A.PartOn[s] then
				rank += 1
				local p = slotPart(model, s)
				if p then
					if not first then first, firstRank = p, rank end
					if not fb or partAvailable(model, p) then
						chosen, chosenRank = p, rank
						break
					end
				end
			end
		end
		if not chosen then chosen, chosenRank = first, firstRank end -- ничего не доступно: основная существующая часть (дальше отсеет проверка видимости)
		if not chosen then chosen, chosenRank = model:FindFirstChild("HumanoidRootPart"), 99 end
		local prev = st and st.part and st.part.Parent and st or nil
		if prev and chosen ~= prev.part then
			if fb and chosenRank < prev.rank then
				-- вернулась более приоритетная часть: Return to main возвращает цель на неё (с задержкой 0.15 с против мерцания),
				-- без Return to main цель остаётся на запасной части, пока та доступна
				local hold = true
				if A.PartReturn then
					prev.up = prev.up or now
					hold = now - prev.up < 0.15
				end
				if hold and partAvailable(model, prev.part) then chosen, chosenRank = prev.part, prev.rank end
			else
				prev.up = nil
			end
		elseif prev then
			prev.up = nil
		end
		st = prev or {}
		st.gen, st.t, st.part, st.rank = NX.gen, now, chosen, chosenRank
		partState[model] = st
		return chosen
	end

	-- ===== Кинематика цели =====
	-- Скорость и ускорение берутся из ИЗМЕНЕНИЯ ПОЗИЦИИ (сглаженно), а не только из AssemblyLinearVelocity:
	-- у чужих персонажей на клиенте она часто равна 0 или шумит (CFrame-движение, интерполяция) — поэтому предикт «не работал».
	-- Холодный старт (цель ещё не отслеживалась) берёт скорость движка; дальше работает трекер.
	local trk = setmetatable({}, {__mode = "k"})
	local function trackPart(part)
		local now, pos = os.clock(), part.Position
		local k = trk[part]
		local ev = part.AssemblyLinearVelocity
		if ev.Magnitude > 150 then ev = Vector3.zero end
		if not k then
			k = {p = pos, t = now, v = ev, a = Vector3.zero, warm = false}
			trk[part] = k
			return k
		end
		local dt = now - k.t
		if dt < 0.012 then return k end -- в одном кадре второй раз не считаем
		if dt > 0.4 then -- цель давно не обновлялась: начинаем заново
			k.p, k.t, k.v, k.a, k.warm = pos, now, ev, Vector3.zero, false
			return k
		end
		local raw = (pos - k.p) / dt
		if raw.Magnitude > 220 then -- телепорт / респавн
			k.p, k.t, k.v, k.a, k.warm = pos, now, Vector3.zero, Vector3.zero, false
			return k
		end
		-- позиция почти не меняется, а движок сообщает о движении — верим движку
		if raw.Magnitude < 0.3 and ev.Magnitude > 1 then raw = ev end
		local nv = k.v:Lerp(raw, 1 - math.exp(-dt / 0.06))
		local an = (nv - k.v) / dt
		if an.Magnitude > 80 then an = an.Unit * 80 end
		k.a = k.a:Lerp(an, 1 - math.exp(-dt / 0.15))
		k.v, k.p, k.t, k.warm = nv, pos, now, true
		return k
	end

	-- «в воздухе»: под целью на ближайших 8 студах нет земли (FloorMaterial у чужих гуманоидов ненадёжен)
	local groundRP, groundModel = RaycastParams.new(), nil
	groundRP.FilterType = Enum.RaycastFilterType.Exclude
	local function groundBelow(part, len)
		local model = part.Parent
		if groundModel ~= model then
			groundModel = model
			groundRP.FilterDescendantsInstances = {model, LP.Character}
		end
		return Workspace:Raycast(part.Position, Vector3.new(0, -len, 0), groundRP)
	end

	-- Basic predict: линейная экстраполяция (на земле вертикаль не экстраполируем — шаги и неровности дают шум)
	local function basicPoint(part, pos)
		local lead = getLead()
		if lead <= 0 then return pos end
		local v = trackPart(part).v
		if v.Magnitude > 80 then v = v.Unit * 80 end
		if not groundBelow(part, 8) then
			-- в воздухе: параболу не строим, но и не уводим точку под землю
			v = Vector3.new(v.X, math.clamp(v.Y, -40, 40), v.Z)
		else
			v = Vector3.new(v.X, 0, v.Z)
		end
		local d = v * lead
		if d.Magnitude > 50 then d = d.Unit * 50 end
		return pos + d
	end

	-- ===== Advanced prediction: скорость + ускорение + прыжок/падение + Bullet Drop + стрейфы =====
	-- Атрибуты Tool: BulletSpeed (стадов/с) и BulletGravity (стадов/с^2), те же, что использует сервер.
	-- ВАЖНО: сервер проверяет попадание МГНОВЕННО вдоль всей дуги пули (цель за время полёта не двигается),
	-- поэтому на время полёта цель опережать нельзя — это давало перелёт. Упреждение = только задержка сети (getLead),
	-- а время полёта нужно лишь для компенсации падения пули. Для игр с настоящими снарядами поставь true.
	local ADV_FLIGHT_LEAD = false
	local function advancedPoint(part, pos)
		local k = trackPart(part)
		local vel = k.v
		if vel.Magnitude > 80 then vel = vel.Unit * 80 end
		local ground = groundBelow(part, 8)
		local airborne = ground == nil
		local ch = LP.Character
		local head = ch and ch:FindFirstChild("Head")
		local origin = head and head.Position or camera.CFrame.Position
		local tool = ch and ch:FindFirstChildOfClass("Tool")
		local speed = tool and tool:GetAttribute("BulletSpeed")
		local grav = tool and tool:GetAttribute("BulletGravity")
		local hasSpeed = type(speed) == "number" and speed > 0
		local flatV = Vector3.new(vel.X, 0, vel.Z)
		local flatA = k.warm and Vector3.new(k.a.X, 0, k.a.Z) or Vector3.zero
		if flatA.Magnitude > 40 then flatA = flatA.Unit * 40 end
		-- стрейф / разворот: заметное ускорение против движения — экстраполяцию укорачиваем
		local strafeK = 1
		if flatV.Magnitude > 3 and flatA.Magnitude > 12 and flatA.Unit:Dot(flatV.Unit) < -0.3 then strafeK = 0.55 end
		local g, lead = Workspace.Gravity, getLead()
		local useFlight = ADV_FLIGHT_LEAD and hasSpeed
		local target = pos
		for _ = 1, useFlight and 3 or 1 do
			local flight = useFlight and (target - origin).Magnitude / speed or 0
			local t = math.clamp((flight + lead) * strafeK, 0, 1.2)
			-- горизонталь: скорость + затухающее ускорение (ходьба разгоняется почти мгновенно, полный a·t²/2 давал бы перелёт)
			local dxz = flatV * t + 0.25 * flatA * t * t
			local dy = airborne and (vel.Y * t - 0.5 * g * t * t) or 0
			local d = Vector3.new(dxz.X, dy, dxz.Z)
			if d.Magnitude > 60 then d = d.Unit * 60 end
			target = pos + d
		end
		-- падающая цель приземляется: не целимся под землю
		if airborne and target.Y < pos.Y then
			local land = Workspace:Raycast(pos, Vector3.new(0, -120, 0), groundRP)
			if land then
				local rest = part.Name == "Head" and 4.6 or 3.1
				target = Vector3.new(target.X, math.max(target.Y, land.Position.Y + rest), target.Z)
			end
		end
		-- падение пули: как на сервере, дуга только если заданы И BulletSpeed, И BulletGravity (иначе мгновенный луч)
		if hasSpeed and type(grav) == "number" and grav > 0 then
			local base = target
			for _ = 1, 3 do -- время полёта до уже приподнятой точки (сервер: pos = dir*v*t - g*t²/2)
				local f = (target - origin).Magnitude / speed
				target = base + Vector3.new(0, 0.5 * grav * f * f, 0)
			end
		end
		return target
	end

	local function getAimPoint(part)
		local pos = part.Position
		if A.Multipoint then
			local model = humModel(part)
			pos = model and scanPoint(model, part) or pos
		end
		if A.AdvPredict then return advancedPoint(part, pos) end
		return basicPoint(part, pos)
	end

	local function isVisible(model, part)
		if not A.WallCheck then return true end
		if A.Multipoint then return scanPoint(model, part) ~= nil end
		local origin = eyePos()
		local result = Workspace:Raycast(origin, part.Position - origin, rayParams)
		return result ~= nil and result.Instance:IsDescendantOf(model)
	end

	-- byPrio: вернуть оценку по выбранному приоритету (в масштабе радиуса), иначе расстояние до прицела в px
	local function evaluate(model, part, radius, byPrio)
		local dist = (part.Position - camera.CFrame.Position).Magnitude
		if dist > A.MaxDistance then return nil end
		local sp, onScreen = camera:WorldToViewportPoint(part.Position)
		if not onScreen then return nil end
		local sd = (V2(sp.X, sp.Y) - SP.aim).Magnitude
		local lim = radius or SP.fov
		if sd > lim then return nil end
		if not isVisible(model, part) then return nil end
		if byPrio and A.Priority ~= "Crosshair" then
			if A.Priority == "Distance" then
				return dist / math.max(A.MaxDistance, 1) * lim * 0.999 + sd * 0.001
			end
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum then
				return math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1) * lim * 0.999 + sd * 0.001
			end
		end
		return sd
	end

	local bestPart, bestDistance = nil, 0
	local function consider(model)
		if model == skipModel and os.clock() < skipUntil then return end
		local part = getTargetPart(model)
		if not part or part == currentTarget then return end
		local d = evaluate(model, part, nil, true)
		if d and d < bestDistance then
			bestDistance, bestPart = d, part
		end
	end

	-- ===== Target Lock: цель удерживается, пока жива, видима и в радиусе LockRadius =====
	local function lockedPart()
		if not lockedModel or not lockedModel.Parent then return nil end
		local part = getTargetPart(lockedModel)
		if not part then return nil end
		if evaluate(lockedModel, part, SP.lock) == nil then return nil end
		return part
	end

	local function pickTarget()
		if A.TargetLock then
			local lp = lockedPart()
			if lp then return lp end
			lockedModel = nil
		elseif lockedModel then
			lockedModel = nil
		end
		local currentDistance
		if currentTarget and currentTarget.Parent then
			local model = humModel(currentTarget)
			if model and getTargetPart(model) == currentTarget then
				currentDistance = evaluate(model, currentTarget, nil, true)
			end
		end
		bestPart = nil
		bestDistance = currentDistance and (currentDistance * A.Sticky) or SP.fov
		eachTarget(consider)
		if bestPart then
			if A.TargetLock then lockedModel = humModel(bestPart) end
			return bestPart
		end
		if currentDistance then return currentTarget end
		return nil
	end

	-- E / кнопка: сбросить захват и перейти к следующей ближайшей к прицелу цели
	switchTarget = function()
		if not A.TargetLock then return end
		skipModel, skipUntil = lockedModel, os.clock() + 1.5
		lockedModel, currentTarget = nil, nil
	end

	-- ===== Hitbox / Head hitbox =====
	-- Размеры хитбоксов в студах (0 = выключено). Фактическое значение режется лимитом сервера (атрибуты ремоута).
	local function hbPads()
		if not A.Hitbox and not A.HeadHitbox then return 0, 0 end
		local fr = fireRemote or ReplicatedStorage:FindFirstChild(REMOTE_NAME)
		local capB = fr and fr:GetAttribute("HitboxMaxBody")
		local capH = fr and fr:GetAttribute("HitboxMaxHead")
		if type(capB) ~= "number" then capB = HB_BODY_MAX end
		if type(capH) ~= "number" then capH = HB_HEAD_MAX end
		local b = A.Hitbox and math.min(A.HitboxSize, capB) or 0
		local h = A.HeadHitbox and math.min(A.HeadHitboxSize, capH) or 0
		return math.max(b, 0), math.max(h, 0)
	end

	-- цель, чей расширенный хитбокс ближе всего пересекает луч (origin, dir — единичный)
	local function hitboxTarget(origin, dir, range)
		local b, h = hbPads()
		if b <= 0 and h <= 0 then return nil end
		local bestM, bestT = nil, range
		eachTarget(function(model)
			local hum = model:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then return end
			local t = rayModelHitbox(origin, dir, bestT, model, b, h)
			if t and t <= bestT then bestM, bestT = model, t end
		end)
		return bestM, bestT
	end

	-- ===== Hitbox Visual (v4.0): ТОЛЬКО отрисовка =====
	-- Размер каждого бокса = размер части + 2 * pad. pad берётся из hbPads() - это ровно те значения, по которым считаются попадания.
	-- Цвета, прозрачность, обводка, дистанция и режимы показа читаются из AIMCFG.Hbv* и на размеры хитбоксов не влияют.
	-- Бокс = невидимая рамка-Part (CanQuery = false, лежит в камере, лучи и физика её не видят) + SelectionBox (обводка и заливка граней).
	-- Всё считается каждый кадр и сглаживается (размер, цвет, прозрачность, толщина линий): цели появляются, исчезают и меняют цвет плавно.
	-- Рамки лежат в пуле: создаются один раз на часть тела и переиспользуются, поэтому ничего не мерцает.
	local hbVis = {m = {}, sel = {}, selT = 0, fid = 0, folder = nil}
	local function clearHbVis()
		if hbVis.folder then hbVis.folder:Destroy() end
		hbVis.folder = nil
		table.clear(hbVis.m)
		table.clear(hbVis.sel)
		hbVis.selT = 0
	end
	-- расстояние до цели, если она жива и в пределах лимита; иначе nil
	hbVis.dist = function(m, camPos, limit)
		if not m or not m.Parent or m == LP.Character then return nil end
		local hum = m:FindFirstChildOfClass("Humanoid")
		local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
		if not hum or hum.Health <= 0 or not root then return nil end
		local d = (root.Position - camPos).Magnitude
		if d > limit then return nil end
		return d
	end
	hbVis.drop = function(m, s)
		for _, e in s.parts do e.px:Destroy() end
		hbVis.m[m] = nil
	end
	hbVis.newEntry = function(folder, p, pad)
		local px = Instance.new("Part")
		px.Name = "THHitboxVis"
		px.Anchored, px.CanCollide, px.CanQuery, px.CanTouch = true, false, false, false
		px.CastShadow, px.Massless, px.Locked, px.Transparency = false, true, true, 1
		px.Size = p.Size + Vector3.new(pad, pad, pad) * 2
		px.CFrame = p.CFrame
		px.Parent = folder
		local sb = Instance.new("SelectionBox")
		sb.Name = "THHitboxBox"
		sb.Adornee = px
		sb.Visible = false
		sb.LineThickness = 0.02
		sb.Parent = px
		return {px = px, sb = sb, pad = pad, f = 0} -- pad - сглаженное расширение (догоняет значение из hbPads)
	end

	local function updateHbVis(now, dt)
		local V = hbVis
		local cam = camera
		if not cam then clearHbVis() return end
		dt = math.clamp(dt or 0.016, 0.001, 0.1)
		local limit = A.HbvDist
		local camPos = cam.CFrame.Position

		-- физические расширения (только чтение): тело и голова
		local b, h = 0, 0
		local active = A.HitboxShow
		if active then
			b, h = hbPads()
			active = (b > 0 or h > 0) and (A.HbvShowHead or A.HbvShowBody)
		end
		-- цель, на которую сейчас наведена наводка (или удерживается Target Lock)
		local tm = currentTarget and humModel(currentTarget) or (A.TargetLock and lockedModel) or nil

		-- какие цели показывать
		if not active then
			if next(V.sel) then V.sel = {} end -- всё плавно гаснет
		elseif A.HbvOnlyTarget then
			V.sel = {}
			if tm and V.dist(tm, camPos, limit) then V.sel[tm] = true end
		elseif now - V.selT >= 0.12 then
			V.selT = now
			local list = {}
			eachTarget(function(m)
				local d = V.dist(m, camPos, limit)
				if d then table.insert(list, {m = m, d = d}) end
			end)
			table.sort(list, function(x, y) return x.d < y.d end)
			V.sel = {}
			for i = 1, math.min(#list, 6) do V.sel[list[i].m] = true end -- ближайшие 6 (нагрузка на телефон)
			if tm and V.dist(tm, camPos, limit) then V.sel[tm] = true end
		end
		for m in V.sel do
			if m.Parent and not V.m[m] then
				V.m[m] = {a = 0, cap = 0, parts = {}, list = {}, listT = -1, idle = 0, shown = false}
			end
		end
		if not next(V.m) then
			if V.folder then V.folder:Destroy() V.folder = nil end
			return
		end
		if not V.folder or V.folder.Parent ~= cam then -- камеру могли пересоздать: рамки пропали вместе с ней
			if V.folder then V.folder:Destroy() end
			for _, s in V.m do table.clear(s.parts) end
			V.folder = Instance.new("Folder")
			V.folder.Name = "THHitboxVis"
			V.folder.Parent = cam
		end

		-- коэффициенты сглаживания (не зависят от частоты кадров)
		V.fid += 1
		local kF = 1 - math.exp(-dt * 12)   -- появление / исчезновение
		local kPad = 1 - math.exp(-dt * 18) -- изменение размера (ползунок)
		local kTh = 1 - math.exp(-dt * 14)  -- толщина линий
		local kCap = A.TargetAnim and (1 - math.exp(-dt * 10 * math.clamp(A.AnimSpeed, 0.25, 3))) or 1 -- захват цели: как у круга FOV
		local tanH = math.tan(math.rad(cam.FieldOfView) * 0.5)
		local vpH = math.max(cam.ViewportSize.Y, 1)
		local fillOp = (1 - A.HbvFillAlpha) * (1 - A.HbvAlpha) -- непрозрачность заливки
		local lineOp = A.HbvThick > 0 and (1 - A.HbvAlpha) or 0 -- непрозрачность обводки
		local colB, colH = hsv(A.HbvBodyCol), hsv(A.HbvHeadCol)
		local colO, colL = hsv(A.HbvOutCol), hsv(A.HbvLockCol)
		local moveP, moveC = {}, {}

		for m, s in V.m do
			local root = m.Parent and (m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart)
			if not root then
				V.drop(m, s) -- модель удалена: сразу убираем
			else
				local inSel = V.sel[m] == true
				local d = (root.Position - camPos).Magnitude
				-- видимость: плавно гаснет у края лимита дистанции и когда цель выбыла из показа
				local f = inSel and math.clamp((limit - d) / (limit * 0.15), 0, 1) or 0
				s.a += (f - s.a) * kF
				if math.abs(f - s.a) < 0.005 then s.a = f end
				-- захват: плавный переход цвета к Locked
				local capT = (A.HbvCapture and m == tm) and 1 or 0
				s.cap += (capT - s.cap) * kCap
				if math.abs(capT - s.cap) < 0.005 then s.cap = capT end

				if s.a <= 0.005 then
					if s.shown then
						for _, e in s.parts do e.sb.Visible = false end
						s.shown = false
					end
					if not inSel then
						s.idle += dt
						if s.idle > 2.5 then V.drop(m, s) end
					end
				else
					s.idle, s.shown = 0, true
					if now - s.listT >= 0.5 then -- те же части, что проверяет физика: прямые BasePart модели, кроме HumanoidRootPart
						s.listT = now
						local list = {}
						for _, p in m:GetChildren() do
							if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then table.insert(list, p) end
						end
						s.list = list
					end
					-- толщина линий: SelectionBox меряет её в студах, пересчитываем из пикселей по дистанции (одинаково на любом расстоянии)
					local thWant = A.HbvThick * 2 * d * tanH / vpH
					s.th = s.th and (s.th + (thWant - s.th) * kTh) or thWant
					local thB = math.clamp(s.th, 0.004, 0.5)
					local thH = math.clamp(s.th * 1.3, 0.004, 0.5) -- у головы линия чуть толще
					-- цвета: тело сильнее уходит в цвет захвата, голова слабее (остаётся отличимой)
					local cB = colB:Lerp(colL, s.cap)
					local cH = colH:Lerp(colL, s.cap * 0.35)
					local oB = A.HbvOutMatch and cB or colO:Lerp(colL, s.cap)
					local oH = A.HbvOutMatch and cH or colO:Lerp(colL, s.cap * 0.35)
					local boost = 1 + 0.3 * s.cap
					local sfB = 1 - math.clamp(fillOp * boost, 0, 1) * s.a        -- прозрачность заливки тела
					local sfH = 1 - math.clamp(fillOp * 1.35 * boost, 0, 1) * s.a -- у головы заливка плотнее
					local lnT = 1 - lineOp * s.a
					for _, p in s.list do
						if p.Parent then
							local isHead = p.Name == "Head"
							local pad = isHead and math.max(b, h) or b -- как в rayModelHitbox
							if pad > 0 and (isHead and A.HbvShowHead or (not isHead and A.HbvShowBody)) then
								local e = s.parts[p]
								if not e then
									e = V.newEntry(V.folder, p, pad)
									s.parts[p] = e
								end
								e.f = V.fid
								e.pad += (pad - e.pad) * kPad
								if math.abs(pad - e.pad) < 0.004 then e.pad = pad end
								local sz = p.Size + Vector3.new(e.pad, e.pad, e.pad) * 2
								if (e.px.Size - sz).Magnitude > 0.003 then e.px.Size = sz end
								local sb = e.sb
								setp(sb, "Visible", true)
								setp(sb, "Color3", isHead and oH or oB)
								setp(sb, "Transparency", lnT)
								setp(sb, "LineThickness", isHead and thH or thB)
								setp(sb, "SurfaceColor3", isHead and cH or cB)
								setp(sb, "SurfaceTransparency", isHead and sfH or sfB)
								table.insert(moveP, e.px)
								table.insert(moveC, p.CFrame) -- рамка стоит ровно на части тела: смещения нет
							end
						end
					end
					for p, e in s.parts do -- части, которые в этом кадре не рисуются (выключены, исчезли)
						if e.f ~= V.fid then
							if e.sb.Visible then e.sb.Visible = false end
							if not p.Parent then
								e.px:Destroy()
								s.parts[p] = nil
							end
						end
					end
				end
			end
		end

		-- все рамки переставляются одним вызовом
		if #moveP > 0 then
			local ok = pcall(Workspace.BulkMoveTo, Workspace, moveP, moveC, Enum.BulkMoveMode.FireCFrameChanged)
			if not ok then
				for i, px in moveP do px.CFrame = moveC[i] end
			end
		end
		if not next(V.m) and V.folder then
			V.folder:Destroy()
			V.folder = nil
		end
	end

	-- ===== Triggerbot: стреляет сам, когда в прицеле допустимая цель =====
	-- Цель «в прицеле», если выполнено ЛЮБОЕ из (работает и без включённой наводки Aim):
	--   1) луч из точки наведения попал прямо в тело цели;
	--   2) луч проходит через расширенный хитбокс (Hitbox / Head hitbox) и стена не мешает;
	--   3) упреждённая точка цели лежит в пределах допуска TriggerR от точки наведения и до неё есть прямая видимость.
	-- В случаях 2 и 3 пуля отправляется точно в точку цели (как Silent Aim; сервер ограничивает угол, SILENT_MAX_ANGLE).
	-- При включённом Silent Aim стреляем, когда цель есть в радиусе Silent.
	local pickMs, pickWarned = 0, false
	local lastTrigger, seenSince, seenModel, lastWarm = 0, nil, nil, 0
	local trigStatus = "off"
	local fireTool -- присваивается ниже (= shoot)
	local silentTarget -- определена ниже (нужна triggerbot'у)
	local function trigValid(model)
		if not model or not model:FindFirstChildOfClass("Humanoid") then return false, "no humanoid" end
		if not getTargetPart(model) then return false, "target filtered (dead/checks)" end
		local plr = Players:GetPlayerFromCharacter(model)
		if plr then
			if not A.TargetPlayers then return false, "Players off" end
			if isTeammate(plr) then return false, "teammate" end
		elseif not A.TargetNPCs then
			return false, "NPCs off"
		end
		return true
	end
	-- цель, чья упреждённая точка в пределах tolPx от точки наведения и видна из головы (Wall check не важен — тут всегда)
	local function tolCandidate(range, tolPx)
		local best, bestD = nil, tolPx
		local origin = eyePos()
		local camPos = camera.CFrame.Position
		eachTarget(function(model)
			local part = getTargetPart(model)
			if not part or (part.Position - camPos).Magnitude > range then return end
			local sp, vis = camera:WorldToViewportPoint(getAimPoint(part))
			if not vis then return end
			local d = (V2(sp.X, sp.Y) - SP.aim).Magnitude
			if d >= bestD then return end
			local r = Workspace:Raycast(origin, part.Position - origin, rayParams)
			if not (r and r.Instance:IsDescendantOf(model)) then return end
			best, bestD = part, d
		end)
		return best
	end
	local function triggerStep(now)
		local ch = LP.Character
		local tool = ch and ch:FindFirstChildOfClass("Tool")
		if not tool then seenSince, seenModel = nil, nil trigStatus = "no tool (equip weapon)" return end
		local range = tool:GetAttribute("Range")
		range = math.min(type(range) == "number" and range or 500, A.MaxDistance)
		local tolPx = math.min(SP.vp.X, SP.vp.Y) * A.TriggerR * 0.01
		local model, aimPart, how, why
		if A.SilentAim then
			-- при Silent Aim стреляем, когда в silent-радиусе есть цель (направление подправит shoot)
			local cand = silentTarget()
			if cand then
				trackPart(cand) -- прогреваем трекер скорости для предикта
				local m = humModel(cand)
				local ok, w = trigValid(m)
				if ok then model, aimPart, how = m, cand, "silent" else why = w end
			else
				why = "no silent target"
			end
		else
			local ray = camera:ViewportPointToRay(SP.aim.X, SP.aim.Y)
			local dirU = ray.Direction.Unit
			local real = Workspace:Raycast(ray.Origin, dirU * range, rayParams)
			-- 1) луч попал прямо в цель
			local hitModel = real and humModel(real.Instance)
			if hitModel then
				local ok, w = trigValid(hitModel)
				if ok then model, how = hitModel, "ray" else why = w end
			else
				why = real and ("no humanoid: " .. real.Instance.Name) or "nothing in sight"
			end
			-- 2) луч проходит через расширенный хитбокс
			if not model then
				local hm, ht = hitboxTarget(ray.Origin, dirU, range)
				if hm and not (real and real.Distance < ht - 0.1 and not real.Instance:IsDescendantOf(hm)) then
					local ok, w = trigValid(hm)
					if ok then model, aimPart, how = hm, getTargetPart(hm), "hitbox" else why = w end
				end
			end
			-- 3) цель рядом с точкой наведения (допуск TriggerR)
			if not model then
				local cand = tolCandidate(range, tolPx)
				if cand then model, aimPart, how = humModel(cand), cand, "tolerance" end
			end
			-- при включённой наводке пуля идёт в текущую цель (упреждённую точку), а не по отстающей камере
			if model and how == "ray" and A.Enabled then
				local ct = currentTarget
				if ct and ct.Parent and humModel(ct) == model then aimPart = ct end
			end
		end
		if not model then seenSince, seenModel = nil, nil trigStatus = why or "no target" return end
		if seenModel ~= model then seenModel, seenSince = model, now end
		local cd = tool:GetAttribute("Cooldown")
		cd = type(cd) == "number" and cd or 0.15
		if now - seenSince < A.TriggerDelay then trigStatus = "aiming" return end
		if now - lastTrigger < cd * 1.06 then trigStatus = "cooldown" return end
		bindRemote()
		if tool:GetAttribute("Damage") ~= nil and fireRemote then
			-- встроенное оружие (Damage + ремоут): выстрел через сервер
			local ok, w = fireTool(tool, aimPart)
			if ok then lastTrigger = now trigStatus = "FIRE (" .. how .. ")" else trigStatus = w or "blocked" end
		else
			-- у оружия нет Damage или нет ремоута: нажимаем родное действие инструмента
			lastTrigger = now
			local okA = pcall(tool.Activate, tool)
			trigStatus = okA and ("FIRE Activate (" .. how .. ")") or "Activate failed"
		end
	end

	-- ===== Silent Aim: направление выстрела меняется только в момент выстрела, камера не двигается =====
	-- SilentFOV в пикселях, а сервер режет отклонение по углу: переводим угол сервера в px
	local function silentRadius()
		local fr = fireRemote or ReplicatedStorage:FindFirstChild(REMOTE_NAME)
		local maxDeg = fr and fr:GetAttribute("SilentMaxAngle")
		if type(maxDeg) ~= "number" then maxDeg = 25 end
		local fovRad = math.rad(math.clamp(camera.FieldOfView, 1, 120))
		local focal = (SP.vp.Y / 2) / math.tan(fovRad / 2)
		local capPx = math.tan(math.rad(math.max(maxDeg - 2, 1))) * focal -- 2° запас
		return math.min(SP.silent, capPx)
	end
	silentTarget = function(rOverride)
		local rad = rOverride or silentRadius()
		local lp = A.TargetLock and lockedPart()
		if lp then
			local lm = humModel(lp)
			if lm and evaluate(lm, lp, rad) then return lp end
		end
		local best, bestD = nil, rad
		local function try(model)
			local part = getTargetPart(model)
			if not part then return end
			local d = evaluate(model, part, rad, true)
			if d and d < bestD then best, bestD = part, d end
		end
		eachTarget(try)
		return best
	end

	-- встроенное оружие: Tool с атрибутом Damage
	local hooked = setmetatable({}, {__mode = "k"})
	local lastSent, shotsSent = 0, 0
	local function shoot(tool, forcePart)
		bindRemote()
		if not fireRemote then return false, "no remote" end
		local ch = LP.Character
		local head = ch and ch:FindFirstChild("Head")
		if not head then return false, "no head" end
		-- единый кулдаун на клиенте: Activated и triggerbot не стреляют дважды, сервер не режет почти-одновременные выстрелы
		local cd = tool:GetAttribute("Cooldown")
		cd = type(cd) == "number" and cd or 0.15
		local t = os.clock()
		if t - lastSent < cd * 1.05 then return false, "cooldown" end
		local origin = head.Position
		-- куда реально смотрит прицел (SP.aim), а не mouse.Hit; свой персонаж исключён через rayParams
		local ray = camera:ViewportPointToRay(SP.aim.X, SP.aim.Y)
		local hit = Workspace:Raycast(ray.Origin, ray.Direction.Unit * 1000, rayParams)
		local point = hit and hit.Position or (ray.Origin + ray.Direction.Unit * 1000)
		local dir = point - origin
		if dir.Magnitude < 0.01 then return false, "bad dir" end
		local aimDir = dir.Unit
		local shotDir = aimDir
		-- цель, в которую летит пуля: переданная (triggerbot), Silent Aim, либо — при включённой наводке —
		-- текущая цель, если упреждённая точка уже у прицела (камера отстаёт из-за Smoothness, пуля — нет)
		local part = forcePart
		if not part and A.SilentAim then part = silentTarget() end
		if not part and A.Enabled and currentTarget and currentTarget.Parent then
			local sp, vis = camera:WorldToViewportPoint(getAimPoint(currentTarget))
			if vis and (V2(sp.X, sp.Y) - SP.aim).Magnitude <= math.min(SP.vp.X, SP.vp.Y) * A.TriggerR * 0.01 then
				part = currentTarget
			end
		end
		if part then
			local toTarget = getAimPoint(part) - origin
			if toTarget.Magnitude > 0.01 then shotDir = toTarget.Unit end
		end
		lastSent = t
		shotsSent += 1
		local hbB, hbH = hbPads()
		fireRemote:FireServer(tool, origin, shotDir, aimDir, hbB, hbH)
		return true
	end
	fireTool = shoot
	local function hookTool(inst)
		if hooked[inst] or not inst:IsA("Tool") then return end
		hooked[inst] = true
		connect(inst.Activated, function()
			if inst:GetAttribute("Damage") ~= nil then shoot(inst) end
		end)
	end
	local function watch(container)
		for _, child in container:GetChildren() do hookTool(child) end
		connect(container.ChildAdded, hookTool)
	end
	local backpack = LP:FindFirstChildOfClass("Backpack")
	if backpack then watch(backpack) end
	if LP.Character then watch(LP.Character) end
	connect(LP.CharacterAdded, watch)
	connect(LP.ChildAdded, function(child) if child:IsA("Backpack") then watch(child) end end)

	-- ===== Triggerbot: отдельный цикл (не зависит от остального кадра; любая ошибка выводится в статус HUD) =====
	connect(RS.Heartbeat, function()
		if not A.Trigger then
			if trigStatus ~= "off" then trigStatus, seenSince, seenModel = "off", nil, nil end
			return
		end
		if editing then trigStatus = "editing" return end
		camera = Workspace.CurrentCamera
		if not camera or not updateSpace() then trigStatus = "screen not ready" return end
		local okT, eT = pcall(triggerStep, os.clock())
		if not okT then trigStatus = "error: " .. tostring(eT):sub(1, 70) end
	end)

	-- ===== Основной цикл =====
	pcall(function() RS:UnbindFromRenderStep("EnkaisyAimAssist") end)
	RS:BindToRenderStep("EnkaisyAimAssist", Enum.RenderPriority.Camera.Value + 1, function(dt)
		camera = Workspace.CurrentCamera
		if not camera then return end

		local now = os.clock()
		if now - lastPingT > 0.5 then
			lastPingT = now
			-- авто-предикт: пинг (туда-обратно) + небольшой запас на интерполяцию чужих персонажей
			local want = math.clamp(getPing() / 1000 + A.LeadBias * 0.001, 0.02, 0.6)
			autoLead += (want - autoLead) * 0.5
		end

		if not updateSpace() then -- экран ещё не готов (0×0 при старте/повороте)
			fov.Visible, aimMark.Visible, currentTarget = false, false, nil
			return
		end
		local okD, eD = pcall(NX.dynStep, now, dt) -- Dynamic FOV: радиус считается до выбора цели и отрисовки круга
		if not okD and not NX.warnD then NX.warnD = true warn("[Enkaisy] dynamic FOV error: " .. tostring(eD)) end
		drawOverlay(now)
		if editing then
			paintEdit()
			xyLabel.Text = string.format("экран %.0f×%.0f | aim: %.0f, %.0f | круг: %.0f, %.0f (%s)",
				SP.vp.X, SP.vp.Y, SP.aim.X, SP.aim.Y, SP.circle.X, SP.circle.Y, A.CircleFollow and "связан" or "отвязан")
			-- панель не уходит за экран
			local ap, asz, vs, bp = editBar.AbsolutePosition, editBar.AbsoluteSize, og.AbsoluteSize, editBar.Position
			local ox = ap.X < 0 and -ap.X or (ap.X + asz.X > vs.X and vs.X - ap.X - asz.X or 0)
			local oy = ap.Y < 0 and -ap.Y or (ap.Y + asz.Y > vs.Y and vs.Y - ap.Y - asz.Y or 0)
			if ox ~= 0 or oy ~= 0 then
				editBar.Position = U(bp.X.Scale, bp.X.Offset + ox, bp.Y.Scale, bp.Y.Offset + oy)
			end
		end

		local t0 = os.clock()
		-- v4.2: прошлая цель остаётся в currentTarget на время pickTarget — иначе Sticky/гистерезис никогда не работал
		-- (цель обнулялась прямо перед выбором, и прицел дёргался между двумя близкими целями)
		if not editing and isActive() then
			local okP, pt = pcall(pickTarget)
			if okP then
				currentTarget = pt
			else
				currentTarget = nil
				if not pickWarned then pickWarned = true warn("[Enkaisy] pickTarget error: " .. tostring(pt)) end
			end
		else
			currentTarget = nil
		end
		pickMs += ((os.clock() - t0) * 1000 - pickMs) * 0.1
		local aimPt = currentTarget and getAimPoint(currentTarget) -- упреждённая точка (камера, HUD)
		-- v4.2: сглаживаем только СМЕЩЕНИЕ (упреждение / multipoint) относительно реальной позиции части тела:
		-- шум трекера скорости больше не трясёт прицел, а сама позиция цели не запаздывает
		if aimPt then
			local f = NX.af
			if not f then f = {} NX.af = f end
			local off = aimPt - currentTarget.Position
			if f.part ~= currentTarget or now - (f.t or 0) > 0.25 then
				f.part, f.off = currentTarget, off
			else
				f.off = f.off:Lerp(off, 1 - math.exp(-math.clamp(dt, 0, 0.1) / 0.04))
			end
			f.t = now
			aimPt = currentTarget.Position + f.off
		elseif NX.af then
			NX.af.part = nil
		end
		NX.refDist = currentTarget and (currentTarget.Position - camera.CFrame.Position).Magnitude or nil
		do -- Target Animation: индикатор в точке, куда целится наводка
			local mdl, sx, sy
			if currentTarget and aimPt then
				mdl = humModel(currentTarget)
				local sp, vis = camera:WorldToViewportPoint(aimPt)
				if vis then sx, sy = sp.X, sp.Y else mdl = nil end
			end
			local okA, eA = pcall(NX.animStep, now, dt, mdl, sx, sy)
			if not okA and not NX.warnA then NX.warnA = true warn("[Enkaisy] target animation error: " .. tostring(eA)) end
		end
		local circleCol = (A.FovTarget and currentTarget) and C.On or hsv(A.FovCol)
		if A.TargetAnim then -- плавная смена цвета круга
			local kc = 1 - math.exp(-math.clamp(dt, 0, 0.1) * 10 * math.clamp(A.AnimSpeed, 0.25, 3))
			NX.cc = (NX.cc or circleCol):Lerp(circleCol, kc)
			circleCol = NX.cc
		else
			NX.cc = circleCol
		end
		setp(fovStroke, "Thickness", A.CircleThick)
		setp(fovStroke, "Transparency", A.FovAlpha)
		setp(fovStroke, "Color", circleCol)
		setp(fov, "BackgroundColor3", circleCol)
		setp(fov, "BackgroundTransparency", A.FovFill and A.FovFillAlpha or 1)

		hud.Visible = A.DebugHUD and (A.Enabled or A.Trigger) and not editing
		if hud.Visible then
			local name, dist = "none", 0
			if currentTarget then
				local model = humModel(currentTarget)
				name = model and model.Name or currentTarget.Name
				dist = (currentTarget.Position - camera.CFrame.Position).Magnitude
			end
			local off = aimPt and (aimPt - currentTarget.Position).Magnitude or 0
			hud.Text = string.format("target: %s | %dm | lead %dms%s%s%s | off %.1fst | pick %.2fms | shots %d", name, math.floor(dist + 0.5),
				math.floor(getLead() * 1000 + 0.5), A.AutoPredict and " auto" or "", A.AdvPredict and " adv" or "",
				(lockedModel and " | LOCK" or "") .. (A.Trigger and (" | trig: " .. trigStatus) or "")
				.. (os.clock() - srvT < 4 and (" | srv: " .. srvCode) or ""), off, pickMs, shotsSent)
			if A.DynFov then hud.Text ..= string.format(" | fov %.1f%%", NX.dynR) end
		end

		if A.SilentAim and not A.Trigger and not editing and now - lastWarm > 0.05 then
			lastWarm = now
			local st = silentTarget()
			if st then trackPart(st) end
		end
		local okH, eH = pcall(updateHbVis, now, dt) -- Hitbox ESP: плавная отрисовка боксов
		if not okH and not NX.warnH then NX.warnH = true warn("[Enkaisy] hitbox visual error: " .. tostring(eH)) end
		if not currentTarget then return end

		-- поворачиваем камеру так, чтобы цель оказалась ровно в точке наведения SP.aim (а не просто в центре экрана)
		local ray = camera:ViewportPointToRay(SP.aim.X, SP.aim.Y)
		local toTarget = aimPt - ray.Origin
		if toTarget.Magnitude < 0.01 then return end
		local dirNow, dirWant = ray.Direction.Unit, toTarget.Unit
		local angle = math.acos(math.clamp(dirNow:Dot(dirWant), -1, 1))
		local axis = dirNow:Cross(dirWant)
		if angle < 1e-4 or axis.Magnitude < 1e-6 then return end
		local smooth = math.clamp(A.Smoothness, 0.01, 1)
		local alpha = 1 - (1 - smooth) ^ (math.clamp(dt, 0, 0.1) * 60)
		local step = angle * alpha
		-- v4.2: при Smoothness < 1 ограничиваем скорость поворота (нет резкого рывка на далёкую цель) и гасим микро-дрожь у цели
		if smooth < 1 then
			if angle < math.rad(0.08) then return end
			step = math.min(step, math.rad(900) * math.clamp(dt, 0, 0.1))
		end
		local cf = camera.CFrame
		camera.CFrame = CFrame.new(cf.Position) * CFrame.fromAxisAngle(axis.Unit, step) * (cf - cf.Position)
	end)

	return {
		overlay = og,
		preview = function(on) previewFov = on and true or false end,
		refresh = function()
			currentTarget = nil
			V4.normalizeParts(A)
			NX.gen += 1
			NX.dynR, NX.dynBack, NX.wasDyn, NX.cc = A.FovR, false, false, nil
			NX.animReset()
			refreshAll(false)
		end,
		destroy = function()
			pcall(function() RS:UnbindFromRenderStep("EnkaisyAimAssist") end)
			for _, c in aconns do c:Disconnect() end
			table.clear(aconns)
			clearHbVis()
			og:Destroy()
			probeGui:Destroy()
			quick:Destroy()
		end,
	}
end

-- ===== Загрузка фона-картинки (общая для окна меню и окна ключа) =====
-- ID / rbxassetid:// / ссылка roblox.com работают везде. Прямая ссылка (png/jpg) скачивается через request/HttpGet,
-- сохраняется writefile и показывается через getcustomasset — это есть только в окружениях, где эти функции доступны.
local CP = game:GetService("ContentProvider")
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
	if not (canFile and getAsset) then
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

-- ===== Главное меню =====
local stop
local function startMain()
	local PW, PH = 480, 392
	local HDR, FTR = 46, 40
	local SBW, TABH, TGAP = 130, 38, 4
	local CX, CY = SBW + 12, HDR + 46
	-- размер области страниц считается от окна: растягивается вместе с ним
	local PAGE_SIZE = U(1, -(CX + 10), 1, -(CY + FTR + 6))
	local TABS = {"Main", "Color", "Sizes", "Extra", "Players", "Aim", "FOV", "Appearance", "Visual"}
	-- группы бокового меню: заголовок + вкладки (визуальное разделение категорий)
	local GROUPS = {
		{"ESP", {"Main", "Color", "Sizes", "Extra", "Players"}},
		{"AIM", {"Aim", "FOV"}},
		{"SETTINGS", {"Appearance", "Visual"}},
	}
	local DISP = {Main = "General", Visual = "Performance"}
	local SUB = {
		Main = "ESP targets and quick toggles", Color = "Palette for every element",
		Sizes = "Opacity, labels and limits", Extra = "Friends, NPC filter, reset",
		Visual = "Update rate, effects, low-end preset", Players = "Tap: mark / hide  •  › per-player look",
		Aim = "Aim assist, auto center, predict", FOV = "Circle look, size and position",
		Appearance = "Window, transparency, theme, accent",
	}
	local SCROLLED = {Main = true, Color = true, Sizes = true, Extra = true, Visual = true, Appearance = true, FOV = true}
	local repaints = {}
	local closeDetail
	local applyUIAll
	local bgFrames = {}
	local curTab = "Main"

	-- кнопка-логотип (когда меню свёрнуто)
	local openBtn = new("TextButton", {
		Size = O(44, 44), AnchorPoint = V2(1, 0),
		Position = U(1, -16, 0, 80), BackgroundTransparency = 1, Text = "", Visible = false,
	}, gui)
	floatScales[new("UIScale", {Scale = UICFG.UIScale}, openBtn)] = true
	local _, openStroke = logo(44, 24, openBtn)
	hoverable(openBtn, openStroke, {base = 0.35, hover = 0.1, down = 0})

	-- окно (CanvasGroup: Menu Transparency = GroupTransparency, плавное появление)
	local panel = new("CanvasGroup", {
		Size = O(UICFG.PanelW, UICFG.PanelH), AnchorPoint = V2(0.5, 0.5), GroupTransparency = 1,
		Position = U(0.5, 0, 0.5, 0), BackgroundColor3 = C.Win, Visible = false, Active = true,
	}, gui)
	rr(panel, 12)
	local panelStroke = outline(panel, 0.78)
	table.insert(bgFrames, panel)
	local scale = new("UIScale", {}, panel)
	-- фон-картинка: лежит под всем содержимым (ZIndex 0), обрезается скруглением окна
	local FIT_TYPES = {Crop = Enum.ScaleType.Crop, Fit = Enum.ScaleType.Fit, Stretch = Enum.ScaleType.Stretch}
	local bgImg = new("ImageLabel", {
		Name = "BgImage", Size = S(1, 1), BackgroundTransparency = 1, Image = "", Visible = false, Active = false, ZIndex = 0,
		ScaleType = FIT_TYPES[UICFG.BgImgFit] or Enum.ScaleType.Crop, ImageTransparency = UICFG.BgImgAlpha,
	}, panel)

	-- шапка: логотип, название, индикаторы включённых функций, закрыть
	local titleBar = new("Frame", {Size = U(1, 0, 0, HDR), BackgroundColor3 = C.Side}, panel)
	rr(titleBar, 12, 12)
	local titleFill = new("Frame", {Size = U(1, 0, 0, 12), Position = U(0, 0, 1, -12), BackgroundColor3 = C.Side, BorderSizePixel = 0, Active = false}, titleBar)
	table.insert(bgFrames, titleBar)
	table.insert(bgFrames, titleFill)
	new("Frame", {Size = U(1, 0, 0, 1), Position = U(0, 0, 1, -1), BackgroundColor3 = C.Line, BorderSizePixel = 0, Active = false, ZIndex = 2}, titleBar)
	local badge = logo(30, 16, titleBar)
	badge.Position = O(12, 8)
	new("TextLabel", {
		Size = O(110, 20), Position = O(52, 6), BackgroundTransparency = 1,
		Text = "Enkaisy", TextColor3 = C.W, Font = GB, TextSize = 15, TextXAlignment = XL,
	}, titleBar)
	new("TextLabel", {
		Size = O(110, 12), Position = O(52, 26), BackgroundTransparency = 1,
		Text = "esp + aim", TextColor3 = C.Mut, Font = GM, TextSize = 10, TextXAlignment = XL,
	}, titleBar)
	local function headChip(text, rightOffset, withDot)
		local c = new("TextLabel", {
			AnchorPoint = V2(1, 0.5), Position = U(1, rightOffset, 0.5, 0), Size = O(0, 24), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.Card, Text = text, TextColor3 = C.Mut, Font = GM, TextSize = 10, Active = false,
		}, titleBar)
		new("UIPadding", {PaddingLeft = UDim.new(0, withDot and 20 or 9), PaddingRight = UDim.new(0, 9)}, c)
		round(c, 12)
		outline(c, OUT.Soft)
		local dot
		if withDot then
			dot = new("Frame", {Size = O(6, 6), AnchorPoint = V2(0, 0.5), Position = U(0, 9, 0.5, 0), BackgroundColor3 = C.Mut, Active = false}, c)
			round(dot, 3)
		end
		return c, dot
	end
	headChip("v3.4", -56)
	local _, aimDot = headChip("AIM", -110, true)
	local _, espDot = headChip("ESP", -168, true)
	local close = new("TextButton", {
		Size = O(36, 36), AnchorPoint = V2(1, 0.5), Position = U(1, -8, 0.5, 0),
		BackgroundColor3 = C.Input, Text = "", AutoButtonColor = false,
	}, titleBar)
	rr(close, 10)
	hoverable(close, outline(close))
	xMark(close, C.W)

	-- размер окна: Menu Scale, но никогда не больше экрана
	local function fit()
		local a = gui.AbsoluteSize
		local maxK = math.max(0.4, math.min((a.Y - 16) / PH, (a.X - 16) / PW))
		return math.clamp(UICFG.MenuScale * math.min(1, maxK), 0.4, maxK)
	end
	-- ===== Размер и положение окна: растягивание за правый нижний угол =====
	-- Размер хранится в UICFG.PanelW/H (логические px до UIScale), центр — в долях экрана PanelCX/CY.
	-- winW/winH — фактический размер с учётом экрана (при повороте/малом экране окно сжимается, но выбранный размер не теряется).
	local winW, winH = UICFG.PanelW, UICFG.PanelH
	local function sizeLimits()
		local a, k = gui.AbsoluteSize, fit()
		local hiW = math.min(WIN_MAX_W, math.floor((a.X - 16) / k))
		local hiH = math.min(WIN_MAX_H, math.floor((a.Y - 16) / k))
		return math.min(WIN_MIN_W, hiW), math.min(WIN_MIN_H, hiH), hiW, hiH
	end
	local function readCenter()
		local gs, p = gui.AbsoluteSize, panel.Position
		return p.X.Scale + p.X.Offset / gs.X, p.Y.Scale + p.Y.Offset / gs.Y
	end
	local function writeCenter(fx, fy) panel.Position = U(fx, 0, fy, 0) end
	local function saveCenter()
		if gui.AbsoluteSize.X < 50 then return end
		UICFG.PanelCX, UICFG.PanelCY = readCenter()
	end
	-- положение: сохранённое или «справа по центру»; окно всегда целиком на экране
	local function clampPanel()
		local gs = gui.AbsoluteSize
		if gs.X < 50 or gs.Y < 50 then return end
		local k = fit()
		local w, h = winW * k, winH * k
		local fx, fy
		if UICFG.PanelCX < 0 then
			fx, fy = 1 - (16 + w / 2) / gs.X, 0.5
		else
			fx, fy = readCenter()
		end
		local cx, cy = fx * gs.X, fy * gs.Y
		local mx, my = 6 + w / 2, 6 + h / 2
		cx = gs.X - 12 < w and gs.X / 2 or math.clamp(cx, mx, gs.X - mx)
		cy = gs.Y - 12 < h and gs.Y / 2 or math.clamp(cy, my, gs.Y - my)
		writeCenter(cx / gs.X, cy / gs.Y)
	end
	local function commitPanel() saveCenter(); clampPanel(); saveCenter() end
	local function updateCols()
		local cw = winW - (CX + 20)
		applyGridCols(cw >= 450 and 3 or cw >= 290 and 2 or 1)
	end
	local function applySize()
		if gui.AbsoluteSize.X < 50 or gui.AbsoluteSize.Y < 50 then return end
		local loW, loH, hiW, hiH = sizeLimits()
		winW = math.clamp(math.floor(UICFG.PanelW + 0.5), loW, hiW)
		winH = math.clamp(math.floor(UICFG.PanelH + 0.5), loH, hiH)
		panel.Size = O(winW, winH)
		updateCols()
		clampPanel()
	end

	-- ручка в правом нижнем углу (зона касания 36x36, рисунок — треугольник из точек) и плашка с размером
	local grip = new("TextButton", {
		Name = "ResizeGrip", Size = O(36, 36), AnchorPoint = V2(1, 1), Position = U(1, 0, 1, 0),
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 30,
	}, panel)
	local gripDots = {}
	for _, d in {{26, 26}, {20, 26}, {14, 26}, {26, 20}, {20, 20}, {26, 14}} do
		local f = new("Frame", {
			Size = O(3, 3), Position = O(d[1], d[2]), BackgroundColor3 = C.Mut, BackgroundTransparency = 0.25,
			BorderSizePixel = 0, Active = false,
		}, grip)
		round(f, 2)
		table.insert(gripDots, f)
	end
	local function paintGrip(hot)
		for _, f in gripDots do
			put(f, {BackgroundColor3 = hot and C.Acc or C.Mut, BackgroundTransparency = hot and 0 or 0.25}, true)
		end
	end
	local sizeChip = new("TextLabel", {
		AnchorPoint = V2(0.5, 1), Position = U(0.5, 0, 1, -48), Size = O(0, 24), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Card, Text = "", TextColor3 = C.W, Font = GB, TextSize = 11, Visible = false, Active = false, ZIndex = 29,
	}, panel)
	new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, sizeChip)
	rr(sizeChip, 12)
	outline(sizeChip, OUT.Soft)

	local rs, lastGripTap = {}, 0
	local function rsMove(i)
		if not rs.act or not move(i) or not (i == rs.act or i.UserInputType == UT.MouseMovement) then return end
		local k, gs = fit(), gui.AbsoluteSize
		local d = V2(i.Position.X, i.Position.Y) - rs.s0
		if not rs.moved then
			if d.Magnitude < 5 then return end
			rs.moved = true
			sizeChip.Visible = true
		end
		local loW, loH, hiW, hiH = sizeLimits()
		local w = math.clamp(math.floor(rs.w0 + d.X / k + 0.5), loW, hiW)
		local h = math.clamp(math.floor(rs.h0 + d.Y / k + 0.5), loH, hiH)
		-- «магнит»: рядом с размером по умолчанию окно прилипает к нему
		if math.abs(w - PW) <= 8 and PW >= loW and PW <= hiW then w = PW end
		if math.abs(h - PH) <= 8 and PH >= loH and PH <= hiH then h = PH end
		winW, winH = w, h
		UICFG.PanelW, UICFG.PanelH = w, h
		panel.Size = O(w, h)
		-- левый верхний угол стоит на месте: центр смещается на половину прироста экранного размера
		local fx = (rs.c0.X + (w - rs.w0) * k / 2) / gs.X
		local fy = (rs.c0.Y + (h - rs.h0) * k / 2) / gs.Y
		writeCenter(fx, fy)
		UICFG.PanelCX, UICFG.PanelCY = fx, fy
		sizeChip.Text = w .. " × " .. h
		updateCols()
	end
	local function rsEnd(i)
		if not rs.act or not (i == rs.act or i.UserInputType == UT.MouseButton1) then return end
		local moved = rs.moved
		rs.act = nil
		dragMoves[rsMove], dragEnds[rsEnd] = nil, nil
		paintGrip(false)
		sizeChip.Visible = false
		tween(panelStroke, fast, {Transparency = 0.78})
		if moved then
			commitPanel()
		else
			-- двойное касание по углу = размер и положение по умолчанию
			local now = os.clock()
			if now - lastGripTap < 0.4 then
				lastGripTap = 0
				UICFG.PanelW, UICFG.PanelH, UICFG.PanelCX, UICFG.PanelCY = PW, PH, -1, -1
				applySize()
			else
				lastGripTap = now
			end
		end
	end
	on(grip.InputBegan, function(i)
		if rs.act or not press(i) then return end
		local gs = gui.AbsoluteSize
		if gs.X < 50 then return end
		local fx, fy = readCenter()
		rs.act, rs.moved, rs.s0 = i, false, V2(i.Position.X, i.Position.Y)
		rs.w0, rs.h0, rs.c0 = winW, winH, V2(fx * gs.X, fy * gs.Y)
		dragMoves[rsMove], dragEnds[rsEnd] = true, true
		paintGrip(true)
		sizeChip.Text = winW .. " × " .. winH
		tween(panelStroke, fast, {Transparency = 0.45})
	end)
	on(grip.MouseEnter, function() if not rs.act then paintGrip(true) end end)
	on(grip.MouseLeave, function() if not rs.act then paintGrip(false) end end)

	local isOpen = false
	local function setOpen(s)
		isOpen = s
		local k = fit()
		if s then applySize() end
		if aim then aim.preview(s and curTab == "FOV") end
		if s then
			openBtn.Visible, panel.Visible = false, true
			if CFG.Anim then
				scale.Scale, panel.GroupTransparency = k * 0.92, 1
				tween(scale, slow, {Scale = k})
				tween(panel, slow, {GroupTransparency = UICFG.MenuAlpha})
			else
				scale.Scale, panel.GroupTransparency = k, UICFG.MenuAlpha
			end
		else
			if CFG.Anim then
				tween(scale, fast, {Scale = k * 0.92})
				tween(panel, fast, {GroupTransparency = 1})
				task.delay(0.17, function()
					if not isOpen and panel.Parent then panel.Visible, openBtn.Visible = false, true end
				end)
			else
				panel.Visible, openBtn.Visible = false, true
			end
		end
	end
	on(gui:GetPropertyChangedSignal("AbsoluteSize"), function()
		if panel.Visible and isOpen then scale.Scale = fit() end
		applySize()
		clampGui(openBtn)
	end)

	-- боковое меню (прокручивается): заголовки групп, иконка + название, точка «функция включена»
	local side = new("Frame", {Size = U(0, SBW, 1, -(HDR + FTR)), Position = O(0, HDR), BackgroundColor3 = C.Side, BorderSizePixel = 0}, panel)
	table.insert(bgFrames, side)
	new("Frame", {Size = U(0, 1, 1, 0), Position = U(1, -1, 0, 0), BackgroundColor3 = C.Line, BorderSizePixel = 0, Active = false}, side)
	local tabsHolder = new("ScrollingFrame", {
		Size = U(0, SBW - 9, 1, -44), Position = O(4, 40), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 2, ScrollBarImageColor3 = C.Mut, ScrollBarImageTransparency = 0.4,
		CanvasSize = U(0, 0, 0, 0), ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.Never,
	}, side)
	local search = new("TextBox", {
        Size = U(1, -12, 0, 30), Position = O(6, 5), BackgroundColor3 = C.Input,
        Text = "", PlaceholderText = "Search / Поиск", TextColor3 = C.W, PlaceholderColor3 = C.Mut,
        Font = GM, TextSize = 11, ClearTextOnFocus = false,
    }, side)
    rr(search, 8)
    outline(search, OUT.Soft)
    local tabPos, ty, groupLabels = {}, 0, {}
	for _, g in GROUPS do
		groupLabels[g[1]] = new("TextLabel", {
			Size = O(SBW - 24, 16), Position = O(8, ty + 2), BackgroundTransparency = 1, Text = g[1],
			TextColor3 = C.Mut, Font = GB, TextSize = 10, TextXAlignment = XL, Active = false,
		}, tabsHolder)
		ty += 20
		for _, n in g[2] do
			tabPos[n] = ty
			ty += TABH + TGAP
		end
		ty += 6
	end
	tabsHolder.CanvasSize = O(0, ty)
	-- выбранная вкладка: светлее фон + акцентная обводка; плавно переезжает между кнопками
	local pill = new("Frame", {
		Size = U(1, -6, 0, TABH), Position = O(2, tabPos.Main), BackgroundColor3 = C.Sel, Active = false, ZIndex = 1,
	}, tabsHolder)
	rr(pill, 8)
	accent(outline(pill, OUT.Active), "Color")

	-- заголовок страницы
	local pTitle = new("TextLabel", {
		Size = U(1, -(CX + 10), 0, 18), Position = O(CX, HDR + 9), BackgroundTransparency = 1, Text = "",
		TextColor3 = C.W, Font = GB, TextSize = 16, TextXAlignment = XL,
	}, panel)
	local pSub = new("TextLabel", {
		Size = U(1, -(CX + 10), 0, 14), Position = O(CX, HDR + 28), BackgroundTransparency = 1, Text = "",
		TextColor3 = C.Mut, Font = GM, TextSize = 10, TextXAlignment = XL,
	}, panel)

	-- вкладки и страницы
	local pages, ptabs = {}, {}
	local function show(n)
		if not tabPos[n] then n = "Main" end
		curTab, UICFG.Tab = n, n
		pill.Visible = true
		tween(pill, fast, {Position = O(2, tabPos[n])})
		pTitle.Text, pSub.Text = DISP[n] or n, SUB[n] or ""
		if aim then aim.preview(isOpen and n == "FOV") end
		-- вкладка всегда в зоне видимости бокового списка
		local top, bot = tabPos[n], tabPos[n] + TABH
		local cp, vh = tabsHolder.CanvasPosition.Y, tabsHolder.AbsoluteSize.Y
		if top - 22 < cp then
			tabsHolder.CanvasPosition = Vector2.new(0, math.max(0, top - 22))
		elseif bot + 6 > cp + vh then
			tabsHolder.CanvasPosition = Vector2.new(0, bot + 6 - vh)
		end
		for k, f in pages do
			local sel = k == n
			if sel and not f.Visible and CFG.Anim then
				f.Position = O(CX + 16, CY)
				f.Visible = true
				tween(f, slow, {Position = O(CX, CY)})
			else
				f.Visible = sel
				if sel then f.Position = O(CX, CY) end
			end
			local t = ptabs[k]
			if t.sel ~= sel then
				t.sel = sel
				t.h.locked = sel
				t.h.over, t.h.pressed = false, false
				tween(t.st, fast, {Transparency = sel and 1 or OUT.Idle})
				tween(t.label, fast, {TextColor3 = sel and C.W or C.Mut})
				t.paintIcon(sel and C.W or C.Mut, true)
			end
		end
	end
	for _, n in TABS do
		local tb = new("TextButton", {
			Size = U(1, -6, 0, TABH), Position = O(2, tabPos[n]), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 2,
		}, tabsHolder)
		rr(tb, 8)
		local st = outline(tb)
		local ic, icPaint = icon(n, tb)
		ic.Position = O(11, TABH / 2)
		local lbl = new("TextLabel", {
			Size = U(1, -54, 1, 0), Position = O(36, 0), BackgroundTransparency = 1, Text = DISP[n] or n, TextColor3 = C.Mut,
			Font = GB, TextSize = 12, TextXAlignment = XL, Active = false,
		}, tb)
		local dot = new("Frame", {
			Size = O(6, 6), AnchorPoint = V2(1, 0.5), Position = U(1, -9, 0.5, 0), BackgroundColor3 = C.On,
			BackgroundTransparency = 1, Active = false,
		}, tb)
		round(dot, 3)
		ptabs[n] = {button = tb, st = st, label = lbl, dot = dot, paintIcon = icPaint, h = hoverable(tb, st)}
		local pg
		if SCROLLED[n] then
			pg = new("ScrollingFrame", {
				Size = PAGE_SIZE, Position = O(CX, CY), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
				ScrollBarThickness = 3, ScrollBarImageColor3 = C.Mut, ScrollBarImageTransparency = 0.3,
				CanvasSize = U(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			}, panel)
			-- отступы, чтобы тонкие обводки карточек не обрезались краем прокрутки
			new("UIPadding", {
				PaddingLeft = UDim.new(0, 2), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), PaddingRight = UDim.new(0, 8),
			}, pg)
		else
			pg = new("Frame", {Size = PAGE_SIZE, Position = O(CX, CY), BackgroundTransparency = 1, Visible = false}, panel)
		end
		new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, pg)
		pages[n] = pg
		on(tb.Activated, function() show(n) end)
	end

	-- индикаторы «включено»: шапка (ESP / AIM) и точки на вкладках; обновляются из frame() раз в 0.1 с, только при изменении
	local stCache = {}
	local function flag(key, v, apply)
		v = v and true or false
		if stCache[key] == v then return end
		stCache[key] = v
		apply(v)
	end
	statusFn = function()
		flag("hESP", CFG.On, function(o) espDot.BackgroundColor3 = o and C.On or C.Mut end)
		flag("hAIM", AIMCFG.Enabled, function(o) aimDot.BackgroundColor3 = o and C.On or C.Mut end)
		flag("tMain", CFG.On, function(o) ptabs.Main.dot.BackgroundTransparency = o and 0 or 1 end)
		flag("tAim", AIMCFG.Enabled, function(o) ptabs.Aim.dot.BackgroundTransparency = o and 0 or 1 end)
		flag("tFOV", AIMCFG.Enabled and AIMCFG.ShowFOV, function(o) ptabs.FOV.dot.BackgroundTransparency = o and 0 or 1 end)
	end

	-- подвал: счётчик, FPS / пинг, выгрузка
	local footer = new("Frame", {Size = U(1, 0, 0, FTR), AnchorPoint = V2(0, 1), Position = U(0, 0, 1, 0), BackgroundColor3 = C.Side}, panel)
	rr(footer, 12, 12)
	local footerFill = new("Frame", {Size = U(1, 0, 0, 12), BackgroundColor3 = C.Side, BorderSizePixel = 0, Active = false}, footer)
	table.insert(bgFrames, footer)
	table.insert(bgFrames, footerFill)
	new("Frame", {Size = U(1, 0, 0, 1), BackgroundColor3 = C.Line, BorderSizePixel = 0, Active = false, ZIndex = 2}, footer)
	counterLbl = new("TextLabel", {
		Size = O(136, 26), AnchorPoint = V2(0, 0.5), Position = U(0, 10, 0.5, 1),
		BackgroundColor3 = C.Card, Text = "Players: 0 • NPC: 0",
		TextColor3 = C.Mut, Font = GM, TextSize = 11,
	}, footer)
	rr(counterLbl, 8)
	outline(counterLbl, OUT.Soft)
	statsCard = new("Frame", {
		Size = O(118, 26), AnchorPoint = V2(0, 0.5), Position = U(0, 154, 0.5, 1),
		BackgroundColor3 = C.Card, Visible = CFG.ShowStats,
	}, footer)
	rr(statsCard, 8)
	outline(statsCard, OUT.Soft)
	statsFps = new("TextLabel", {
		Size = U(0.5, 0, 1, 0), BackgroundTransparency = 1, Text = "-- FPS",
		TextColor3 = C.Mut, Font = GB, TextSize = 11,
	}, statsCard)
	statsPing = new("TextLabel", {
		Size = U(0.5, 0, 1, 0), Position = U(0.5, 0, 0, 0), BackgroundTransparency = 1, Text = "-- ms",
		TextColor3 = C.Mut, Font = GM, TextSize = 11,
	}, statsCard)

	-- кнопка выгрузки скрипта (с подтверждением вторым нажатием)
	local unload = button(footer, "Unload", {
		Size = O(76, 30), AnchorPoint = V2(1, 0.5), Position = U(1, -42, 0.5, 1), TextSize = 11,
	}, {danger = true})
	local armed = false
	on(unload.Activated, function()
		if armed then
			stop()
			return
		end
		armed = true
		unload.Text = "Точно?"
		tween(unload, fast, {BackgroundColor3 = C.DangerBg, TextColor3 = C.W})
		task.delay(2.5, function()
			if armed and unload.Parent then
				armed = false
				unload.Text = "Unload"
				tween(unload, fast, {BackgroundColor3 = C.Input, TextColor3 = C.Danger})
			end
		end)
	end)

	-- ===== Страница Main =====
	local pm = pages.Main
	local toggle = new("TextButton", {
		Size = U(1, 0, 0, 46), BackgroundColor3 = C.Card, Text = "", AutoButtonColor = false, LayoutOrder = 1,
	}, pm)
	rr(toggle, 8)
	hoverable(toggle, outline(toggle), {bg = C.Card, bgHover = C.Sel})
	local tLbl = new("TextLabel", {
		Size = U(1, -72, 0, 18), Position = O(12, 6), BackgroundTransparency = 1,
		Font = GB, TextSize = 13, TextColor3 = C.W, TextXAlignment = XL, Active = false,
	}, toggle)
	new("TextLabel", {
		Size = U(1, -100, 0, 14), Position = O(12, 25), BackgroundTransparency = 1, Text = "Подсветка игроков и NPC",
		TextColor3 = C.Mut, Font = GM, TextSize = 10, TextXAlignment = XL, Active = false,
	}, toggle)
	local tsw, tpaint = makeSwitch(toggle)
	tsw.AnchorPoint, tsw.Position = V2(1, 0.5), U(1, -12, 0.5, 0)
	local function paintToggle(anim)
		tLbl.Text = CFG.On and "Enabled" or "Disabled"
		tpaint(CFG.On, anim)
	end
	table.insert(repaints, function() paintToggle(false) end)

	sectionLabel(pm, "ЦЕЛИ ПОДСВЕТКИ", 2)
	-- сегментированный переключатель: выбранный сегмент светлее и с яркой обводкой
	local segTrack = new("Frame", {Size = U(1, 0, 0, 40), BackgroundColor3 = C.Input, LayoutOrder = 3}, pm)
	rr(segTrack, 8)
	outline(segTrack)
	local segInd = new("Frame", {Size = U(1 / 3, -6, 1, -6), Position = U(0, 3, 0, 3), BackgroundColor3 = C.Sel, Active = false}, segTrack)
	rr(segInd, 6)
	outline(segInd, OUT.Active)
	local segBtns = {}
	local function paintSeg(anim)
		local idx = table.find(MODES, CFG.Mode) or 1
		local pos = U((idx - 1) / 3, 3, 0, 3)
		if anim then tween(segInd, fast, {Position = pos}) else segInd.Position = pos end
		for i, b in segBtns do
			if anim then tween(b, fast, {TextColor3 = i == idx and C.W or C.Mut}) else b.TextColor3 = i == idx and C.W or C.Mut end
		end
	end
	table.insert(repaints, function() paintSeg(false) end)
	for i, m in MODES do
		segBtns[i] = new("TextButton", {
			Size = U(1 / 3, 0, 1, 0), Position = U((i - 1) / 3, 0, 0, 0), BackgroundTransparency = 1,
			Text = m, Font = GB, TextSize = 12, TextColor3 = C.Mut, AutoButtonColor = false, ZIndex = 2,
		}, segTrack)
		on(segBtns[i].Activated, function()
			CFG.Mode = m
			paintSeg(true)
			updAll()
		end)
	end

	-- список переключателей из CFG: {название, ключ, колбэк}
	local function makeChips(parent, list)
		for i, d in list do
			local key, cb = d[2], d[3]
			local _, paint = toggleCard(parent, d[1], i, function() return CFG[key] end, function(v)
				CFG[key] = v
				if cb then cb() end
			end)
			table.insert(repaints, function() paint(false) end)
		end
	end
	sectionLabel(pm, "ОТОБРАЖЕНИЕ", 4)
	makeChips(chipGrid(pm, 5), {
		{"Highlight", "Hl"}, {"Names", "Names"}, {"HP bar", "HP"}, {"HP %", "Pct"},
		{"Team check", "TeamCheck", updAll}, {"Hide dead", "HideDead"},
		{"Rainbow", "Rainbow", refreshHL}, {"Display name", "Disp"},
	})

	-- ===== Страница Extra =====
	local pe = pages.Extra
	makeChips(chipGrid(pe, 1), {{"Distance", "Dist"}, {"HP color", "HPColor", refreshHL}, {"Limit nearest", "Limit"}, {"Hide native", "HideNative"}})

	local _, paintFriend = cycleCard(pe, "Friends", 2, function() return CFG.FriendMode end, function()
		local order = {"Off", "Color", "Hide"}
		CFG.FriendMode = order[(table.find(order, CFG.FriendMode) or 1) % 3 + 1]
		updAll()
	end, function() return CFG.FriendMode ~= "Off" end)
	table.insert(repaints, paintFriend)

	sectionLabel(pe, "ФИЛЬТР NPC ПО ИМЕНИ", 3)
	local frow = row(pe, 40, 6, 4)
	local fmode = button(frow, "", {Size = O(70, 40), LayoutOrder = 1})
	local ftext = new("TextBox", {
		Size = U(1, -76, 1, 0), BackgroundColor3 = C.Input, LayoutOrder = 2,
		Text = CFG.NpcText, PlaceholderText = "имена через запятую", TextColor3 = C.W,
		PlaceholderColor3 = C.Mut, Font = GM, TextSize = 12, ClearTextOnFocus = false,
	}, frow)
	rr(ftext, 8)
	local ftextStroke = outline(ftext)
	on(ftext.Focused, function() tween(ftextStroke, fast, {Transparency = OUT.Active}) end)
	local function paintFilter()
		local off = CFG.NpcFilter == "Off"
		fmode.Text = CFG.NpcFilter
		fmode.TextColor3 = off and C.Mut or C.W
	end
	on(fmode.Activated, function()
		local order = {"Off", "Only", "Hide"}
		CFG.NpcFilter = order[(table.find(order, CFG.NpcFilter) or 1) % 3 + 1]
		paintFilter()
		updAll()
	end)
	on(ftext.FocusLost, function()
		tween(ftextStroke, fast, {Transparency = OUT.Idle})
		CFG.NpcText = ftext.Text
		parseWords()
		updAll()
	end)
	paintFilter()
	table.insert(repaints, function() paintFilter(); ftext.Text = CFG.NpcText end)
	new("TextLabel", {
		Size = U(1, 0, 0, 28), BackgroundTransparency = 1, TextWrapped = true,
		Text = "Only — только совпавшие, Hide — скрыть совпавших. Работает для NPC.",
		TextColor3 = C.Mut, Font = GM, TextSize = 10, TextXAlignment = XL,
		TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 5,
	}, pe)

	local resetBtn = button(pe, "Reset settings", {Size = U(1, 0, 0, 40), LayoutOrder = 6}, {danger = true})
	local rArmed = false
	local function disarmReset()
		rArmed = false
		resetBtn.Text = "Reset settings"
		tween(resetBtn, fast, {BackgroundColor3 = C.Input, TextColor3 = C.Danger})
	end
	on(resetBtn.Activated, function()
		if not rArmed then
			rArmed = true
			resetBtn.Text = "Точно сбросить?"
			tween(resetBtn, fast, {BackgroundColor3 = C.DangerBg, TextColor3 = C.W})
			task.delay(2.5, function() if rArmed and resetBtn.Parent then disarmReset() end end)
			return
		end
		disarmReset()
		for k, v in DEF.CFG do CFG[k] = v end
		for n, t in DEF.col do
			for k, v in t do col[n][k] = v end
		end
		table.clear(pset)
		for k, v in DEF.AIM do AIMCFG[k] = type(v) == "table" and deepCopy(v) or v end
		for k, v in DEF.UI do UICFG[k] = type(v) == "table" and deepCopy(v) or v end
		if applyUIAll then applyUIAll() end
		AIMCFG.Enabled = false
		CFG.On = true
		cur = "Fill"
		parseWords()
		statsCard.Visible = CFG.ShowStats
		if closeDetail then closeDetail() end
		for _, fn in repaints do fn() end
		updAll()
		saveNow()
	end)

	-- ===== Страница Color =====
	local refreshPicker
	local ctabRow = row(pages.Color, 30, 5, 1)
	local ctab = {}
	local function tabsPaint()
		for n, t in ctab do
			t.dot.BackgroundColor3 = hsv(col[n])
			colorTabSel(t, n == cur)
		end
	end
	for i, n in {"Fill", "Outline", "Name", "NPC", "Friend"} do
		ctab[n] = colorTab(ctabRow, n, U(1 / 5, -4, 1, 0), i, function() cur = n; refreshPicker() end)
	end
	local _card
	_card, refreshPicker = makePicker(pages.Color, 2, function() return col[cur] end, refreshHL, tabsPaint)
	table.insert(repaints, function() refreshPicker() end)

	-- ===== v4.1: TEAM COLORS (страница Color) =====
	do
		local pc, ord, paints, pickRefresh = pages.Color, 9, {}, nil
		local function nx() ord += 1 return ord end
		local function repaintAll()
			for _, fn in paints do fn() end
			if pickRefresh then pickRefresh() end
		end
		table.insert(repaints, repaintAll)
		local function apply() refreshHL() repaintAll() end
		local function nextOf(list, v) return list[(table.find(list, v) or 0) % #list + 1] end

		sectionLabel(pc, "TEAM COLORS", nx())
		local function tog(text, key, desc)
			local _, p = toggleCard(pc, text, nx(), function() return CFG[key] end, function(v) CFG[key] = v refreshHL() end, desc)
			table.insert(paints, p)
		end
		tog("Enable Friendly Color", "TcFriend", "Союзники (виден при Team check = OFF)")
		tog("Enable Enemy Color", "TcEnemy", "Игроки из других команд")
		tog("Enable NPC Color", "TcNPC", "Нейтральные NPC")
		tog("Apply colors to all elements", "TcAll", "Всё цветом Team: заливка, бокс, имя, скелет, трасса")
		tog("Show Tracers", "Tracers", "Линии к целям (цвет Tracer)")
		tog("Show Skeleton", "Skeleton", "Скелет целей (цвет Skeleton)")

		local function cyc(text, getv, nextv)
			local _, p = cycleCard(pc, text, nx(), getv, function() nextv() apply() end)
			table.insert(paints, p)
		end
		cyc("Team color preset", function() return CFG.TcPair end, function()
			local n = nextOf(TC.PairOrder, CFG.TcPair)
			local p = TC.Pairs[n]
			if p then
				CFG.TcFP, CFG.TcEP = p[1], p[2]
				TC.put("Friend", TC.FP[p[1]]) TC.put("Enemy", TC.EP[p[2]])
			else
				CFG.TcFP, CFG.TcEP = "Custom", "Custom"
			end
			CFG.TcPair = n
		end)
		cyc("Friendly color preset", function() return CFG.TcFP end, function()
			CFG.TcFP = nextOf(TC.FPOrder, CFG.TcFP)
			if TC.FP[CFG.TcFP] then TC.put("Friend", TC.FP[CFG.TcFP]) end
			TC.sync()
		end)
		cyc("Enemy color preset", function() return CFG.TcEP end, function()
			CFG.TcEP = nextOf(TC.EPOrder, CFG.TcEP)
			if TC.EP[CFG.TcEP] then TC.put("Enemy", TC.EP[CFG.TcEP]) end
			TC.sync()
		end)

		sectionLabel(pc, "CUSTOM COLOR PICKER  (Box = обводка, при Apply to all берётся Team)", nx())
		local sideSel, elemSel, stabs, etabs = "Friend", "Team", {}, {}
		local function tabsPaint()
			for n, t in stabs do
				t.dot.BackgroundColor3 = hsv(col["TC" .. n .. elemSel])
				colorTabSel(t, n == sideSel)
			end
			for n, t in etabs do
				t.dot.BackgroundColor3 = hsv(col["TC" .. sideSel .. n])
				colorTabSel(t, n == elemSel)
			end
		end
		local sRow = row(pc, 30, 5, nx())
		for i, n in TC.Sides do
			stabs[n] = colorTab(sRow, TC.Label[n], U(1 / 3, -4, 1, 0), i, function() sideSel = n pickRefresh() end)
		end
		local eRow = row(pc, 30, 5, nx())
		for i, n in TC.Elems do
			etabs[n] = colorTab(eRow, n, U(1 / 4, -4, 1, 0), i, function() elemSel = n pickRefresh() end)
		end
		local _pk
		_pk, pickRefresh = makePicker(pc, nx(), function() return col["TC" .. sideSel .. elemSel] end, function()
			if sideSel == "Friend" then CFG.TcFP = "Custom" elseif sideSel == "Enemy" then CFG.TcEP = "Custom" end
			TC.sync()
			refreshHL()
			for _, fn in paints do fn() end
		end, tabsPaint)
		local resetTC = button(pc, "Reset Team Colors", {Size = U(1, 0, 0, 40), LayoutOrder = nx()})
		on(resetTC.Activated, function() TC.reset() apply() end)
		pickRefresh()
	end

	-- ===== Страница Sizes =====
	local sOrd = 0
	local function slider(title, key, min, max, pct, fmt)
		sOrd += 1
		local _, paint = sliderCard(pages.Sizes, title, sOrd, min, max,
			function() return CFG[key] end,
			function(v)
				CFG[key] = pct and v or math.floor(v + 0.5)
				refreshHL()
			end,
			function(v)
				if fmt then return fmt(v) end
				if pct then return math.floor(v * 100 + 0.5) .. "%" end
				return tostring(v)
			end,
			not pct and 1 or nil)
		table.insert(repaints, function() paint() end)
	end
	slider("Fill strength", "Fill", 0, 1, true)
	slider("Outline opacity", "Outline", 0, 1, true)
	slider("Name size", "NameSize", 10, 30)
	slider("Name length", "NameLen", 3, 20)
	slider("Max distance", "MaxDist", 50, DIST_MAX, false, function(v) return v >= DIST_MAX and "∞" or v .. "m" end)
	slider("Limit count", "LimitN", 1, 31)

	-- ===== Страница Players =====
	local pp = pages.Players
	local pl = pp:FindFirstChildOfClass("UIListLayout")
	if pl then pl:Destroy() end
	local listView = new("Frame", {Size = S(1, 1), BackgroundTransparency = 1}, pp)
	new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, listView)
	local head = row(listView, 26, 6, 1)
	new("TextLabel", {
		Size = U(1, -66, 1, 0), BackgroundTransparency = 1, Text = "Tap: Mark > Hide > Off",
		TextColor3 = C.Mut, Font = GM, TextSize = 11, TextXAlignment = XL, LayoutOrder = 1,
	}, head)
	local clearBtn = button(head, "Clear", {Size = O(60, 26), TextSize = 11, TextColor3 = C.Mut, LayoutOrder = 2})
	local listUI = new("ScrollingFrame", {
		Size = U(1, 0, 1, -32), LayoutOrder = 2, BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = C.Mut, ScrollBarImageTransparency = 0.3,
		CanvasSize = U(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, listView)
	new("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.Name}, listUI)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 2), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), PaddingRight = UDim.new(0, 8),
	}, listUI)

	-- --- экран настроек одного игрока ---
	local detail = new("ScrollingFrame", {
		Size = S(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
		ScrollBarThickness = 3, ScrollBarImageColor3 = C.Mut, ScrollBarImageTransparency = 0.3,
		CanvasSize = U(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, pp)
	new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, detail)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 2), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), PaddingRight = UDim.new(0, 8),
	}, detail)
	local selP, pcur = nil, "Fill"
	local paintDetail, pickRefresh

	local dHead = row(detail, 28, 6, 1)
	local backBtn = button(dHead, "‹ Back", {Size = O(64, 28), TextSize = 11, LayoutOrder = 1})
	local dName = new("TextLabel", {
		Size = U(1, -70, 1, 0), BackgroundTransparency = 1, Text = "", TextColor3 = C.W, Font = GB,
		TextSize = 12, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 2,
	}, dHead)
	sectionLabel(detail, "ЭЛЕМЕНТЫ (Auto = как в общих настройках)", 2)
	local dgrid = chipGrid(detail, 3)
	local TRI = {
		{"Nickname", "Name"}, {"Highlight", "Hl"}, {"Fill", "Fill"},
		{"Outline", "Outline"}, {"HP bar", "HP"}, {"Distance", "Dist"},
	}
	local triLbl = {}
	for i, d in TRI do
		local b = new("TextButton", {LayoutOrder = i, BackgroundColor3 = C.Card, Text = "", AutoButtonColor = false}, dgrid)
		rr(b, 8)
		hoverable(b, outline(b), {bg = C.Card, bgHover = C.Sel})
		new("TextLabel", {
			Size = U(1, -56, 1, 0), Position = O(10, 0), BackgroundTransparency = 1, Text = d[1],
			TextColor3 = C.W, Font = GM, TextSize = 12, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, Active = false,
		}, b)
		triLbl[d[2]] = new("TextLabel", {
			Size = O(44, 34), AnchorPoint = V2(1, 0), Position = U(1, -8, 0, 0), BackgroundTransparency = 1,
			Font = GB, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right, Text = "Auto", TextColor3 = C.Mut, Active = false,
		}, b)
		on(b.Activated, function()
			if not selP then return end
			local id = tostring(selP.UserId)
			local e = pset[id] or {}
			local v = e[d[2]]
			e[d[2]] = v == nil and "On" or v == "On" and "Off" or nil
			pset[id] = e
			cleanPs(id)
			paintDetail()
			upd(selP.Character, selP)
			refreshHL()
		end)
	end
	sectionLabel(detail, "ЦВЕТА ИГРОКА", 4)
	local ctabs = row(detail, 30, 5, 5)
	local pctab = {}
	local function ctabPaint()
		local e = selP and pset[tostring(selP.UserId)]
		for n, t in pctab do
			local c = e and e.cols and e.cols[n] or col[n]
			t.dot.BackgroundColor3 = hsv(c)
			colorTabSel(t, n == pcur)
		end
	end
	for i, n in PCOLS do
		pctab[n] = colorTab(ctabs, n, U(1 / 3, -4, 1, 0), i, function() pcur = n; pickRefresh() end)
	end
	local function getPC(edit)
		if not selP then return col[pcur] end
		local id = tostring(selP.UserId)
		local e = pset[id]
		local c = e and e.cols and e.cols[pcur]
		if c then return c end
		if not edit then return col[pcur] end
		e = e or {}
		pset[id] = e
		e.cols = e.cols or {}
		local g = col[pcur]
		c = {h = g.h, s = g.s, v = g.v}
		e.cols[pcur] = c
		return c
	end
	local _pc
	_pc, pickRefresh = makePicker(detail, 6, getPC, refreshHL, ctabPaint)
	local rrow = row(detail, 32, 6, 7)
	local useGlobal = button(rrow, "Use global color", {Size = U(0.5, -3, 1, 0), TextSize = 11, LayoutOrder = 1})
	local resetP = button(rrow, "Reset player", {Size = U(0.5, -3, 1, 0), TextSize = 11, LayoutOrder = 2}, {danger = true})
	on(useGlobal.Activated, function()
		if not selP then return end
		local id = tostring(selP.UserId)
		local e = pset[id]
		if e and e.cols then e.cols[pcur] = nil end
		cleanPs(id)
		refreshHL()
		paintDetail()
	end)
	on(resetP.Activated, function()
		if not selP then return end
		pset[tostring(selP.UserId)] = nil
		upd(selP.Character, selP)
		refreshHL()
		paintDetail()
	end)
	paintDetail = function()
		if not selP then return end
		dName.Text = selP.DisplayName .. "  @" .. selP.Name
		local e = pset[tostring(selP.UserId)]
		for k, lbl in triLbl do
			local v = e and e[k]
			lbl.Text = v or "Auto"
			lbl.TextColor3 = v == "On" and C.W or v == "Off" and C.Off or C.Mut
		end
		pickRefresh()
	end
	closeDetail = function()
		selP = nil
		detail.Visible = false
		listView.Visible = true
	end
	local function openDetail(p)
		selP, pcur = p, "Fill"
		listView.Visible = false
		detail.Visible = true
		detail.CanvasPosition = V2(0, 0)
		paintDetail()
	end
	on(backBtn.Activated, closeDetail)

	-- --- список игроков ---
	local rowsUI = {}
	local RING = Color3.fromRGB(90, 90, 100)
	local function paintRow(p)
		local r = rowsUI[p]
		if not r then return end
		local st = marks[p.UserId]
		r.tag.Text = st == "Mark" and "Marked" or st == "Hide" and "Hidden" or "Visible"
		local tc = st == "Mark" and hsv(col.Mark) or st == "Hide" and C.Off or C.Mut
		tween(r.tag, fast, {TextColor3 = tc})
		tween(r.btn, fast, {BackgroundColor3 = st == "Mark" and C.Sel
			or st == "Hide" and Color3.fromRGB(34, 24, 26) or C.Card})
		r.acc.BackgroundColor3 = tc
		r.acc.BackgroundTransparency = st and 0 or 1
		r.ring.Color = (CFG.TeamColors and p.Team) and p.Team.TeamColor.Color or RING
		r.sub.Text = p.Team and p.Team.Name or ("@" .. p.Name)
	end
	local function refreshRows() for p in rowsUI do paintRow(p) end end
	plrHook = paintRow
	table.insert(repaints, function() refreshRows(); paintDetail() end)
	local function addRow(p)
		if p == LP or rowsUI[p] then return end
		local b = button(listUI, "", {Size = U(1, 0, 0, 38), BackgroundColor3 = C.Card, Name = p.Name:lower()})
		local acc = new("Frame", {Size = O(3, 20), Position = O(6, 9), BackgroundColor3 = C.W, BackgroundTransparency = 1, BorderSizePixel = 0, Active = false}, b)
		round(acc, 2)
		local av = new("ImageLabel", {Size = O(28, 28), Position = O(14, 5), BackgroundColor3 = C.Input, Active = false}, b)
		round(av, 14)
		local ring = stroke(av, RING, 0, 1.5)
		new("TextLabel", {
			Size = U(1, -140, 0, 18), Position = O(50, 4), BackgroundTransparency = 1, Text = p.DisplayName,
			TextColor3 = C.W, Font = GB, TextSize = 12, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, Active = false,
		}, b)
		local sub = new("TextLabel", {
			Size = U(1, -140, 0, 12), Position = O(50, 21), BackgroundTransparency = 1, Text = "",
			TextColor3 = C.Mut, Font = GM, TextSize = 10, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, Active = false,
		}, b)
		local tag = new("TextLabel", {
			Size = O(52, 38), AnchorPoint = V2(1, 0), Position = U(1, -40, 0, 0), BackgroundTransparency = 1,
			Text = "Visible", TextColor3 = C.Mut, Font = GB, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right, Active = false,
		}, b)
		-- кнопка справа: персональные настройки подсветки
		local gear = button(b, "›", {
			Size = O(28, 28), AnchorPoint = V2(1, 0.5), Position = U(1, -5, 0.5, 0), TextSize = 18, ZIndex = 2,
		})
		rowsUI[p] = {btn = b, tag = tag, acc = acc, ring = ring, sub = sub}
		task.spawn(function()
			local ok, img = pcall(Players.GetUserThumbnailAsync, Players, p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
			if ok and av.Parent then av.Image = img end
		end)
		paintRow(p)
		on(b.Activated, function()
			local st = marks[p.UserId]
			marks[p.UserId] = st == nil and "Mark" or st == "Mark" and "Hide" or nil
			paintRow(p)
			upd(p.Character, p)
			refreshHL()
		end)
		on(gear.Activated, function() openDetail(p) end)
	end
	on(clearBtn.Activated, function()
		table.clear(marks)
		refreshRows()
		updAll()
	end)
	for _, p in Players:GetPlayers() do addRow(p) end
	on(Players.PlayerAdded, addRow)
	on(Players.PlayerRemoving, function(p)
		if selP == p then closeDetail() end
		if rowsUI[p] then rowsUI[p].btn:Destroy() rowsUI[p] = nil end
	end)

	-- ===== Страница Performance =====
	local pv2 = pages.Visual
	local paintCap
	local perfChips = {
		{"Team colors", "TeamColors", function() refreshHL(); refreshRows() end},
		{"Size by dist", "DistScale"},
		{"Animations", "Anim"},
		{"FPS / ping", "ShowStats", function() statsCard.Visible = CFG.ShowStats end},
	}
	if canFps then
		table.insert(perfChips, {"FPS unlock", "FpsUnlock", function() paintCap(); applyFps() end})
	end
	makeChips(chipGrid(pv2, 1), perfChips)
	if canFps then
		local _, p = cycleCard(pv2, "FPS cap", 2, function() return CFG.FpsCap == 0 and "Max" or CFG.FpsCap end, function()
			CFG.FpsCap = FPS_STEPS[(table.find(FPS_STEPS, CFG.FpsCap) or 1) % #FPS_STEPS + 1]
			applyFps()
		end, function() return CFG.FpsUnlock end)
		paintCap = p
		table.insert(repaints, function() paintCap(); applyFps() end)
	end
	-- частота обновления ESP (подписи, HP-бары, ранги): чем ниже, тем меньше нагрузка на слабых телефонах
	local HZ_STEPS = {60, 30, 20, 10}
	local _, paintHz = cycleCard(pv2, "ESP update rate", 3, function() return CFG.EspHz .. " Hz" end, function()
		CFG.EspHz = HZ_STEPS[(table.find(HZ_STEPS, CFG.EspHz) or 0) % #HZ_STEPS + 1]
	end)
	table.insert(repaints, paintHz)
	local lowBtn = button(pv2, "Low-end preset", {Size = U(1, 0, 0, 40), LayoutOrder = 4})
	on(lowBtn.Activated, function()
		CFG.Anim, CFG.DistScale, CFG.Limit, CFG.LimitN, CFG.EspHz = false, false, true, 12, 20
		for _, fn in repaints do fn() end
	end)
	new("TextLabel", {
		Size = U(1, 0, 0, 40), BackgroundTransparency = 1, TextWrapped = true, LayoutOrder = 5,
		Text = "Low-end: без анимаций, 12 ближайших целей, ESP 20 Гц. Чем ниже частота ESP, тем реже обновляются подписи и HP-бары.",
		TextColor3 = C.Mut, Font = GM, TextSize = 10, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top,
	}, pv2)

	-- ===== Страница Appearance (настройки интерфейса) =====
	-- Всё применяется в реальном времени. Menu Scale / Transparency / Background — само окно;
	-- UI Scale — плавающие элементы (кнопка AIM, кнопка меню, HUD, окно ключа).
	local pa = pages.Appearance
	local ao = 0
	local function nextA() ao += 1 return ao end
	local function pct(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end

	local function applyGlass()
		local t = (bgImg.Visible and bgImg.Image ~= "") and UICFG.CardAlpha or 0
		glassNow = t
		for o in glass do
			if o.Parent then
				o.BackgroundTransparency = o:IsDescendantOf(panel) and t or 0
			else
				glass[o] = nil
			end
		end
	end
	local function applyLook()
		if isOpen then
			panel.GroupTransparency = UICFG.MenuAlpha
			scale.Scale = fit()
		end
		applySize()
		for _, f in bgFrames do f.BackgroundTransparency = UICFG.BgAlpha end
		bgImg.ImageTransparency = UICFG.BgImgAlpha
		bgImg.ScaleType = FIT_TYPES[UICFG.BgImgFit] or Enum.ScaleType.Crop
		applyGlass()
		applyRadius()
		for s in floatScales do
			if s.Parent then s.Scale = UICFG.UIScale else floatScales[s] = nil end
		end
	end
	local function paintAccents()
		applyAccent()
		for inst, prop in accents do
			if inst.Parent then inst[prop] = C.Acc else accents[inst] = nil end
		end
	end
	local pend = false
	local function accentLive() -- во время перетаскивания палитры: быстро красим акценты, переключатели — раз в 0.12 с
		paintAccents()
		if pend then return end
		pend = true
		task.delay(0.12, function()
			pend = false
			if alive then
				for _, fn in repaints do fn() end
			end
		end)
	end

	local themeTabs = {}
	local function paintThemeTabs()
		for name, t in themeTabs do
			local h = THEMES[name].Hi
			t.dot.BackgroundColor3 = Color3.fromRGB(h[1], h[2], h[3])
			colorTabSel(t, UICFG.Theme == name)
		end
	end
	local function setTheme(name)
		if not THEMES[name] then return end
		local old = {}
		for _, k in PAL do old[C[k]:ToHex()] = k end
		UICFG.Theme = name
		applyPalette(name)
		local function swap(inst, prop)
			local k = old[inst[prop]:ToHex()]
			if k then inst[prop] = C[k] end
		end
		local roots = {gui}
		if aim and aim.overlay then table.insert(roots, aim.overlay) end
		for _, root in roots do
			for _, d in root:GetDescendants() do
				if d:IsA("GuiObject") then swap(d, "BackgroundColor3") end
				if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then swap(d, "TextColor3") end
				if d:IsA("TextBox") then swap(d, "PlaceholderColor3") end
				if d:IsA("ScrollingFrame") then swap(d, "ScrollBarImageColor3") end
				if d:IsA("UIStroke") then swap(d, "Color") end
			end
		end
		paintAccents()
		for _, fn in repaints do fn() end
		paintThemeTabs()
	end
	applyUIAll = function()
		setTheme(UICFG.Theme)
		applyLook()
		paintAccents()
		for _, fn in repaints do fn() end
	end

	local function aSlider(title, key, min, max, step, fmt)
		local _, paint = sliderCard(pa, title, nextA(), min, max,
			function() return UICFG[key] end,
			function(v) UICFG[key] = math.clamp(tonumber(string.format("%.3f", v)), min, max); applyLook() end,
			fmt, step)
		table.insert(repaints, paint)
	end
	sectionLabel(pa, "WINDOW", nextA())
	aSlider("Menu Scale (zoom)", "MenuScale", 0.7, 1.2, 0.05, function(v) return string.format("%.2fx", v) end)
	aSlider("Menu Transparency", "MenuAlpha", 0, 0.6, 0.05, pct)
	aSlider("Background Transparency", "BgAlpha", 0, 0.8, 0.05, pct)
	local winReset = button(pa, "Reset window size & position", {Size = U(1, 0, 0, 40), LayoutOrder = nextA()})
	on(winReset.Activated, function()
		UICFG.PanelW, UICFG.PanelH, UICFG.PanelCX, UICFG.PanelCY = PW, PH, -1, -1
		applySize()
	end)
	new("TextLabel", {
		Size = U(1, 0, 0, 28), BackgroundTransparency = 1, TextWrapped = true, LayoutOrder = nextA(),
		Text = "Размер окна: тяни за правый нижний угол. Двойное касание угла — сброс.",
		TextColor3 = C.Mut, Font = GM, TextSize = 10, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top,
	}, pa)
	-- ----- фон окна: любая картинка по ссылке или ID -----
	-- ID / rbxassetid:// / ссылка roblox.com работают везде. Прямая ссылка (png/jpg) скачивается через request/HttpGet,
	-- сохраняется writefile и показывается через getcustomasset — это есть только в окружениях, где эти функции доступны.
	local bgToken, bgApplied, bgAsset, bgLoading = 0, UICFG.BgImage, nil, false
	local bgStatus, applyBg
	local function setBgStatus(msg, ok)
		if bgStatus then
			bgStatus.Text = msg
			bgStatus.TextColor3 = ok == true and C.On or ok == false and C.Off or C.Mut
		end
	end
	applyBg = function(src, quiet)
		src = trimS(src)
		bgToken += 1
		local my = bgToken
		if src == "" then
			bgApplied, bgAsset, bgLoading = "", nil, false
			UICFG.BgImage = ""
			_G.TH_BgImage = nil
			bgImg.Visible, bgImg.Image = false, ""
			setBgStatus("Фон не задан", nil)
			applyLook()
			return
		end
		bgApplied, bgLoading = src, true
		setBgStatus("Загрузка…", nil)
		task.spawn(function()
			local asset, err = bgFetch(src)
			if my ~= bgToken or not alive then return end
			local prev, loaded = bgAsset, false
			if asset then
				bgImg.Image, bgImg.Visible = asset, true
				pcall(CP.PreloadAsync, CP, {bgImg})
				if my ~= bgToken or not alive then return end
				loaded = bgImg.IsLoaded
				if not loaded then err = "Картинка не загрузилась: проверь ID или ссылку" end
			end
			bgLoading = false
			if loaded then
				bgAsset = asset
				UICFG.BgImage = src
				_G.TH_BgImage = src
				local first = prev == nil and not quiet
				if first and UICFG.BgAlpha < 0.3 then
					UICFG.BgAlpha = 0.4 -- иначе шапка/бок/подвал закрывают картинку
				end
				applyLook()
				for _, fn in repaints do fn() end
				setBgStatus(first and "Фон применён (прозрачность окна поднята, чтобы было видно)" or "Фон применён", true)
			else
				bgApplied = UICFG.BgImage
				bgImg.Image, bgImg.Visible = prev or "", prev ~= nil
				applyLook()
				setBgStatus(err or "Ошибка", false)
			end
		end)
	end

	sectionLabel(pa, "BACKGROUND IMAGE", nextA())
	local bgBox = new("TextBox", {
		Size = U(1, 0, 0, 40), BackgroundColor3 = C.Input, LayoutOrder = nextA(), Text = UICFG.BgImage,
		PlaceholderText = "ссылка на картинку или ID", TextColor3 = C.W, PlaceholderColor3 = C.Mut, Font = GM, TextSize = 12,
		ClearTextOnFocus = false, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd,
	}, pa)
	rr(bgBox, 8)
	new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, bgBox)
	local bgBoxStroke = outline(bgBox)
	on(bgBox.Focused, function() tween(bgBoxStroke, fast, {Transparency = OUT.Active}) end)
	on(bgBox.FocusLost, function()
		tween(bgBoxStroke, fast, {Transparency = OUT.Idle})
		-- вставил ссылку и ушёл с поля — применяется сразу (Enter / Apply не обязательны)
		if trimS(bgBox.Text) ~= trimS(UICFG.BgImage) then applyBg(bgBox.Text) end
	end)
	local bgRow = row(pa, 40, 6, nextA())
	local bgApplyBtn = button(bgRow, "Apply", {Size = U(0.5, -3, 1, 0), LayoutOrder = 1}, {primary = true})
	local bgClearBtn = button(bgRow, "Clear", {Size = U(0.5, -3, 1, 0), LayoutOrder = 2}, {danger = true})
	on(bgApplyBtn.Activated, function() applyBg(bgBox.Text) end)
	on(bgClearBtn.Activated, function() bgBox.Text = ""; applyBg("") end)
	bgStatus = new("TextLabel", {
		Size = U(1, 0, 0, 14), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, TextWrapped = true, LayoutOrder = nextA(),
		Text = UICFG.BgImage ~= "" and "Загрузка сохранённого фона…" or "Вставь ссылку на PNG/JPG или ID картинки и нажми Apply.",
		TextColor3 = C.Mut, Font = GM, TextSize = 10, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top,
	}, pa)
	aSlider("Image Transparency", "BgImgAlpha", 0, 0.95, 0.05, pct)
	aSlider("Card Transparency (with image)", "CardAlpha", 0, 0.9, 0.05, pct)
	local _, paintFit = cycleCard(pa, "Image fit", nextA(), function() return UICFG.BgImgFit end, function()
		local order = {"Crop", "Fit", "Stretch"}
		UICFG.BgImgFit = order[(table.find(order, UICFG.BgImgFit) or 0) % #order + 1]
		applyLook()
	end)
	table.insert(repaints, paintFit)
	-- после сброса настроек / внешней смены UICFG.BgImage окно и поле догоняют конфиг (дёшево: без повторной загрузки)
	table.insert(repaints, function()
		if not bgBox:IsFocused() then bgBox.Text = UICFG.BgImage end
		if not bgLoading and bgApplied ~= UICFG.BgImage then applyBg(UICFG.BgImage, true) end
	end)

	sectionLabel(pa, "SCALE AND SHAPE", nextA())
	aSlider("UI Scale (buttons, HUD, key)", "UIScale", 0.8, 1.3, 0.05, function(v) return string.format("%.2fx", v) end)
	aSlider("Corner Radius", "Corner", 0, 16, 1, function(v) return string.format("%d px", math.floor(v + 0.5)) end)

	sectionLabel(pa, "UI THEME", nextA())
	local themeGrid = chipGrid(pa, nextA())
	for i, name in THEME_ORDER do
		themeTabs[name] = colorTab(themeGrid, name, U(1, 0, 1, 0), i, function()
			setTheme(name)
		end)
	end
	paintThemeTabs()
	table.insert(repaints, paintThemeTabs)

	sectionLabel(pa, "ACCENT COLOR", nextA())
	local ACC_PRESETS = {{0, 0, 0.94}, {0.55, 0.7, 1}, {0.38, 0.7, 0.9}, {0.75, 0.6, 1}, {0.08, 0.85, 1}, {0, 0.8, 0.95}}
	local accRow = row(pa, 40, 8, nextA())
	local accPicker, accRefresh
	for i, p in ACC_PRESETS do
		local b = new("TextButton", {
			Size = O(40, 40), BackgroundColor3 = Color3.fromHSV(p[1], p[2], p[3]), Text = "", AutoButtonColor = false, LayoutOrder = i,
		}, accRow)
		rr(b, 8)
		outline(b, 0.4)
		on(b.Activated, function()
			UICFG.Accent = {h = p[1], s = p[2], v = p[3]}
			accRefresh()
			accentLive()
		end)
	end
	accPicker, accRefresh = makePicker(pa, nextA(), function() return UICFG.Accent end, accentLive, nil)
	accRefresh()
	table.insert(repaints, accRefresh)

	local appReset = button(pa, "Reset appearance", {Size = U(1, 0, 0, 40), LayoutOrder = nextA()}, {danger = true})
	on(appReset.Activated, function()
		for k, v in DEF.UI do UICFG[k] = type(v) == "table" and deepCopy(v) or v end
		applyUIAll()
	end)


	-- ===== Вкладка Aim =====
	local okA, resA = pcall(buildAim, pages.Aim, {menu = function(s) setOpen(s) end, fovPage = pages.FOV})
	if okA then
		aim = resA
		table.insert(repaints, aim.refresh)
	else
		warn("[Enkaisy] Aim init error: " .. tostring(resA))
	end

	-- Справка открывается поверх страницы, поэтому работает и на сенсорном экране.
    local helpBox = new("Frame", {Size = U(1, -24, 0, 150), AnchorPoint = V2(0.5, 0.5),
        Position = U(0.5, 0, 0.5, 0), BackgroundColor3 = C.Card, Visible = false, ZIndex = 50}, panel)
    rr(helpBox, 10)
    outline(helpBox, OUT.Active)
    local helpTitle = new("TextLabel", {Size = U(1, -50, 0, 28), Position = O(12, 8), BackgroundTransparency = 1,
        Text = "", TextColor3 = C.W, Font = GB, TextSize = 13, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 51}, helpBox)
    local helpText = new("TextLabel", {Size = U(1, -24, 1, -44), Position = O(12, 36), BackgroundTransparency = 1,
        Text = "", TextColor3 = C.W, Font = GM, TextSize = 12, TextWrapped = true,
        TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 51}, helpBox)
    local helpClose = new("TextButton", {Size = O(32, 32), AnchorPoint = V2(1, 0), Position = U(1, -6, 0, 6),
        BackgroundColor3 = C.Input, Text = "×", TextColor3 = C.W, Font = GB, TextSize = 18, ZIndex = 51}, helpBox)
    rr(helpClose, 8)
    on(helpClose.Activated, function() helpBox.Visible = false end)
    helpUI.open = function(title, desc)
        local info = helpUI.info[title]
        helpTitle.Text = title
        helpText.Text = info and ("RU: " .. info[1] .. "\n\nEN: " .. info[2])
            or (desc and ("RU: " .. desc .. "\n\nEN: Description not available yet.")
            or "RU: Описание пока недоступно.\n\nEN: Description not available yet.")
        helpBox.Visible = true
    end
    -- Поиск по названиям папок и карточек, включая известные русские описания.
    local function fold(s)
        s = string.lower(s)
        local upper, lower = {"А","Б","В","Г","Д","Е","Ё","Ж","З","И","Й","К","Л","М","Н","О","П","Р","С","Т","У","Ф","Х","Ц","Ч","Ш","Щ","Ъ","Ы","Ь","Э","Ю","Я"},
            {"а","б","в","г","д","е","ё","ж","з","и","й","к","л","м","н","о","п","р","с","т","у","ф","х","ц","ч","ш","щ","ъ","ы","ь","э","ю","я"}
        for i, c in upper do s = s:gsub(c, lower[i]) end
        return s
    end
    local function filterTabs()
        local q = fold(search.Text:match("^%s*(.-)%s*$"))
        local matches = {}
        for _, n in TABS do
            local hay = n .. " " .. (DISP[n] or "") .. " " .. (SUB[n] or "")
            for _, g in GROUPS do if table.find(g[2], n) then hay ..= " " .. g[1] end end
            for _, item in helpUI.items do
                if item.card:IsDescendantOf(pages[n]) then
                    local info = helpUI.info[item.title]
                    hay ..= " " .. item.title .. " " .. (item.desc or "") .. (info and (" " .. info[1] .. " " .. info[2]) or "")
                end
            end
            matches[n] = q == "" or string.find(fold(hay), q, 1, true) ~= nil
        end
        local y = 0
        for _, g in GROUPS do
            local any = false
            for _, n in g[2] do if matches[n] then any = true end end
            groupLabels[g[1]].Visible = any
            if any then
                groupLabels[g[1]].Position = O(8, y + 2)
                y += 20
                for _, n in g[2] do
                    ptabs[n].button.Visible = matches[n]
                    if matches[n] then
                        tabPos[n] = y
                        ptabs[n].button.Position = O(2, y)
                        y += TABH + TGAP
                    end
                end
                y += 6
            else
                for _, n in g[2] do ptabs[n].button.Visible = false end
            end
        end
        tabsHolder.CanvasSize = O(0, y)
        tabsHolder.CanvasPosition = V2(0, 0)
        pill.Visible = matches[curTab]
        if pill.Visible then pill.Position = O(2, tabPos[curTab]) end
    end
    on(search:GetPropertyChangedSignal("Text"), filterTabs)

	-- ===== События =====
	movable(openBtn, openBtn, function() setOpen(true) end, function() clampGui(openBtn) end)
	movable(titleBar, panel, nil, commitPanel)
	on(close.Activated, function() setOpen(false) end)
	on(toggle.Activated, function() CFG.On = not CFG.On; updAll(); paintToggle(true) end)
	on(LP:GetPropertyChangedSignal("Team"), function() if CFG.TeamCheck then updAll() else refreshHL() end end)
	on(RS.Heartbeat, frame)
	on(Players.PlayerAdded, track)
	on(Players.PlayerRemoving, untrack)
	on(Workspace.DescendantAdded, function(d) if d:IsA("Humanoid") then addNpc(d) end end)

	paintToggle(false)
	paintSeg(false)
	refreshPicker()
	show(table.find(TABS, UICFG.Tab) and UICFG.Tab or "Main")
	applyLook()
	if UICFG.BgImage ~= "" then applyBg(UICFG.BgImage, true) end
	applyFps()
	for _, p in Players:GetPlayers() do track(p) end
	setOpen(true)
	task.spawn(function()
		local n = 0
		for _, d in Workspace:GetDescendants() do
			if not alive then return end
			if d:IsA("Humanoid") then addNpc(d) end
			n += 1
			if n % 400 == 0 then task.wait() end
		end
	end)
end

-- ===== Экран ключа =====
-- Карточка строго по центру экрана, 380x296 (масштабируется под экран и UI Scale, не обрезается), 
-- поля 46 px под палец; при экранной клавиатуре карточка приподнимается ровно настолько, чтобы поле не скрылось.
local function keyScreen(done)
	local KW, KH = 380, 296
	pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end) -- центр = точный центр экрана, без отступа выреза
	blur = new("BlurEffect", {Size = 0}, Lighting)
	tween(blur, slow, {Size = KEY_BLUR})
	local dim = new("Frame", {Size = S(1, 1), BackgroundColor3 = C.B, BackgroundTransparency = 1, Active = true, ZIndex = 10}, gui)
	tween(dim, slow, {BackgroundTransparency = KEY_DIM})
	local card = new("CanvasGroup", {
		Size = O(KW, KH), AnchorPoint = V2(0.5, 0.5), Position = U(0.5, 0, 0.5, 0),
		BackgroundColor3 = C.Side, GroupTransparency = 1,
	}, dim)
	rr(card, 16)
	outline(card, 0.45)
	local function keyScale()
		local a = gui.AbsoluteSize
		local maxK = math.max(0.4, math.min((a.X - 24) / KW, (a.Y - 24) / KH))
		return math.min(maxK, 1.1 * UICFG.UIScale)
	end
	local sc = new("UIScale", {Scale = keyScale() * 0.92}, card)
	tween(card, slow, {GroupTransparency = 0}) tween(sc, slow, {Scale = keyScale()})
	local closed = false
	local xBtn = new("TextButton", {
		Size = O(36, 36), AnchorPoint = V2(1, 0), Position = U(1, -12, 0, 12),
		BackgroundColor3 = C.Input, Text = "", AutoButtonColor = false, ZIndex = 5,
	}, card)
	rr(xBtn, 10)
	hoverable(xBtn, outline(xBtn))
	xMark(xBtn, C.W)
	local lg = logo(60, 32, card)
	lg.AnchorPoint, lg.Position = V2(0.5, 0), U(0.5, 0, 0, 24)
	local function label(y, h, text, color, font, size)
		return new("TextLabel", {
			Size = U(1, 0, 0, h), Position = O(0, y), BackgroundTransparency = 1,
			Text = text, TextColor3 = color, Font = font, TextSize = size,
		}, card)
	end
	label(94, 28, "Enkaisy", C.W, GB, 22)
	local sub = label(124, 20, "Введите ключ доступа", C.Mut, Enum.Font.Gotham, 14)
	local status = label(268, 20, "", C.Off, GM, 13)
	local box = new("TextBox", {
		Size = U(1, -40, 0, 46), Position = O(20, 158), BackgroundColor3 = C.Input,
		Text = "", PlaceholderText = "• • • • •", TextColor3 = C.W, PlaceholderColor3 = C.Mut,
		Font = GB, TextSize = 20, ClearTextOnFocus = false,
	}, card)
	rr(box, 10)
	local boxStroke = outline(box, 0.5)
	local btn = button(card, "Активировать", {
		Size = U(1, -40, 0, 46), Position = O(20, 214), TextSize = 16,
	}, {primary = true})

	-- фон-картинка из Appearance: та же ссылка / ID, прозрачность картинки, режим и прозрачность карточек
	do
		local src = trimS(UICFG.BgImage)
		if src ~= "" then
			local FIT = {Crop = Enum.ScaleType.Crop, Fit = Enum.ScaleType.Fit, Stretch = Enum.ScaleType.Stretch}
			local img = new("ImageLabel", {
				Name = "KeyBgImage", Size = S(1, 1), BackgroundTransparency = 1, Image = "", Visible = false, Active = false,
				ZIndex = 0, ScaleType = FIT[UICFG.BgImgFit] or Enum.ScaleType.Crop, ImageTransparency = 1,
			}, card)
			local glassItems = {xBtn, lg, box, btn}
			task.spawn(function()
				local asset = bgFetch(src)
				if not asset or closed or not img.Parent then return end
				img.Image, img.Visible = asset, true
				pcall(CP.PreloadAsync, CP, {img})
				if closed or not img.Parent then return end
				if not img.IsLoaded then img.Visible, img.Image = false, "" return end
				tween(img, slow, {ImageTransparency = UICFG.BgImgAlpha})
				for _, o in glassItems do tween(o, slow, {BackgroundTransparency = UICFG.CardAlpha}) end
				sub.TextColor3 = C.W
			end)
		end
	end

	-- положение по центру; при экранной клавиатуре — сдвиг вверх на минимально нужную величину
	local shiftY = 0
	local function place(anim)
		shiftY = 0
		if box:IsFocused() and UIS.OnScreenKeyboardVisible then
			local a = gui.AbsoluteSize
			local half = KH * sc.Scale / 2
			local bottom = a.Y / 2 + half
			local top = UIS.OnScreenKeyboardPosition.Y
			shiftY = math.clamp(bottom - top + 12, 0, math.max(0, a.Y / 2 - half - 8))
		end
		local pos = U(0.5, 0, 0.5, -shiftY)
		if anim then tween(card, fast, {Position = pos}) else card.Position = pos end
	end
	local rc = on(gui:GetPropertyChangedSignal("AbsoluteSize"), function()
		if dim.Parent then
			sc.Scale = keyScale()
			place(false)
		end
	end)
	on(UIS:GetPropertyChangedSignal("OnScreenKeyboardVisible"), function()
		if dim.Parent then place(true) end
	end)

	local busy, tries = false, 0
	local function submit()
		if busy then return end
		busy = true
		if hashKey((box.Text:gsub("%s", ""))) == KEY_HASH then
			status.TextColor3, status.Text = C.On, "Ключ принят"
			task.wait(0.4)
			if closed then return end
			tween(card, slow, {GroupTransparency = 1})
			tween(dim, slow, {BackgroundTransparency = 1}) tween(blur, slow, {Size = 0})
			task.wait(0.4)
			if closed then return end
			rc:Disconnect()
			dim:Destroy() blur:Destroy() blur = nil
			pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
			done()
			return
		end
		tries += 1
		status.TextColor3, status.Text = C.Off, "Неверный ключ"
		if CFG.Anim then
			for _, dx in {-12, 12, -8, 8, -4, 4, 0} do
				if closed then return end
				local t = TS:Create(card, TweenInfo.new(0.045), {Position = U(0.5, dx, 0.5, -shiftY)})
				t:Play()
				t.Completed:Wait()
			end
		end
		if tries >= 5 then
			for i = 10, 1, -1 do
				if closed then return end
				status.Text = "Подождите " .. i .. " c"
				task.wait(1)
			end
			if closed then return end
			tries, status.Text = 0, ""
		end
		box.Text, busy = "", false
	end
	on(xBtn.Activated, function()
		closed = true
		stop()
	end)
	on(btn.Activated, submit)
	on(box.Focused, function()
		tween(boxStroke, fast, {Transparency = OUT.Active})
		task.delay(0.3, function()
			if not closed and dim.Parent then place(true) end
		end)
	end)
	on(box.FocusLost, function(enter)
		tween(boxStroke, fast, {Transparency = 0.5})
		if dim.Parent then place(true) end
		if enter then submit() end
	end)
end

stop = function()
	alive = false
	saveNow()
	if aim then pcall(aim.destroy) aim = nil end
	_G.TH_Stop = nil
	plrHook = nil
	statusFn = nil
	if canFps then pcall(setfpscap, 60) end
	for _, c in conns do c:Disconnect() end
	for _, c in npcConn do c:Disconnect() end
	table.clear(npcConn)
	table.clear(npcs)
	for p in pconn do untrack(p) end
	for ch in esp do unhl(ch) end
	if blur then blur:Destroy() end
	if TC.gui then TC.gui:Destroy() end
	gui:Destroy()
end
_G.TH_Stop = stop
if script then script.Destroying:Connect(stop) end
keyScreen(function()
	local ok, e = pcall(startMain)
	if not ok then
		pcall(function() game:GetService("StarterGui"):SetCore("SendNotification", {Title = "Enkaisy error", Text = tostring(e):sub(1, 120), Duration = 15}) end)
	end
end)
