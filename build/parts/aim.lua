-- ЧАСТЬ: панель Aim. Отдельный кусок кода — свои 200 локалей, не общие с интерфейсом.
return function(page, api)
	local AIM = {} -- состояние панели Aim: редкие локали вынесены в таблицу (лимит Lua 200)
	local A = AIMCFG
	AIM.CS = game:GetService("CollectionService")
	AIM.GuiService = game:GetService("GuiService")
	local camera = Workspace.CurrentCamera
	local fireRemote = GLB.ReplicatedStorage:FindFirstChild(GLB.REMOTE_NAME)

	AIM.TAG = "AimTarget" -- NPC с этим тегом тоже считаются целями
	local tagged, aconns = {}, {}
	local function connect(sig, fn)
		local c = sig:Connect(fn)
		table.insert(aconns, c)
		return c
	end
	for _, inst in AIM.CS:GetTagged(AIM.TAG) do tagged[inst] = true end
	connect(AIM.CS:GetInstanceAddedSignal(AIM.TAG), function(inst) tagged[inst] = true end)
	connect(AIM.CS:GetInstanceRemovedSignal(AIM.TAG), function(inst) tagged[inst] = nil end)

	-- ответ сервера на выстрел (hit / miss / причина отказа) — показывается в HUD
	local srvCode, srvT, remoteBound = "-", 0, nil
	local function bindRemote()
		fireRemote = fireRemote or GLB.ReplicatedStorage:FindFirstChild(GLB.REMOTE_NAME)
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
		local p = V2(touch.Position.X, touch.Position.Y) + AIM.GuiService:GetGuiInset()
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
	-- Стили круга: Glow — мягкий ореол, Dashed — пунктир из сегментов, Gradient — градиентная обводка.
	-- Объекты создаются один раз и только показываются/прячутся, чтобы не плодить инстансы каждый кадр.
	-- Стили живут ВНУТРИ круга и двигаются вместе с ним: раньше сегменты и ореол были отдельными
	-- объектами в оверлее и считались в долях экрана — из-за этого пунктир «улетал» от круга.
	local fovGlow = new("Frame", {Name = "FovGlow", Size = S(1, 1), BackgroundTransparency = 1,
		Visible = false, Active = false}, fov)
	new("UICorner", {CornerRadius = UDim.new(0.5, 0)}, fovGlow)
	AIM.fovGlowStroke = stroke(fovGlow, C.W, 0.8, 5)
	pcall(function() AIM.fovGlowStroke.LineJoinMode = Enum.LineJoinMode.Round end)
	-- мягкое свечение: несколько концентрических контуров с падающей непрозрачностью (2..6 px)
	local fovHalo = {}
	for i = 1, 5 do
		local ring = new("Frame", {Name = "FovHalo" .. i, Size = S(1, 1), BackgroundTransparency = 1,
			Visible = false, Active = false}, fov)
		new("UICorner", {CornerRadius = UDim.new(0.5, 0)}, ring)
		local st = stroke(ring, C.W, 0.9, i * 1.1)
		table.insert(fovHalo, {f = ring, st = st, k = i})
	end
	local fovGrad -- градиент обводки стиля Gradient (создаётся один раз)
	local fovStrokeGrad -- сам UIGradient: без объявления он уходил в глобал (переменная = nil)
	-- пунктир: сегменты — ДЕТИ круга, координаты в его долях (0.5 ± радиус)
	AIM.fovDash = {}
	local DASH_N = 24
	for i = 1, DASH_N do
		local d = new("Frame", {Name = "FovDash" .. i, AnchorPoint = V2(0.5, 0.5), Size = O(7, 2.5),
			BackgroundColor3 = C.W, BackgroundTransparency = 0.2, Visible = false, Active = false}, fov)
		rr(d, 2)
		table.insert(AIM.fovDash, d)
	end
	local fovSc -- масштаб круга при появлении (0.6 -> 1), совпадение с областью не страдает
	local markHot = false
	-- маркер ТОЧКИ НАВЕДЕНИЯ (зелёный крест): виден в редакторе и когда круг отвязан от области
	local aimMark = new("Frame", {
		Name = "AimPoint", AnchorPoint = V2(0.5, 0.5), Size = O(16, 16), BackgroundTransparency = 1,
		Visible = false, Active = false, ZIndex = 7,
	}, og)
	AIM.markBar1 = new("Frame", {
		AnchorPoint = V2(0.5, 0.5), Position = U(0.5, 0, 0.5, 0), Size = U(1, 0, 0, 2),
		BackgroundColor3 = C.On, BorderSizePixel = 0, Active = false, ZIndex = 7,
	}, aimMark)
	AIM.markBar2 = new("Frame", {
		AnchorPoint = V2(0.5, 0.5), Position = U(0.5, 0, 0.5, 0), Size = U(0, 2, 1, 0),
		BackgroundColor3 = C.On, BorderSizePixel = 0, Active = false, ZIndex = 7,
	}, aimMark)
	-- калибровочный ScreenGui С отступом экрана: нужен только режиму Crosshair (см. crosshairPoint)
	AIM.probeGui = new("ScreenGui", {
		Name = "EnkaisyProbe", ResetOnSpawn = false, DisplayOrder = -1, IgnoreGuiInset = false,
	}, LP:WaitForChild("PlayerGui"))
	AIM.probe = new("Frame", {Size = O(1, 1), BackgroundTransparency = 1, Active = false}, AIM.probeGui)
	local hudSc -- UIScale HUD: пружина при появлении
	local hud = new("TextLabel", {
		AnchorPoint = V2(0.5, 0), Position = U(0.5, 0, 0, 44), Size = O(320, 24), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
		BackgroundColor3 = C.Side, BackgroundTransparency = 0.08,
		TextColor3 = C.W, TextSize = 12, FontFace = GM, Text = "", Visible = false,
	}, og)
	new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4)}, hud)
	rr(hud, 7) outline(hud, OUT.Soft)
	do
		local sc = new("UIScale", {Scale = UICFG.UIScale}, hud)
		hudSc = sc -- тот же UIScale использует анимация появления: второй UIScale на одном объекте не работает
		sc:SetAttribute("AnimOwned", true) -- масштабом владеет анимация: applyLook его не трогает
		GLB.floatScales[sc] = true
		local function fitHud() hud.Size = O(math.clamp((og.AbsoluteSize.X - 24) / sc.Scale, 1, 660), 24) end
		connect(og:GetPropertyChangedSignal("AbsoluteSize"), fitHud)
		connect(sc:GetPropertyChangedSignal("Scale"), fitHud)
		fitHud()
	end

	-- Плавающий ярлык повторяет плитку папки и использует обычный переключатель меню.
	local quick = new("TextButton", {
		Name = "QuickAim", Size = O(126, 40), AnchorPoint = V2(0, 0.5), Position = U(0, 16, 0.45, 0),
		BackgroundColor3 = C.Card, Text = "", AutoButtonColor = false, ZIndex = 10,
	}, gui)
	rr(quick, Skin.Radius)
	hoverable(quick, outline(quick))
	GLB.floatScales[new("UIScale", {Scale = UICFG.UIScale}, quick)] = true
	AIM.qIcon = icon("Aim", quick, 17, C.W)
	AIM.qIcon.Position = U(0, 19, 0.5, 0)
	new("TextLabel", {Size = O(38, 40), Position = O(36, 0), BackgroundTransparency = 1, Text = "AIM",
		TextColor3 = C.W, FontFace = GB, TextSize = 14, TextXAlignment = XL, Active = false}, quick)
	local qSwitch, qPaint = makeSwitch(quick)
	qSwitch.AnchorPoint, qSwitch.Position = V2(1, 0.5), U(1, -10, 0.5, 0)

	AIM.CIRCLE_COLORS = {
		White = C.W, Green = Color3.fromRGB(80, 220, 120), Red = Color3.fromRGB(240, 80, 80),
		Cyan = Color3.fromRGB(80, 220, 255), Yellow = Color3.fromRGB(255, 220, 80),
	}
	local currentTarget = nil
	local targetSince = nil -- когда текущая цель захвачена: даёт липкость по времени и антидребезг
	local camLag, shakeOff = nil, CFrame.new() -- сглаженный «свой» поворот камеры и текущая тряска
	local shakePrev = 0 -- прошлый сэмпл шума: тряска без «памяти» кадра
	local lastPingT, autoLead = 0, 0.1
	local editing = false
	AIM.previewFov = false -- живой предпросмотр круга, пока открыта вкладка FOV
	-- ЭКРАННОЕ ПРОСТРАНСТВО, общее для логики и визуала; заполняется updateSpace() в начале каждого кадра:
	--   vp     — размер экрана в пикселях (camera.ViewportSize)
	--   aim    — ТОЧКА НАВЕДЕНИЯ (px экрана): выбор цели, поворот камеры, triggerbot, выстрел
	--   circle — где РИСУЕТСЯ круг (по умолчанию = aim, но его можно отвязать)
	--   fov / silent / lock — радиусы областей (px экрана); тот же fov использует и отрисовка круга
	local SP = {vp = V2(1920, 1080), aim = V2(960, 540), circle = V2(960, 540), fov = 0, silent = 0, lock = 0}
	local updateSpace, runSelfTest, setEditing -- задаются ниже
	AIM.testUntil = 0

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
		-- при выключенном Dynamic FOV радиус в пикселях: обратный переход тоже считаем в пикселях
		if A.DynFov then
			SP.fov = NX.dynR * 0.01 * short
		elseif NX.dynBack then
			local target = math.max(2, A.FovPx * 0.5)
			NX.dynPx = (NX.dynPx or SP.fov) + (target - (NX.dynPx or SP.fov)) * a
			SP.fov = NX.dynPx
		end
		if NX.radLbl and AIM.previewFov and now - NX.radT > 0.1 then
			NX.radT = now
			local info = "normal FOV (Dynamic FOV is off)"
			if A.DynFov then
				info = NX.shownRef
					and string.format("dynamic: target %d st, goal %.1f%%", math.floor(NX.shownRef + 0.5), NX.wantR)
					or string.format("dynamic: no target, goal %.1f%% (max)", NX.wantR)
			end
			-- радиус всегда показываем в пикселях: это то, что видно на экране
			local radiusPx = math.floor(SP.fov + 0.5)
			local pctInfo = A.DynFov and string.format("%.1f%% of screen, ", NX.dynR) or ""
			NX.radLbl.Text = string.format("Current radius: %s%d px (diameter %d px)\n%s",
				pctInfo, radiusPx, radiusPx * 2, info)
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
		if A.RcsStrength <= 0 then
			-- 0% — RCS выключен на деле, даже если галочка включена
			rcsRef = nil
			return false
		end
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
	AIM.editLayer = new("Frame", {
		Size = S(1, 1), BackgroundColor3 = C.B, BackgroundTransparency = 0.7, Active = true, Visible = false, ZIndex = 5,
	}, og)
	local editBar = new("Frame", {
		AnchorPoint = V2(0.5, 0), Position = U(0.5, 0, 0, 80), Size = O(300, 232),
		BackgroundColor3 = C.Win, Active = true, Visible = false, ZIndex = 8,
	}, og)
	rr(editBar, Skin.Radius) outline(editBar, OUT.Window)
	do
		local head = new("Frame", {Size = U(1, 0, 0, 31), BackgroundTransparency = 1}, editBar)
		local glyph = icon("FOV", head, 15, C.W)
		glyph.Position = U(0, 17, 0.5, 0)
		new("TextLabel", {Size = O(132, 31), Position = O(31, 0), BackgroundTransparency = 1,
			Text = "Редактор позиции", TextColor3 = C.W, FontFace = GB, TextSize = 14, TextXAlignment = XL}, head)
		new("TextLabel", {Size = U(1, -171, 1, 0), Position = O(160, 0), BackgroundTransparency = 1,
			Text = "Тяни круг или точку", TextColor3 = C.Mut, FontFace = GR, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right}, head)
		new("Frame", {Size = U(1, 0, 0, 1), Position = U(0, 0, 1, -1), BackgroundColor3 = C.Line}, head)
	end
	AIM.doneBtn = button(editBar, "Готово", {
		Size = O(86, 32), Position = O(8, 36), TextSize = 13,
	}, {primary = true})
	AIM.centerBtn = button(editBar, "В центр", {
		Size = O(86, 32), Position = O(107, 36), TextSize = 13,
	})
	AIM.resetBtn = button(editBar, "Сброс", {
		Size = O(86, 32), Position = O(206, 36), TextSize = 13,
	})
	movable(editBar, editBar, nil, function() clampGui(editBar) end) -- панель можно перетаскивать
	connect(AIM.doneBtn.Activated, function() setEditing(false) end)

	-- шаг стрелок в пикселях экрана
	new("TextLabel", {
		Size = O(120, 18), Position = O(160, 74), BackgroundTransparency = 1, Text = "Шаг, px",
		TextColor3 = C.Mut, FontFace = GM, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
	}, editBar)
	AIM.stepBox = new("TextBox", {
		Size = O(120, 32), Position = O(160, 94), BackgroundColor3 = C.Input, Text = tostring(A.StepPx),
		TextColor3 = C.W, FontFace = GM, TextSize = 14, ClearTextOnFocus = true, PlaceholderText = "10", PlaceholderColor3 = C.Mut,
	}, editBar)
	Skin.field(AIM.stepBox)
	local function readStep()
		local n = tonumber(AIM.stepBox.Text)
		if n then A.StepPx = math.clamp(n, 0.5, 500) end
		return A.StepPx
	end
	connect(AIM.stepBox.FocusLost, function() AIM.stepBox.Text = tostring(readStep()) end)

	AIM.targetBtn = button(editBar, "", {Size = O(120, 28), Position = O(160, 130), TextSize = 11})
	AIM.followBtn = button(editBar, "", {Size = O(284, 28), Position = O(8, 166), TextSize = 11})
	AIM.xyLabel = new("TextLabel", {
		Size = O(284, 30), Position = O(8, 198), BackgroundTransparency = 1, Text = "", TextWrapped = true,
		TextColor3 = C.Mut, FontFace = GM, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, editBar)

	local editTarget = "Circle" -- что двигаем: "Circle" (визуал) или "Aim" (точка наведения)
	local function clampN(x) return math.clamp(x, 0.02, 0.98) end
	local function circleN() return V2(SP.circle.X / SP.vp.X, SP.circle.Y / SP.vp.Y) end
	local function aimN() return V2(SP.aim.X / SP.vp.X, SP.aim.Y / SP.vp.Y) end

	-- ===== Плавность наводки (Smoothness) =====
	-- Число A.Smoothness (0.01..1) — общая скорость, а форма задаётся отдельно:
	--   Linear — ровное сглаживание (как раньше);
	--   Ease   — мягко в начале, точнее у цели (лучше для мелких поправок);
	--   Human  — кривая с живой неровностью, движение не выглядит механическим.
	-- Плюс три предохранителя: предел угловой скорости, мёртвая зона в пикселях и доля догоняния камеры.
	local function smoothAlpha(angle, dt)
		local smooth = math.clamp(A.Smoothness, 0.01, 1)
		local alpha = 1 - (1 - smooth) ^ (math.clamp(dt, 0, 0.1) * 60)
		if A.SmoothMode == "Ease" then
			-- ease-out: большие углы берём быстрее, остаток добираем точнее
			alpha = alpha * (0.6 + 0.4 * math.clamp(angle / 0.5, 0, 1))
		elseif A.SmoothMode == "Human" then
			-- неровность задаётся шумом по времени: рука «дышит», но линия не дрожит
			local t = os.clock()
			alpha = alpha * (0.75 + 0.5 * (math.noise(t * 2.3) * 0.5 + 0.5))
		end
		return math.clamp(alpha, 0, 1)
	end
	-- предел скорости поворота: degree per second, как у настоящей руки, а не телепорт
	local function clampStep(step, dt)
		local maxDeg = math.clamp(A.SmoothMaxSpeed, 100, 3600)
		return math.min(step, math.rad(maxDeg) * math.clamp(dt, 0, 0.1))
	end
	-- доля, с которой камера догоняет реальный поворот за кадр (100% = мгновенно)
	local function camFollow()
		return math.clamp(A.SmoothCamFollow / 100, 0.05, 1)
	end

	-- ===== RCS (Recoil Control System) =====
	-- Игра может сама двигать камеру вверх при выстреле (Tool.Attributes RecoilPitch / RecoilYaw
	-- в градусах, периодическое дрожание — MuzzleOffset как Vector3 в градусах). RCS это гасит:
	--   * запоминает прицел перед выстрелом и возвращает его после отдачи (плавность = RcsSmooth);
	--   * при RcsSuppress отдача камеры не отрисовывается вовсе — ствол не задирается;
	--   * точка выстрела считается от прицела ДО отдачи (shoot), поэтому пуля не уходит выше цели.
	local rcsRef -- {cf = прицел до выстрела, t = когда}
	local rcsPulses, rcsCorr = {}, CFrame.new() -- остатки отдачи (MuzzleOffset) и текущая компенсация
	local function rcsReset()
		rcsRef = nil
		if #rcsPulses > 0 then table.clear(rcsPulses) end
		rcsCorr = CFrame.new()
	end
	-- необязательные крючки: игра может разрешить отдачу атрибутами Tool (иначе стрельба ведёт себя как раньше)
	local function rcsAngles(tool)
		if not tool then return 0, 0, 0 end
		local function num(name) local v = tool:GetAttribute(name) return type(v) == "number" and v or 0 end
		return num("RecoilPitch"), num("RecoilYaw"), num("RecoilRoll")
	end
	local function rcsPulse(tool)
		local p, y, r = rcsAngles(tool)
		local off = tool:GetAttribute("MuzzleOffset")
		if typeof(off) == "Vector3" then p, y, r = p + off.X, y + off.Y, r + off.Z end
		local amp = math.max(math.abs(p), math.abs(y), math.abs(r))
		if amp >= 0.05 then table.insert(rcsPulses, {p = math.rad(p), y = math.rad(y), r = math.rad(r)}) end
	end
	-- луч прицела на момент ДО отдачи: на миг возвращаем камере прежний поворот,
	-- считаем ViewportPointToRay и сразу возвращаем всё как было (иначе пуля летит в небо вместе с камерой)
	local function rcsAimRay()
		local ray = camera:ViewportPointToRay(SP.aim.X, SP.aim.Y)
		if not (A.Rcs and rcsRef) then return ray end
		local now = camera.CFrame
		camera.CFrame = CFrame.new(now.Position) * (rcsRef.cf - rcsRef.cf.Position)
		local ok, before = pcall(function() return camera:ViewportPointToRay(SP.aim.X, SP.aim.Y) end)
		camera.CFrame = now
		return ok and before or ray
	end
	-- шаг RCS: гасим отрисовку отдачи и мягко возвращаем камеру к прицелу
	local function rcsStep(now, dt)
		if not A.Rcs or A.RcsStrength <= 0 then
			-- RCS выключен (или сила 0%): отдаём назад уже снятую отдачу, чтобы камера не прыгнула
			if rcsRef or (A.RcsSuppress and not A.Rcs and rcsCorr ~= CFrame.new()) then
				local cf = camera.CFrame
				if rcsCorr ~= CFrame.new() then
					camera.CFrame = CFrame.new(cf.Position) * rcsCorr * (cf - cf.Position)
				end
			end
			if rcsRef or rcsCorr ~= CFrame.new() then rcsReset() end
			return false
		end
		local cf = camera.CFrame
		local changed = false
		dt = math.clamp(dt, 0, 0.1)
		-- 1. подавление отрисовки дрожания: снимаем ровно то, что добавила игра
		if A.RcsSuppress and #rcsPulses > 0 then
			local want = CFrame.new()
			for _, q in rcsPulses do
				want = want * CFrame.fromEulerAnglesYXZ(q.p * A.RcsStrength, q.y * A.RcsStrength, q.r * A.RcsStrength)
			end
			local undo = rcsCorr:Inverse() * want
			camera.CFrame = CFrame.new(cf.Position) * undo * (cf - cf.Position)
			rcsCorr = want
			changed = true
		end
		-- 2. возврат к прицелу после отдачи: сначала полностью, затем остаток мягко
		if rcsRef then
			local toRef = cf.LookVector:Dot(rcsRef.cf.LookVector)
			if toRef > 0.999999 then -- камера уже ровно на прицеле
				rcsRef = nil
			else
				-- сила задаёт долю отдачи, которую снимаем за кадр; плавность растягивает возврат
				local ease = A.RcsSmooth > 0.01 and math.clamp(1 - A.RcsSmooth * 0.75, 0.05, 1) or 1
				local alpha = (1 - (1 - math.max(A.RcsStrength, 0.05)) ^ (dt * 60)) * ease
				local axis = cf.LookVector:Cross(rcsRef.cf.LookVector)
				local ang = math.acos(math.clamp(toRef, -1, 1))
				if axis.Magnitude > 1e-6 and ang > 1e-5 then
					camera.CFrame = CFrame.new(cf.Position) * CFrame.fromAxisAngle(axis.Unit, ang * math.clamp(alpha, 0, 1)) * (cf - cf.Position)
					changed = true
				end
			end
		end
		return changed
	end
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
		if AIM.targetBtn.Text ~= t1 then AIM.targetBtn.Text = t1 end
		if AIM.followBtn.Text ~= t2 then AIM.followBtn.Text = t2 end
	end
	paintEdit()
	connect(AIM.targetBtn.Activated, function()
		editTarget = editTarget == "Aim" and "Circle" or "Aim"
		paintEdit()
	end)
	connect(AIM.followBtn.Activated, function()
		if A.CircleFollow then unlinkCircle() else A.CircleFollow = true end
		paintEdit()
	end)
	connect(AIM.centerBtn.Activated, function()
		if editTarget == "Aim" then
			A.AimMode, A.AimX, A.AimY = "Center", 0.5, 0.5
		else
			-- круг уже связан с точкой, стоящей в центре — менять нечего
			if A.CircleFollow and (SP.aim - V2(SP.vp.X / 2, SP.vp.Y / 2)).Magnitude < 0.5 then return end
			unlinkCircle()
			A.CircleX, A.CircleY = 0.5, 0.5 -- только круг; точка наведения остаётся как была
		end
	end)
	connect(AIM.resetBtn.Activated, function()
		A.AimMode, A.AimX, A.AimY = "Center", 0.5, 0.5
		A.CircleFollow, A.CircleX, A.CircleY, A.StepPx = true, 0.5, 0.5, 10
		AIM.stepBox.Text = tostring(A.StepPx)
		paintEdit()
	end)

	-- стрелки: точный сдвиг выбранного объекта на N пикселей экрана
	local function nudge(dx, dy)
		local st, v = readStep(), SP.vp
		local n = getTargetN()
		setTargetN(n.X + dx * st / v.X, n.Y + dy * st / v.Y)
	end
	-- удержание стрелки = непрерывный сдвиг
	AIM.holdToken = 0
	local function arrow(txt, x, y, dx, dy)
		local b = Skin.iconAction(editBar, "Next", math.deg(math.atan2(dy, dx)), {
			Name = txt, Size = O(40, 32), Position = O(x, y),
		})
		connect(b.InputBegan, function(i)
			if not press(i) then return end
			AIM.holdToken += 1
			local my = AIM.holdToken
			nudge(dx, dy)
			task.spawn(function()
				task.wait(0.4)
				while AIM.holdToken == my and b.Parent do
					nudge(dx, dy)
					task.wait(0.05)
				end
			end)
		end)
	end
	connect(UIS.InputEnded, function(i) if press(i) then AIM.holdToken += 1 end end)
	arrow("▲", 56, 72, 0, -1)
	arrow("◀", 12, 108, -1, 0)
	arrow("▼", 56, 108, 0, 1)
	arrow("▶", 100, 108, 1, 0)

	-- перетаскивание: новая позиция = позиция на старте + сдвиг пальца в ДОЛЯХ экрана (без накопления ошибки)
	local dragInput, dragStart, dragN0
	connect(AIM.editLayer.InputBegan, function(i)
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
		qPaint(o, anim)
	end
	table.insert(refreshers, paintQuick)
	paintQuick(false)
	local lockedModel, skipModel, skipUntil, switchTarget -- Target Lock
	local function setEnabled(state)
		A.Enabled = state
		if not state then currentTarget = nil; lockedModel = nil; rcsReset(); camLag, shakeOff = nil, CFrame.new() end
		refreshAll(true)
	end
	movable(quick, quick, function() setEnabled(not A.Enabled) end, function() clampGui(quick) end)

	-- ===== UI папок Aim / Targets / Trigger / Hitbox / FOV =====
	-- Правило навигации: одна папка = одна задача, похожие настройки стоят рядом.
	-- Smoothness и Sticky идут подряд; Triggerbot и его задержка/допуск — в одной папке Trigger;
	-- Hitbox и его размеры, вид и приоритет частей тела — в одной папке Hitbox.
	local scroll = new("ScrollingFrame", {
		Size = S(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 2,
		ScrollBarImageColor3 = C.Mut, ScrollBarImageTransparency = 0.6,
		CanvasSize = U(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, page)
	new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, scroll)
	-- отступы, чтобы тонкие обводки карточек не обрезались краем прокрутки
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 2), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), PaddingRight = UDim.new(0, 8),
	}, scroll)
	local ord = 0
	local function nextOrder() ord += 1 return ord end
	local tgt = scroll -- текущая страница сборки: Aim / Targets / Trigger / Hitbox / FOV

	local function section(text) sectionLabel(tgt, text, nextOrder()) end
	-- пояснение под разделом: серый текст во всю ширину, не карточка
	local function note(text, height)
		new("TextLabel", {
			Size = U(1, 0, 0, height or 40), BackgroundTransparency = 1, TextWrapped = true, LayoutOrder = nextOrder(),
			Text = text, TextColor3 = C.Mut, FontFace = GM, TextSize = 10, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top,
		}, tgt)
	end

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

	local function cycleKeep(text, key, options) -- как cycle, но не сбрасывает текущую цель
		local _, paint = cycleCard(tgt, text, nextOrder(), function() return A[key] end, function()
			local idx = table.find(options, A[key]) or 0
			A[key] = options[idx % #options + 1]
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

	-- ---------- Aim: сама наводка, захват цели, silent aim, точка наведения, диагностика ----------
	section("AIM ASSIST")
	chips({
		{"Aim on", "Enabled", setEnabled, "Включает наводку (то же, что кнопка AIM)"},
	})
	-- Smoothness и Sticky — две части одного ощущения наводки, поэтому стоят подряд
	slider("Smoothness (higher = faster)", "Smoothness", 0.01, 1, 0.01, 2)
	slider("Sticky (lower = stickier)", "Sticky", 0.2, 1, 0.05, 2)
	-- ===== Плавность: форма кривой и предохранители относятся к той же наводке =====
	section("SMOOTHNESS — ПЛАВНОСТЬ")
	cycleKeep("Smooth curve", "SmoothMode", {"Linear", "Ease", "Human"})
	slider("Max turn speed, deg/s", "SmoothMaxSpeed", 100, 3600, 50, 0)
	slider("Dead zone, px", "SmoothDeadPx", 0, 6, 0.1, 1)
	slider("Camera follow, %", "SmoothCamFollow", 5, 100, 5, 0)
	chips({
		{"Auto predict", "AutoPredict"},
		{"Adv predict", "AdvPredict", nil, "Скорость, ускорение, прыжок/падение цели и падение пули (нужны BulletSpeed + BulletGravity)"},
		{"Float button", "ShowButton", function(v) A.ShowButton = v; paintQuick(true) end, "Плавающая кнопка AIM на экране"},
	})
	slider("Auto predict bias (ms)", "LeadBias", 0, 300, 5, 0)
	slider("Manual predict (sec)", "Prediction", 0, 0.6, 0.01, 2)
	slider("Aim max distance", "MaxDistance", 50, 2000, 25, 0)
	-- качество наводки: удержание по времени, тряска и подстройка упреждения
	slider("Stick time (sec)", "StickTime", 0, 2, 0.05, 2)
	slider("Predict multiplier, %", "LeadMul", 0, 200, 5, 0)
	slider("Shake (soft aim), deg", "Shake", 0, 3, 0.05, 2)

	-- RCS живёт рядом с наводкой: это та же работа с камерой, но против отдачи.
	-- Ползунки гаснут, пока сам RCS выключен, — видно, что они на него не влияют.
	local rcsSlaves = {}
	local function paintRcs()
		local dim = A.Rcs and 0 or 0.55
		for _, card in rcsSlaves do
			if card.Parent then
				for _, d in card:GetDescendants() do
					-- гасим подпись, но не значение справа: видно, какое число выставлено
					if d:IsA("TextLabel") and d.Name ~= "Value" then d.TextTransparency = dim end
				end
			end
		end
	end
	section("RCS — RECOIL CONTROL")
	local _, paintRcsMaster = toggleCard(tgt, "RCS (recoil control)", nextOrder(), function() return A.Rcs end,
		function(v)
			A.Rcs = v
			if not v then rcsReset() end
			paintRcs()
		end, "Возвращает камеру в точку прицела после отдачи и гасит увод ствола")
	table.insert(refreshers, paintRcsMaster)
	local suppressCard, paintRcsSuppress = toggleCard(tgt, "RCS suppress (no kick)", nextOrder(), function() return A.RcsSuppress end,
		function(v) A.RcsSuppress = v; if not v then rcsReset() end end,
		"Камера не уходит вверх при выстреле: отдача не отрисовывается")
	table.insert(refreshers, paintRcsSuppress)
	-- подавление без RCS не работает, поэтому его карточка тоже считается зависимой
	table.insert(rcsSlaves, suppressCard)
	-- 0% = RCS полностью выключен, 100% = снимает всю отдачу
	AIM.strengthCard = sliderCard(tgt, "RCS strength", nextOrder(), 0, 1,
		function() return A.RcsStrength end,
		function(v) A.RcsStrength = math.clamp(tonumber(string.format("%.4f", v)), 0, 1) end,
		function(v) return string.format("%.0f%%", v * 100) end, 0.05)
	table.insert(refreshers, AIM.strengthCard)
	table.insert(rcsSlaves, AIM.strengthCard)
	AIM.smoothCard = sliderCard(tgt, "RCS smoothness", nextOrder(), 0, 1,
		function() return A.RcsSmooth end,
		function(v) A.RcsSmooth = math.clamp(tonumber(string.format("%.4f", v)), 0, 1) end,
		function(v) return v < 0.01 and "instant" or string.format("%.2f", v) end, 0.05)
	table.insert(refreshers, AIM.smoothCard)
	table.insert(rcsSlaves, AIM.smoothCard)
	table.insert(refreshers, paintRcs)

	section("TARGET LOCK")
	chips({
		{"Target lock", "TargetLock", function(v) A.TargetLock = v; lockedModel = nil end, "Держит цель; смена — кнопкой ниже"},
	})
	AIM.switchBtn = button(scroll, "Switch locked target", {Size = U(1, 0, 0, 40), LayoutOrder = nextOrder()})
	on(AIM.switchBtn.Activated, function() if switchTarget then switchTarget() end end)
	slider("Lock release radius, %", "LockR", 5, 90, 1, 0)

	section("SILENT AIM")
	chips({
		{"Silent aim", "SilentAim", nil, "Пуля летит в цель, камера не двигается"},
	})
	slider("Select radius (silent), %", "SilentR", 2, 60, 1, 0)

	section("AIM POINT")
	cycle("Aim center", "AimMode", {"Auto", "Center", "Touch", "Custom", "Crosshair"})
	AIM.editBtn = button(scroll, "Edit aim point", {Size = U(1, 0, 0, 40), LayoutOrder = nextOrder()})
	on(AIM.editBtn.Activated, function() editTarget = "Aim"; paintEdit(); setEditing(true) end)
	note("Точка наведения — куда поворачивается камера. Круг FOV настраивается в папке FOV.", 28)

	section("DIAGNOSTICS")
	chips({{"Debug HUD", "DebugHUD"}})
	AIM.testBtn = button(scroll, "Check coordinates", {Size = U(1, 0, 0, 40), LayoutOrder = nextOrder()})
	AIM.selfLabel = new("TextLabel", {
		Size = U(1, 0, 0, 62), BackgroundTransparency = 1, TextWrapped = true, LayoutOrder = nextOrder(), Text = "",
		TextColor3 = C.Mut, FontFace = GM, TextSize = 10, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top,
	}, scroll)
	on(AIM.testBtn.Activated, function() if runSelfTest then runSelfTest() end end)

	-- ---------- Targets: по кому целиться, проверки и фильтр моделей ----------
	tgt, ord = api.targetsPage or scroll, 0
	section("WHO TO TARGET")
	chips({
		{"Players", "TargetPlayers"}, {"NPCs", "TargetNPCs"},
		{"Team check (Aim)", "TeamCheck"}, {"Wall check", "WallCheck"},
	})
	cycle("Target priority", "Priority", {"Crosshair", "Distance", "Lowest HP"})
	chips({{"Visibility from head", "VisFromHead"}})

	section("CHECKS")
	chips({{"Invuln check", "CheckInvuln"}, {"Flash check", "CheckFlash"}, {"Smoke check", "CheckSmoke"}})

	section("ФИЛЬТР NPC ПО ИМЕНИ")
	AIM.frow = row(tgt, 40, 6, nextOrder())
	AIM.fmode = button(AIM.frow, "", {Size = O(70, 40), LayoutOrder = 1})
	AIM.ftext = new("TextBox", {
		Size = U(1, -76, 1, 0), BackgroundColor3 = C.Input, LayoutOrder = 2,
		Text = CFG.NpcText, PlaceholderText = "имена через запятую", TextColor3 = C.W,
		PlaceholderColor3 = C.Mut, FontFace = GM, TextSize = 12, ClearTextOnFocus = false,
	}, AIM.frow)
	Skin.field(AIM.ftext)
	local function paintFilter()
		local off = CFG.NpcFilter == "Off"
		AIM.fmode.Text = CFG.NpcFilter
		AIM.fmode.TextColor3 = off and C.Mut or C.W
	end
	on(AIM.fmode.Activated, function()
		local order = {"Off", "Only", "Hide"}
		CFG.NpcFilter = order[(table.find(order, CFG.NpcFilter) or 1) % 3 + 1]
		paintFilter()
		updAll()
	end)
	on(AIM.ftext.FocusLost, function()
		CFG.NpcText = AIM.ftext.Text
		parseWords()
		updAll()
	end)
	paintFilter()
	table.insert(refreshers, function() paintFilter(); AIM.ftext.Text = CFG.NpcText end)
	note("Only — только совпавшие, Hide — скрыть совпавших. Работает для NPC.", 28)

	section("TARGET MODELS / МОДЕЛИ ДЛЯ AIM И ESP")
	local modelBox = new("TextBox", {
		Size = U(1, 0, 0, 40), BackgroundColor3 = C.Input, LayoutOrder = nextOrder(),
		Text = CFG.ModelNames, PlaceholderText = "Все модели / имена через запятую", TextColor3 = C.W,
		PlaceholderColor3 = C.Mut, FontFace = GM, TextSize = 12, ClearTextOnFocus = false,
	}, tgt)
	Skin.field(modelBox)
	new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, modelBox)
	on(modelBox.FocusLost, function()
		CFG.ModelNames = modelBox.Text
		pruneModels()
		scanModels()
		updAll()
	end)
	table.insert(refreshers, function() if not modelBox:IsFocused() then modelBox.Text = CFG.ModelNames end end)
	AIM.modelPick = button(tgt, "Выбрать модель: все", {Size = U(1, 0, 0, 40), LayoutOrder = nextOrder()})
	AIM.modelPick.TextTruncate = Enum.TextTruncate.AtEnd
	local function paintModelPick()
		AIM.modelPick.Text = CFG.ModelNames:match("^%s*$") and "Выбрать модель: все" or ("Модель: " .. CFG.ModelNames)
	end
	on(AIM.modelPick.Activated, function()
		local paths, seen = {}, {}
		local function add(m)
			if m and m:IsDescendantOf(Workspace) and not seen[m] then
				seen[m] = true
				table.insert(paths, m:GetFullName())
			end
		end
		for _, player in Players:GetPlayers() do if player ~= LP then add(player.Character) end end
		for m in npcs do add(m) end
		table.sort(paths)
		local current = table.find(paths, CFG.ModelNames) or 0
		CFG.ModelNames = current < #paths and paths[current + 1] or ""
		modelBox.Text = CFG.ModelNames
		pruneModels()
		scanModels()
		updAll()
		paintModelPick()
	end)
	paintModelPick()
	table.insert(refreshers, paintModelPick)
	on(modelBox.FocusLost, paintModelPick)
	note("Кнопка перебирает найденные модели. Или введи имена/полный путь через запятую; пусто — все. Включи NPC отдельно в папках Targets и ESP.", 40)

	-- ---------- Trigger: триггербот и multipoint ----------
	tgt, ord = api.triggerPage or scroll, 0
	section("TRIGGERBOT")
	chips({
		{"Triggerbot", "Trigger", nil, "Стреляет сам, когда цель в прицеле, в хитбоксе или рядом с прицелом (Aim не нужен). Статус — в Debug HUD"},
	})
	slider("Trigger delay (sec)", "TriggerDelay", 0, 0.5, 0.01, 2)
	slider("Trigger tolerance (% of screen)", "TriggerR", 0.5, 15, 0.5, 1)

	section("MULTIPOINT")
	chips({{"Multipoint", "Multipoint", nil, "Ищет видимую точку по краям хитбокса"}})
	note("Части тела, на которые переходить, если выбранная закрыта:", 28)
	chips({{"Edges (края)", "MPEdges"}, {"Head", "MPHead"}, {"Torso", "MPTorso"}, {"Arms", "MPArms"}, {"Legs", "MPLegs"}})

	-- ---------- Hitbox: попадания, размеры, вид и приоритет частей тела ----------
	tgt, ord = api.hitboxPage or scroll, 0
	section("HITBOX")
	chips({
		{"Hitbox", "Hitbox", nil, "Расширяет попадание по всему телу цели (сервер ограничивает размер)"},
		{"Head hitbox", "HeadHitbox", nil, "Расширяет попадание по голове цели"},
	})
	slider("Hitbox size (studs)", "HitboxSize", 0, HB_BODY_MAX, 0.25, 2)
	slider("Head hitbox size (studs)", "HeadHitboxSize", 0, HB_HEAD_MAX, 0.25, 2)

	section("HITBOX ESP")
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
		note("Только вид: цвета, прозрачность, заливка и обводка не меняют размеры хитбоксов и попадания. Размеры - ползунки Hitbox size / Head hitbox size.", 40)
	end

	section("BODY PART PRIORITY")
	note("Первая включённая часть - основная. Кнопки: ★ сделать основной, ▲▼ очередь; переключатель - вкл/выкл. Основная закрыта - цель берётся на следующую доступную часть.", 40)
	AIM.partPaint = {}
	local function partsChanged()
		V4.normalizeParts(A)
		NX.gen += 1
		for _, fn in AIM.partPaint do fn(true) end
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
		local _, mp = cycleCard(tgt, "Main part", nextOrder(),
			function() return V4.NAMES[A.TargetPart] or A.TargetPart end,
			function()
				local i = table.find(V4.SLOTS, A.TargetPart) or 0
				partMain(V4.SLOTS[i % #V4.SLOTS + 1])
			end)
		table.insert(refreshers, mp)
		table.insert(AIM.partPaint, mp)
	end
	chips({
		{"Auto fallback", "PartFallback", function(v) A.PartFallback = v; NX.gen += 1 end, "Основная часть закрыта - цель на следующую доступную"},
		{"Return to main", "PartReturn", function(v) A.PartReturn = v; NX.gen += 1 end, "Основная часть снова доступна - вернуться к ней"},
	})
	AIM.partBase = ord
	ord += 9 -- 8 рядов частей тела: LayoutOrder = partBase + место в очереди
	for _, slot in ipairs(V4.SLOTS) do
		local f = new("Frame", {Size = U(1, 0, 0, 40), BackgroundColor3 = C.Card}, tgt)
		rr(f, 8)
		outline(f)
		local sw, swPaint = makeSwitch(f)
		sw.AnchorPoint, sw.Position = V2(0, 0.5), U(0, 8, 0.5, 0)
		local rankLbl = new("TextLabel", {
			Size = O(18, 40), Position = O(66, 0), BackgroundTransparency = 1, Text = "", TextColor3 = C.Mut,
			FontFace = GB, TextSize = 11, Active = false,
		}, f)
		local nameLbl = new("TextLabel", {
			Size = U(1, -202, 1, 0), Position = O(86, 0), BackgroundTransparency = 1, Text = V4.NAMES[slot], TextColor3 = C.W,
			FontFace = GM, TextSize = 12, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, Active = false,
		}, f)
		local hit = new("TextButton", {Size = O(64, 40), BackgroundTransparency = 1, Text = "", AutoButtonColor = false}, f)
		local starBtn, paintStar = Skin.iconAction(f, "Star", 0, {Name = "Primary", Size = O(32, 28), AnchorPoint = V2(1, 0.5), Position = U(1, -80, 0.5, 0), TextSize = 14})
		local upBtn, paintUp = Skin.iconAction(f, "Next", -90, {Name = "MoveUp", Size = O(32, 28), AnchorPoint = V2(1, 0.5), Position = U(1, -44, 0.5, 0), TextSize = 12})
		local dnBtn, paintDown = Skin.iconAction(f, "Next", 90, {Name = "MoveDown", Size = O(32, 28), AnchorPoint = V2(1, 0.5), Position = U(1, -8, 0.5, 0), TextSize = 12})
		local function paint(anim)
			local isOn = A.PartOn[slot] == true
			local rank = partRank(slot)
			f.LayoutOrder = AIM.partBase + rank
			swPaint(isOn, anim)
			local n = 0
			for _, s in ipairs(A.PartOrder) do
				if A.PartOn[s] then n += 1 end
				if s == slot then break end
			end
			local isMain = isOn and A.TargetPart == slot
			rankLbl.Text = not isOn and "·" or (isMain and "★" or tostring(n))
			rankLbl.TextColor3 = isMain and C.Acc or C.Mut
			nameLbl.TextColor3 = isOn and C.W or C.Mut
			paintStar(isMain and C.Acc or C.Mut, anim)
			paintUp(rank <= 1 and C.Hi or C.W, anim)
			paintDown(rank >= #A.PartOrder and C.Hi or C.W, anim)
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
		table.insert(AIM.partPaint, paint)
	end
	AIM.resetParts = button(tgt, "Reset body part priority", {Size = U(1, 0, 0, 40), LayoutOrder = nextOrder()})
	on(AIM.resetParts.Activated, function()
		A.PartOrder, A.PartOn, A.TargetPart = deepCopy(DEF.AIM.PartOrder), deepCopy(DEF.AIM.PartOn), DEF.AIM.TargetPart
		partsChanged()
	end)

	-- ---------- FOV: круг, его вид, положение, динамический радиус и анимация цели ----------
	-- Размер круга = область выбора цели. Позиция круга (CircleX/Y) не связана с точкой наведения (AimX/Y),
	-- пока выключено «Circle = aim area»: двигается только рисунок.
	do
		tgt, ord = api.fovPage or scroll, 0
		section("VISIBILITY")
		chips({
			{"FOV circle", "ShowFOV", nil, "Показывать круг, пока Aim включён"},
			{"Fill circle", "FovFill", nil, "Заливка внутри круга"},
			{"Highlight on target", "FovTarget", nil, "Круг зеленеет, когда цель захвачена"},
		})
		-- Вид круга: карточки с живым превью, как в референсе (Glow / Gradient / Dashed / Classic).
		-- Превью рисуется теми же приёмами, что и сам круг: градиент, пунктир, мягкое свечение.
		section("CIRCLE STYLE")
		do
			local styles = {
				{key = "Glow", label = "Glow"},
				{key = "Gradient", label = "Gradient"},
				{key = "Dashed", label = "Dashed"},
				{key = "Classic", label = "Classic"},
			}
			local srow2 = row(tgt, 64, 6, nextOrder())
			local paintStyle
			local cards = {}
			for i, st in ipairs(styles) do
				local b = new("TextButton", {Size = U(0.25, -5, 1, 0), BackgroundColor3 = C.Card,
					BackgroundTransparency = 0.15, AutoButtonColor = false, LayoutOrder = i, Text = ""}, srow2)
				rr(b, 9)
				local strokeObj = outline(b, OUT.Hover)
				local dot = new("Frame", {Size = O(32, 32), AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.38),
					BackgroundColor3 = C.W, BackgroundTransparency = 1}, b)
				rr(dot, 20)
				local ring = new("Frame", {Size = O(26, 26), AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.38),
					BackgroundTransparency = 1}, b)
				rr(ring, 14)
				local ringStroke = new("UIStroke", {Color = C.W, Thickness = 2, Transparency = 0.35}, ring)
				-- превью: у каждого стиля своя подача
				if st.key == "Glow" then
					dot.BackgroundTransparency, dot.Size = 0.82, O(34, 34)
					ringStroke.Transparency = 0.1
				elseif st.key == "Gradient" then
					dot.BackgroundTransparency = 0.55
					dot.Size = O(30, 30)
					new("UIGradient", {Color = ColorSequence.new(C.Acc, C.W), Rotation = 45}, dot)
					ringStroke.Transparency = 0
					ringStroke.Thickness = 2.5
				elseif st.key == "Dashed" then
					dot.Visible = false
					ringStroke.Transparency = 0
					ringStroke.Thickness = 2
					-- пунктир: четыре короткие дуги по кругу
					for q = 0, 3 do
						local seg = new("Frame", {Size = U(0.28, 0, 0, 2.5), AnchorPoint = V2(0.5, 0.5),
							Position = U(0.5 + math.cos(math.rad(q * 90)) * 0.5, 0.5 + math.sin(math.rad(q * 90)) * 0.5, 0, 0),
							BackgroundColor3 = C.W, BackgroundTransparency = 0.15, Rotation = q * 90}, ring)
						rr(seg, 2)
					end
					ringStroke.Transparency = 1
				else
					dot.Visible = false
					ringStroke.Transparency = 0.05
					ringStroke.Thickness = 2
				end
				new("TextLabel", {Size = U(1, 0, 0, 16), Position = U(0, 0, 1, -18), BackgroundTransparency = 1,
					Text = st.label, TextColor3 = C.Mut, FontFace = GM, TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Center, Active = false}, b)
				cards[st.key] = {btn = b, stroke = strokeObj, label = b:FindFirstChildOfClass("TextLabel")}
				connect(b.Activated, function()
					A.FovStyle = st.key
					paintStyle()
				end)
			end
			paintStyle = function()
				for k, c in cards do
					local on = (A.FovStyle == k)
					c.stroke.Color = on and C.Acc or PURE
					c.stroke.Transparency = on and 0 or OUT.Hover
					c.stroke.Thickness = on and 2 or 1
					c.label.TextColor3 = on and C.W or C.Mut
				end
			end
			paintStyle()
			table.insert(refreshers, paintStyle)
		end
		section("SIZE AND LOOK")
		do
			-- Размер задаётся в пикселях: одно и то же число даёт одинаковый круг на любом телефоне.
			-- FovR (% от экрана) остаётся для Dynamic FOV и обновляется сам, чтобы оба режима были согласованы.
			local _, paint = sliderCard(tgt, "FOV Size (diameter, px)", nextOrder(), 40, 1400,
				function() return A.FovPx end,
				function(v)
					A.FovPx = math.floor(v + 0.5)
					local short = math.min(SP.vp.X, SP.vp.Y)
					if short and short > 2 then A.FovR = math.clamp(A.FovPx * 0.5 / short * 100, 2, 60) end
				end,
				function(v) return string.format("%d px", math.floor(v + 0.5)) end,
				1)
			table.insert(refreshers, paint)
		end
		slider("FOV Transparency", "FovAlpha", 0, 1, 0.05, 2)
		slider("FOV Thickness", "CircleThick", 0.5, 6, 0.5, 1)
		slider("Fill Transparency", "FovFillAlpha", 0, 1, 0.02, 2)

		-- цвет круга: рядом с размером и прозрачностью, потому что это тоже внешний вид
		section("FOV COLOR")
		local FOVCOL = {{0, 0, 0.94}, {0.33, 0.75, 0.9}, {0, 0.8, 0.95}, {0.52, 0.8, 1}, {0.14, 0.85, 1}, {0.8, 0.6, 1}}
		local srow = row(tgt, 40, 8, nextOrder())
		local fovPicker, fovRefresh
		for i, p in FOVCOL do
			local b = Skin.swatch(srow, i, #FOVCOL, Color3.fromHSV(p[1], p[2], p[3]))
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
		note("Размер в пикселях: один и тот же круг на любом экране. Он же задаёт область выбора цели. Позиция круга — только визуал, пока он не связан с точкой наведения.", 40)

		section("DYNAMIC FOV")
		chips({
			{"Dynamic FOV", "DynFov", nil, "Радиус круга и выбора цели меняется с дистанцией до цели"},
			{"Invert (far = bigger)", "DynInvert", nil, "Выкл: ближе - больше радиус; вкл: дальше - больше"},
		})
		cycleKeep("Change mode", "DynMode", {"Smooth", "Linear"})
		-- Dynamic FOV живёт в процентах: его шкала зависит от дистанции, а не от размера круга
		slider("Min radius, % of screen", "DynMin", 2, 60, 1, 0)
		slider("Max radius, % of screen", "DynMax", 2, 60, 1, 0)
		slider("Start distance (studs)", "DynNear", 0, 1000, 5, 0)
		slider("Max-change distance (studs)", "DynFar", 10, 2000, 10, 0)
		slider("Smoothing (higher = smoother)", "DynSmooth", 0, 0.95, 0.05, 2)
		NX.radLbl = new("TextLabel", {
			Size = U(1, 0, 0, 34), BackgroundTransparency = 1, TextWrapped = true, LayoutOrder = nextOrder(), Text = "",
			TextColor3 = C.W, FontFace = GM, TextSize = 11, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top,
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
				and not o:IsDescendantOf(og) and not o:IsDescendantOf(gui) and not o:IsDescendantOf(AIM.probeGui)
				and chainVisible(o) then
				local n = o.Name:lower()
				if n:find("crosshair") or n:find("reticle") or AIM.CS:HasTag(o, "Crosshair") then
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
			offset = AIM.GuiService:GetGuiInset() - AIM.probe.AbsolutePosition
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
		-- без Dynamic FOV радиус берётся из пикселей (FovPx), с ним — из процентов, которые считает dynStep
		local rPx = (A.DynFov or NX.dynBack) and (NX.dynR * 0.01 * short) or math.max(2, A.FovPx * 0.5)
		SP.fov, SP.silent, SP.lock = rPx, A.SilentR * 0.01 * short, A.LockR * 0.01 * short
		SP.aim = resolveAimPoint(v)
		SP.circle = A.CircleFollow and SP.aim or V2(v.X * A.CircleX, v.Y * A.CircleY)
		return true
	end

	-- ВИЗУАЛ: только читает SP, ничего в логике не меняет
	local function drawOverlay(now)
		local v = SP.vp
		local showCircle = editing or (A.Enabled and A.ShowFOV) or now < AIM.testUntil or (AIM.previewFov and A.ShowFOV)
		-- Появление круга: он «расходится» из точки наведения масштабом и только затем живёт обычной жизнью.
		-- Размер по-прежнему задаётся в px (через UIScale), поэтому совпадение с областью не теряется.
		local circleOn = showCircle and (AIM.previewFov or editing or A.Enabled or now < AIM.testUntil)
		if showCircle and not fov.Visible then
			if CFG.Anim and UICFG.AnimPulse and circleOn then
				if not fovSc then fovSc = new("UIScale", {Scale = 0.6}, fov) end
				fovSc.Scale = 0.6
				fovStroke.Transparency = 1
				tween(fovSc, TWEEN.pop, {Scale = 1})
				tween(fovStroke, TWEEN.ui, {Transparency = 0.35})
			elseif fovSc then
				fovSc.Scale = 1
			end
		end
		setp(fov, "Visible", showCircle)
		if showCircle then
			-- квадрат в пикселях: ширина всегда равна высоте, при любом разрешении и соотношении сторон
			local d = math.max(4, 2 * SP.fov)
			setp(fov, "Size", O(d, d))
			setp(fov, "Position", S(SP.circle.X / v.X, SP.circle.Y / v.Y))
			if fovSc and fovSc.Scale > 1.001 then fovSc.Scale = 1 end
			-- ===== стиль круга: Glow / Gradient / Dashed / Classic =====
			-- Все элементы стиля — дети круга, поэтому двигаются и масштабируются вместе с ним.
			local style = A.FovStyle or "Gradient"
			local accent = A.FovTarget and currentTarget and C.Acc or nil
			local line = accent or A.FovCol and hsv(A.FovCol) or C.W
			local thick = math.max(0.5, A.CircleThick or 1.5)
			local alpha = math.clamp(1 - (A.FovAlpha or 0.35), 0, 1)
			-- если настройки сохранились неполными, ключа может не быть: тогда анимация ДОЛЖНА быть включена,
			-- иначе градиент замирает под 45° и стили выглядят одинаково
			local animate = (A.FovAnim ~= false) and (CFG.Anim ~= false)

			-- сначала гасим всё, что относится к другим стилям: лишние объекты не должны мигать
			fovGlow.Visible = (style == "Glow")
			for _, ring in fovHalo do ring.f.Visible = (style == "Glow") end
			local dashed = (style == "Dashed")
			for _, seg in AIM.fovDash do seg.Visible = dashed end
			if fovGrad then fovGrad.Enabled = (style == "Gradient") end

			if style == "Glow" then
				-- Glow: тонкая яркая линия + мягкий ореол из концентрических контуров,
				-- «дыхание» яркости — видно, что это свечение, а не просто рамка
				local breathe = animate and (0.82 + 0.18 * math.sin(now * 2.2)) or 1
				setp(fov, "BackgroundTransparency", 1)
				fovStroke.Color = line
				fovStroke.Thickness = math.max(1, thick * 0.8)
				fovStroke.Transparency = math.clamp(1 - alpha * 0.55 * breathe, 0, 1)
				AIM.fovGlowStroke.Color = line
				AIM.fovGlowStroke.Thickness = thick * 3
				AIM.fovGlowStroke.Transparency = math.clamp(1 - alpha * 0.85 * breathe, 0.1, 1)
				for _, ring in fovHalo do
					ring.st.Color = line
					ring.st.Thickness = thick * (1.6 + ring.k * 1.5)
					ring.st.Transparency = math.clamp(1 - alpha * (0.34 - ring.k * 0.055) * breathe, 0.25, 1)
				end
			elseif style == "Dashed" then
				-- Dashed: 24 сегмента по окружности, вращаются; линия и заливка круга выключены
				setp(fovStroke, "Transparency", 1)
				setp(fov, "BackgroundTransparency", 1)
				local spin = animate and (now * 0.6) or 0
				for i, seg in AIM.fovDash do
					local ang = ((i - 1) / DASH_N) * math.pi * 2 + spin
					seg.Size = O(math.max(3, thick * 4), math.max(1.5, thick))
					seg.Position = U(0.5 + math.cos(ang) * 0.5, 0.5 + math.sin(ang) * 0.5)
					seg.Rotation = math.deg(ang) + 90
					seg.BackgroundColor3 = line
					seg.BackgroundTransparency = math.clamp(1 - alpha, 0, 1)
				end
			elseif style == "Gradient" then
				-- Gradient: обводка переливается — цвет бежит по кругу (вращение градиента)
				local showFill = A.FovFill
				setp(fov, "BackgroundTransparency", showFill and math.clamp(1 - (A.FovFillAlpha or 0.9), 0, 1) or 1)
				setp(fovStroke, "Transparency", math.clamp(1 - alpha, 0, 1))
				fovStroke.Thickness = thick
				fovStroke.Color = Color3.new(1, 1, 1)
				fovStrokeGrad = fovStrokeGrad or new("UIGradient", {Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, line),
					ColorSequenceKeypoint.new(0.35, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(0.6, line),
					ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
				})}, fovStroke)
				fovGrad = fovStrokeGrad
				fovGrad.Enabled = true
				-- вращение: угол растёт со временем (0.35 оборота в секунду), при выключенной
				-- анимации — фиксированные 45°, чтобы круг не «дёргался»
				fovGrad.Rotation = animate and ((now * 125) % 360) or 45
			else
				-- Classic: ровная линия выбранного цвета, без переливов и сегментов
				local showFill = A.FovFill
				setp(fov, "BackgroundTransparency", showFill and math.clamp(1 - (A.FovFillAlpha or 0.9), 0, 1) or 1)
				setp(fovStroke, "Transparency", math.clamp(1 - alpha, 0, 1))
				fovStroke.Thickness = thick
				fovStroke.Color = line
			end
		else
			fovGlow.Visible = false
			for _, ring in fovHalo do ring.f.Visible = false end
			for _, seg in AIM.fovDash do seg.Visible = false end
			if fovGrad then fovGrad.Enabled = false end
		end
		local showMark = editing or (A.Enabled and A.ShowFOV and not A.CircleFollow) or now < AIM.testUntil
		aimMark.Visible = showMark
		if showMark then aimMark.Position = S(SP.aim.X / v.X, SP.aim.Y / v.Y) end
		-- Маркер «дышит», когда наводка держит цель: видно, что aimbot реально за кем-то следит.
		-- Пока цели нет — маркер спокойный, без лишних кадров.
		local hasT = currentTarget ~= nil
		if hasT ~= markHot then
			markHot = hasT
			if CFG.Anim and UICFG.AnimPulse then
				tween(aimMark, TWEEN.ui, {Size = O(hasT and 22 or 16, hasT and 22 or 16)})
				tween(AIM.markBar1, TWEEN.ui, {BackgroundColor3 = hasT and C.Acc or C.On})
				tween(AIM.markBar2, TWEEN.ui, {BackgroundColor3 = hasT and C.Acc or C.On})
			else
				aimMark.Size = O(hasT and 22 or 16, hasT and 22 or 16)
				AIM.markBar1.BackgroundColor3, AIM.markBar2.BackgroundColor3 = hasT and C.Acc or C.On, hasT and C.Acc or C.On
			end
		end
	end

	-- Проверка на устройстве: кнопка Check coordinates (вкладка Aim)
	runSelfTest = function()
		AIM.testUntil = os.clock() + 3
		if fovSc then fovSc.Scale = 1 end -- проверка измеряет реальный радиус: анимация появления не должна её сбивать
		task.spawn(function()
			task.wait(0.3) -- пусть цикл отрисует круг и движок пересчитает AbsolutePosition
			if not updateSpace() then AIM.selfLabel.Text = "Экран ещё не готов, повтори" return end
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
			AIM.selfLabel.Text, AIM.selfLabel.TextColor3 = text, ok and C.On or C.Off
			print("[Enkaisy] " .. text:gsub("\n", " | "))
		end)
	end

	setEditing = function(s)
		if s == editing then return end
		editing = s
		AIM.editLayer.Visible, editBar.Visible = s, s
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
				if plr ~= LP and not isTeammate(plr) and plr.Character and RIG.matches(plr.Character) then fn(plr.Character) end
			end
		end
		if A.TargetNPCs then
			for m in npcs do if m.Parent and RIG.matches(m) then fn(m) end end
			for m in tagged do
                if m:IsA("Model") and m:IsDescendantOf(Workspace) and not npcs[m] and m ~= LP.Character and RIG.matches(m) then fn(m) end
            end
		end
	end

	-- ближайшая к прицелу цель (опорная дистанция для Dynamic FOV, пока цель не выбрана); пересчёт ~8 раз в секунду
	NX.nearest = function(now)
		if now - NX.nearT < 0.12 then return NX.nearD end
		NX.nearT, NX.nearD = now, nil
		local best = math.max(A.DynMin, A.DynMax) * 0.01 * math.min(SP.vp.X, SP.vp.Y)
		local camPos = camera.CFrame.Position
		eachTarget(function(model)
			local root = RIG.root(model)
			if not RIG.alive(model) or not root or model == LP.Character then return end
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
			local clouds = AIM.CS:GetTagged("SmokeCloud")
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
		return inst and RIG.fromPart(inst)
	end

	local function getTargetPart(model)
		if not model or not model:IsA("Model") or model == LP.Character then return nil end
		if not RIG.matches(model) or not RIG.alive(model) then return nil end
        local player = Players:GetPlayerFromCharacter(model)
        if player then
            if player == LP or not A.TargetPlayers or isTeammate(player) then return nil end
        elseif not A.TargetNPCs then
            return nil
        end
		local part = NX.resolve(model) -- v4.0 Body Part Priority: основная часть, затем запасные по очереди
		if not part or not passChecks(model, part) then return nil end
		return part
	end

	local function getLead()
		return A.AutoPredict and autoLead or A.Prediction
	end

	-- ===== Multipoint: ищем видимую точку по краям хитбокса (голова, плечи) =====
	AIM.scanCache = setmetatable({}, {__mode = "k"})
	AIM.GROUPS = {
		Head = {"Head"},
		Torso = {"UpperTorso", "LowerTorso", "Torso", "HumanoidRootPart"},
		Arms = {"LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "Left Arm", "Right Arm"},
		Legs = {"LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot", "Left Leg", "Right Leg"},
	}
	AIM.GROUP_ORDER = {{"Head", "MPHead"}, {"Torso", "MPTorso"}, {"Arms", "MPArms"}, {"Legs", "MPLegs"}}
	AIM.EDGES = {{0, 0, 0}, {0.4, 0, 0}, {-0.4, 0, 0}, {0, 0.4, 0}, {0, -0.4, 0}}
	AIM.CENTER = {{0, 0, 0}}
	-- порядок: выбранная часть (центр + края), затем включённые запасные части тела.
	-- Если выбрана голова, а видны только ноги и включено "MP legs", прицел уйдёт на ноги.
	local function scanPoint(model, part)
		local now = os.clock()
		local c = AIM.scanCache[model]
		if c and c.part == part and now - c.t < 0.05 then return c.pos end
		local origin = eyePos()
		local pts = {}
		local function add(p, offsets)
			local cf, sz = p.CFrame, p.Size
			for _, o in offsets do table.insert(pts, cf * Vector3.new(o[1] * sz.X, o[2] * sz.Y, o[3] * sz.Z)) end
		end
		add(part, A.MPEdges and AIM.EDGES or AIM.CENTER)
		for _, g in AIM.GROUP_ORDER do
			if A[g[2]] then
				local offs = (A.MPEdges and (g[1] == "Head" or g[1] == "Torso")) and AIM.EDGES or AIM.CENTER
				for _, name in AIM.GROUPS[g[1]] do
					local p = model:FindFirstChild(name)
					if p and p:IsA("BasePart") and p ~= part then add(p, offs) end
				end
			end
		end
		-- качество: сначала точки ближе к прицелу — они чаще открыты и дают менее «кривой» угол,
		-- края хитбокса проверяются следом (раньше порядок был произвольным)
		local keyed = {}
		for _, pt in pts do
			local sp = camera:WorldToViewportPoint(pt)
			table.insert(keyed, {pt = pt, d = (V2(sp.X, sp.Y) - SP.aim).Magnitude})
		end
		table.sort(keyed, function(a, b) return a.d < b.d end)
		for i, k in keyed do pts[i] = k.pt end
		local found
		for _, pt in pts do
			local r = Workspace:Raycast(origin, pt - origin, rayParams)
			if r and r.Instance:IsDescendantOf(model) then
				found = pt
				break
			end
		end
		AIM.scanCache[model] = {t = now, part = part, pos = found}
		return found
	end

	-- ===== v4.0 Body Part Priority =====
	-- Очередь: A.PartOrder + A.PartOn; основная часть = первая включённая (A.TargetPart всегда равен ей).
	-- Часть "доступна", если существует и (при Wall check) видна: тогда при закрытой основной берётся следующая.
	-- Выбор кэшируется на 0.06 с на модель (лучи не летят на каждый вызов); любая смена настроек сбрасывает кэш (NX.gen).
	AIM.partState = setmetatable({}, {__mode = "k"})
	local function slotPart(model, slot)
		for _, n in ipairs(V4.ALIAS[slot]) do
			local p = RIG.part(model, n)
			if p then return p end
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
		local st = AIM.partState[model]
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
		if not chosen then chosen, chosenRank = RIG.root(model), 99 end
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
		AIM.partState[model] = st
		return chosen
	end

	-- ===== Кинематика цели =====
	-- Скорость и ускорение берутся из ИЗМЕНЕНИЯ ПОЗИЦИИ (сглаженно), а не только из AssemblyLinearVelocity:
	-- у чужих персонажей на клиенте она часто равна 0 или шумит (CFrame-движение, интерполяция) — поэтому предикт «не работал».
	-- Холодный старт (цель ещё не отслеживалась) берёт скорость движка; дальше работает трекер.
	AIM.trk = setmetatable({}, {__mode = "k"})
	local function trackPart(part)
		local now, pos = os.clock(), part.Position
		local k = AIM.trk[part]
		local ev = part.AssemblyLinearVelocity
		if ev.Magnitude > 150 then ev = Vector3.zero end
		if not k then
			k = {p = pos, t = now, v = ev, a = Vector3.zero, warm = false, hist = {{t = now, p = pos}}}
			AIM.trk[part] = k
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
		-- короткая история позиций: по ней считаем скорость, устойчивую к просадкам FPS
		-- (однокадровый raw на лагающем телефоне дёргался и давал «перелёт» упреждения)
		local hist = k.hist or {}
		table.insert(hist, {t = now, p = pos})
		while #hist > 1 and now - hist[1].t > 0.12 do table.remove(hist, 1) end
		k.hist = hist
		local first = hist[1]
		local span = now - first.t
		local nv = raw
		if span > 0.03 then
			local avg = (pos - first.p) / span
			if avg.Magnitude < 220 then
				-- смесь мгновенной и усреднённой скорости: резкий старт виден сразу, шум давится
				nv = raw:Lerp(avg, 0.55)
			end
		end
		nv = k.v:Lerp(nv, 1 - math.exp(-dt / 0.05))
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
		local lead = getLead() * (A.LeadMul / 100) -- LeadMul: подстроить упреждение под игру, не меняя пинг
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
	AIM.ADV_FLIGHT_LEAD = false
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
		local g, lead = Workspace.Gravity, getLead() * (A.LeadMul / 100)
		local useFlight = AIM.ADV_FLIGHT_LEAD and hasSpeed
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
				-- пока цель «своя», радиус удержания не меньше круга: удержание не зависит от того,
				-- насколько далеко она успела уйти (раньше при Sticky → 1 цель терялась на краю круга)
				currentDistance = evaluate(model, currentTarget, nil, true)
			end
		end
		bestPart = nil
		bestDistance = currentDistance and (currentDistance * math.min(A.Sticky, 1)) or SP.fov
		if not bestDistance or bestDistance < SP.fov then bestDistance = SP.fov end
		-- StickTime: пока цель молодая, никакая другая её не перебивает (антидребезг между двумя рядом)
		local hold = currentTarget and targetSince and (os.clock() - targetSince < A.StickTime)
		if hold then
			local model = humModel(currentTarget)
			if model and evaluate(model, currentTarget, nil, false) then return currentTarget end
		end
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
		local fr = fireRemote or GLB.ReplicatedStorage:FindFirstChild(GLB.REMOTE_NAME)
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
			if not RIG.alive(model) then return end
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
		local root = RIG.root(m)
		if not RIG.alive(m) or not root then return nil end
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
			local root = m.Parent and RIG.root(m)
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
							local pad = isHead and (h > 0 and h or b) or b -- ровно как в rayModelHitbox
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
	local lastTrigger, seenSince, seenModel, lastWarm = setmetatable({}, {__mode = "k"}), nil, nil, 0
	local trigStatus = "off"
	local fireTool -- присваивается ниже (= shoot)
	local silentTarget -- определена ниже (нужна triggerbot'у)
	local function trigValid(model)
		if not model or not model:IsA("Model") or not RIG.matches(model) then return false, "model filtered" end
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
		-- дальность триггера = Range самого оружия (Aim max distance к триггеру больше не применяется:
		-- из-за него оружие с Range 800 молча не стреляло дальше 500 студов)
		local range = tool:GetAttribute("Range")
		if type(range) ~= "number" or range ~= range or range <= 0 or range == math.huge then range = 500 end
		range = math.clamp(range, 1, 5000)
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
		if now - (lastTrigger[tool] or 0) < cd * 1.06 then trigStatus = "cooldown" return end
		bindRemote()
		if tool:GetAttribute("Damage") ~= nil and fireRemote then
			-- встроенное оружие (Damage + ремоут): выстрел через сервер
			local ok, w = fireTool(tool, aimPart)
			if ok then lastTrigger[tool] = now trigStatus = "FIRE (" .. how .. ")" else trigStatus = w or "blocked" end
		else
			-- у оружия нет Damage или нет ремоута: нажимаем родное действие инструмента
			lastTrigger[tool] = now
			local okA = pcall(tool.Activate, tool)
			trigStatus = okA and ("FIRE Activate (" .. how .. ")") or "Activate failed"
		end
	end

	-- ===== Silent Aim: направление выстрела меняется только в момент выстрела, камера не двигается =====
	-- SilentFOV в пикселях, а сервер режет отклонение по углу: переводим угол сервера в px
	local function silentRadius()
		local fr = fireRemote or GLB.ReplicatedStorage:FindFirstChild(GLB.REMOTE_NAME)
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
		-- качество: если наводка уже держит цель в радиусе silent, пуля летит в неё же —
		-- камера и выстрел больше не «спорят» из-за разных целей (частая причина промахов)
		if A.Enabled and currentTarget and currentTarget.Parent then
			local cm = humModel(currentTarget)
			if cm and evaluate(cm, currentTarget, rad) then return currentTarget end
		end
		-- иначе берём цель, чья точка ПОПАДАНИЯ ближе всего к прицелу, а не чей центр в круге:
		-- у крупной цели у края круга точка тела реально ближе, и выстрел точнее
		local best, bestScore = nil, math.huge
		local function try(model)
			local part = getTargetPart(model)
			if not part then return end
			if not evaluate(model, part, rad, true) then return end
			local pos = getAimPoint(part)
			local sp, on = camera:WorldToViewportPoint(pos)
			if not on then return end
			local d = (V2(sp.X, sp.Y) - SP.aim).Magnitude
			local dist = (pos - camera.CFrame.Position).Magnitude
			-- оценка: близость к прицелу + небольшая поправка на дистанцию (у равных — ближняя цель)
			local score = d + dist * 0.02
			if score < bestScore then best, bestScore = part, score end
		end
		eachTarget(try)
		return best
	end

	-- встроенное оружие: Tool с атрибутом Damage
	AIM.hooked = setmetatable({}, {__mode = "k"})
	local lastSent, shotsSent = setmetatable({}, {__mode = "k"}), 0 -- [Tool] = время последнего выстрела
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
		if t - (lastSent[tool] or 0) < cd * 1.05 then return false, "cooldown" end
		local origin = head.Position
		-- куда реально смотрит прицел (SP.aim), а не mouse.Hit; свой персонаж исключён через rayParams
		-- RCS: если включён, целимся по прицелу до отдачи — пуля не уходит вверх вместе с камерой
		local ray = rcsAimRay()
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
		lastSent[tool] = t
		if A.Rcs then
			-- RCS: прицел до выстрела и остаток отдачи, который затем гасится в кадре
			rcsRef = {cf = camera.CFrame, t = t}
			rcsPulse(tool)
		end
		shotsSent += 1
		local hbB, hbH = hbPads()
		fireRemote:FireServer(tool, origin, shotDir, aimDir, hbB, hbH)
		return true
	end
	fireTool = shoot
	local function hookTool(inst)
		if AIM.hooked[inst] or not inst:IsA("Tool") then return end
		AIM.hooked[inst] = true
		connect(inst.Activated, function()
			if inst:GetAttribute("Damage") ~= nil then shoot(inst) end
		end)
	end
	local function watch(container)
		for _, child in container:GetChildren() do hookTool(child) end
		connect(container.ChildAdded, hookTool)
	end
	AIM.backpack = LP:FindFirstChildOfClass("Backpack")
	if AIM.backpack then watch(AIM.backpack) end
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
			AIM.xyLabel.Text = string.format("экран %.0f×%.0f | aim: %.0f, %.0f | круг: %.0f, %.0f (%s)",
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
				if pt ~= currentTarget then targetSince = pt and os.clock() or nil end
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
		if not aimPt then camLag = nil end -- цель потеряна: следующий захват начнёт с реальной камеры
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

		-- HUD: при появлении — пружина, при смене цифр — мягкое «дыхание», а не дёргание каждый кадр
		local hudOn = A.DebugHUD and (A.Enabled or A.Trigger) and not editing
		if hudOn ~= hud.Visible then
			hud.Visible = hudOn
			if hudOn and CFG.Anim and UICFG.AnimPulse then
				local base = UICFG.UIScale
				hud.TextTransparency = 1
				if hudSc then hudSc.Scale = base * 0.94 end
				tween(hud, TWEEN.ui, {TextTransparency = 0})
				tween(hud, TWEEN.ui, {BackgroundTransparency = 0.08})
				if hudSc then spring(hudSc, {Scale = base}, TWEEN.pop) end
			end
		end
		if hud.Visible then
			local name, dist = "none", 0
			if currentTarget then
				local model = humModel(currentTarget)
				name = model and model.Name or currentTarget.Name
				dist = (currentTarget.Position - camera.CFrame.Position).Magnitude
			end
			local off = aimPt and (aimPt - currentTarget.Position).Magnitude or 0
			local line = string.format("target: %s | %dm | lead %dms%s%s%s | off %.1fst | pick %.2fms | shots %d", name, math.floor(dist + 0.5),
				math.floor(getLead() * 1000 + 0.5), A.AutoPredict and " auto" or "", A.AdvPredict and " adv" or "",
				(A.Rcs and (" | RCS " .. math.floor(A.RcsStrength * 100 + 0.5) .. "%" .. (A.RcsSuppress and " no-kick" or "")) or "")
				.. (lockedModel and " | LOCK" or "") .. (A.Trigger and (" | trig: " .. trigStatus) or "")
				.. (os.clock() - srvT < 4 and (" | srv: " .. srvCode) or ""), off, pickMs, shotsSent)
			if A.DynFov then line ..= string.format(" | fov %.1f%%", NX.dynR) end
			if hud.Text ~= line then
				hud.Text = line
				-- мягкое «дыхание»: прозрачность кратко падает и возвращается (только при смене строки)
				if CFG.Anim and hud.Visible then
					TS:Create(hud, TweenInfo.new(0.05), {TextTransparency = 0.35}):Play()
					task.delay(0.06, function()
						if hud.Parent and hud.Visible then TS:Create(hud, TweenInfo.new(0.12), {TextTransparency = 0}):Play() end
					end)
				end
			end
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
		local step = angle * smoothAlpha(angle, dt)
		-- качество: мёртвая зона в ЭКРАННЫХ пикселях, предел скорости и плавное догоняние камеры.
		-- При Smoothness = 1 движение остаётся мгновенным, как раньше.
		local deadPx = smooth < 1 and A.SmoothDeadPx or 0.2
		if smooth < 1 then
			local sp, on = camera:WorldToViewportPoint(aimPt)
			if on and (V2(sp.X, sp.Y) - SP.aim).Magnitude < deadPx then return end
			step = clampStep(step, dt)
		end
		local cf = camera.CFrame
		if not camLag then camLag = cf end
		-- лаг обновляем долей от кадра: при Smoothness 1 камера идёт за мышью/игрой почти мгновенно
		-- при Smoothness < 1 камера догоняет реальный поворот долей SmoothCamFollow
		local follow = smooth < 1 and camFollow() or 1
		camLag = camLag:Lerp(cf, follow)
		-- Shake: продолжение того же поворота (камера уже на цели) плюс небольшое дрожание.
		-- Дрожание сидит поверх поворота, поэтому при Shake = 0 прицел идёт ровно по цели.
		local stepCF = camLag * CFrame.fromAxisAngle(axis.Unit, step)
		if A.Shake > 0 then
			local amp = math.rad(A.Shake)
			local t = os.clock()
			-- шум фильтруем по кадру: резких скачков нет, прицел «дышит» а не дёргается
			local k = 1 - math.exp(-math.clamp(dt, 0, 0.1) / 0.12)
			shakePrev = shakePrev + ((math.noise(t * 7) * 0.5 + math.noise(t * 9 + 13) * 0.5) - shakePrev) * k
			shakeOff = CFrame.fromEulerAnglesYXZ(shakePrev * amp, (math.noise(t * 5 + 31) - 0.5) * amp * 0.6, 0)
		elseif shakeOff ~= CFrame.new() then
			shakeOff = CFrame.new()
		end
		camera.CFrame = stepCF * shakeOff
	end)

	-- ===== RCS: отдельный шаг после наводки, чтобы Smoothness и возврат отдачи не спорили =====
	pcall(function() RS:UnbindFromRenderStep("EnkaisyRCS") end)
	RS:BindToRenderStep("EnkaisyRCS", Enum.RenderPriority.Camera.Value + 2, function(dt)
		camera = Workspace.CurrentCamera
		if not camera then return end
		local okR, eR = pcall(rcsStep, os.clock(), dt)
		if not okR then
			if not NX.warnR then NX.warnR = true warn("[Enkaisy] RCS error: " .. tostring(eR)) end
			rcsReset()
		end
	end)
	-- выгрузка снимает шаг вместе с остальными соединениями модуля
	table.insert(aconns, {Disconnect = function() pcall(function() RS:UnbindFromRenderStep("EnkaisyRCS") end) end})

	return {
		overlay = og,
		preview = function(on) AIM.previewFov = on and true or false end,
		cancelEdit = function() if editing then setEditing(false) end end,
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
			pcall(function() RS:UnbindFromRenderStep("EnkaisyRCS") end)
			rcsReset()
			for _, c in aconns do c:Disconnect() end
			table.clear(aconns)
			clearHbVis()
			og:Destroy()
			AIM.probeGui:Destroy()
			quick:Destroy()
		end,
	}
end
