-- ЧАСТЬ: главное окно и запуск. Отдельный кусок — свой лимит 200.
return {run = function(env)
	local gui, stop, startMain, keyScreen = env.gui, env.stop, env.startMain, env.keyScreen
	local function startMain()
		local PW, PH = DEF.UI.PanelW, DEF.UI.PanelH
		local HDR, RAIL, TABH, TGAP = Skin.Header, Skin.Rail, Skin.Tab, 2
		local CY = HDR + 40
		local PAGE_SIZE = U(1 - RAIL, -Skin.RailBase - 26, 1, -(CY + 9))
		local function pagePos(dx) return U(RAIL, Skin.RailBase + Skin.Inset + (dx or 0), 0, CY) end
		local cascadeGen = setmetatable({}, {__mode = "k"}) -- поколение каскада на страницу
		-- Каскад карточек: строки страницы проявляются сверху вниз по очереди, а не появляются разом.
		-- Проявление элемента: UIScale работает у ЛЮБОГО GuiObject (GroupTransparency есть только у CanvasGroup,
		-- запись этого свойства в обычный Frame — ошибка рантайма). Масштаб не влияет на раскладку списка.
		local function appear(o, delay)
			if not (CFG.Anim and UICFG.AnimPages) or not o.Parent then return end
			task.delay(delay or 0, function()
				if not o.Parent then return end
				local sc = o:FindFirstChild("AppearScale")
				if not sc then
					sc = new("UIScale", {Name = "AppearScale", Scale = 0.94}, o)
				else
					sc.Scale = 0.94
				end
				spring(sc, {Scale = 1}, TWEEN.pop)
			end)
		end
		-- Каскад карточек: строки страницы «подпрыгивают» друг за другом сверху вниз.
		local function cascade(f)
			if not (CFG.Anim and UICFG.AnimPages) then return end
			local gen = (cascadeGen[f] or 0) + 1 -- быстрые переключения: старый каскад уступает новому
			cascadeGen[f] = gen
			local i = 0
			for _, c in f:GetChildren() do
				if c:IsA("GuiObject") then
					i += 1
					if i > 20 then break end
					local my = gen
					local delay = math.min(0.22, (i - 1) * 0.018)
					task.delay(delay, function()
						if cascadeGen[f] ~= my then return end
						appear(c)
						-- название карточки печатается одновременно с её появлением: текст «собирается» на глазах
						local title = c:FindFirstChild("Title")
						if title and title:IsA("TextLabel") and title.Text ~= "" then
							revealText(title, title.Text, {step = 0.012, dur = 0.3, particles = 2})
						end
					end)
				end
			end
		end
		-- Один каталог определяет порядок, подписи, старые поисковые термины и имена пиктограмм.
		-- Порядок папок повторяет путь игрока: что подсвечивать → по кому → как целиться → чем стрелять → круг → хитбоксы → цвета.
		-- Похожие настройки всегда стоят рядом внутри своей папки (Smoothness + Sticky, Triggerbot + его ползунки и т.д.).
		local folders = {
			{id = "Main", title = "ESP", keywords = "ESP targets display sizes opacity limits filters friends distance"},
			{id = "Targets", keywords = "AIM targets players NPC team wall priority checks models filter"},
			{id = "Aim", keywords = "AIM assist smoothness sticky predict lock silent radius aim point diagnostics", ownScroll = true},
			{id = "Trigger", keywords = "AIM triggerbot multipoint delay tolerance edges head torso arms legs"},
			{id = "FOV", keywords = "AIM circle look size position dynamic animation"},
			{id = "Hitbox", keywords = "AIM hitbox head size ESP visual preset body part priority"},
			{id = "Color", keywords = "ESP palette team colors for every element"},
			{id = "Players", keywords = "ESP mark hide per-player look", ownScroll = true},
			{id = "Visual", title = "Performance", keywords = "SETTINGS update rate effects low-end preset"},
			{id = "Appearance", keywords = "SETTINGS window transparency theme accent reset"},
		}
		local repaints = {}
		local closeDetail
		local applyUIAll
		local dialog -- модальное окно справки и подтверждений (собирается ниже)
		local bgFrames = {}
		local curTab = "Main"
		-- Поиск: функции объявлены ниже (после сборки страниц), но нужны обработчику папок.
		local searchTerms, nearestIn, showHit

		-- кнопка-логотип (когда меню свёрнуто)
		local openBtn = new("TextButton", {
			Size = O(44, 44), AnchorPoint = V2(1, 0),
			Position = U(1, -16, 0, 80), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Visible = false,
		}, gui)
		GLB.floatScales[new("UIScale", {Scale = UICFG.UIScale}, openBtn)] = true
		local _, openStroke = logo(44, openBtn)
		hoverable(openBtn, openStroke, {base = OUT.Window})

		-- окно (CanvasGroup: Menu Transparency = GroupTransparency, плавное появление)
		local panel = new("CanvasGroup", {
			Name = "MainWindow", Size = O(UICFG.PanelW, UICFG.PanelH), AnchorPoint = V2(0.5, 0.5), GroupTransparency = 1,
			Position = U(0.5, 0, 0.5, 0), BackgroundColor3 = C.Win, Visible = false, Active = true, ZIndex = 20,
		}, gui)
		rr(panel, 14)
		local panelStroke = outline(panel, OUT.Window)
		table.insert(bgFrames, panel)
		local scale = new("UIScale", {}, panel)
		-- фон-картинка: лежит под всем содержимым (ZIndex 0), обрезается скруглением окна
		local FIT_TYPES = {Crop = Enum.ScaleType.Crop, Fit = Enum.ScaleType.Fit, Stretch = Enum.ScaleType.Stretch}
		local bgImg = new("ImageLabel", {
			Name = "BgImage", Size = S(1, 1), BackgroundTransparency = 1, Image = "", Visible = false, Active = false, ZIndex = 0,
			ScaleType = FIT_TYPES[UICFG.BgImgFit] or Enum.ScaleType.Crop, ImageTransparency = UICFG.BgImgAlpha,
		}, panel)

		local titleBar = Skin.header(panel)
		table.insert(bgFrames, titleBar)
		local espDot = Skin.badge(titleBar, "ESP", 138, 46, true)
		local aimDot = Skin.badge(titleBar, "AIM", 190, 46, true)
		Skin.badge(titleBar, "v" .. GLB.BUILD .. " · Mobile", 242, 78)
		local chrome = {}
		chrome.min = Skin.iconButton(titleBar, "Min", 66)
		chrome.max, chrome.maxIcon = Skin.iconButton(titleBar, "Max", 36)
		chrome.restoreIcon = icon("Restore", chrome.max, 14)
		chrome.restoreIcon.Visible = false
		chrome.close = Skin.iconButton(titleBar, "Close", 6)

		-- Сначала ужимаем раскладку до минимального рабочего размера и только затем
		-- масштабируем её целиком. На телефоне широкий макет не превращается в миниатюру.
		local function fit()
			local a = gui.AbsoluteSize
			return math.max(0.1, math.min(UICFG.MenuScale, (a.X - 16) / WIN_MIN_W, (a.Y - 16) / WIN_MIN_H))
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
			if chrome.maximized then
				fx, fy = 0.5, 0.5
			elseif UICFG.PanelCX < 0 then
				fx, fy = 1 - (16 + w / 2) / gs.X, 0.5
			else
				fx, fy = UICFG.PanelCX, UICFG.PanelCY
			end
			local cx, cy = fx * gs.X, fy * gs.Y
			local mx, my = 6 + w / 2, 6 + h / 2
			cx = gs.X - 12 < w and gs.X / 2 or math.clamp(cx, mx, gs.X - mx)
			cy = gs.Y - 12 < h and gs.Y / 2 or math.clamp(cy, my, gs.Y - my)
			writeCenter(cx / gs.X, cy / gs.Y)
		end
		local function commitPanel() saveCenter(); clampPanel(); saveCenter() end
		local function updateCols()
			local cw = winW * (1 - RAIL) - Skin.RailBase - 36
			applyGridCols(cw >= 600 and 2 or 1)
		end
		local function applySize()
			if gui.AbsoluteSize.X < 50 or gui.AbsoluteSize.Y < 50 then return end
			local loW, loH, hiW, hiH = sizeLimits()
			winW = chrome.maximized and hiW or math.clamp(math.floor(UICFG.PanelW + 0.5), loW, hiW)
			winH = chrome.maximized and hiH or math.clamp(math.floor(UICFG.PanelH + 0.5), loH, hiH)
			panel.Size = O(winW, winH)
			updateCols()
			clampPanel()
		end

		-- ручка в правом нижнем углу (зона касания 36x36, рисунок — треугольник из точек) и плашка с размером
		local grip = new("TextButton", {
			Name = "ResizeGrip", Size = O(36, 36), AnchorPoint = V2(1, 1), Position = U(1, 0, 1, 0),
			BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 30,
		}, panel)
		function chrome.maximize(state)
			chrome.maximized = state
			chrome.maxIcon.Visible, chrome.restoreIcon.Visible, grip.Visible = not state, state, not state
			applySize() -- сохранённый размер/центр не меняются при разворачивании
		end
		on(chrome.max.Activated, function() chrome.maximize(not chrome.maximized) end)
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
			BackgroundColor3 = C.Card, Text = "", TextColor3 = C.W, FontFace = GB, TextSize = 11, Visible = false, Active = false, ZIndex = 29,
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
			tween(panelStroke, fast, {Transparency = OUT.Window})
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
			tween(panelStroke, fast, {Transparency = OUT.Active})
		end)
		on(grip.MouseEnter, function() if not rs.act then paintGrip(true) end end)
		on(grip.MouseLeave, function() if not rs.act then paintGrip(false) end end)

		local isOpen = false
		local pages, ptabs -- заполняются ниже; setOpen трогает вкладки для пульсации акцента
		local function setOpen(s)
			isOpen = s
			local k = fit()
			if s then applySize() end
			if aim then aim.preview(s and curTab == "FOV") end
			if s then
				openBtn.Visible, panel.Visible = false, true
				for n, t in ptabs do pulse(t.tile, n == curTab and 0.05 or nil) end
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
				for _, t in ptabs do pulse(t.tile, nil) end
			end
		end
		on(gui:GetPropertyChangedSignal("AbsoluteSize"), function()
			if panel.Visible and isOpen then scale.Scale = fit() end
			applySize()
			clampGui(openBtn)
		end)

		-- Плоский список папок, как у референса: плитка со знаком слева и одна выделенная строка.
		-- Поиск и телеметрия закреплены снизу; на коротком экране прокручиваются только папки.
		local side = new("Frame", {Name = "Sidebar", Size = U(RAIL, Skin.RailBase, 1, -HDR), Position = O(0, HDR), BackgroundColor3 = C.Side}, panel)
		table.insert(bgFrames, side)
		new("Frame", {Size = U(0, 1, 1, 0), Position = U(1, -1, 0, 0), BackgroundColor3 = C.Line}, side)
		local tabsHolder = new("ScrollingFrame", {
			Name = "Folders", Size = U(1, -10, 1, -93), Position = O(6, 10), BackgroundTransparency = 1,
			ScrollBarThickness = 2, ScrollBarImageColor3 = C.Mut, ScrollBarImageTransparency = 0.65,
			CanvasSize = O(0, #folders * (TABH + TGAP)), ScrollingDirection = Enum.ScrollingDirection.Y,
			ElasticBehavior = Enum.ElasticBehavior.Never,
		}, side)
		local search = new("TextBox", {
			Name = "Search", Size = U(1, -20, 0, 28), Position = U(0, 10, 1, -77), BackgroundColor3 = C.Card,
			Text = "", PlaceholderText = "Поиск", TextColor3 = C.W, PlaceholderColor3 = C.Mut,
			FontFace = GM, TextSize = 12, TextXAlignment = XL, ClearTextOnFocus = false,
		}, side)
		Skin.field(search)
		new("UIPadding", {PaddingLeft = UDim.new(0, 29), PaddingRight = UDim.new(0, 24)}, search)
		-- Кнопка очистки: появляется, только когда в поле есть текст. Раньше приходилось стирать по символу.
		local clearBtn = new("TextButton", {Name = "SearchClear", Size = O(20, 20), AnchorPoint = V2(1, 0.5),
			Position = U(1, -14, 1, -63), BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
			Visible = false, ZIndex = 24}, side)
		icon("Close", clearBtn, 10, C.Mut)
		on(clearBtn.Activated, function()
			search.Text = ""
			if CFG.Anim then spring(clearBtn, {Size = O(20, 20)}, TWEEN.pop) end
		end)
		local searchIcon = icon("Search", side, 13)
		searchIcon.Position = U(0, 25, 1, -63)
		local empty = new("TextLabel", {Size = U(1, -8, 0, 38), Position = O(4, 0), BackgroundTransparency = 1, TextWrapped = true,
			Text = "Ничего не найдено", TextColor3 = C.Mut, FontFace = GR, TextSize = 12, Visible = false}, tabsHolder)

		local pTitle = new("TextLabel", {
			Size = U(1 - RAIL, -Skin.RailBase - 54, 0, 24), Position = U(RAIL, Skin.RailBase + 42, 0, HDR + 9), BackgroundTransparency = 1, Text = "",
			TextColor3 = C.W, FontFace = GB, TextSize = 18, TextXAlignment = XL,
		}, panel)
		pages, ptabs = {}, {}
		local function paintTab(t, sel, anim)
			t.selected = sel
			t.headIcon.Visible = sel
			t.h.locked, t.h.over, t.h.pressed = sel, false, false
			put(t.button, {BackgroundTransparency = sel and 0 or 1}, anim)
			put(t.st, {Transparency = sel and OUT.Idle or 1}, anim)
			put(t.label, {TextColor3 = sel and C.W or C.Mut}, anim)
			put(t.tile, {BackgroundColor3 = sel and C.Acc or C.Card}, anim)
			t.paintIcon(sel and C.AccTx or C.Mut, anim)
			-- активная вкладка мягко пульсирует (только когда меню открыто и анимации включены)
			pulse(t.tile, sel and isOpen and 0.05 or nil)
		end
		local function show(n)
			if not ptabs[n] then n = "Main" end
			curTab, UICFG.Tab = n, n
			local newTitle = ptabs[n].label.Text
			local shown = pTitle:GetAttribute("Shown")
			if shown ~= newTitle then
				pTitle:SetAttribute("Shown", newTitle)
				-- Название папки печатается по буквам: короткое, поэтому успевает за 0.2–0.4 с.
				-- Если анимации выключены, typeText просто ставит текст.
				revealText(pTitle, newTitle, {step = 0.026, dur = 0.36, particles = 3})
				if CFG.Anim and UICFG.AnimText then
					-- вместе с текстом мягко проявляется сама строка, чтобы смена папки читалась
					pTitle.Position = U(RAIL - 4, Skin.RailBase + 42, 0, HDR + 9)
					tween(pTitle, TWEEN.ui, {Position = U(RAIL, Skin.RailBase + 42, 0, HDR + 9)})
				end
			end
			if aim then aim.preview(isOpen and n == "FOV") end
			local tab = ptabs[n].button
			local y = tab.AbsolutePosition.Y - tabsHolder.AbsolutePosition.Y
			local overflow = y + tab.AbsoluteSize.Y - tabsHolder.AbsoluteSize.Y
			if y < 0 or overflow > 0 then
				tabsHolder.CanvasPosition = V2(0, math.max(0, tabsHolder.CanvasPosition.Y + (y < 0 and y or overflow)))
			end
			for k, f in pages do
				local sel = k == n
				if sel and not f.Visible and CFG.Anim then
					f.Position, f.Visible = pagePos(8), true
					tween(f, slow, {Position = pagePos()})
					cascade(f)
				else
					f.Visible = sel
					if sel then f.Position = pagePos() end
				end
				local t = ptabs[k]
				if t.selected ~= sel then paintTab(t, sel, t.selected ~= nil) end
			end
		end
		for i, folder in folders do
			local n = folder.id
			local tb = new("TextButton", {
				Name = n, Size = U(1, -5, 0, TABH), Position = O(2, (i-1) * (TABH + TGAP)), BackgroundColor3 = C.Sel,
				BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
			}, tabsHolder)
			rr(tb, 8)
			local st = outline(tb, 1)
			local tile = new("Frame", {Size = O(24, 24), Position = U(0, 7, 0.5, 0), AnchorPoint = V2(0, 0.5), BackgroundColor3 = C.Card}, tb)
			rr(tile, 6, 8)
			local _, icPaint = icon(n, tile, 15)
			local headIcon = icon(n, panel, 18, C.W)
			headIcon.Position, headIcon.Visible = U(RAIL, Skin.RailBase + 24, 0, HDR + 21), false
			local lbl = new("TextLabel", {
				Size = U(1, -49, 1, 0), Position = O(39, 0), BackgroundTransparency = 1, Text = folder.title or n, TextColor3 = C.Mut,
				FontFace = GM, TextSize = 13, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, Active = false,
			}, tb)
			local dot = new("Frame", {Size = O(4, 4), AnchorPoint = V2(1, 0.5), Position = U(1, -6, 0.5, 0),
				BackgroundColor3 = C.W, BackgroundTransparency = 1, Active = false}, tb)
			round(dot, 2)
			-- бейдж стоит левее точки «включено» (та занимает правые 4 px), поэтому они не перекрываются
			local hitsBadge = new("TextLabel", {Name = "Hits", Size = O(26, 16), AnchorPoint = V2(1, 0.5), Position = U(1, -14, 0.5, 0),
				BackgroundColor3 = C.Sel, BackgroundTransparency = 1, Text = "", TextColor3 = C.Mut, FontFace = GM,
				TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center, Visible = false, Active = false}, tb)
			rr(hitsBadge, 5)
			ptabs[n] = {button = tb, st = st, tile = tile, label = lbl, dot = dot, headIcon = headIcon, paintIcon = icPaint,
				hits = hitsBadge, h = hoverable(tb, st, {base = 1})}
			local pg
			if not folder.ownScroll then
				pg = new("ScrollingFrame", {
					Name = n .. "Page", Size = PAGE_SIZE, Position = pagePos(), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
					ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 2, ScrollBarImageColor3 = C.Mut, ScrollBarImageTransparency = 0.6,
					CanvasSize = U(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
				}, panel)
				-- отступы, чтобы тонкие обводки карточек не обрезались краем прокрутки
				new("UIPadding", {
					PaddingLeft = UDim.new(0, 2), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), PaddingRight = UDim.new(0, 8),
				}, pg)
			else
				pg = new("Frame", {Name = n .. "Page", Size = PAGE_SIZE, Position = pagePos(), BackgroundTransparency = 1, Visible = false}, panel)
			end
			new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, pg)
			pages[n] = pg
			on(tb.Activated, function()
				-- при активном поиске папка ведёт к ближайшему совпадению в ней, а не к началу страницы
				show(n)
				if #searchTerms() > 0 then
					local i = nearestIn(n)
					if i then showHit(i) end
				end
			end)
		end

		table.insert(repaints, function()
			for n, t in ptabs do paintTab(t, n == curTab, false) end
		end)

		-- индикаторы «включено»: шапка (ESP / AIM) и точки на вкладках; обновляются из frame() раз в 0.1 с, только при изменении
		local stCache = {}
		local function flag(key, v, apply)
			v = v and true or false
			if stCache[key] == v then return end
			stCache[key] = v
			apply(v)
		end
		statusFn = function()
			flag("hESP", CFG.On, function(o) espDot.BackgroundColor3 = o and C.W or C.Mut end)
			flag("hAIM", AIMCFG.Enabled, function(o) aimDot.BackgroundColor3 = o and C.W or C.Mut end)
			-- точки не мигают прозрачностью, а «вырастают»: включённая функция заметна боковым зрением
			-- точка «вырастает» и коротко подсвечивается: включённую функцию видно и без чтения подписей
			local function dotFlag(key, on_)
				flag(key, on_, function(o)
					local d = ptabs[key == "tMain" and "Main" or key == "tAim" and "Aim" or "FOV"].dot
					d.BackgroundTransparency = 0
					popIn(d, o)
					if o and CFG.Anim and UICFG.AnimPulse then
						-- вспышка цвета: точка «моргает» один раз, затем возвращается к обычному цвету
						d.BackgroundColor3 = C.Acc
						task.delay(0.4, function()
							if d.Parent and d.BackgroundTransparency == 0 then
								tween(d, TWEEN.ui, {BackgroundColor3 = C.W})
							end
						end)
					end
				end)
			end
			dotFlag("tMain", CFG.On)
			dotFlag("tAim", AIMCFG.Enabled)
			dotFlag("tFOV", AIMCFG.Enabled and AIMCFG.ShowFOV)
		end

		new("Frame", {Size = U(1, -20, 0, 1), Position = U(0, 10, 1, -41), BackgroundColor3 = C.Line}, side)
		counterLbl = new("TextLabel", {Size = U(1, -20, 0, 16), Position = U(0, 12, 1, -38), BackgroundTransparency = 1,
			Text = "Players: 0 • NPC: 0", TextColor3 = C.Mut, FontFace = GM, TextSize = 11, TextXAlignment = XL}, side)
		statsCard = new("Frame", {Size = U(1, -20, 0, 15), Position = U(0, 12, 1, -21), BackgroundTransparency = 1, Visible = CFG.ShowStats}, side)
		statsFps = new("TextLabel", {Size = U(0.5, 0, 1, 0), BackgroundTransparency = 1,
			Text = "-- FPS", TextColor3 = C.Mut, FontFace = GM, TextSize = 10, TextXAlignment = XL}, statsCard)
		statsPing = new("TextLabel", {Size = U(0.5, 0, 1, 0), Position = S(0.5, 0), BackgroundTransparency = 1,
			Text = "-- ms", TextColor3 = C.Mut, FontFace = GM, TextSize = 10, TextXAlignment = XL}, statsCard)

		-- ===== Папка ESP (Main): что подсвечивать, как выглядит подсветка и какие цели фильтровать =====
		-- Сначала включение, затем цели, затем внешний вид, затем фильтры: папка читается сверху вниз без прыжков.
		local pm = pages.Main
		sectionLabel(pm, "ESP", 0)
		local _, paintToggle = toggleCard(pm, "Enable ESP", 1, function() return CFG.On end, function(v)
			CFG.On = v
			updAll()
		end)
		table.insert(repaints, function() paintToggle(false) end)

		sectionLabel(pm, "ЦЕЛИ ПОДСВЕТКИ", 2)
		-- сегментированный переключатель: выбранный сегмент светлее и с тонким контуром
		local segTrack = new("Frame", {Size = U(1, 0, 0, 40), BackgroundColor3 = C.Card, LayoutOrder = 3}, pm)
		rr(segTrack, 8)
		outline(segTrack)
		local segInd = new("Frame", {Size = U(1 / 3, -6, 1, -6), Position = U(0, 3, 0, 3), BackgroundColor3 = C.Sel, Active = false}, segTrack)
		rr(segInd, 6)
		outline(segInd, OUT.Hover)
		local segBtns = {}
		local function paintSeg(anim)
			local idx = table.find(GLB.MODES, CFG.Mode) or 1
			local pos = U((idx - 1) / 3, 3, 0, 3)
			if anim then tween(segInd, fast, {Position = pos}) else segInd.Position = pos end
			for i, b in segBtns do
				if anim then tween(b, fast, {TextColor3 = i == idx and C.W or C.Mut}) else b.TextColor3 = i == idx and C.W or C.Mut end
			end
		end
		table.insert(repaints, function() paintSeg(false) end)
		for i, m in GLB.MODES do
			segBtns[i] = new("TextButton", {
				Size = U(1 / 3, 0, 1, 0), Position = U((i - 1) / 3, 0, 0, 0), BackgroundTransparency = 1,
				Text = m, FontFace = GB, TextSize = 12, TextColor3 = C.Mut, AutoButtonColor = false, ZIndex = 2,
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
			{"Highlight", "Hl"}, {"Names", "Names"}, {"HP bar", "HP"}, {"HP %", "Pct"}, {"ESP box", "Box"},
			{"Team check", "TeamCheck", updAll}, {"Hide dead", "HideDead"},
			{"Rainbow", "Rainbow", refreshHL}, {"Display name", "Disp"},
		})

		-- ===== CHAMS LOOK: список стилей подсветки, как в референсе =====
		-- Каждая строка: кружок-образец (что именно даёт стиль) + название, выбранная строка
		-- подсвечивается оранжевым контуром. Стилей много, поэтому список в своей прокрутке.
		sectionLabel(pm, "CHAMS LOOK", 6.6)
		do
			local listCard = new("Frame", {Size = U(1, 0, 0, 236), BackgroundColor3 = C.Card,
				BackgroundTransparency = 0.4, LayoutOrder = 6.7}, pm)
			rr(listCard, Skin.Radius)
			outline(listCard)
			local inner = new("ScrollingFrame", {Size = U(1, -8, 1, -8), Position = O(4, 4),
				BackgroundTransparency = 1, ScrollBarThickness = 3, CanvasSize = U(0, 0, 0, 0),
				ScrollingDirection = Enum.ScrollingDirection.Y, AutomaticCanvasSize = Enum.AutomaticSize.Y}, listCard)
			new("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, inner)
			local rows = {}
			for i, st in CHAMS do
				local r = new("TextButton", {Size = U(1, -6, 0, 34), BackgroundColor3 = C.Side,
					BackgroundTransparency = 0.55, AutoButtonColor = false, LayoutOrder = i, Text = ""}, inner)
				rr(r, 9)
				local edge = outline(r, OUT.Hover)
				-- образец стиля: квадрат заливки и контур той же толщины, что будут на цели, —
				-- по строке видно, чем Solid отличается от Soft, не включая стиль.
				-- Оттенок стиля подмешан к белому, как он подмешается к цвету цели.
				-- те же формулы, что в chamsAlpha: превью не должно обещать не то, что будет на цели
				local pvFillA = math.clamp(0.45 * (2.0 - st.fill * 1.9), 0, 1)
				local pvEdgeA = math.clamp(1.0 * (1.35 - st.outline * 1.1), 0, 1)
				local swatch = new("Frame", {Size = O(18, 18), Position = U(0, 42, 0.5, 0), AnchorPoint = V2(0, 0.5),
					BackgroundColor3 = st.col and st.col:Lerp(Color3.new(1, 1, 1), 0.15) or C.W,
					BackgroundTransparency = 1 - pvFillA}, r)
				rr(swatch, 5)
				stroke(swatch, st.col or PURE, 1 - pvEdgeA, math.clamp(0.9 + st.thick, 1, 2.6))
				-- что именно делает стиль: материал тела, а не только плотность подсветки
				local MAT_TAG = {
					Neon = "neon glow", Lava = "lava", Ice = "ice", Glass = "glass", ForceField = "force field",
					Metal = "foil", Chrome = "chrome", Metallic = "metal", Diamond = "glass shine",
					Ghost = "phantom", ["Water Flow"] = "water", Iridescent = "shift", Wireframe = "neon mesh",
					Glow = "glow", Glossy = "gloss", Crystal = "crystal",
				}
				local tag = MAT_TAG[st.key]
				new("TextLabel", {Size = U(1, -110, 1, 0), Position = O(64, 0), BackgroundTransparency = 1,
					Text = st.name, TextColor3 = C.Mut, FontFace = GB, TextSize = 13, TextXAlignment = XL,
					Active = false}, r)
				if tag then
					new("TextLabel", {Size = O(70, 1), Position = U(1, -74, 0, 0), BackgroundTransparency = 1,
						Text = tag, TextColor3 = st.col or C.Mut, FontFace = GM, TextSize = 10,
						TextXAlignment = Enum.TextXAlignment.Right, Active = false}, r)
				end
				rows[st.key] = {row = r, edge = edge, label = r:FindFirstChildOfClass("TextLabel")}
				-- bind — файловый хелпер: не зависит от того, виден ли connect в этой области
				local function pick()
					CFG.Chams = st.key
					saveNow()
					refreshHL()
					updAll()
					for k, rr2 in rows do
						local sel = (k == CFG.Chams)
						rr2.edge.Color = sel and C.Acc or PURE
						rr2.edge.Transparency = sel and 0 or OUT.Hover
						rr2.edge.Thickness = sel and 2 or 1
						rr2.row.BackgroundColor3 = sel and C.Acc or C.Side
						rr2.row.BackgroundTransparency = sel and 0.86 or 0.55
						rr2.label.TextColor3 = sel and C.W or C.Mut
					end
				end
				bind(r.Activated, pick)
			end
			local function paintChams()
				for k, r in rows do
					local on = (k == (CFG.Chams or "Outline"))
					r.edge.Color = on and C.Acc or PURE
					r.edge.Transparency = on and 0 or OUT.Hover
					r.edge.Thickness = on and 2 or 1
					r.row.BackgroundColor3 = on and C.Acc or C.Side
					r.row.BackgroundTransparency = on and 0.86 or 0.55
					r.label.TextColor3 = on and C.W or C.Mut
				end
			end
			paintChams()
			table.insert(repaints, paintChams)
		end

		-- размеры и прозрачность подсветки: раньше жили в отдельной папке, теперь рядом с самим ESP
		sectionLabel(pm, "РАЗМЕР И ПРОЗРАЧНОСТЬ", 8)
		local sOrd = 11 -- порядок после списка Chams Look (он занимает 6.7)
		-- Ползунки панели ESP. Аргументы: pct = значение в долях (0..1) и проценты в подписи,
		-- fmt = своя подпись значения, step = шаг, если подпись не процентная.
		-- fmt приходит из длинного списка вызовов, поэтому неверный тип (число вместо функции)
		-- трактуем как шаг: панель не должна падать с "attempt to call a number value".
		local function slider(title, key, min, max, pct, fmt, step)
			sOrd += 1
			if type(fmt) == "number" and step == nil then fmt, step = nil, fmt end
			if type(fmt) ~= "function" then fmt = nil end
			if type(step) ~= "number" then step = nil end
			local function label(v)
				if fmt then return fmt(v) end
				if pct then return math.floor(v * 100 + 0.5) .. "%" end
				return tostring(math.floor(v + 0.5))
			end
			local _, paint = sliderCard(pm, title, sOrd, min, max,
				function() return CFG[key] end,
				function(v)
					CFG[key] = pct and v or math.floor(v + 0.5)
					refreshHL()
				end,
				label,
				step or (not pct and 1 or nil))
			table.insert(repaints, function() paint() end)
		end
		slider("Fill strength", "Fill", 0, 1, true)
		slider("Outline opacity", "Outline", 0, 1, true)
		slider("Name size", "NameSize", 10, 30)
		slider("Name length", "NameLen", 3, 20)
		slider("ESP max distance", "MaxDist", 50, DIST_MAX, false, function(v) return v >= DIST_MAX and "∞" or v .. "m" end)
		slider("Limit count", "LimitN", 1, 31)
		-- Min dist: ближе этого ESP не рисуется — вплотную рамка и подписи только мешают
		slider("Min distance (studs)", "MinDist", 0, 500, false, function(v) return v .. " m" end)

		-- фильтры целей: рядом с размерами, потому что тоже влияют только на подсветку
		sectionLabel(pm, "ФИЛЬТРЫ", 13)
		makeChips(chipGrid(pm, 14), {
			{"Distance", "Dist"}, {"HP color", "HPColor", refreshHL}, {"Limit nearest", "Limit"}, {"Hide native", "HideNative"},
		})
		local _, paintFriend = cycleCard(pm, "Friends", 15, function() return CFG.FriendMode end, function()
			local order = {"Off", "Color", "Hide"}
			CFG.FriendMode = order[(table.find(order, CFG.FriendMode) or 1) % 3 + 1]
			updAll()
		end, function() return CFG.FriendMode ~= "Off" end)
		table.insert(repaints, paintFriend)
		new("TextLabel", {
			Size = U(1, 0, 0, 28), BackgroundTransparency = 1, TextWrapped = true, LayoutOrder = 16,
			Text = "Friends: Off — как обычные цели, Color — цвет союзников, Hide — не показывать.",
			TextColor3 = C.Mut, FontFace = GM, TextSize = 10, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top,
		}, pm)

		-- ===== Страница Color =====
		local refreshPicker
		sectionLabel(pages.Color, "PALETTE", 0)
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

		-- ===== Страница Players =====
		local pp = pages.Players
		local pl = pp:FindFirstChildOfClass("UIListLayout")
		if pl then pl:Destroy() end
		local listView = new("Frame", {Size = S(1, 1), BackgroundTransparency = 1}, pp)
		new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, listView)
		local head = row(listView, 26, 6, 1)
		new("TextLabel", {
			Size = U(1, -66, 1, 0), BackgroundTransparency = 1, Text = "Tap: Mark > Hide > Off",
			TextColor3 = C.Mut, FontFace = GM, TextSize = 11, TextXAlignment = XL, LayoutOrder = 1,
		}, head)
		local clearBtn = button(head, "Clear", {Size = O(60, 26), TextSize = 11, TextColor3 = C.Mut, LayoutOrder = 2})
		local listUI = new("ScrollingFrame", {
			Size = U(1, 0, 1, -32), LayoutOrder = 2, BackgroundTransparency = 1, BorderSizePixel = 0,
			ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 2, ScrollBarImageColor3 = C.Mut, ScrollBarImageTransparency = 0.6,
			CanvasSize = U(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		}, listView)
		new("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.Name}, listUI)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 2), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), PaddingRight = UDim.new(0, 8),
		}, listUI)

		-- --- экран настроек одного игрока ---
		local detail = new("ScrollingFrame", {
			Size = S(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
			ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 2, ScrollBarImageColor3 = C.Mut, ScrollBarImageTransparency = 0.6,
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
			Size = U(1, -70, 1, 0), BackgroundTransparency = 1, Text = "", TextColor3 = C.W, FontFace = GB,
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
			local b = Skin.setting(dgrid, i, true)
			new("TextLabel", {
				Size = U(1, -88, 1, 0), Position = O(Skin.Inset, 0), BackgroundTransparency = 1, Text = d[1],
				TextColor3 = C.W, FontFace = GM, TextSize = 12, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, Active = false,
			}, b)
			triLbl[d[2]] = new("TextLabel", {
				Size = O(46, 24), AnchorPoint = V2(1, 0.5), Position = U(1, -Skin.Inset, 0.5, 0), BackgroundColor3 = C.Sel,
				FontFace = GM, TextSize = 12, Text = "Auto", TextColor3 = C.Mut, Active = false,
			}, b)
			rr(triLbl[d[2]], 6)
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
		for i, n in GLB.PCOLS do
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
		-- Переход между списком игроков и карточкой игрока: новый экран «въезжает» справа,
		-- старый коротко уходит влево. Видно, что мы внутри одной папки, а не в другом разделе.
		local function slideIn(o)
			if not (CFG.Anim and UICFG.AnimPages) then return end
			o.Position, o.Visible = U(0.03, 0, 0, 0), true -- сдвиг только по X: AbsoluteSize не меняется
			tween(o, TWEEN.ui, {Position = U(0, 0, 0, 0)})
		end
		local function slideOut(o, after)
			if not (CFG.Anim and UICFG.AnimPages) or not o.Visible then
				o.Visible = false
				o.Position = U(0, 0, 0, 0)
				if after then after() end
				return
			end
			local t = TS:Create(o, TWEEN.snap, {Position = U(-0.03, 0, 0, 0)})
			t:Play()
			t.Completed:Once(function()
				o.Visible, o.Position = false, U(0, 0, 0, 0)
				if after then after() end
			end)
		end
		closeDetail = function()
			selP = nil
			slideOut(detail, function() slideIn(listView) end)
		end
		local function openDetail(p)
			selP, pcur = p, "Fill"
			detail.CanvasPosition = V2(0, 0)
			paintDetail()
			slideOut(listView, function() slideIn(detail) end)
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
			local b = button(listUI, "", {Size = U(1, 0, 0, 48), BackgroundColor3 = C.Card, Name = p.Name:lower()})
			local acc = new("Frame", {Size = O(3, 20), Position = O(6, 14), BackgroundColor3 = C.W, BackgroundTransparency = 1, BorderSizePixel = 0, Active = false}, b)
			round(acc, 2)
			local av = new("ImageLabel", {Size = O(30, 30), Position = O(14, 9), BackgroundColor3 = C.Input, Active = false}, b)
			rr(av, 7, 10)
			local ring = stroke(av, RING, 0, 1.5)
			new("TextLabel", {
				Size = U(1, -140, 0, 18), Position = O(54, 6), BackgroundTransparency = 1, Text = p.DisplayName,
				TextColor3 = C.W, FontFace = GB, TextSize = 12, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, Active = false,
			}, b)
			local sub = new("TextLabel", {
				Size = U(1, -150, 0, 14), Position = O(54, 25), BackgroundTransparency = 1, Text = "",
				TextColor3 = C.Mut, FontFace = GM, TextSize = 10, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd, Active = false,
			}, b)
			local tag = new("TextLabel", {
				Size = O(52, 48), AnchorPoint = V2(1, 0), Position = U(1, -40, 0, 0), BackgroundTransparency = 1,
				Text = "Visible", TextColor3 = C.Mut, FontFace = GB, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right, Active = false,
			}, b)
			-- кнопка справа: персональные настройки подсветки
			local gear = Skin.iconAction(b, "Next", 0, {
				Name = "PlayerDetail", Size = O(28, 28), AnchorPoint = V2(1, 0.5), Position = U(1, -5, 0.5, 0), TextSize = 18, ZIndex = 2,
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
		sectionLabel(pv2, "PERFORMANCE", 0)
		local paintCap
		local perfChips = {
			{"Team colors", "TeamColors", function() refreshHL(); refreshRows() end},
			{"Size by dist", "DistScale"},
			-- общий выключатель обновляет и карточки эффектов: видно, что они «спят», пока анимации выключены
			{"Animations", "Anim", function() for _, fn in repaints do fn() end end},
			{"FPS / ping", "ShowStats", function() statsCard.Visible = CFG.ShowStats end},
		}

		if GLB.canFps then
			table.insert(perfChips, {"FPS unlock", "FpsUnlock", function() paintCap(); applyFps() end})
		end
		makeChips(chipGrid(pv2, 1), perfChips)
		if GLB.canFps then
			local _, p = cycleCard(pv2, "FPS cap", 2, function() return CFG.FpsCap == 0 and "Max" or CFG.FpsCap end, function()
				CFG.FpsCap = GLB.FPS_STEPS[(table.find(GLB.FPS_STEPS, CFG.FpsCap) or 1) % #GLB.FPS_STEPS + 1]
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
		-- Эффекты анимации: общий Animations выше включает всё, здесь каждый эффект гасится отдельно.
		-- Пока общий выключатель выключен, переключатели эффектов всё равно не дают картинки — это написано в подписи.
		sectionLabel(pv2, "ANIMATION EFFECTS", 3)
		for i, d in {
			{"Animated numbers", "AnimCounters", "Счётчики доезжают до нового значения."},
			{"Toasts", "AnimToasts", "Результаты и ошибки — карточкой в углу."},
			{"Page cascade", "AnimPages", "Карточки страницы проявляются сверху вниз."},
			{"Accent pulse", "AnimPulse", "Активная вкладка и точки мягко дышат."},
			{"Intro after key", "AnimIntro", "Заставка UNICRASE после ключа (3 с)."},
			{"Particle text", "AnimText", "Текст в папке собирается из искр."},
		} do
			local key = d[2]
			local card, paint = toggleCard(pv2, d[1], 3 + i * 0.1, function() return UICFG[key] end,
				function(v) UICFG[key] = v end, d[3])
			table.insert(repaints, function()
				paint(false)
				-- эффект живёт только вместе с общими анимациями: подпись карточки притухает,
				-- значение и фон не трогаем (фоном управляет прозрачность фона-картинки)
				local dim = not CFG.Anim and 0.55 or 0
				for _, c in card:GetChildren() do
					if c:IsA("TextLabel") then tween(c, TWEEN.ui, {TextTransparency = dim}) end
				end
			end)
		end
		local lowBtn = button(pv2, "Low-end preset", {Size = U(1, 0, 0, 40), LayoutOrder = 4})
		on(lowBtn.Activated, function()
			CFG.Anim, CFG.DistScale, CFG.Limit, CFG.LimitN, CFG.EspHz = false, false, true, 12, 20
			UICFG.AnimCounters, UICFG.AnimToasts, UICFG.AnimPages, UICFG.AnimPulse = false, false, false, false
			UICFG.AnimIntro, UICFG.AnimText = false, false
			for _, fn in repaints do fn() end
			notify("Low-end preset", "Анимации выключены, 12 целей, ESP 20 Гц", false)
		end)
		new("TextLabel", {
			Size = U(1, 0, 0, 40), BackgroundTransparency = 1, TextWrapped = true, LayoutOrder = 5,
			Text = "Low-end: без анимаций, 12 ближайших целей, ESP 20 Гц. Чем ниже частота ESP, тем реже обновляются подписи и HP-бары.",
			TextColor3 = C.Mut, FontFace = GM, TextSize = 10, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top,
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
			for s in GLB.floatScales do
				if not s.Parent then
					GLB.floatScales[s] = nil
				elseif not (s:GetAttribute("AnimOwned") and CFG.Anim and UICFG.AnimPulse) then
					s.Scale = UICFG.UIScale -- у HUD масштабом владеет анимация появления, иначе пружина сбивается
				end
			end
		end
		local function paintAccents()
			applyAccent()
			for inst, props in GLB.accents do
				if inst.Parent then
					for prop, token in props do inst[prop] = C[token] end
				else
					GLB.accents[inst] = nil
				end
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
			for _, k in GLB.PAL do old[C[k]:ToHex()] = k end
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
			chrome.maximize(false)
			setTheme(UICFG.Theme)
			applyLook()
			paintAccents()
			for _, fn in repaints do fn() end
		end

		-- ===== Полный сброс: выключается абсолютно всё, значения и цвета возвращаются к заводским =====
		-- Запускается только из подтверждения (раздел RESET внизу Appearance), поэтому случайно не срабатывает.
		local function fullReset()
			-- 1. ESP и общие настройки: каждый флаг OFF, числа / строки / таблицы — к значениям по умолчанию
			for k, v in DEF.CFG do
				if type(v) == "boolean" then CFG[k] = false
				elseif type(v) == "table" then CFG[k] = deepCopy(v)
				else CFG[k] = v end
			end
			-- 2. Aim целиком: наводка, Target Lock, Silent, Triggerbot, Hitbox, Dynamic FOV, анимация, HUD — OFF
			for k, v in DEF.AIM do
				if type(v) == "boolean" then AIMCFG[k] = false
				elseif type(v) == "table" then AIMCFG[k] = deepCopy(v)
				else AIMCFG[k] = v end
			end
			V4.normalizeParts(AIMCFG) -- очередь частей тела как после установки: основная = первая включённая
			-- 3. Цвета подсветки и Team Colors — заводские
			for n, t in DEF.col do
				for k, v in t do col[n][k] = v end
			end
			TC.reset()
			-- 4. Оформление окна как при первом запуске: тема, акцент, размер, фон-картинка, вкладка
			for k, v in DEF.UI do
				UICFG[k] = type(v) == "table" and deepCopy(v) or v
			end
			-- 5. Сессионные данные: метки игроков, фильтры имён моделей, редактор точки наведения
			table.clear(pset)
			table.clear(marks)
			cur = "Fill"
			if aim and aim.cancelEdit then aim.cancelEdit() end
			parseWords()
			pruneModels()
			scanModels()
			if applyUIAll then applyUIAll() end
			statsCard.Visible = CFG.ShowStats
			if closeDetail then closeDetail() end
			for _, fn in repaints do fn() end
			updAll()
			applyFps()
			saveNow()
			notify("Настройки сброшены", "Все функции выключены", false)
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
			chrome.maximize(false)
		end)
		new("TextLabel", {
			Size = U(1, 0, 0, 28), BackgroundTransparency = 1, TextWrapped = true, LayoutOrder = nextA(),
			Text = "Размер окна: тяни за правый нижний угол. Двойное касание угла — сброс.",
			TextColor3 = C.Mut, FontFace = GM, TextSize = 10, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top,
		}, pa)
		-- ----- фон окна: любая картинка по ссылке или ID -----
		-- ID / rbxassetid:// / ссылка roblox.com работают везде. Прямая ссылка (png/jpg) скачивается через request/HttpGet,
		-- сохраняется writefile и показывается через getcustomasset — это есть только в окружениях, где эти функции доступны.
		local bgToken, bgApplied, bgAsset, bgLoading = 0, UICFG.BgImage, nil, false
		local bgStatus, applyBg
		local function setBgStatus(msg, ok)
			if bgStatus then
				bgStatus.Text = msg
				bgStatus.TextColor3 = ok == true and C.W or ok == false and C.Danger or C.Mut
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
					pcall(GLB.CP.PreloadAsync, GLB.CP, {bgImg})
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
			PlaceholderText = "ссылка на картинку или ID", TextColor3 = C.W, PlaceholderColor3 = C.Mut, FontFace = GM, TextSize = 12,
			ClearTextOnFocus = false, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd,
		}, pa)
		Skin.field(bgBox)
		new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, bgBox)
		on(bgBox.FocusLost, function()
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
			TextColor3 = C.Mut, FontFace = GM, TextSize = 10, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top,
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
			local b = Skin.swatch(accRow, i, #ACC_PRESETS, Color3.fromHSV(p[1], p[2], p[3]))
			on(b.Activated, function()
				UICFG.Accent = {h = p[1], s = p[2], v = p[3]}
				accRefresh()
				accentLive()
			end)
		end
		accPicker, accRefresh = makePicker(pa, nextA(), function() return UICFG.Accent end, accentLive, nil)
		accRefresh()
		table.insert(repaints, accRefresh)

		-- ----- сброс: сначала оформление, затем полный сброс всех настроек (с подтверждением) -----
		sectionLabel(pa, "RESET / СБРОС", nextA())
		local appReset = button(pa, "Reset appearance", {Size = U(1, 0, 0, 40), LayoutOrder = nextA()}, {danger = true})
		on(appReset.Activated, function()
			for k, v in DEF.UI do UICFG[k] = type(v) == "table" and deepCopy(v) or v end
			applyUIAll()
		end)
		local fullBtn = button(pa, "Полный сброс — выключить всё", {
			Size = U(1, 0, 0, 44), LayoutOrder = nextA(), BackgroundColor3 = C.DangerBg, TextColor3 = C.W,
		}, {danger = true})
		on(fullBtn.Activated, function()
			if not dialog then return end
			dialog.confirm("Сбросить все настройки?",
				"Абсолютно все функции будут выключены: ESP, Aim, Target Lock, Silent Aim, Triggerbot, Multipoint, Hitbox и Hitbox ESP, "
					.. "Dynamic FOV, Target Animation, HUD, трассы, скелет, Team Colors, FPS unlock — всё станет OFF. "
					.. "Цвета, тема, акцент, фон-картинка, размер окна и метки игроков вернутся к заводским. Отменить это нельзя.",
				"Да, сбросить всё", true, fullReset)
		end)
		new("TextLabel", {
			Size = U(1, 0, 0, 46), BackgroundTransparency = 1, TextWrapped = true, LayoutOrder = nextA(),
			Text = "Полный сброс сначала спросит подтверждение. После него все переключатели выключены — включай только то, что нужно.",
			TextColor3 = C.Mut, FontFace = GM, TextSize = 10, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top,
		}, pa)


		-- ===== Папки Aim / Targets / Trigger / Hitbox / FOV =====
		-- Aim и FOV дополнительно несут оверлеи, а Targets, Trigger и Hitbox — обычные страницы,
		-- в которые модуль наводки складывает свои разделы (см. buildAim).
		local okA, resA = pcall(buildAim, pages.Aim, {
			menu = function(s) setOpen(s) end,
			fovPage = pages.FOV, targetsPage = pages.Targets, triggerPage = pages.Trigger, hitboxPage = pages.Hitbox,
		})
		if okA then
			aim = resA
			table.insert(repaints, aim.refresh)
		else
			warn("[Enkaisy] Aim init error: " .. tostring(resA))
		end

		dialog = helpUI.mount(panel, stop)
		on(chrome.close.Activated, dialog.unload)
		-- Подсказки статичны после сборки страниц. Индекс строится только один раз,
		-- поэтому набор текста на телефоне не обходит все карточки на каждую букву.
		local function fold(s)
			s = string.lower(s)
			return (s:gsub("[\208\209][\128-\191]", function(c)
				local n = utf8.codepoint(c)
				if n == 0x401 then return "ё" end
				if n >= 0x410 and n <= 0x42F then return utf8.char(n + 32) end
				return c
			end))
		end
		local searchIndex = {}
		for _, folder in folders do
			local n = folder.id
			local words = {n, folder.title or n, folder.keywords}
			for _, item in helpUI.items do
				if item.card:IsDescendantOf(pages[n]) then
					table.insert(words, item.title)
					if item.desc then table.insert(words, item.desc) end
					local info = helpUI.info[item.title]
					if info then table.insert(words, info[1]); table.insert(words, info[2]) end
				end
			end
			searchIndex[n] = fold(table.concat(words, " "))
		end
		-- Слова запроса ищутся по отдельности: "дистанция esp" находит папки с обоими словами,
		-- даже если они стоят в разном порядке и не рядом.
		function searchTerms()
			local out = {}
			for w in fold(search.Text):gmatch("%S+") do table.insert(out, w) end
			return out
		end
		local function matchAll(hay, terms)
			for _, w in terms do
				if not string.find(hay, w, 1, true) then return false end
			end
			return true
		end

		-- ===== Переход к совпадению и стрелки справа от страницы =====
		-- Поиск не только прячет папки без совпадений: клик по папке открывает её страницу и
		-- прокручивает к ближайшей подходящей настройке. Дальше совпадения листаются стрелками ▲▼
		-- справа от страницы (как счётчик в поиске Telegram) — они не зависят от прокрутки папок.
		local hits, hitStep = {}, 1 -- hits: {папка, карточка} в порядке обхода, hitStep: текущее совпадение
		local navUp, navDn, navCount, setNavOpen

		-- прокрутка страницы к карточке; у Aim и Players прокрутка своя, внутри страницы
		local function scrollPage(pg, card)
			if not pg or not card or not card.Parent then return end
			local target = pg
			if not pg:IsA("ScrollingFrame") then
				for _, d in pg:GetDescendants() do if d:IsA("ScrollingFrame") then target = d break end end
			end
			task.defer(function()
				if not card.Parent or not target.Parent then return end
				local y = card.AbsolutePosition.Y - target.AbsolutePosition.Y + target.CanvasPosition.Y
				-- элемент встаёт в верхнюю треть видимой области: видно и подпись, и что идёт дальше
				tween(target, fast, {CanvasPosition = V2(0, math.max(0, y - target.AbsoluteSize.Y * 0.28))})
			end)
		end
		-- короткая вспышка контура: видно, к какой именно карточке привёл поиск
		local flashes = setmetatable({}, {__mode = "k"})
		local function flash(card)
			if not card or not card.Parent then return end
			local ring = flashes[card]
			if not (ring and ring.Parent) then
				ring = new("UIStroke", {Color = C.Acc, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					LineJoinMode = Enum.LineJoinMode.Round, Transparency = 0.15}, card)
				flashes[card] = ring
			end
			ring.Transparency = 0.15
			task.delay(1.1, function()
				if ring.Parent and ring.Transparency < 1 then
					tween(ring, slow, {Transparency = 1})
				end
			end)
		end
		-- счётчик на стрелках: "3/12"; кнопки видны, только пока есть несколько совпадений
		local function paintNav()
			if not (navUp and navDn) then return end
			local any = #hits > 1
			setNavOpen(any) -- страница уступает полосу справа под стрелки
			navUp.Visible, navDn.Visible = any, any
			if navCount then navCount.Visible = any end
			if any then
				-- счётчик совпадений меняется плавно: видно, что стрелка сработала
				local newText = hitStep .. "/" .. #hits
				if navCount.Text ~= newText then
					navCount.Text = newText
					if CFG.Anim and UICFG.AnimCounters then
						tween(navCount, TWEEN.snap, {TextTransparency = 0.45})
						task.delay(0.08, function()
							if navCount.Parent then tween(navCount, TWEEN.ui, {TextTransparency = 0}) end
						end)
					end
				end
			end
		end
		function showHit(i)
			if #hits == 0 then return end
			hitStep = (i - 1) % #hits + 1
			local sig = hits[hitStep]
			if curTab ~= sig[1] then show(sig[1]) end
			scrollPage(pages[sig[1]], sig[2])
			flash(sig[2])
			paintNav()
		end
		-- ближайшее к видимой области совпадение на открытой странице (для клика по папке)
		function nearestIn(folder)
			local pg = pages[folder]
			if not pg then return nil end
			local sf = pg
			if not pg:IsA("ScrollingFrame") then
				for _, d in pg:GetDescendants() do if d:IsA("ScrollingFrame") then sf = d break end end
			end
			local mid = sf and (sf.AbsolutePosition.Y + sf.AbsoluteSize.Y * 0.35) or nil
			local best, bestD, first = nil, math.huge, nil
			for i, sig in hits do
				if sig[1] == folder then
					first = first or i
					if mid and sig[2].Parent then
						local d = math.abs(sig[2].AbsolutePosition.Y - mid)
						if d < bestD then best, bestD = i, d end
					end
				end
			end
			return best or first
		end
		-- пересчёт совпадений под запрос (список папок фильтруется отдельно, в filterTabs)
		local function refreshSearch()
			local terms = searchTerms()
			table.clear(hits)
			if #terms > 0 then
				for _, folder in folders do
					for _, it in helpUI.items do
						if it.title and it.card and it.card.Parent and it.card:IsDescendantOf(pages[folder.id]) then
							if matchAll(fold(it.title .. " " .. (it.desc or "")), terms) then
								table.insert(hits, {folder.id, it.card})
							end
						end
					end
				end
			end
			hitStep = 1
			-- текущая папка могла исчезнуть из списка: открываем первую оставшуюся
			if #terms > 0 and not (ptabs[curTab] and ptabs[curTab].button.Visible) then
				for _, folder in folders do
					if ptabs[folder.id].button.Visible then show(folder.id) break end
				end
			end
			-- во время набора по странице не прыгаем: к совпадению ведёт клик по папке или Enter
			paintNav()
		end

		-- Две стрелки и счётчик справа от страницы: ▲ предыдущее совпадение, ▼ следующее.
		-- Страница сужается на полосу, поэтому стрелки не закрывают переключатели у правого края карточек.
		local NAV_GUTTER = 32
		local navOpen = false
		setNavOpen = function(on_)
			if navOpen == on_ then return end
			navOpen = on_
			for _, pg in pages do
				pg.Size = U(1 - RAIL, -Skin.RailBase - 26 - (on_ and NAV_GUTTER or 0), 1, -(CY + 9))
			end
		end
		do
			local navW = 24
			local function navBtn(glyph, name, order)
				local b = new("TextButton", {Name = name, Size = O(navW, 24), AnchorPoint = V2(1, 0),
					Position = U(1, -5, 0, CY + 4 + order * 28), BackgroundColor3 = C.Card, Text = "",
					AutoButtonColor = false, Visible = false, ZIndex = 26}, panel)
				rr(b, 7)
				local st = outline(b)
				icon(glyph, b, 12, C.W)
				hoverable(b, st, {bg = C.Card, bgHover = C.Sel})
				return b
			end
			navUp = navBtn("Up", "SearchPrev", 0)
			navDn = navBtn("Down", "SearchNext", 1)
			navCount = new("TextLabel", {Name = "SearchCount", Size = O(NAV_GUTTER, 14), AnchorPoint = V2(1, 0),
				Position = U(1, -7, 0, CY + 4 + 2 * 28), BackgroundTransparency = 1, Text = "", TextColor3 = C.Mut,
				FontFace = GM, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center, Visible = false,
				ZIndex = 26, Active = false}, panel)
			on(navUp.Activated, function() showHit(hitStep - 1) end)
			on(navDn.Activated, function() showHit(hitStep + 1) end)
		end

		-- Папки: при запросе остаются только те, где есть совпадения (как и раньше).
		local function filterTabs()
			local terms = searchTerms()
			local y = 0
			for _, folder in folders do
				local n = folder.id
				local tab = ptabs[n].button
				local visible = #terms == 0
				if not visible then
					visible = true
					for _, w in terms do
						if not string.find(searchIndex[n], w, 1, true) then visible = false break end
					end
				end
				-- сколько совпадений внутри папки: видно, куда идти за ответом, ещё до клика
				local badge = ptabs[n].hits
				local cnt = 0
				if visible and #terms > 0 then
					for _, sig in hits do if sig[1] == n then cnt += 1 end end
				end
				local badgeText = cnt > 0 and tostring(cnt) or ""
				if badge.Text ~= badgeText then
					badge.Text = badgeText
					if CFG.Anim and cnt > 0 then
						badge.BackgroundTransparency = 0.7
						tween(badge, TWEEN.ui, {BackgroundTransparency = 0.55})
					end
				end
				badge.Visible = cnt > 0
				local wasHidden = not tab.Visible
				tab.Visible = visible
				if visible then
					if wasHidden and CFG.Anim and UICFG.AnimPages then
						appear(tab) -- найденная папка проявляется, а не возникает рывком
					end
					tab.Position = O(2, y)
					y += TABH + TGAP
				end
			end
			empty.Visible = y == 0
			tabsHolder.CanvasSize, tabsHolder.CanvasPosition = O(0, y), V2(0, 0)
		end

		-- новое совпадение по мере ввода — к нему и ведём (после того как список папок ужался)
		local function onQueryChanged()
			refreshSearch() -- сначала считаем совпадения: по ним filterTabs рисует бейджи на папках
			filterTabs()
			-- крестик очистки виден только при непустом запросе и появляется с лёгким «прыжком»
			local has = #searchTerms() > 0
			if has ~= clearBtn.Visible then
				clearBtn.Visible = has
				if has then
					clearBtn.Size = O(0, 20)
					tween(clearBtn, TWEEN.pop, {Size = O(20, 20)})
				end
			end
		end
		on(search:GetPropertyChangedSignal("Text"), onQueryChanged)
		-- Enter на клавиатуре телефона = следующее совпадение
		on(search.FocusLost, function(enter)
			if enter and #hits > 0 then
				-- первый Enter — к ближайшему совпадению, следующие — по кругу
				showHit(hitStep > 1 and hitStep + 1 or 1)
			end
		end)
		paintNav()

		-- ===== События =====
		movable(openBtn, openBtn, function() setOpen(true) end, function() clampGui(openBtn) end)
		movable(titleBar, panel, nil, commitPanel, function() return not chrome.maximized end)
		on(chrome.min.Activated, function() setOpen(false) end)
		on(LP:GetPropertyChangedSignal("Team"), function() if CFG.TeamCheck then updAll() else refreshHL() end end)
		on(RS.Heartbeat, frame)
		on(Players.PlayerAdded, track)
		on(Players.PlayerRemoving, untrack)
		on(Workspace.DescendantAdded, function(d)
	        if d:IsA("Model") or d:IsA("Humanoid") or d:IsA("BasePart") then addNpc(d) end
	    end)
	    local modelTags = game:GetService("CollectionService")
	    on(modelTags:GetInstanceAddedSignal("AimTarget"), function(d) if d:IsA("Model") then addNpc(d) end end)
	    on(modelTags:GetInstanceRemovedSignal("AimTarget"), pruneModels)

		paintToggle(false)
		paintSeg(false)
		refreshPicker()
		show(UICFG.Tab)
		applyLook()
		if UICFG.BgImage ~= "" then applyBg(UICFG.BgImage, true) end
		applyFps()
		for _, p in Players:GetPlayers() do track(p) end
		setOpen(true)
		task.spawn(function()
			local n = 0
			for _, d in Workspace:GetDescendants() do
				if not alive then return end
				if d:IsA("Model") then addNpc(d) end
				n += 1
				if n % 400 == 0 then task.wait() end
			end
		end)
	end

	-- ===== Заставка после ключа: осколки слетаются в логотип =====
	-- Чистый UI: без картинок и звука, всё внутри своего ScreenGui и удаляется целиком.
	-- Сцена ~3.1 с и её НЕЛЬЗЯ пропустить: нет обработчика касаний, фон активен и до конца
	-- держит ввод (чтобы случайное нажатие не попало в меню под заставкой).
	-- При выключенных анимациях (CFG.Anim / AnimIntro) заставки нет — экран открывается сразу.
	local INTRO_WORD = "UNICRASE"
	local INTRO_SUB = "MOBILE AIM ASSIST"
	local INTRO_LEN = 3.1
	-- Шрифт логотипа: широкий техно-гротеск Michroma. Цепочка строго через pcall:
	-- 1) семейство Michroma, 2) Enum.Font.Michroma (в старых клиентах его может не быть),
	-- 3) тяжёлый Gotham — чтобы заставка не падала никогда, что бы ни было с клиентом.
	local INTRO_FONT = Font.fromEnum(Enum.Font.GothamBlack)
	do
		local candidates = {
			function() return Font.new("rbxasset://fonts/families/Michroma.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal) end,
			function() return Font.fromEnum(Enum.Font.Michroma) end,
		}
		for _, pick in candidates do
			local ok, f = pcall(pick)
			if ok and typeof(f) == "Font" then
				INTRO_FONT = f
				break
			end
		end
	end
	local function playIntro(after)
		local done = false
		local function finish()
			if done then return end
			done = true
			if after then after() end
		end
		if not (CFG.Anim and UICFG.AnimIntro) then finish() return end
		local t0 = os.clock() -- время сцены: все эффекты считаются от него, а не от первого кадра
		local stage = new("ScreenGui", {Name = "EnkaisyIntro", ResetOnSpawn = false, DisplayOrder = 120,
			IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, LP:WaitForChild("PlayerGui"))
		pcall(function() stage.ScreenInsets = Enum.ScreenInsets.None end)
		-- фон: чёрный, активный — держит ввод до конца сцены (пропустить нельзя)
		local bg = new("Frame", {Name = "IntroBg", Size = S(1, 1), BackgroundColor3 = C.B, BackgroundTransparency = 0,
			Active = true, ZIndex = 1}, stage)
		-- виньетка: сверху и снизу мягкая тень, чтобы сцена читалась как кадр, а не как пустой экран
		local function vignette(anchorY, alignY)
			local v = new("Frame", {Size = U(1, 0, 0.34, 0), AnchorPoint = V2(0.5, anchorY), Position = S(0.5, alignY),
				BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Active = false, ZIndex = 2}, stage)
			new("UIGradient", {Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, anchorY == 0 and 0.05 or 1),
				NumberSequenceKeypoint.new(1, anchorY == 0 and 1 or 0.05),
			})}, v)
			return v
		end
		vignette(0, 0)
		vignette(1, 1)
		-- СВЕТ ИЗ ГЛУБИНЫ: холодный белый взрыв за словом (как в хромовом референсе).
		-- Десятки тонких лучей бьют из-за текста к камере, вокруг — дымка и яркое ядро.
		local LIGHT_W, LIGHT_COLD = Color3.fromRGB(255, 255, 255), Color3.fromRGB(214, 224, 240)
		local corePos = S(0.5, 0.47)

		-- Дымка: концентрические круги с падающей прозрачностью — дешёвый «bloom»
		local haze = {}
		for i = 1, 7 do
			local f = new("Frame", {Name = "Haze" .. i, Size = O(10, 10), AnchorPoint = V2(0.5, 0.5),
				Position = corePos, BackgroundColor3 = i <= 4 and LIGHT_W or LIGHT_COLD,
				BackgroundTransparency = 1, ZIndex = 2, Active = false}, stage)
			rr(f, 400)
			table.insert(haze, {f = f, k = i / 7})
		end
		-- Лучи: закреплены в точке схода за словом, растворяются к краю экрана
		local rays = {}
		for i = 1, 48 do
			local long = (i % 4 == 0)
			local ray = new("Frame", {Name = "Ray" .. i, Size = U(0, math.random(3, 10), 1, 0), AnchorPoint = V2(0.5, 0),
				Position = corePos, BackgroundColor3 = (i % 3 == 0) and LIGHT_COLD or LIGHT_W,
				BackgroundTransparency = 1, Rotation = (i - 1) * (360 / 48) + math.random(-2, 2),
				ZIndex = 3, Active = false}, stage)
			new("UIGradient", {Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, math.random(1, 8) / 100),
				NumberSequenceKeypoint.new(0.35, math.random(30, 50) / 100),
				NumberSequenceKeypoint.new(1, 1),
			}), Rotation = 90}, ray)
			table.insert(rays, {f = ray, w0 = ray.Size.X.Offset, phase = math.random() * math.pi * 2,
				boost = long and 1.4 or 1, twinkle = 0.6 + math.random() * 0.8})
		end
		-- яркое ядро в точке схода
		local core = new("Frame", {Name = "Core", Size = O(10, 10), AnchorPoint = V2(0.5, 0.5), Position = corePos,
			BackgroundColor3 = LIGHT_W, BackgroundTransparency = 1, ZIndex = 4, Active = false}, stage)
		rr(core, 200)
		-- ПЫЛЬ: мелкие точки, летящие от центра к камере — глубина кадра и «искры в луче»
		local dust = {}
		for i = 1, 34 do
			local a = math.random() * math.pi * 2
			local dot = new("Frame", {Name = "Dust" .. i, Size = O(math.random(1, 3), math.random(1, 3)),
				AnchorPoint = V2(0.5, 0.5), Position = corePos, BackgroundColor3 = LIGHT_W,
				BackgroundTransparency = 1, ZIndex = 7, Active = false}, stage)
			rr(dot, 2)
			table.insert(dust, {f = dot, a = a, k = math.random(), speed = 0.35 + math.random() * 0.8})
		end
		-- КРИСТАЛЛЫ: осколки-ромбы, летящие на камеру из глубины. Цвет — серебро с белой кромкой,
		-- поэтому они блестят на свету и дают ощущение объёма, как в референсе.
		local crystals = {}
		for i = 1, 18 do
			local a = math.random() * math.pi * 2
			local s0 = math.random(10, 26)
			local shard = new("Frame", {Name = "Crystal" .. i, Size = O(s0, s0 * 2), AnchorPoint = V2(0.5, 0.5),
				Position = S(0.5 + math.cos(a) * 0.42, 0.5 + math.sin(a) * 0.42), BackgroundColor3 = Color3.fromRGB(206, 214, 228),
				BackgroundTransparency = 1, Rotation = math.random(0, 359), ZIndex = 8, Active = false}, stage)
			-- грань ромба: скругление малым радиусом + светлый контур = гранёный кристалл
			rr(shard, 2)
			local stroke = new("UIStroke", {Color = Color3.fromRGB(255, 255, 255), Thickness = 1.5,
				Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, shard)
			new("UIGradient", {Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(0.45, Color3.fromRGB(198, 206, 220)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(96, 104, 120)),
			}), Rotation = 35}, shard)
			table.insert(crystals, {f = shard, st = stroke, a = a, k = math.random() * 0.5,
				spin = (math.random() - 0.5) * 260, size = s0, speed = 0.5 + math.random() * 0.7})
		end
		-- свечение позади слова: мягкий ореол вокруг источника
		local halo = new("Frame", {Name = "Halo", Size = S(1, 1), AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.47),
			BackgroundColor3 = LIGHT_W, BackgroundTransparency = 1, Active = false, ZIndex = 3}, stage)
		rr(halo, 400)
		local haloGrad = new("UIGradient", {Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.15), NumberSequenceKeypoint.new(1, 1),
		})}, halo)
		-- ударные кольца: две тонкие окружности, расходящиеся в момент сборки
		local rings = {}
		for i = 1, 2 do
			local r = new("Frame", {Name = "Ring" .. i, Size = O(10, 10), AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5),
				BackgroundTransparency = 1, Active = false, ZIndex = 4}, stage)
			rr(r, 300)
			local st = new("UIStroke", {Color = i == 1 and C.W or C.Acc, Thickness = i == 1 and 3 or 2,
				Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, r)
			table.insert(rings, {f = r, st = st})
		end
		-- осколки: вытянутые «стёкла» с градиентом, летят к центру, вращаясь и истончаясь
		local shards = {}
		for i = 1, 30 do
			local a = (i / 30) * math.pi * 2 + (math.random() - 0.5) * 0.22
			local tall = i % 3 ~= 0
			local w = tall and math.random(2, 4) or math.random(5, 8)
			local h = tall and math.random(16, 42) or math.random(6, 10)
			local f = new("Frame", {Name = "Shard", Size = O(w, h), AnchorPoint = V2(0.5, 0.5),
				Position = S(0.5 + math.cos(a) * 0.62, 0.5 + math.sin(a) * 0.58), BackgroundColor3 = C.W,
				BackgroundTransparency = 1, Rotation = math.deg(a), Active = false, ZIndex = 6}, stage)
			rr(f, 3)
			new("UIGradient", {Color = ColorSequence.new(C.Acc, C.W),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 0.9),
				}), Rotation = 90}, f)
			local st = outline(f, 1)
			table.insert(shards, {f = f, st = st, a = a, spin = (math.random() - 0.5) * 180,
				delay = math.random() * 0.3, dur = 0.55 + math.random() * 0.3, w = w, h = h})
		end
		-- Слово собираем БЕЗ UIListLayout и без ручного расчёта ширин.
		-- Каждый TextLabel измеряет себя сам (AutomaticSize), поэтому шрифт может быть любым:
		-- раньше ширины считались через GetTextSize, а рендерился другой шрифт — слово «плыло» вправо.
		local word = new("Frame", {Name = "Word", Size = O(0, 0), AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.47),
			BackgroundTransparency = 1, Active = false, ZIndex = 10}, stage)
		local letters = {}
		-- ХРОМ: у каждой буквы металлическая «голова» (белая кромка + серое тело + тёмный низ),
		-- глянцевая передняя грань с узким бликом и несколько копий-подложек, уходящих в глубину.
		-- Так буквы читаются как объёмный металл, как в референсе.
		local CHROME_HI, CHROME_MID, CHROME_LOW = Color3.fromRGB(255, 255, 255),
			Color3.fromRGB(186, 194, 208), Color3.fromRGB(74, 80, 92)
		local FACE_TOP, FACE_FLASH, FACE_LOW = Color3.fromRGB(236, 240, 248),
			Color3.fromRGB(255, 255, 255), Color3.fromRGB(96, 104, 118)
		local shimmer = {} -- градиенты лицевых граней: по ним бежит перелив
		local function mkLetter(ch, color, z)
			local o = new("TextLabel", {Size = O(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
				AnchorPoint = V2(0.5, 0.5), Position = O(0, 0), BackgroundTransparency = 1, Text = ch,
				TextColor3 = color, FontFace = INTRO_FONT, TextSize = 40, TextTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = z, Active = false}, word)
			return o
		end
		-- голова буквы: тело из хрома + светлая кромка сверху/по контуру
		local function chrome(ch, z)
			local o = mkLetter(ch, CHROME_MID, z)
			new("UIGradient", {Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0.00, CHROME_HI),
				ColorSequenceKeypoint.new(0.30, CHROME_MID),
				ColorSequenceKeypoint.new(0.62, CHROME_HI),
				ColorSequenceKeypoint.new(1.00, CHROME_LOW),
			}), Rotation = 90}, o)
			o.TextStrokeColor3 = CHROME_HI
			o.TextStrokeTransparency = 1
			return o
		end
		-- передняя грань: светлее и с ярким бликом посередине
		local function face(ch, z, shift)
			local o = mkLetter(ch, FACE_TOP, z)
			local g = new("UIGradient", {Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0.00, FACE_TOP),
				ColorSequenceKeypoint.new(0.34, FACE_FLASH),
				ColorSequenceKeypoint.new(0.52, FACE_LOW),
				ColorSequenceKeypoint.new(0.70, FACE_FLASH),
				ColorSequenceKeypoint.new(1.00, FACE_TOP),
			}), Rotation = 90}, o)
			table.insert(shimmer, {g = g, shift = shift})
			return o
		end
		for i = 1, #INTRO_WORD do
			local ch = INTRO_WORD:sub(i, i)
			-- подложки уходят вниз-вправо, темнея: так буква получает толщину
			local depths = {}
			for d = 4, 1, -1 do
				local shade = mkLetter(ch, CHROME_LOW, 9)
				shade.TextTransparency = 1
				table.insert(depths, {o = shade, k = d})
			end
			local body = chrome(ch, 10)
			local lbl = face(ch, 11, i * 0.6)
			local sc = new("UIScale", {Scale = 1}, lbl)
			table.insert(letters, {i = i, lbl = lbl, body = body, depths = depths, sc = sc, cx = 0, w = 0})
		end
		-- блик: белая полоса проезжает по слову на «выдержке», обрезается своим контейнером
		local shineClip = new("Frame", {Name = "ShineClip", Size = O(0, 0), AnchorPoint = V2(0.5, 0.5),
			Position = O(0, 0), BackgroundTransparency = 1, Active = false, ClipsDescendants = true, ZIndex = 12}, word)
		local shine = new("Frame", {Name = "Shine", Size = U(0.2, 0, 1, 0), AnchorPoint = V2(0.5, 0.5),
			BackgroundColor3 = C.W, BackgroundTransparency = 1, Rotation = 16, Active = false, ZIndex = 12}, shineClip)
		new("UIGradient", {Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1),
		})}, shine)
		-- подпись под словом + акцентная линия под ней
		local sub = new("TextLabel", {Name = "Sub", Size = U(1, 0, 0.05, 0), Position = S(0.5, 0.60), AnchorPoint = V2(0.5, 0),
			BackgroundTransparency = 1, Text = INTRO_SUB, TextColor3 = C.Mut, TextTransparency = 1,
			TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12}, stage)
		local rule = new("Frame", {Name = "Rule", Size = O(0, 2), AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.675),
			BackgroundColor3 = C.Acc, BackgroundTransparency = 1, Active = false, ZIndex = 12}, stage)
		rr(rule, 1)
		-- базовые размеры для кадровых эффектов (иначе умножение в кадре накапливается)
		local baseHal, baseWordW = 0, 0
		local layoutGen = 0
		-- Раскладка: задаём кегль, ждём один кадр (AutomaticSize пересчитывает ширины),
		-- читаем реальные ширины и расставляем буквы от центра. Если слово шире потолка —
		-- уменьшаем кегль и повторяем. Никаких предположений о метриках шрифта.
		local function layoutWord()
			layoutGen += 1
			local my = layoutGen
			local a = stage.AbsoluteSize
			if a.X < 50 then return end
			local maxW = math.clamp(a.X * 0.84, 140, 820)
			local h = math.clamp(math.floor(a.X * 0.185), 18, 180)
			local gap = 0
			local total = 0
			for _ = 1, 5 do
				-- кегль задаём и грани, и телу, и подложкам: иначе толщина не совпадёт с буквой
				for _, l in letters do
					l.lbl.TextSize = h
					l.body.TextSize = h
					for _, d in l.depths do d.o.TextSize = h end
				end
				-- трекинг 16% от кегля: у Michroma буквы широкие, при меньшем зазоре они слипаются
				gap = math.max(1, math.floor(h * 0.16))
				task.wait() -- кадр на пересчёт AutomaticSize
				if layoutGen ~= my or not stage.Parent then return end
				total = 0
				for _, l in letters do
					local w = l.lbl.AbsoluteSize.X
					if w <= 1 then w = h * 0.62 end -- ещё не измерилось: грубая оценка по кеглю
					l.w = w
					total += w
				end
				total += gap * math.max(0, #letters - 1)
				if total <= maxW or h <= 18 then break end
				-- шире потолка: ужимаем кегль пропорционально и пробуем снова
				h = math.max(18, math.floor(h * math.clamp(maxW / total, 0.5, 0.95)))
			end
			-- расстановка: центр каждой буквы относительно центра слова
			local depth = math.max(1, math.floor(h * 0.055)) -- толщина хрома в пикселях
			local x = -total / 2
			for _, l in letters do
				l.cx = x + l.w / 2
				l.lbl.Position = O(l.cx, 0)
				l.body.Position = O(l.cx, 0)
				l.body.TextSize = h
				for _, d in l.depths do
					d.o.TextSize = h
					d.o.Position = O(l.cx + depth * d.k, depth * d.k)
				end
				x += l.w + gap
			end
			local lineH = math.ceil(h * 1.25)
			word.Size = O(0, 0) -- размер слова не нужен: буквы позиционируются от центра
			shineClip.Size = O(total + gap * 2, lineH)
			shine.Size = O(math.max(24, h * 0.8), lineH * 2.6)
			sub.TextSize = math.clamp(math.floor(h * 0.2), 9, 20)
			sub.Size = O(total, math.ceil(h * 0.4))
			baseHal, baseWordW = total * 1.5, total
			halo.Size = O(baseHal, baseHal)
		end
		on(stage:GetPropertyChangedSignal("AbsoluteSize"), function() pcall(layoutWord) end)
		pcall(layoutWord)

		-- подпись стартует узкой: ширину задаст раскладка (иначе она растянется на весь экран)
		sub.Size = O(0, 0)
		-- стартовое состояние: буквы мельче, немного повёрнуты и прозрачны
		for _, l in letters do
			l.sc.Scale = 0.68
			l.lbl.Rotation = -7
			l.body.Rotation = -7
			for _, d in l.depths do d.o.Rotation = -7 end
		end
		-- появление букв: пружина с перелётом + проявление; вызывается из таймлайна, не из кадра
		local function revealLetter(l, delay)
			task.delay(delay, function()
				if not stage.Parent then return end
				spring(l.sc, {Scale = 1}, TWEEN.pop)
				tween(l.lbl, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
					{TextTransparency = 0, Rotation = 0})
				tween(l.body, TweenInfo.new(0.65, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
					{TextTransparency = 0, Rotation = 0})
				for _, d in l.depths do
					-- подложки выезжают из-под буквы: сначала прозрачные, потом проявляются в тени
					tween(d.o, TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
						{TextTransparency = math.clamp(0.35 + d.k * 0.1, 0, 1), Rotation = 0})
				end
				tween(l.lbl, TweenInfo.new(0.55), {TextStrokeTransparency = 0.55})
			end)
		end
		for _, l in letters do
			revealLetter(l, 1.02 + l.i * 0.055)
		end
		-- подпись и линия появляются после сборки слова
		task.delay(2.02, function()
			if not stage.Parent then return end
			tween(sub, TweenInfo.new(0.4, Enum.EasingStyle.Quint), {TextTransparency = 0})
			tween(rule, TweenInfo.new(0.35, Enum.EasingStyle.Quint), {BackgroundTransparency = 0.1, Size = O(baseWordW * 0.5, 2)})
		end)
		-- блик по слову на выдержке
		task.delay(2.25, function()
			if not stage.Parent then return end
			shine.Position = U(-0.15, 0, 0.5, 0)
			tween(shine, TweenInfo.new(0.55, Enum.EasingStyle.Sine), {Position = U(1.15, 0, 0.5, 0), BackgroundTransparency = 0.45})
		end)

		local rb
		local function step(dt)
			local t = os.clock() - t0
			-- осколки: летят к центру с ускорением, вращаются, истончаются и гаснут на сборке
			for _, sh in shards do
				local k = math.clamp((t - sh.delay) / sh.dur, 0, 1)
				local ease = k * k -- влёт медленно, к центру быстро
				local d = 0.62 * (1 - ease)
				sh.f.Position = S(0.5 + math.cos(sh.a) * d, 0.5 + math.sin(sh.a) * d * 0.94)
				sh.f.Rotation = math.deg(sh.a) + sh.spin * ease
				local thin = 1 - ease * 0.85
				sh.f.Size = O(math.max(1, sh.w * thin), math.max(2, sh.h * (1 - ease * 0.5)))
				-- проявление в начале, растворение к центру
				local vis = math.clamp(k * 3, 0, 1)
				sh.f.BackgroundTransparency = math.clamp(1 - vis * 0.9 + ease * 0.9, 0, 1)
				sh.st.Transparency = math.clamp(1 - vis + ease, 0, 1)
			end
			-- СВЕТ: взрыв света к моменту сборки букв, затем ровное «горение» до ухода.
			-- Яркость считается от времени, поэтому взрыв читается: вспышка → выдержка → затухание.
			local blast = math.clamp(t / 1.15, 0, 1)          -- разгорание к сборке
			local decay = 1 - math.clamp((t - 2.45) / 0.55, 0, 1)
			local lightK = (0.22 + blast * 0.78) * decay
			local diag = math.max(stage.AbsoluteSize.X, stage.AbsoluteSize.Y) * 1.45
			-- лучи: длина и яркость дышат, у каждого свой ритм — пучок «живой», а не статичный
			for _, r in rays do
				r.f.Rotation = r.f.Rotation + dt * 2.2 * r.twinkle * (1.2 - blast * 0.4)
				local len = math.floor(diag * r.boost * (0.68 + math.sin(t * r.twinkle * 2.4 + r.phase) * 0.12))
				local wide = math.max(1, r.w0 * (0.85 + math.sin(t * 1.7 + r.phase) * 0.3))
				r.f.Size = U(0, wide, 0, math.max(20, len))
				r.f.BackgroundTransparency = math.clamp(1 - lightK * (0.9 + math.sin(t * 3.1 + r.phase) * 0.1), 0, 1)
			end
			-- дымка: мягкие круги, растут с вспышкой
			for _, hz in haze do
				local size = diag * (0.10 + hz.k * 0.55) * (0.9 + blast * 0.35)
				hz.f.Size = O(math.floor(size), math.floor(size))
				hz.f.BackgroundTransparency = math.clamp(1 - lightK * (1.05 - hz.k * 0.75), 0, 1)
			end
			-- ПЫЛЬ: точки летят от центра наружу, ускоряясь, и гаснут у края — ощущение глубины
			for _, d in dust do
				local k = (t * d.speed + d.k) % 1
				local r = 0.04 + k * 0.62
				d.f.Position = S(0.5 + math.cos(d.a) * r, 0.47 + math.sin(d.a) * r * 0.9)
				d.f.BackgroundTransparency = math.clamp(1 - math.sin(k * math.pi) * 0.85, 0, 1) * decay
			end
			-- КРИСТАЛЛЫ: ромбы летят на камеру (растут), вращаются и вспыхивают на свету
			for _, c in crystals do
				local k = (t * c.speed * 0.55 + c.k) % 1
				local r = 0.45 * (1 - k * 0.85) -- сходятся к центру, пока растут
				c.f.Position = S(0.5 + math.cos(c.a) * r, 0.47 + math.sin(c.a) * r * 0.9)
				c.f.Rotation = c.f.Rotation + dt * c.spin * (0.4 + k)
				local s2 = c.size * (0.5 + k * 2.1)
				c.f.Size = O(math.floor(s2), math.floor(s2 * 1.7))
				-- блик: кристалл проявляется в середине полёта и гаснет у камеры
				local glowK = math.sin(k * math.pi)
				c.f.BackgroundTransparency = math.clamp(1 - glowK * 0.85, 0, 1)
				c.st.Transparency = math.clamp(1 - glowK * 1.1, 0, 1)
			end
			-- ядро: маленькое и плотное, на вспышке раскрывается
			local coreK = math.clamp((t - 0.25) / 0.85, 0, 1) * decay
			local cs = math.floor(18 + coreK * 120 + math.sin(t * 6.5) * 4)
			core.Size = O(cs, cs)
			core.BackgroundTransparency = math.clamp(1 - coreK * 0.92, 0, 1)
			-- СЕРЕБРЯНЫЙ ПЕРЕЛИВ: у каждой буквы градиент едет по вертикали с разным сдвигом —
			-- по слову бежит волна, как по полированному металлу
			for _, sh in shimmer do
				-- Offset ограничен [-1, 1], поэтому перелив — мягкое покачивание, а не бесконечный бег
				sh.g.Offset = V2(0, math.clamp(math.sin(t * 1.15 + sh.shift) * 0.9, -1, 1))
			end
			-- свечение: нарастает к моменту сборки, потом мягко дышит
			local pulse = math.clamp((t - 0.55) / 0.6, 0, 1)
			local breathe = 1 + math.sin((t - 1.1) * 3) * 0.02
			haloGrad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, math.clamp(0.92 - pulse * 0.75, 0, 1)),
				NumberSequenceKeypoint.new(1, 1),
			})
			halo.Rotation = t * 22
			if baseHal > 0 then halo.Size = O(baseHal * breathe, baseHal * breathe) end
			-- кольца: расходятся от сборки
			for i, r in rings do
				local kr = math.clamp((t - (1.02 + i * 0.09)) / 0.75, 0, 1)
				if kr > 0 and kr < 1 then
					local size = 40 + kr * 620
					r.f.Size = O(size, size)
					r.st.Transparency = 1 - (1 - kr) * 0.85
				elseif kr >= 1 then
					r.st.Transparency = 1
				end
			end
			-- выдержка и уход: слово чуть подрастает и всё гаснет вместе с фоном
			if t > 2.62 then
				local out = math.clamp((t - 2.62) / 0.45, 0, 1)
				for _, l in letters do
					l.lbl.TextTransparency = out
					l.body.TextTransparency = out
					for _, d in l.depths do d.o.TextTransparency = math.max(0.35, out + d.k * 0.08) end
				end
				sub.TextTransparency = out
				rule.BackgroundTransparency = math.max(0.1, out)
				bg.BackgroundTransparency = out
				for _, r in rays do r.f.BackgroundTransparency = math.max(r.f.BackgroundTransparency, out) end
				for _, hz in haze do hz.f.BackgroundTransparency = math.max(hz.f.BackgroundTransparency, out) end
				for _, d in dust do d.f.BackgroundTransparency = math.max(d.f.BackgroundTransparency, out) end
				for _, c in crystals do
					c.f.BackgroundTransparency = math.max(c.f.BackgroundTransparency, out)
					c.st.Transparency = math.max(c.st.Transparency, out)
				end
				core.BackgroundTransparency = math.max(core.BackgroundTransparency, out)
				-- уход: буквы чуть разлетаются от центра и гаснут вместе с фоном
				for _, l in letters do
					local nx = l.cx * (1 + out * 0.06)
					local depth = math.max(1, math.floor((l.lbl.TextSize or 40) * 0.055))
					l.lbl.Position = O(nx, 0)
					l.body.Position = O(nx, 0)
					for _, d in l.depths do d.o.Position = O(nx + depth * d.k, depth * d.k) end
				end
			end
		end
		local function stop()
			if rb then rb:Disconnect() rb = nil end
			if stage.Parent then stage:Destroy() end
			finish()
		end
		rb = RS.RenderStepped:Connect(function(dt)
			if not stage.Parent then stop() return end
			-- сцену нельзя сократить касанием: единственный выход — конец таймлайна или страховка
			if not pcall(step, dt) then stop() end
			if os.clock() - t0 > INTRO_LEN then stop() end
		end)
		pcall(step, 0)
		-- страховка: что бы ни случилось, сцена не держит экран дольше 3.6 с
		task.delay(INTRO_LEN + 0.5, stop)
	end

	-- ===== Экран ключа =====
	-- Та же шапка и материалы, что у основного окна. Масштаб и сдвиг под клавиатуру
	-- считаются от размеров карточки; логика проверки ключа от оформления не зависит.
	local function keyScreen(done)
		local KW, KH = 406, 302
		pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end) -- центр = точный центр экрана, без отступа выреза
		blur = new("BlurEffect", {Size = 0}, GLB.Lighting)
		tween(blur, slow, {Size = GLB.KEY_BLUR})
		local dim = new("Frame", {Size = S(1, 1), BackgroundColor3 = C.B, BackgroundTransparency = 1, Active = true, ZIndex = 10}, gui)
		tween(dim, slow, {BackgroundTransparency = GLB.KEY_DIM})
		local card = new("CanvasGroup", {
			Name = "KeyWindow", Size = O(KW, KH), AnchorPoint = V2(0.5, 0.5), Position = U(0.5, 0, 0.5, 0),
			BackgroundColor3 = C.Win, GroupTransparency = 1,
		}, dim)
		rr(card, 14)
		outline(card, OUT.Window)
		local function keyScale()
			local a = gui.AbsoluteSize
			local maxK = math.max(0.4, math.min((a.X - 24) / KW, (a.Y - 24) / KH))
			return math.min(maxK, UICFG.UIScale)
		end
		local sc = new("UIScale", {Scale = keyScale() * 0.92}, card)
		tween(card, slow, {GroupTransparency = 0}) tween(sc, slow, {Scale = keyScale()})
		local closed = false
		local header = Skin.header(card)
		Skin.badge(header, "v" .. GLB.BUILD .. " · Mobile", 138, 78)
		local xBtn = Skin.iconButton(header, "Close", 6)
		local keyIcon = icon("Key", card, 18, C.W)
		keyIcon.Position = O(24, Skin.Header + 23)
		new("TextLabel", {Size = U(1, -60, 0, 24), Position = O(42, Skin.Header + 11), BackgroundTransparency = 1,
			Text = "Ключ доступа", TextColor3 = C.W, FontFace = GB, TextSize = 18, TextXAlignment = XL}, card)
		local section = sectionLabel(card, "АВТОРИЗАЦИЯ")
		section.Size, section.Position = U(1, -28, 0, 18), O(14, 96)
		local form = new("Frame", {Size = U(1, -28, 0, 97), Position = O(14, 120), BackgroundColor3 = C.Card}, card)
		rr(form, Skin.Radius)
		outline(form)
		new("TextLabel", {Size = U(1, -28, 0, 18), Position = O(14, 8), BackgroundTransparency = 1,
			Text = "Ключ активации", TextColor3 = C.W, FontFace = GM, TextSize = 14, TextXAlignment = XL}, form)
		local sub = new("TextLabel", {Size = U(1, -28, 0, 16), Position = O(14, 26), BackgroundTransparency = 1,
			Text = "Введите ключ, чтобы открыть меню Enkaisy.", TextColor3 = C.Mut, FontFace = GR, TextSize = 12, TextXAlignment = XL}, form)
		local box = new("TextBox", {Name = "AccessKey", Size = U(1, -24, 0, 42), Position = O(12, 46), BackgroundColor3 = C.Side,
			Text = "", PlaceholderText = "Ваш ключ", TextColor3 = C.W, PlaceholderColor3 = C.Mut,
			FontFace = GM, TextSize = 15, TextXAlignment = XL, ClearTextOnFocus = false}, form)
		new("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12)}, box)
		Skin.field(box)
		local btn = button(card, "Активировать", {Size = U(1, -28, 0, 44), Position = O(14, 226), TextSize = 14}, {primary = true})
		local nextIcon = icon("Next", btn, 14, C.AccTx)
		nextIcon.Position = U(1, -18, 0.5, 0)
		local status = new("TextLabel", {Name = "Status", Size = U(1, -28, 0, 18), Position = O(14, 276), BackgroundTransparency = 1,
			Text = "Ожидание ключа", TextColor3 = C.Mut, FontFace = GM, TextSize = 12, TextXAlignment = XL}, card)

		-- фон-картинка из Appearance: та же ссылка / ID, прозрачность картинки, режим и прозрачность карточек
		do
			local src = trimS(UICFG.BgImage)
			if src ~= "" then
				local FIT = {Crop = Enum.ScaleType.Crop, Fit = Enum.ScaleType.Fit, Stretch = Enum.ScaleType.Stretch}
				local img = new("ImageLabel", {
					Name = "KeyBgImage", Size = S(1, 1), BackgroundTransparency = 1, Image = "", Visible = false, Active = false,
					ZIndex = 0, ScaleType = FIT[UICFG.BgImgFit] or Enum.ScaleType.Crop, ImageTransparency = 1,
				}, card)
				local glassItems = {form, box}
				task.spawn(function()
					local asset = bgFetch(src)
					if not asset or closed or not img.Parent then return end
					img.Image, img.Visible = asset, true
					pcall(GLB.CP.PreloadAsync, GLB.CP, {img})
					if closed or not img.Parent then return end
					if not img.IsLoaded then img.Visible, img.Image = false, "" return end
					tween(img, slow, {ImageTransparency = UICFG.BgImgAlpha})
					header.BackgroundTransparency = UICFG.BgAlpha
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
		-- ключ проверяется здесь, в клиенте: сравниваем djb2 введённого текста без пробелов с KEY_HASH
		local function submit()
			if busy then return end
			busy = true
			if hashKey((box.Text:gsub("%s", ""))) == KEY_HASH then
				status.TextColor3, status.Text = C.W, "Ключ принят"
				-- карточка ключа уходит, а поверх играет заставка «осколки → UNICRASE»
				-- (имя видно уже на входе, поэтому меню открывается как продолжение сцены)
				pcall(function() pulse(btn, nil) end)
				tween(card, fast, {GroupTransparency = 1})
				tween(card, fast, {Position = U(0.5, 0, 0.5, -shiftY - 24)}) -- карточка «всплывает» и тает
				task.wait(0.22)
				if closed then return end
				rc:Disconnect()
				-- заставка не должна уметь отменить открытие меню: любая её ошибка — просто пропуск сцены
				local function afterIntro()
					if closed then return end
					dim:Destroy() blur:Destroy() blur = nil
					pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
					done()
				end
				-- страховка двойная: pcall вокруг запуска и таймер, который откроет меню, если сцена не позвала callback
				local opened = false
				local function safeAfter()
					if opened then return end
					opened = true
					afterIntro()
				end
				local okIntro = pcall(playIntro, safeAfter)
				task.delay(INTRO_LEN + 1.2, function() pcall(safeAfter) end)
				if not okIntro then
					pcall(function() if dim.Parent then dim:Destroy() end if blur then blur:Destroy() blur = nil end end)
					pcall(safeAfter)
				end
				return
			end
			tries += 1
			status.TextColor3, status.Text = C.Danger, "Неверный ключ"
			if CFG.Anim then
				-- тряска карточки: амплитуда гаснет; при repeat — сильнее (ошибка)
				shake(form, 9, 7)
				shake(box, 3, 5)
				local st = TS:Create(status, TweenInfo.new(0.08), {TextTransparency = 0.4})
				st:Play()
				st.Completed:Once(function()
					if status.Parent then TS:Create(status, TweenInfo.new(0.2), {TextTransparency = 0}):Play() end
				end)
				task.wait(0.34)
			end
			if tries >= 5 then
				for i = 10, 1, -1 do
					if closed then return end
					status.Text = "Подождите " .. i .. " c"
					task.wait(1)
				end
				if closed then return end
				tries, status.Text, status.TextColor3 = 0, "Ожидание ключа", C.Mut
			end
			box.Text, busy = "", false
		end
		on(xBtn.Activated, function()
			closed = true
			stop()
		end)
		on(btn.Activated, submit)
		-- пульс кнопки: пока в поле есть текст, «Активировать» мягко подсвечивается — видно, куда нажимать
		local pulsing = false
		local function updatePulse()
			local want = not closed and box.Text:gsub("%s", "") ~= ""
			if want == pulsing then return end
			pulsing = want
			pulse(btn, want and 0.04 or nil)
		end
		on(box:GetPropertyChangedSignal("Text"), updatePulse)
		updatePulse()
		on(box.Focused, function()
			task.delay(0.3, function()
				if not closed and dim.Parent then place(true) end
			end)
		end)
		on(box.FocusLost, function(enter)
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
		if GLB.canFps then pcall(setfpscap, 60) end
		for _, c in conns do c:Disconnect() end
		for _, c in npcConn do c:Disconnect() end
		table.clear(npcConn)
		table.clear(npcs)
		for p in pconn do untrack(p) end
		for ch in esp do unhl(ch) end
		-- подстраховка: тела всех целей возвращаются к исходным материалам
		for char in chamsLights do
			if char and char.Parent then pcall(chamsClear, char) end
		end
		chamsOrig, chamsLights = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
		-- Выгрузка с «затуханием»: интерфейс тает за 0.2 с, а не исчезает одним кадром.
		-- При выключенных анимациях удаление происходит сразу.
		if CFG.Anim and gui.Parent then
			local fade = new("Frame", {Name = "FadeOut", Size = S(1, 1), BackgroundColor3 = C.B,
				BackgroundTransparency = 1, Active = true, ZIndex = 200}, gui)
			tween(fade, TWEEN.ui, {BackgroundTransparency = 0.5})
			task.wait(0.2)
		end
		if blur then blur:Destroy() end
		if TC.gui then TC.gui:Destroy() end
		gui:Destroy()
		Brand.release()
	end
	_G.TH_Stop = stop
	if script then script.Destroying:Connect(stop) end
	keyScreen(function()
		local ok, e = pcall(startMain)
		if not ok then
			pcall(function() game:GetService("StarterGui"):SetCore("SendNotification", {Title = "Enkaisy error", Text = tostring(e):sub(1, 120), Duration = 15}) end)
		end
	end)
end}
