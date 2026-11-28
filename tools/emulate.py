"""Эмуляция Roblox API: довести скрипт до меню и прогнать кадровый цикл без запуска игры.

Зачем: статические проверки (компиляция, тесты) видят только текст. Реальные падения
вида «удалили поле — осталась строка math.clamp(AIMCFG.SilentR)» ловятся только
исполнением. Здесь скрипт действительно запускается: строится экран ключа, «нажимается»
кнопка активации, собирается всё меню, включаются все функции и прокручивается
кадровый цикл (наводка, триггер, ESP, FOV, хитбоксы).

Запуск:  python3 tools/emulate.py [файл]      (нужен пакет lupa: pip install lupa)
Успех:   STARTMAIN OK + «кадровый цикл ... OK» и отсутствие STARTMAIN ERROR.
"""

import sys
import traceback

from lupa import LuaRuntime

SOURCE = sys.argv[1] if len(sys.argv) > 1 else "/home/user/unicrase/Enkaisy_Combined_UI_v4_2.lua"
KEYTEXT = sys.argv[2] if len(sys.argv) > 2 else None

LUA_PRELUDE = r"""
-- ============================ перечисления ============================
local function enumItems(list)
    local t = {}
    for _, v in ipairs(list) do t[v] = v end
    return t
end
local __E = {
    Material = enumItems({"Plastic","SmoothPlastic","Neon","Glass","ForceField","CrackedLava","Ice",
        "Foil","Metal","Water","Wood","Slate","Concrete","Granite","Marble","Sand","Fabric","Grass"}),
    ScaleType = enumItems({"Crop","Fit","Stretch"}),
    TextXAlignment = enumItems({"Left","Center","Right"}),
    TextYAlignment = enumItems({"Top","Center","Bottom"}),
    ScrollingDirection = enumItems({"X","Y"}),
    AutomaticSize = enumItems({"X","Y","XY","None"}),
    SortOrder = enumItems({"LayoutOrder","Name","Custom"}),
    FillDirection = enumItems({"Horizontal","Vertical"}),
    ApplyStrokeMode = enumItems({"Contextual","Border"}),
    LineJoinMode = enumItems({"Round","Miter","Bevel"}),
    ZIndexBehavior = enumItems({"Global","Sibling"}),
    ScreenInsets = enumItems({"None","DeviceSafeInsets","CoreUISafeInsets","TopbarSafeInsets"}),
    HighlightDepthMode = enumItems({"AlwaysOnTop","Occluded"}),
    UserInputType = enumItems({"Touch","MouseButton1","MouseButton2","MouseMovement"}),
    KeyCode = setmetatable({}, {__index = function(t, k) rawset(t, k, k) return k end}),
    RaycastFilterType = enumItems({"Exclude","Include"}),
    EasingStyle = enumItems({"Linear","Quad","Cubic","Sine"}),
    EasingDirection = enumItems({"In","Out","InOut"}),
    PlaybackState = enumItems({"Playing","Completed"}),
    Font = enumItems({"Gotham","GothamBold","GothamMedium","GothamBlack","Code","Arial"}),
    FontWeight = enumItems({"Thin","ExtraLight","Light","Regular","Medium","SemiBold","Bold","ExtraBold","Heavy"}),
    FontStyle = enumItems({"Normal","Italic"}),
    TextTruncate = enumItems({"None","AtEnd","SplitWord"}),
    AutomaticCanvasSize = enumItems({"X","Y","XY","None"}),
    ScrollingDirection2 = enumItems({"X","Y","XY"}),
    SizeConstraint = enumItems({"RelativeXY","RelativeXX","RelativeYY"}),
    HorizontalAlignment = enumItems({"Left","Center","Right"}),
    VerticalAlignment = enumItems({"Top","Center","Bottom"}),
    ActuatorRelativeTo = enumItems({"Attachment0","Attachment1","World"}),
    TextDirection = enumItems({"LeftToRight","RightToLeft"}),
    NameOcclusion = enumItems({"None","Enemy","All"}),
    QualityLevel = enumItems({"Automatic","Level01","Level02","Level03","Level04","Level05"}),
    Technology = enumItems({"Legacy","Voxel","ShadowMap","Future","Compatibility"}),
    VideoSampleSize = enumItems({"1x1"}),
    HttpContentType = enumItems({"ApplicationJson"}),
    SaveMethod = enumItems({"DataStore"}),
    AvatarContextMenuOption = enumItems({"Friend","Chat"}),
    SafeAreaCompatibility = enumItems({"None","FullscreenExtension"}),
    ScreenInsetsType = enumItems({"None","DeviceSafeInsets","CoreUISafeInsets","TopbarSafeInsets"}),
    HumanoidStateType = enumItems({"Running","Jumping","Falling"}),
    CameraType = enumItems({"Custom","Scriptable","Fixed"}),
    CoreGuiType = enumItems({"All","PlayerList","Health"}),
    RunContext = enumItems({"Legacy","Server","Client"}),
    ThumbnailType = enumItems({"Avatar","HeadShot"}),
}
-- любое неизвестное перечисление эмуляции отдаёт себя как значение: в игре это настоящий Enum
__E.RenderPriority = enumItems({"First", "Input", "Camera", "Character", "Last"})
for i, n in ipairs({"First", "Input", "Camera", "Character", "Last"}) do
    __E.RenderPriority[n] = {Name = n, Value = i * 100}
end
Enum = setmetatable(__E, {__index = function(t, k)
    local sub = setmetatable({}, {__index = function(_, key) return key end})
    rawset(t, k, sub)
    return sub
end})

-- ============================ типы значений ============================
local function mk(cls, fields)
    local t = {}
    t.ClassName = cls
    for k, v in pairs(fields or {}) do t[k] = v end
    return t
end
UDim = { new = function(s, o) return mk("UDim", {Scale = s or 0, Offset = o or 0}) end }
UDim2 = { new = function(sx, ox, sy, oy) return mk("UDim2", {X = {Scale = sx or 0, Offset = ox or 0},
    Y = {Scale = sy or 0, Offset = oy or 0}}) end }
UDim2.fromScale = function(x, y) return UDim2.new(x or 0, 0, y or 0, 0) end
UDim2.fromOffset = function(x, y) return UDim2.new(0, x or 0, 0, y or 0) end
TweenInfo_ = { new = function(t, st, ed) return mk("TweenInfo", {Time = t or 1}) end }
TweenInfo = TweenInfo_
Color3 = {
    new = function(r, g, b) return mk("Color3", {R = r or 0, G = g or 0, B = b or 0}) end,
    fromRGB = function(r, g, b) return mk("Color3", {R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255}) end,
    fromHSV = function(h, s, v) return mk("Color3", {R = h or 0, G = s or 0, B = v or 0}) end,
}
local c3mt = {
    __index = function(t, k)
        if k == "Lerp" then
            return function(a, b, t2) return a end
        elseif k == "ToHSV" then
            return function(a) return a.R or 0, a.G or 0, a.B or 0 end
        elseif k == "ToHex" then
            return function(a) return "AABBCC" end
        end
        return nil
    end,
}
-- make Color3 instances carry methods
local function color(r, g, b)
    local c = Color3.new(r, g, b)
    return setmetatable(c, c3mt)
end
Color3.new = function(r, g, b) return setmetatable(mk("Color3", {R = r or 0, G = g or 0, B = b or 0}), c3mt) end
Color3.fromRGB = function(r, g, b)
    return setmetatable(mk("Color3", {R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255}), c3mt)
end
Color3.fromHSV = function(h, s, v)
    return setmetatable(mk("Color3", {R = h or 0, G = s or 0, B = v or 0}), c3mt)
end
Color3.fromHex = function(hex)
    local h = tostring(hex):gsub("#", "")
    if #h ~= 6 then error("invalid hex") end
    local r = tonumber(h:sub(1, 2), 16) or 0
    local g = tonumber(h:sub(3, 4), 16) or 0
    local b = tonumber(h:sub(5, 6), 16) or 0
    return setmetatable(mk("Color3", {R = r / 255, G = g / 255, B = b / 255}), c3mt)
end
Vector2 = { new = function(x, y) return mk("Vector2", {X = x or 0, Y = y or 0}) end }
Vector3 = { new = function(x, y, z) return mk("Vector3", {X = x or 0, Y = y or 0, Z = z or 0}) end }
CFrame = { new = function() return mk("CFrame", {}) end, Angle = function() return mk("CFrame", {}) end }
Rect = { new = function() return mk("Rect", {}) end }
NumberRange = { new = function(a, b) return mk("NumberRange", {Min = a, Max = b or a}) end }
NumberSequence = { new = function(...) return mk("NumberSequence", {}) end }
NumberSequenceKeypoint = { new = function(t, v) return mk("NumberSequenceKeypoint", {Time = t, Value = v}) end }
ColorSequence = { new = function(...) return mk("ColorSequence", {}) end }
ColorSequenceKeypoint = { new = function(t, c) return mk("ColorSequenceKeypoint", {Time = t, Value = c}) end }
Font = {
    new = function(family, weight, style) return mk("Font", {Family = family or "rbxasset://fonts/families/Roboto.json"}) end,
    fromEnum = function(e) return mk("Font", {Family = "rbxasset://fonts/families/" .. tostring(e) .. ".json"}) end,
    fromName = function(n, w) return mk("Font", {Family = "rbxasset://fonts/families/" .. tostring(n) .. ".json"}) end,
    fromId = function(n, w) return mk("Font", {Family = "rbxasset://fonts/families/" .. tostring(n) .. ".json"}) end,
}
Ray = { new = function() return mk("Ray", {}) end }
RaycastParams = { new = function()
    return mk("RaycastParams", {FilterDescendantsInstances = {}, FilterType = "Exclude",
        IgnoreWater = false, CollisionGroup = "Default", RespectCanCollide = true, BruteForceAllSlow = false})
end }

-- ============================ инстансы ============================
local created, parents = {}, {}
local function newInstance(cls)
    local o
    o = {
        ClassName = cls, Name = cls, Parent = nil, children = {},
        _signals = {}, _props = {},
    }
    -- универсальный __index: свойства, дети, методы
    setmetatable(o, {
        __index = function(t, k)
            local raw = rawget(t, k)
            if raw ~= nil then return raw end
            if k == "FindFirstChild" then
                return function(self, name) for _, c in ipairs(self.children) do if c.Name == name then return c end end end
            elseif k == "FindFirstChildOfClass" then
                return function(self, cname) for _, c in ipairs(self.children) do if c.ClassName == cname then return c end end end
            elseif k == "FindFirstChildWhichIsA" then
                return function(self, cname) for _, c in ipairs(self.children) do if c.ClassName == cname then return c end end end
            elseif k == "FindFirstAncestorOfClass" then
                return function(self) return nil end
            elseif k == "GetChildren" then
                return function(self) return self.children end
            elseif k == "GetDescendants" then
                return function(self)
                    local out = {}
                    local function walk(n) for _, c in ipairs(n.children) do table.insert(out, c) walk(c) end end
                    walk(self)
                    return out
                end
            elseif k == "IsA" then
                return function(self, cname) return self.ClassName == cname end
            elseif k == "WaitForChild" then
                return function(self, name) return self:FindFirstChild(name) or newInstance(name) end
            elseif k == "Destroy" then
                return function(self) self.Parent = nil end
            elseif k == "Clone" then
                return function(self) return newInstance(self.ClassName) end
            elseif k == "GetPropertyChangedSignal" then
                return function(self) return mkSignal("prop", self) end
            elseif k == "GetAttribute" then
                return function(self) return nil end
            elseif k == "SetAttribute" then
                return function(self) end
            elseif k == "IsDescendantOf" then
                return function(self) return true end
            elseif k == "GetPlayers" then
                return function(self) return {} end
            elseif k == "GetService" then
                return function(self, name) return service(name) end
            elseif k == "Connect" then
                return function(self, fn) return mkSignal("x", self) end
            elseif k == "Once" then
                return function(self, fn) return mkSignal("x", self) end
            elseif k == "Wait" then
                return function(self) return nil end
            elseif k == "Play" or k == "Pause" or k == "Cancel" then
                return function(self) end
            elseif k == "GetValue" then
                return function(self) return 60 end
            elseif k == "IsFocused" then
                return function(self) return false end
            elseif k == "GetMouseLocation" then
                return function(self) return Vector2.new(0, 0) end
            elseif k == "Create" then
                return function(self, inst, info, props)
                    local tw = mk("Tween", {})
                    tw.Play = function() end
                    tw.Cancel = function() end
                    tw.Pause = function() end
                    tw.Completed = mkSignal("tw", nil)
                    return tw
                end
            elseif k == "AddTag" or k == "RemoveTag" or k == "HasTag" then
                return function(self) return nil end
            elseif k == "GetTagged" then
                return function(self) return {} end
            elseif k == "BindToRenderStep" then
                return function(self, name, prio, fn)
                    RENDER_STEPS[name] = fn
                end
            elseif k == "UnbindFromRenderStep" then
                return function(self, name) RENDER_STEPS[name] = nil end
            elseif k == "ViewportPointToRay" or k == "ScreenPointToRay" then
                return function(self) return mk("Ray", {Origin = Vector3.new(0,0,0), Direction = Vector3.new(0,0,1)}) end
            elseif k == "WorldToViewportPoint" or k == "WorldToScreenPoint" then
                return function(self) return 0, 0, true end
            elseif k == "Raycast" then
                return function(self) return nil end
            elseif k == "GetGuiInset" then
                return function(self) return Vector2.new(0, 0) end
            elseif k == "SetCore" or k == "SetCoreGuiEnabled" then
                return function(self) return true end
            elseif k == "PreloadAsync" or k == "Preload" then
                return function(self) return nil end
            elseif k == "GetRankInGroup" or k == "GetRoleInGroup" then
                return function(self) return 0, "Guest" end
            elseif k == "GetNetworkPing" then
                return function(self) return 0.05 end
            elseif k == "GetPlayerFromCharacter" then
                return function(self) return nil end
            elseif k == "HttpGet" or k == "GetAsync" or k == "JSONDecode" or k == "JSONEncode" then
                return function(self) return nil end
            elseif k == "GetInstanceAddedSignal" or k == "GetInstanceRemovedSignal" then
                return function(self, tag) return mkSignal("tag", self) end
            elseif k == "GetUserIdFromNameAsync" then
                return function(self) return 1 end
            end
            -- свойства по умолчанию
            if k == "AbsoluteSize" then return Vector2.new(800, 600) end
            if k == "AbsolutePosition" then return Vector2.new(0, 0) end
            if k == "ViewportSize" then return Vector2.new(1600, 900) end
            if k == "Text" then return "" end
            if k == "Position" then return UDim2.new(0,0,0,0) end
            if k == "Size" then return UDim2.new(0,0,0,0) end
            if k == "Visible" then return true end
            if k == "Enabled" then return true end
            if k == "Transparency" then return 0 end
            if k == "BackgroundTransparency" then return 0 end
            if k == "Rotation" then return 0 end
            if k == "Thickness" then return 1 end
            if k == "CFrame" then
                return mk("CFrame", {Position = Vector3.new(0, 5, 0), LookVector = Vector3.new(0, 0, -1),
                    RightVector = Vector3.new(1, 0, 0), UpVector = Vector3.new(0, 1, 0)})
            end
            if k == "LookVector" or k == "RightVector" or k == "UpVector" then return Vector3.new(0, 0, -1) end
            if k == "p" or k == "X" then return 0 end
            if k == "Health" or k == "MaxHealth" then return 100 end
            if k == "Character" then return nil end
            if k == "LocalPlayer" then return nil end
            if k == "CurrentCamera" then return nil end
            if k == "ScreenInsets" then return "None" end
            if k == "ImageContent" then return nil end
            if k == "IsLoaded" then return true end
            if k == "Magnitude" then return 1 end
            if k == "Unit" then return t end
            if k == "X" or k == "Y" or k == "Z" then return 0 end
            if k == "Scale" then return 1 end
            if k == "Offset" then return 0 end
            if k == "Color" then return color(1,1,1) end
            if k == "Team" then return nil end
            if k == "UserId" then return 1 end
            if k == "DisplayName" then return "Player" end
            if k == "TouchEnabled" then return true end
            if k == "OnScreenKeyboardVisible" then return false end
            if k == "OnScreenKeyboardPosition" then return Vector2.new(0, 0) end
            if k == "MouseIconEnabled" then return true end
            if k == "CharacterAutoLoads" then return true end
            if k == "Workspace" then return nil end
            if k == "Lighting" then return nil end
            if SIGNALS[k] then return mkSignal(k, t) end
            return nil
        end,
        __newindex = function(t, k, v)
            if k == "Parent" then
                local old = rawget(t, "Parent")
                if old and old.children then
                    for i, c in ipairs(old.children) do if c == t then table.remove(old.children, i) break end end
                end
                rawset(t, "Parent", v)
                if v and v.children then table.insert(v.children, t) end
                return
            end
            rawset(t, k, v)
        end,
    })
    table.insert(created, o)
    return o
end

SIGNALS = {}
RENDER_STEPS = {}
RAW_FIRE = true
for _, n in ipairs({"MouseEnter", "MouseLeave", "InputBegan", "InputEnded", "InputChanged",
        "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "Focused", "FocusLost",
        "Changed", "Touched", "TouchEnded", "ChildAdded", "ChildRemoved", "DescendantAdded",
        "Destroying", "AncestryChanged", "SelectionChanged", "TextChanged", "CanvasPosition", "Deactivated",
        "PlayerAdded", "PlayerRemoving", "PlayerConnecting", "CharacterAdded", "CharacterRemoving",
        "RenderStepped", "Heartbeat", "Stepped", "PreRender", "PostSimulation", "PreSimulation",
        "TouchStarted", "TouchMoved", "TouchEnded", "TouchTap", "InputBegan", "InputEnded", "InputChanged",
        "JumpRequest", "StateChanged", "Died", "HealthChanged", "FocusLost", "Focused", "MouseButton1Down"}) do
    SIGNALS[n] = true
end

FIRE = {}   -- [Instance] = {EventName = fn}
function mkSignal(kind, owner)
    local s = { _kind = kind, _owner = owner }
    s.Connect = function(self, fn)
        if RAW_FIRE and owner ~= nil and kind ~= nil then
            FIRE[owner] = FIRE[owner] or {}
            FIRE[owner][kind] = fn
        end
        return { Disconnect = function() end }
    end
    s.Once = function(self, fn) return { Disconnect = function() end } end
    s.Wait = function(self) return nil end
    return s
end

-- ============================ сервисы ============================
local services = {}
local function service(name)
    if services[name] then return services[name] end
    local o = newInstance(name)
    o.Name = name
    services[name] = o
    return o
end

game = {
    ClassName = "DataModel",
    GetService = function(self, name) return service(name) end,
    FindService = function(self, name) return service(name) end,
    PlaceId = 1, JobId = "job", GameId = 1,
    IsLoaded = function() return true end,
    Workspace = service("Workspace"),
}
game = setmetatable(game, {__index = function(t, k) return service(k) end})

-- сервисы с заданными свойствами
local function svc(name)
    local s = service(name)
    return s
end
local __lp = newInstance("Player")
__lp.Name = "Tester"
__lp.UserId = 1
local __plrgui = newInstance("PlayerGui")
__plrgui.Name = "PlayerGui"
__plrgui.Parent = __lp
__lp.WaitForChild = function(self, name) if name == "PlayerGui" then return __plrgui end return newInstance(name) end
__lp.FindFirstChild = function(self, name) if name == "PlayerGui" then return __plrgui end return nil end
svc("Players").LocalPlayer = __lp
svc("Players").GetPlayers = function(self) return {} end
local __rs = svc("RunService")
__rs.RenderStepped = mkSignal("RenderStepped", __rs)
__rs.Heartbeat = mkSignal("Heartbeat", __rs)
__rs.Stepped = mkSignal("Stepped", __rs)
__rs.PreRender = mkSignal("PreRender", __rs)
svc("RunService").IsClient = function() return true end
svc("RunService").IsServer = function() return false end
svc("RunService").IsStudio = function() return false end
local __uis = svc("UserInputService")
__uis.TouchStarted = mkSignal("TouchStarted", __uis)
__uis.TouchMoved = mkSignal("TouchMoved", __uis)
__uis.InputChanged = mkSignal("InputChanged", __uis)
__uis.InputEnded = mkSignal("InputEnded", __uis)
__uis.InputBegan = mkSignal("InputBegan", __uis)
svc("UserInputService").TouchEnabled = true
svc("UserInputService").MouseEnabled = false
svc("UserInputService").KeyboardEnabled = false
svc("UserInputService").GetMouseLocation = function() return Vector2.new(0, 0) end
svc("Workspace").CurrentCamera = newInstance("Camera")
svc("Workspace").CurrentCamera.ViewportSize = Vector2.new(1600, 900)
svc("Lighting").ClockTime = 14
svc("Stats").Network = {ServerStatsItem = {["Data Ping"] = newInstance("StatsItem")}}

Instance = {new = function(cls, parent)
    local o = newInstance(cls)
    if parent then o.Parent = parent end
    return o
end}
Instance.new = Instance.new

-- ============================ типы ============================
function typeof(v)
    if type(v) == "table" then
        if v.ClassName then return "Instance" end
        return "table"
    end
    return type(v)
end

task = {
    wait = function(t) return t end,
    spawn = function(fn, ...) local ok, err = pcall(fn, ...) if not ok then print("[task.spawn error] " .. tostring(err)) end end,
    delay = function(t, fn) end,
    defer = function(fn) pcall(fn) end,
    cancel = function() end,
}
wait = function(t) return t end
spawn = function(fn) pcall(fn) end
U = function(a, b, c, d)
    return mk("UDim2", {X = {Scale = a or 0, Offset = b or 0}, Y = {Scale = c or 0, Offset = d or 0}})
end
S = function(a, b) return mk("UDim2", {X = {Scale = a or 0, Offset = 0}, Y = {Scale = b or 0, Offset = 0}}) end
O = function(a, b) return mk("UDim2", {X = {Scale = 0, Offset = a or 0}, Y = {Scale = 0, Offset = b or 0}}) end
V2 = function(a, b) return mk("Vector2", {X = a or 0, Y = b or 0}) end
tick = function() return os.clock() end
time = function() return os.clock() end
print = function(...)
    local parts = {}
    local n = select("#", ...)
    for i = 1, n do
        local v = select(i, ...)
        parts[#parts + 1] = tostring(v)
    end
    __py_print(table.concat(parts, " "))
end
warn = print

-- ============================ Luau-расширения стандартной библиотеки ============================
-- В Luau у table есть find/clear/create, у math — clamp, у string — split. В Lua 5.5 их нет,
-- поэтому дописываем: иначе эмуляция падает на местах, которые в игре работают.
function table.find(t, v, from)
    if type(t) ~= "table" then return nil end
    local i = from or 1
    while t[i] ~= nil do
        if t[i] == v then return i end
        i = i + 1
    end
    return nil
end
function table.clear(t)
    for k in pairs(t) do t[k] = nil end
end
function table.create(n, v)
    local t = {}
    for i = 1, (n or 0) do t[i] = v end
    return t
end
function math.clamp(x, lo, hi)
    if x ~= x then return lo end
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end
math.atan2 = math.atan2 or function(y, x) if x == 0 then return (y > 0 and math.pi or -math.pi) / 2 end return math.atan(y / x) end
math.sign = function(x) return x > 0 and 1 or (x < 0 and -1 or 0) end
function math.round(x) return math.floor(x + 0.5) end
bit32 = bit32 or { band = function(a,b) return a end, bor = function(a,b) return a end,
    bxor = function(a,b) return a end, lshift = function(a,n) return a end, rshift = function(a,n) return a end }

Random = { new = function()
    return { NextNumber = function(self, a, b) return (a or 0) + math.random() * ((b or 1) - (a or 0)) end,
             NextInteger = function(self, a, b) return math.random(a, b) end }
end }
Instance_ = Instance
"""


def lint(src):
    """Ищем использование НЕОБЪЯВЛЕННЫХ имён (в Luau это глобал = nil в рантайме)."""
    import re
    from lupa import LuaRuntime
    L = LuaRuntime()
    declared = set()
    pats = [r"\blocal\s+(?:function\s+)?([\w, ]+?)\s*[=(]", r"\bfor\s+([\w, ]+?)\s*(?:=|in)\b",
            r"function\s*[\w.:]*\s*\(([^)]*)\)", r"^\s*([A-Za-z_]\w*)\s*=[^=]"]
    for line in src.split("\n"):
        for pat in pats:
            for m in re.finditer(pat, line):
                for n in m.group(1).split(","):
                    n = n.split("=")[0].strip()
                    if re.match(r"^[A-Za-z_]\w*$", n):
                        declared.add(n)
    # локальные переменные цикла for i = ... и параметры уже покрыты
    used = {}
    for i, line in enumerate(src.split("\n"), 1):
        code = line.split("--")[0]
        for m in re.finditer(r"(?<![\w.:])([A-Za-z_]\w*)\s*=(?!=)", code):
            declared.add(m.group(1))
        for m in re.finditer(r"(?<![\w.:\"'])([A-Za-z_][A-Za-z0-9_]{2,})\b(?!\s*=[^=])", code):
            used.setdefault(m.group(1), []).append(i)
    builtin = set("game workspace script print warn tostring tonumber type pcall xpcall ipairs pairs next select error assert "
        "setmetatable getmetatable rawget rawset unpack table string math os task Enum Instance Vector2 Vector3 CFrame "
        "Color3 ColorSequence ColorSequenceKeypoint NumberSequence NumberSequenceKeypoint NumberRange UDim UDim2 TweenInfo "
        "Rect Ray Region3 Random Font FontFace tick time wait spawn delay require typeof bit32 utf8 coroutine debug "
        "loadstring getgenv getrenv writefile readfile isfile delfile listfiles makefolder setfpscap identifyexecutor "
        "getcustomasset getsynasset request syn http firetouchinterest fireclickdetector Drawing cleardrawcache "
        "setclipboard gethui getconnections hookfunction getrawmetatable setreadonly checkcaller is_synapse_function "
        "getnilinstances getinstances getloadedmodules decompile getscriptbytecode getscripthash protectgui "
        "cloneref islclosure newcclosure getnamecallmethod hookmetamethod getcallingscript _G _VERSION self nil true false "
        "and or not if then else elseif end function local return for while do repeat until break in".split())
    unknown = {n: v for n, v in used.items() if n not in declared and n not in builtin}
    return unknown



import re as _reg


def _is_call(expr):
    """Выражение — это вызов функции целиком (Players:GetPlayers(), pairs(t))?"""
    m = _reg.match(r"^[A-Za-z_][\w.:]*\s*\(", expr)
    if not m:
        return False
    i, depth = expr.index("(", m.start()), 0
    for j in range(i, len(expr)):
        if expr[j] == "(":
            depth += 1
        elif expr[j] == ")":
            depth -= 1
            if depth == 0:
                return j == len(expr) - 1
    return False


def normalize_generic_for(text):
    """Luau понимает `for k in t do` как обход таблицы (generalized iteration), в том числе
    для литералов-таблиц. Lua 5.5 так не умеет — оборачиваем правую часть в pairs()."""
    out = []
    for line in text.split("\n"):
        m = _reg.match(r"^(?P<ind>\s*)for\s+(?P<vars>[\w,][\w\s,]*?)\s+in\s+(?P<expr>.+?)\s+do\b(?P<tail>.*)$", line)
        if not m:
            out.append(line)
            continue
        expr = m.group("expr").strip()
        # Luau обходит ЛЮБУЮ таблицу, даже возвращённую вызовом (Players:GetPlayers()).
        # Не трогаем только настоящие итераторы.
        if expr.startswith("{"):
            out.append("%sfor %s in pairs(%s) do%s" % (m.group("ind"), m.group("vars"), expr, m.group("tail")))
            continue
        if _reg.match(r"^(pairs|ipairs|next|string\.gmatch|[\w.]+:?gmatch)\s*\(", expr):
            out.append(line)
        elif _reg.search(r"[\w\)]\s*\(", expr) and not _is_call(expr):
            out.append(line)  # сложное выражение с вызовом внутри — оставляем как есть
        else:
            out.append("%sfor %s in pairs(%s) do%s" % (m.group("ind"), m.group("vars"), expr, m.group("tail")))
    return "\n".join(out)


def main():
    L = LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()

    log = []

    def py_print(s):
        log.append(str(s))

    g.__py_print = py_print
    L.execute(LUA_PRELUDE)

    src = open(SOURCE, encoding="utf-8").read()
    # груз работает как в Roblox: сначала компиляция, потом выполнение сверху вниз
    # Luau-операторы (+= и т.п.) и continue — единственное, чего нет в Lua 5.5,
    # поэтому для проверки переводим их в обычную запись; остальное парсится как есть.
    import re
    import re as _re
    norm = _re.sub(r"(\b[\w\.\[\]\(\)]+)\s*(\+|-|\*|/|%|\^|\.\.)=\s*",
                   lambda m: "%s = %s %s " % (m.group(1), m.group(1),
                                              ".." if m.group(2) == ".." else m.group(2)),
                   src)
    # Lua 5.5 считает переменную for-цикла константной, в Luau переприсваивание разрешено:
    # переименовываем такие переменные, чтобы проверять остальной файл, а не этот нюанс
    import re as _r2
    def _fix_loops(text):
        out = []
        for line in text.split("\n"):
            m = _r2.match(r"^(\s*)for\s+(\w+)\s+in\s+(.+)\s+do\s*$", line)
            if m:
                var = m.group(2)
                out.append(line)
                out.append("__LOOPVAR__" + var)
                continue
            out.append(line)
        return "\n".join(out)
    _lines2, _forvars = norm.split("\n"), []
    _fix = []
    for _l in _lines2:
        _m = _re.match(r"^(\s*)for\s+(\w+)\s+(in|=)\s", _l)
        if _m: _forvars.append(_m.group(2))
        if _forvars:
            _v = _forvars[-1]
            if re.search(r"(?<![\w.:])" + _v + r"\s*=(?!=)", _l) and not _m:
                _l = re.sub(r"(?<![\w.:])" + _v + r"\s*=(?!=)", _v + "_x =", _l)
        if re.match(r"^\s*end\b", _l) and _forvars:
            _forvars.pop()
        _fix.append(_l)
    norm = "\n".join(_fix)
    norm = normalize_generic_for(norm)
    # эмулятор не знает правильного ключа: подменяем только проверку хэша, чтобы прогнать всё меню
    norm = norm.replace('if hashKey((box.Text:gsub("%s", ""))) == KEY_HASH then', 'if true then')
    # ошибку startMain скрипт глушит через pcall + SendNotification: в эмуляции печатаем её прямо
    norm = norm.replace('local ok, e = pcall(startMain)', 'local ok, e = xpcall(startMain, debug.traceback) if not ok then print("STARTMAIN ERROR: " .. tostring(e)) else print("STARTMAIN OK") end')
    norm = norm.replace('local ok, e = pcall(GLB.selfTest)', 'local ok, e = pcall(GLB.selfTest)')
    import pathlib as _pl
    _pl.Path("/tmp/rbx/norm.lua").write_text(norm, encoding="utf-8")
    loader = L.eval("function(code) local f, e = load(code, 'Enkaisy') if f then return f end return nil, e end")
    res = loader(norm)
    if isinstance(res, tuple):
        fn, err = (res + (None,))[:2]
    else:
        fn, err = res, None
    # continuation-стиль из lupa: load вернул два значения
    if fn is None and err is None:
        fn, err = res, None
    if fn is None:
        print("COMPILE ERROR:", err)
        # ограничение Lua 5.5 на 200 локалей: Luau держит до 200 на функцию,
        # но у нас лимит исчерпан и на функциях, которые в Luau компилируются —
        # тогда сообщаем, сколько осталось до лимита, и продолжаем анализ
        if "too many local variables" in (err or ""):
            print("(Lua 5.5 лимит 200; в Luau лимит тот же, но часть наших локалей — "
                  "внутренние замыкания, поэтому проверим остальной файл отдельно)")
        return
    print("COMPILE OK")
    # 1) имитируем ввод верного ключа: ищем TextBox ключа и кнопку активации
    def call(fn_owner, kind, *args):
        ev = globals().get("_fire")
        return None

    try:
        fn()
        print("RUN OK (скрипт дошёл до конца без ошибок)")
        # 2) нажимаем кнопки экрана ключа (Activated) — это открывает меню
        click = L.eval("""
function()
    -- кнопки экрана ключа: первая — «Активировать» (submit), вторая — закрыть
    local list = {}
    for owner, evs in pairs(FIRE) do
        if evs.Activated then table.insert(list, owner) end
    end
    local n = 0
    for _, owner in ipairs(list) do
        if owner.Text == "Активировать" or (type(owner.Text) == "string" and owner.Text:find("ктив")) then
            n = n + 1
            local ok, e = pcall(FIRE[owner].Activated)
            if not ok then print("CLICK ERROR: " .. tostring(e)) end
        end
    end
    return n
end""")
        print("нажато кнопок активации:", click())
        # лог печатается до клика, поэтому показать всё, что накопилось (включая ошибки startMain)
        for line in log:
            print("  ", line)
        # 3) кадровый цикл: наводка, триггер, ESP, FOV — всё, что висит на RenderStepped
        frames = L.eval("""
function(n)
    local steps = {}
    for name, fn in pairs(RENDER_STEPS) do table.insert(steps, fn) end
    for owner, evs in pairs(FIRE) do
        if evs.RenderStepped then table.insert(steps, evs.RenderStepped) end
    end
    if #steps == 0 then return -1 end
    local ok, err = pcall(function() for i = 1, n do for _, fn in ipairs(steps) do fn(1 / 60) end end end)
    if not ok then return err end
    return 0
end""")
        res = frames(3)
        print("кадровый цикл (всё выключено):", "OK" if res == 0 else res)
        # 4) включаем всё и гоняем цикл: наводка, триггер, ESP, FOV, RCS, предсказание
        on_all = L.eval("""
function()
    return pcall(function()
        local A = AIMCFG
        A.Enabled, A.Trigger, A.TargetLock, A.Multipoint = true, true, true, true
        A.Hitbox, A.HitboxShow, A.HeadHitbox, A.Rcs, A.ShowFOV, A.DebugHUD = true, true, true, true, true, true
        local C2 = CFG
        C2.On, C2.ShowBox, C2.ShowName, C2.ShowDist, C2.ShowHealth = true, true, true, true, true
        C2.TeamColors = true
        if updAll then updAll() end
        if paintQuick then paintQuick(true) end
    end)
end""")
        ok_all, err_all = (on_all + (None,))[:2] if isinstance(on_all, tuple) else (on_all, None)
        if not ok_all:
            print("ОШИБКА включения функций:", err_all)
        res2 = frames(30)
        print("кадровый цикл (всё включено):", "OK" if res2 == 0 else res2)
    except Exception as e:  # noqa: BLE001
        print("RUNTIME ERROR:", str(e)[:2000])
    print("--- printed output ---")
    for line in log[:40]:
        print("  ", line)


if __name__ == "__main__":
    main()
