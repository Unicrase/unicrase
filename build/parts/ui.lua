-- ЧАСТЬ: интерфейс (карточки, папки, поиск, HUD). Отдельный кусок — свой лимит 200.
return function(env)
	local gui, new, C, S, U, O = env.gui, env.new, env.C, env.S, env.U, env.O
	-- ===== Главное меню =====
	local stop
	-- Одно модальное окно для справки и подтверждения выгрузки. Подложка перехватывает
	-- касания: прокрутка, переключатели и ручка размера под диалогом не активируются.
	function helpUI.mount(panel, unload)
		local shade = new("Frame", {Name = "DialogLayer", Size = S(1, 1), BackgroundColor3 = C.B, BackgroundTransparency = 0.38,
			Active = true, Visible = false, ZIndex = 50}, panel)
		local box = new("Frame", {Size = U(1, -48, 0, 180), AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5),
			BackgroundColor3 = C.Win, Active = true}, shade)
		new("UISizeConstraint", {MaxSize = V2(406, 180)}, box)
		rr(box, 12)
		outline(box, OUT.Window)
		local head = new("Frame", {Size = U(1, -24, 0, 42), Position = O(12, 2), BackgroundTransparency = 1}, box)
		local glyph = icon("Info", head, 17, C.W)
		glyph.Position = U(0, 9, 0.5, 0)
		local title = new("TextLabel", {Size = U(1, -60, 1, 0), Position = O(25, 0), BackgroundTransparency = 1,
			Text = "", TextColor3 = C.W, FontFace = GB, TextSize = 16, TextXAlignment = XL, TextTruncate = Enum.TextTruncate.AtEnd}, head)
		local close = Skin.iconButton(head, "Close", 0)
		new("Frame", {Size = U(1, 0, 0, 1), Position = O(0, 44), BackgroundColor3 = C.Line}, box)
		local body = new("ScrollingFrame", {Size = U(1, -28, 1, -60), Position = O(14, 54), BackgroundTransparency = 1,
			ScrollBarThickness = 2, ScrollBarImageColor3 = C.Mut, CanvasSize = O(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y}, box)
		local copy = new("TextLabel", {Size = U(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
			Text = "", TextColor3 = C.W, FontFace = GR, TextSize = 14, TextWrapped = true, TextXAlignment = XL, TextYAlignment = Enum.TextYAlignment.Top}, body)
		local actions = row(box, 36, 8)
		actions.Size, actions.Position = U(1, -28, 0, 36), U(0, 14, 1, -50)
		local cancel = button(actions, "Отмена", {Size = U(0.5, -4, 1, 0), LayoutOrder = 1})
		-- два варианта одной правой кнопки: обычное действие (акцент) и опасное (красное)
		local confirm = button(actions, "Подтвердить", {Size = U(0.5, -4, 1, 0), LayoutOrder = 2}, {primary = true})
		local danger = button(actions, "Сбросить всё", {Size = U(0.5, -4, 1, 0), LayoutOrder = 2,
			BackgroundColor3 = C.DangerBg, TextColor3 = C.W, Visible = false}, {danger = true})
		local pending -- что выполнить после подтверждения; nil у справочных окон
		-- Появление диалога: подложка проявляется, карточка «выпрыгивает» масштабом.
		-- Закрытие — короткое сжатие, чтобы окно не исчезало рывком.
		local dscale = new("UIScale", {Scale = 1}, box)
		local hiding = false
		local function dialogIn()
			hiding = false
			shade.Visible = true
			if not CFG.Anim then
				shade.BackgroundTransparency, box.BackgroundTransparency, dscale.Scale = 0.38, 0, 1
				return
			end
			shade.BackgroundTransparency, dscale.Scale = 1, 0.92
			tween(shade, TWEEN.ui, {BackgroundTransparency = 0.38})
			spring(dscale, {Scale = 1}, TWEEN.pop)
		end
		local function hide()
			if not shade.Visible then return end
			pending = nil
			if not CFG.Anim then
				shade.Visible = false
				return
			end
			hiding = true
			tween(shade, TWEEN.snap, {BackgroundTransparency = 1})
			tween(dscale, TWEEN.snap, {Scale = 0.94})
			task.delay(0.14, function()
				if hiding then
					shade.Visible = false
					shade.BackgroundTransparency, dscale.Scale = 0.38, 1
				end
			end)
		end
		local function complete()
			local fn = pending
			pending = nil
			hide()
			if fn then fn() end
		end
		on(close.Activated, hide)
		on(cancel.Activated, hide)
		on(confirm.Activated, function() if shade.Visible and actions.Visible and not danger.Visible then complete() end end)
		on(danger.Activated, function() if shade.Visible and actions.Visible and danger.Visible then complete() end end)
		-- ask = false: обычная справка без кнопок; danger = true: красная кнопка для необратимых действий
		local function open(name, text, ask, okText, isDanger, onOk)
			title.Text, copy.Text = name, text
			actions.Visible = ask and true or false
			confirm.Visible = actions.Visible and not isDanger
			danger.Visible = actions.Visible and isDanger and true or false
			if ask then
				if isDanger then danger.Text = okText or "Сбросить всё" else confirm.Text = okText or "Подтвердить" end
				pending = onOk
			else
				pending = nil
			end
			body.Size = U(1, -28, 1, ask and -110 or -64)
			body.CanvasPosition = V2(0, 0)
			dialogIn()
		end
		local api = {}
		api.help = function(name, desc)
			local info = helpUI.info[name]
			local ru = info and info[1] or desc or "Описание пока недоступно."
			local en = info and info[2] or "Description not available yet."
			open(name, "RU: " .. ru .. "\n\nEN: " .. en, false)
		end
		helpUI.open = api.help
		api.confirm = function(name, text, okText, isDanger, onOk)
			open(name, text, true, okText, isDanger, onOk)
		end
		api.unload = function()
			open("Выгрузить Enkaisy?", "Меню и плавающие элементы будут закрыты. Чтобы просто свернуть окно, нажмите минус в шапке.", true, "Выгрузить", false, unload)
		end
		return api
	end

	return {mid = true}
end
