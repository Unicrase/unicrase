-- Exercise logo() without a live game or an uploaded Roblox asset.
local function vec(...) return {...} end
local V2, S, U, O = vec, vec, vec, vec
local C, PURE, OUT = {B = "black"}, "white", {Window = 0.89}
local Enum = {ScaleType = {Fit = "Fit"}}
local Color3 = {fromHex = function(hex) assert(#hex == 6); return hex end}
local ColorSequenceKeypoint = {new = vec}
local ColorSequence = {new = function(keys)
	assert(#keys >= 2 and #keys <= 20 and keys[1][1] == 0 and keys[#keys][1] == 1)
	for i = 2, #keys do assert(keys[i][1] > keys[i-1][1] and keys[i][2]) end
	return keys
end}
local function new(class, props, parent)
	props.class, props.Parent, props.children = class, parent, {}
	if parent then table.insert(parent.children, props) end
	return props
end
local function rr(o, radius) o.radius = radius end
local function outline(o) return {Parent = o} end
local policy, calls, writes, freed = "allow", 0, 0, 0
local assets = {CreateEditableImage = function(_, opts)
	calls += 1
	if policy == "deny" then error("Image API disabled") end
	if policy == "oom" then return nil end
	return {WritePixelsBuffer = function(_, pos, dims, pixels)
		assert(dims == opts.Size and pos[1] == 0 and pos[2] == 0)
		assert(buffer.len(pixels) == dims[1] * dims[2] * 4)
		for i = 3, buffer.len(pixels)-1, 4 do assert(buffer.readu8(pixels, i) == 255) end
		writes += 1
	end, Destroy = function() freed += 1 end}
end}
local game = {GetService = function(_, name) assert(name == "AssetService"); return assets end}
local Content = {fromObject = function(image) return {Object = image} end}

-- INSERT_FACTORIES

local host = {children = {}}
local header, edge = logo(32, host)
local launcher = logo(44, host)
assert(header.class == "ImageLabel" and header.Parent == host and edge.Parent == header)
assert(header.ScaleType == Enum.ScaleType.Fit and header.ImageContent == launcher.ImageContent)
assert(header.Size[1] == 32 and launcher.Size[1] == 44 and not launcher.Active)
assert(calls == 1 and writes == 1)
Brand.release()
assert(freed == 1 and not Brand.content and not Brand.image)
for _, state in {"deny", "oom"} do
	policy, Brand.tried = state, false
	local previousCalls = calls
	for _, size in {32, 44} do
		local mark, stroke = logo(size, host)
		assert(mark.class == "CanvasGroup" and mark.Size[1] == size and stroke.Parent == mark)
		assert(#mark.children == 128) -- two spans per scanline, never an Instance per pixel
		for _, strip in mark.children do assert(strip.children[1].class == "UIGradient") end
	end
	assert(calls == previousCalls + 1)
end
