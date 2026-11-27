-- Minimal property/signal doubles. The Python test inserts the production factories below.
local C = {W = "text", Mut = "muted", Hi = "rail", Acc = "accent", AccTx = "inverse"}
local function U(...) return {...} end
local O, V2 = U, U
local Enum = {TextTruncate = {AtEnd = 1}, TextXAlignment = {Right = 1}}
local GM, XL = "medium", "left"
local function new(kind, props, parent)
	props.Parent, props.kind, props.children, props.Activated = parent, kind, {}, {}
	if parent then parent.children[props.Name or kind] = props end
	function props:FindFirstAncestorWhichIsA(k)
		local p = self.Parent
		while p and p.kind ~= k do p = p.Parent end
		return p
	end
	return props
end
local function put(o, props) for k, v in props do o[k] = v end end
local function on(signal, fn) signal.fire = fn end
local function drag(o, change, begin, finish) o.change, o.begin, o.finish = change, begin, finish end
local function round() end
local function accent(o, prop) o[prop] = C.Acc end
local helpUI = {add = function() end}
local Skin = {Inset = 14, copy = function() end}
function Skin.setting(parent, _, button)
	return new(button and "TextButton" or "Frame", {}, parent), {apply = function() end}
end

-- INSERT_FACTORIES

local list = new("ScrollingFrame", {ScrollingEnabled = true})
local state = false
local row, repaint = toggleCard(list, "Option", 1, function() return state end, function(v) state = v end)
local track = row.children.Switch
local thumb = track.children.Thumb
assert(track.BackgroundColor3 == C.Hi and thumb.Position[1] == 0)
row.Activated.fire()
assert(state and track.BackgroundColor3 == C.Acc and thumb.BackgroundColor3 == C.AccTx and thumb.Position[1] == 1)
C.Acc = "custom accent"
repaint(false)
assert(track.BackgroundColor3 == C.Acc)
row.Activated.fire()
assert(not state and thumb.Position[1] == 0)

local value = 30
local card = sliderCard(list, "Value", 2, 10, 50, function() return value end, function(v) value = v end, tostring, 5)
local hit = card.children.SliderHit
local rail = hit.children.Track
local function check(expected, fraction)
	assert(value == expected and card.children.Value.Text == tostring(value))
	assert(rail.children.Thumb.Position[1] == fraction and rail.children.ValueFill.Size[1] == fraction)
end
check(30, 0.5)
hit.begin()
assert(not list.ScrollingEnabled and hit.Size[4] > rail.Size[4])
hit.change(0); check(10, 0)
hit.change(0.58); check(35, 0.625)
hit.change(1); check(50, 1)
hit.finish()
assert(list.ScrollingEnabled)
