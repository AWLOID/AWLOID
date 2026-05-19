--[[
    ╔══════════════════════════════════════════════════════════════╗
    ║                       OBSCURA UI LIBRARY                     ║
    ║                  Monochrome · Sharp · Universal              ║
    ╚══════════════════════════════════════════════════════════════╝

    Чёрно-белая UI-библиотека для Roblox.
    Без скруглений. Идеальный drag для ПК и мобилы.
    Полный набор элементов: Button, Toggle, Slider, Dropdown,
    MultiDropdown, Textbox, Keybind, Colorpicker, Label, Paragraph,
    Divider, Section, Notifications.

    USAGE:
        local Library = loadstring(game:HttpGet("..."))()
        local Window  = Library:CreateWindow({ Title = "Obscura", Size = UDim2.fromOffset(620, 460) })
        local Tab     = Window:CreateTab("Main")
        local Section = Tab:CreateSection("General", "left")
        Section:AddButton({ Text = "Click me", Callback = function() print("hi") end })
]]

----------------------------------------------------------------------
-- LIBRARY ROOT
----------------------------------------------------------------------
local Library              = {}
Library.__index            = Library
Library.Flags              = {}        -- [flag] = value
Library.FlagCallbacks      = {}        -- [flag] = { fn, fn, ... }
Library.FlagControls       = {}
Library.Connections        = {}        -- runtime connections (cleaned on :Destroy)
Library.UnloadCallbacks    = {}
Library.Keybinds           = {}
Library.Windows            = {}
Library.Notifications      = {}
Library.Settings           = { Folder = "Obscura/settings", Profile = "default" }
Library.Premium            = { Enabled = false, Unlocked = false, Owned = {}, Prices = {} }
Library.ActiveListItems    = {}
Library.Open               = true
Library.Version            = "2.0.0"
Library.Name               = "Obscura"
Library._zCounter          = 10
Library._activeDropdown    = nil
Library._activeColorpicker = nil
Library._activeModal       = nil
Library._themeVersion      = 0

----------------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------------
local UIS         = game:GetService("UserInputService")
local TS          = game:GetService("TweenService")
local RS          = game:GetService("RunService")
local CoreGui     = game:GetService("CoreGui")
local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local GuiService  = game:GetService("GuiService")
local LP          = Players.LocalPlayer

----------------------------------------------------------------------
-- THEME (strict monochrome, no roundness anywhere)
----------------------------------------------------------------------
local Theme = {
    Bg          = Color3.fromRGB(8,   8,   8),   -- main window bg
    Bg2         = Color3.fromRGB(14,  14,  14),  -- sidebars / sections
    Bg3         = Color3.fromRGB(20,  20,  20),  -- inputs / controls
    Hover       = Color3.fromRGB(30,  30,  30),
    Border      = Color3.fromRGB(40,  40,  40),
    BorderHi    = Color3.fromRGB(255, 255, 255),
    Text        = Color3.fromRGB(235, 235, 235),
    SubText     = Color3.fromRGB(155, 155, 155),
    DimText     = Color3.fromRGB(85,  85,  85),
    Accent      = Color3.fromRGB(255, 255, 255),
    Track       = Color3.fromRGB(32,  32,  32),
    Disabled    = Color3.fromRGB(60,  60,  60),
    Success     = Color3.fromRGB(120, 255, 170),
    Warning     = Color3.fromRGB(255, 215, 120),
    Danger      = Color3.fromRGB(255, 120, 120),
    Premium     = Color3.fromRGB(255, 255, 255),
}
Library.Theme = Theme

local FONT    = Enum.Font.Gotham
local FONT_M  = Enum.Font.GothamMedium
local FONT_SB = Enum.Font.GothamSemibold
local FONT_B  = Enum.Font.GothamBold

local TEXT_SIZE       = 13
local TEXT_SIZE_SMALL = 12
local TEXT_SIZE_TITLE = 14

local IS_MOBILE = UIS.TouchEnabled and not UIS.MouseEnabled

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------
local function new(class, props)
    local inst = Instance.new(class)
    if props then
        for k, v in pairs(props) do
            if k ~= "Parent" then inst[k] = v end
        end
        if props.Parent then inst.Parent = props.Parent end
    end
    return inst
end

local function stroke(parent, color, thickness, mode)
    return new("UIStroke", {
        Parent          = parent,
        Color           = color or Theme.Border,
        Thickness       = thickness or 1,
        ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border,
    })
end

local function pad(parent, l, t, r, b)
    return new("UIPadding", {
        Parent        = parent,
        PaddingLeft   = UDim.new(0, l or 0),
        PaddingTop    = UDim.new(0, t or l or 0),
        PaddingRight  = UDim.new(0, r or l or 0),
        PaddingBottom = UDim.new(0, b or t or l or 0),
    })
end

local function listLayout(parent, dir, padding, halign, valign, sortOrder)
    return new("UIListLayout", {
        Parent              = parent,
        FillDirection       = dir or Enum.FillDirection.Vertical,
        Padding             = UDim.new(0, padding or 0),
        HorizontalAlignment = halign or Enum.HorizontalAlignment.Left,
        VerticalAlignment   = valign or Enum.VerticalAlignment.Top,
        SortOrder           = sortOrder or Enum.SortOrder.LayoutOrder,
    })
end

local function tween(obj, t, props, style, dir)
    local tw = TS:Create(obj, TweenInfo.new(
        t or 0.15,
        style or Enum.EasingStyle.Quad,
        dir or Enum.EasingDirection.Out
    ), props)
    tw:Play()
    return tw
end

local function register(c)
    table.insert(Library.Connections, c)
    return c
end

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

local function round(n, decimals)
    local m = 10 ^ (decimals or 0)
    return math.floor(n * m + 0.5) / m
end

local function isInside(frame, pos)
    local p, s = frame.AbsolutePosition, frame.AbsoluteSize
    return pos.X >= p.X and pos.X <= p.X + s.X
       and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
    warn("[Obscura] " .. tostring(a))
    return nil
end

local function readFlagDefault(flag, default)
    if flag and Library.Flags[flag] ~= nil then
        return Library.Flags[flag]
    end
    return default
end

local function matchesText(value, query)
    query = tostring(query or ""):lower()
    if query == "" then return true end
    return tostring(value or ""):lower():find(query, 1, true) ~= nil
end

local function normalizeKeyList(keys)
    if keys == nil then return {} end
    if type(keys) == "table" then return keys end
    return { keys }
end

local function iconIsImage(icon)
    if type(icon) == "number" then return true end
    if type(icon) ~= "string" then return false end
    return icon:find("rbxasset", 1, true) ~= nil or icon:match("^%d+$") ~= nil
end

local function iconImage(icon)
    if type(icon) == "number" then return "rbxassetid://" .. tostring(icon) end
    if type(icon) == "string" and icon:match("^%d+$") then return "rbxassetid://" .. icon end
    return tostring(icon)
end

local function makeIcon(parent, icon, opts)
    opts = opts or {}
    if icon == nil then return nil end
    local size = opts.Size or UDim2.fromOffset(14, 14)
    local z = opts.ZIndex
    if iconIsImage(icon) then
        return new("ImageLabel", {
            Parent                 = parent,
            Name                   = opts.Name or "Icon",
            BackgroundTransparency = 1,
            Size                   = size,
            Position               = opts.Position or UDim2.new(),
            AnchorPoint            = opts.AnchorPoint or Vector2.new(),
            Image                  = iconImage(icon),
            ImageColor3            = opts.Color or Theme.SubText,
            ScaleType              = Enum.ScaleType.Fit,
            ZIndex                 = z or parent.ZIndex,
        })
    end
    return new("TextLabel", {
        Parent                 = parent,
        Name                   = opts.Name or "Icon",
        BackgroundTransparency = 1,
        Size                   = size,
        Position               = opts.Position or UDim2.new(),
        AnchorPoint            = opts.AnchorPoint or Vector2.new(),
        Font                   = opts.Font or FONT_SB,
        TextSize               = opts.TextSize or TEXT_SIZE,
        TextColor3             = opts.Color or Theme.SubText,
        TextXAlignment         = Enum.TextXAlignment.Center,
        TextYAlignment         = Enum.TextYAlignment.Center,
        Text                   = tostring(icon),
        ZIndex                 = z or parent.ZIndex,
    })
end

local function setIconColor(icon, color)
    if not icon then return end
    if icon:IsA("ImageLabel") or icon:IsA("ImageButton") then
        icon.ImageColor3 = color
    elseif icon:IsA("TextLabel") or icon:IsA("TextButton") then
        icon.TextColor3 = color
    end
end

local function serializeValue(value)
    local t = typeof(value)
    if t == "Color3" then
        return { __type = "Color3", R = value.R, G = value.G, B = value.B }
    elseif t == "EnumItem" then
        return { __type = "EnumItem", EnumType = tostring(value.EnumType):gsub("^Enum%.", ""), Name = value.Name }
    elseif t == "Vector2" then
        return { __type = "Vector2", X = value.X, Y = value.Y }
    elseif t == "UDim2" then
        return {
            __type = "UDim2",
            XS = value.X.Scale,
            XO = value.X.Offset,
            YS = value.Y.Scale,
            YO = value.Y.Offset,
        }
    elseif type(value) == "table" then
        local out = {}
        for k, v in pairs(value) do
            out[k] = serializeValue(v)
        end
        return out
    end
    return value
end

local function deserializeValue(value)
    if type(value) ~= "table" then return value end
    if value.__type == "Color3" then
        return Color3.new(tonumber(value.R) or 0, tonumber(value.G) or 0, tonumber(value.B) or 0)
    elseif value.__type == "EnumItem" then
        local enum = Enum[value.EnumType]
        return enum and enum[value.Name] or nil
    elseif value.__type == "Vector2" then
        return Vector2.new(tonumber(value.X) or 0, tonumber(value.Y) or 0)
    elseif value.__type == "UDim2" then
        return UDim2.new(
            tonumber(value.XS) or 0,
            tonumber(value.XO) or 0,
            tonumber(value.YS) or 0,
            tonumber(value.YO) or 0
        )
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = deserializeValue(v)
    end
    return out
end

local function settingPath(name)
    name = tostring(name or Library.Settings.Profile or "default"):gsub("[^%w_%-]", "_")
    return tostring(Library.Settings.Folder or "Obscura/settings") .. "/" .. name .. ".json"
end

local function ensureSettingFolder()
    local folder = tostring(Library.Settings.Folder or "Obscura/settings")
    if makefolder then
        local parts = {}
        for part in folder:gmatch("[^/\\]+") do table.insert(parts, part) end
        local path = ""
        for _, part in ipairs(parts) do
            path = path == "" and part or (path .. "/" .. part)
            pcall(function() makefolder(path) end)
        end
    end
end

local function sameArray(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if #a ~= #b then return false end
    for i = 1, #a do
        if tostring(a[i]) ~= tostring(b[i]) then return false end
    end
    return true
end

----------------------------------------------------------------------
-- DRAG (works perfectly on PC and Mobile)
----------------------------------------------------------------------
local function makeDraggable(target, handle)
    handle = handle or target

    local dragging  = false
    local dragInput = nil
    local startPos
    local startInput

    register(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging   = true
            startInput = input.Position
            startPos   = target.Position

            local conn
            conn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if conn then conn:Disconnect() end
                end
            end)
        end
    end))

    register(handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))

    register(UIS.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - startInput
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))
end

----------------------------------------------------------------------
-- SCREEN GUI (initialized lazily)
----------------------------------------------------------------------
local function getScreenGui()
    if Library.ScreenGui and Library.ScreenGui.Parent then
        return Library.ScreenGui
    end

    local ok, parent = pcall(function() return CoreGui end)
    if not ok or not parent then
        parent = LP:WaitForChild("PlayerGui")
    end

    -- Try to use CoreGui if possible (executor environment)
    local sg = new("ScreenGui", {
        Name              = "Obscura_" .. HttpService:GenerateGUID(false):sub(1, 8),
        ResetOnSpawn      = false,
        IgnoreGuiInset    = true,
        ZIndexBehavior    = Enum.ZIndexBehavior.Sibling,
        DisplayOrder      = 999999999,
    })

    local protected = false
    pcall(function()
        if syn and syn.protect_gui then
            syn.protect_gui(sg); sg.Parent = CoreGui; protected = true
        elseif (gethui) then
            sg.Parent = gethui(); protected = true
        elseif (get_hidden_gui) then
            sg.Parent = get_hidden_gui(); protected = true
        elseif protect_gui then
            protect_gui(sg); sg.Parent = CoreGui; protected = true
        end
    end)

    if not protected then
        local ok2 = pcall(function() sg.Parent = CoreGui end)
        if not ok2 then sg.Parent = LP:WaitForChild("PlayerGui") end
    end

    Library.ScreenGui = sg
    return sg
end

----------------------------------------------------------------------
-- KEY UTILS
----------------------------------------------------------------------
local KEY_NAMES = {
    [Enum.UserInputType.MouseButton1] = "MB1",
    [Enum.UserInputType.MouseButton2] = "MB2",
    [Enum.UserInputType.MouseButton3] = "MB3",
}
local function keyToString(key)
    if not key then return "NONE" end
    if typeof(key) == "EnumItem" then
        if key.EnumType == Enum.KeyCode then
            return key.Name
        elseif KEY_NAMES[key] then
            return KEY_NAMES[key]
        end
    end
    return tostring(key)
end

local function isKeyPressed(key, input)
    if not key then return false end
    if typeof(key) == "EnumItem" then
        if key.EnumType == Enum.KeyCode then
            return input.KeyCode == key
        end
        return input.UserInputType == key
    end
    return false
end

----------------------------------------------------------------------
-- FLAG SYSTEM
----------------------------------------------------------------------
function Library:SetFlag(flag, value)
    if not flag then return end
    Library.Flags[flag] = value
    if Library._flagSyncing == flag then return end
    Library._flagSyncing = flag
    local controls = Library.FlagControls[flag]
    if controls then
        for _, api in ipairs(controls) do
            if api and api.Set then
                pcall(function()
                    if api.SetFlagValue then
                        api:SetFlagValue(value, true)
                    else
                        api:Set(value, true)
                    end
                end)
            end
        end
    end
    Library._flagSyncing = nil
    local list = Library.FlagCallbacks[flag]
    if list then
        for _, fn in ipairs(list) do
            task.spawn(fn, value)
        end
    end
end

function Library:GetFlag(flag, default)
    local v = Library.Flags[flag]
    if v == nil then return default end
    return v
end

function Library:OnFlag(flag, fn)
    Library.FlagCallbacks[flag] = Library.FlagCallbacks[flag] or {}
    table.insert(Library.FlagCallbacks[flag], fn)
end

function Library:_registerFlagControl(flag, api)
    if not flag or not api then return api end
    Library.FlagControls[flag] = Library.FlagControls[flag] or {}
    table.insert(Library.FlagControls[flag], api)
    return api
end

function Library:ApplyFlag(flag, value, fire)
    if fire then
        local controls = Library.FlagControls[flag]
        if controls and controls[1] then
            local api = controls[1]
            if api.SetFlagValue then
                api:SetFlagValue(value, false)
            elseif api.Set then
                api:Set(value, false)
            end
            return
        end
    end
    self:SetFlag(flag, value)
end

function Library:OnUnload(fn)
    if type(fn) == "function" then
        table.insert(Library.UnloadCallbacks, fn)
    end
    return fn
end

function Library:Track(object, cleanup)
    if typeof(object) == "RBXScriptConnection" then
        return register(object)
    end
    if type(cleanup) == "function" then
        self:OnUnload(function() cleanup(object) end)
    elseif typeof(object) == "Instance" then
        self:OnUnload(function()
            if object.Parent then object:Destroy() end
        end)
    end
    return object
end

function Library:SetTheme(theme, apply)
    theme = theme or {}
    local old = {}
    for k, v in pairs(Theme) do old[k] = v end
    for k, v in pairs(theme) do
        if Theme[k] ~= nil and typeof(v) == "Color3" then
            Theme[k] = v
        end
    end
    Library._themeVersion += 1
    if apply == false or not Library.ScreenGui then return end
    for _, inst in ipairs(Library.ScreenGui:GetDescendants()) do
        if inst:IsA("Frame") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            for k, v in pairs(old) do
                if inst.BackgroundColor3 == v then inst.BackgroundColor3 = Theme[k] end
            end
        end
        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            for k, v in pairs(old) do
                if inst.TextColor3 == v then inst.TextColor3 = Theme[k] end
            end
        end
        if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
            for k, v in pairs(old) do
                if inst.ImageColor3 == v then inst.ImageColor3 = Theme[k] end
            end
        end
        if inst:IsA("UIStroke") then
            for k, v in pairs(old) do
                if inst.Color == v then inst.Color = Theme[k] end
            end
        end
    end
end

function Library:SetFont(font, medium, semibold, bold)
    if type(font) == "table" then
        FONT = font.Regular or font.Font or FONT
        FONT_M = font.Medium or font.Font or FONT_M
        FONT_SB = font.Semibold or font.SemiBold or font.Bold or FONT_SB
        FONT_B = font.Bold or font.Semibold or FONT_B
    else
        FONT = font or FONT
        FONT_M = medium or font or FONT_M
        FONT_SB = semibold or medium or font or FONT_SB
        FONT_B = bold or semibold or medium or font or FONT_B
    end
    if Library.ScreenGui then
        for _, inst in ipairs(Library.ScreenGui:GetDescendants()) do
            if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
                inst.Font = FONT
            end
        end
    end
end

function Library:GetSettingsSnapshot()
    local flags = {}
    for k, v in pairs(Library.Flags) do
        flags[k] = serializeValue(v)
    end
    local theme = {}
    for k, v in pairs(Theme) do
        theme[k] = serializeValue(v)
    end
    return {
        Name = Library.Name,
        Version = Library.Version,
        SavedAt = os.time(),
        Flags = flags,
        Theme = theme,
        Font = serializeValue(FONT),
        Premium = {
            Unlocked = Library.Premium.Unlocked,
            Owned = serializeValue(Library.Premium.Owned),
        },
    }
end

function Library:ApplySettings(data)
    if type(data) ~= "table" then return false end
    if data.Theme then
        local theme = {}
        for k, v in pairs(data.Theme) do
            theme[k] = deserializeValue(v)
        end
        self:SetTheme(theme)
    end
    if data.Font then
        local font = deserializeValue(data.Font)
        if font then self:SetFont(font) end
    end
    if data.Premium then
        Library.Premium.Unlocked = data.Premium.Unlocked and true or false
        Library.Premium.Owned = deserializeValue(data.Premium.Owned or {}) or {}
    end
    local flags = data.Flags or data
    for k, v in pairs(flags) do
        self:ApplyFlag(k, deserializeValue(v), true)
    end
    return true
end

function Library:SaveSetting(name)
    ensureSettingFolder()
    local path = settingPath(name)
    local json = HttpService:JSONEncode(self:GetSettingsSnapshot())
    if writefile then
        writefile(path, json)
        return true, path
    end
    return false, json
end

function Library:LoadSetting(name)
    local path = settingPath(name)
    if readfile and isfile and isfile(path) then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(path))
        end)
        if ok then return self:ApplySettings(data), path end
        return false, data
    end
    return false, "setting not found"
end

function Library:DeleteSetting(name)
    local path = settingPath(name)
    if delfile and isfile and isfile(path) then
        delfile(path)
        return true, path
    end
    return false, "setting not found"
end

function Library:ListSettings()
    local folder = tostring(Library.Settings.Folder or "Obscura/settings")
    local out = {}
    if listfiles then
        local ok, files = pcall(function() return listfiles(folder) end)
        if ok then
            for _, path in ipairs(files) do
                local name = tostring(path):match("([^/\\]+)%.json$")
                if name then table.insert(out, name) end
            end
        end
    end
    return out
end

Library.SaveConfig = Library.SaveSetting
Library.LoadConfig = Library.LoadSetting

function Library:SetPremium(state)
    Library.Premium.Unlocked = state and true or false
end

function Library:UnlockPremium(feature)
    if feature then
        Library.Premium.Owned[tostring(feature)] = true
    else
        Library.Premium.Unlocked = true
    end
end

function Library:IsPremium(feature)
    if Library.Premium.Unlocked then return true end
    if not feature then return false end
    return Library.Premium.Owned[tostring(feature)] and true or false
end

function Library:ShowPurchase(opts)
    opts = opts or {}
    local feature = tostring(opts.Feature or opts.Text or "Premium")
    local price = opts.Price or Library.Premium.Prices[feature] or "Premium"
    local modal
    modal = self:CreateModal({
        Title = "Premium",
        Text = feature .. "\n" .. tostring(price),
        Buttons = {
            {
                Text = "Buy",
                Callback = function()
                    local ok = safeCall(opts.PurchaseCallback or Library.Premium.PurchaseCallback, feature, price)
                    if ok == nil or ok == true then
                        Library:UnlockPremium(feature)
                        Library:Notify({ Title = "Premium", Text = feature .. " unlocked", Duration = 3 })
                    end
                    if modal then modal:Close() end
                end,
            },
            { Text = "Later", Close = true },
        },
    })
    return modal
end

function Library:_premiumAllowed(opts)
    opts = opts or {}
    if not opts.Premium and not opts.Locked then return true end
    local feature = opts.Feature or opts.Text or "Premium"
    if self:IsPremium(feature) then return true end
    self:ShowPurchase({
        Feature = feature,
        Price = opts.Price,
        PurchaseCallback = opts.PurchaseCallback,
    })
    return false
end

function Library:RegisterKeybind(opts)
    opts = opts or {}
    local bind = {
        Name = tostring(opts.Name or opts.Text or opts.Flag or "Keybind"),
        Key = readFlagDefault(opts.Flag, opts.Key or opts.Default),
        Mode = tostring(opts.Mode or "Toggle"):lower(),
        Flag = opts.Flag,
        Callback = opts.Callback or function() end,
        OnChanged = opts.OnChanged or function() end,
        Enabled = opts.Enabled ~= false,
        IgnoreProcessed = opts.IgnoreProcessed and true or false,
        State = false,
    }
    function bind:Set(key, silent)
        self.Key = key
        if self.Flag then Library:SetFlag(self.Flag, key) end
        if not silent then task.spawn(self.OnChanged, key) end
    end
    function bind:Get()
        return self.Key
    end
    function bind:SetMode(mode)
        self.Mode = tostring(mode or "Toggle"):lower()
    end
    function bind:Destroy()
        self.Enabled = false
        for i, item in ipairs(Library.Keybinds) do
            if item == self then
                table.remove(Library.Keybinds, i)
                break
            end
        end
    end
    table.insert(Library.Keybinds, bind)
    if bind.Flag and bind.Key then Library:SetFlag(bind.Flag, bind.Key) end
    return bind
end

----------------------------------------------------------------------
-- TOGGLE VISIBILITY
----------------------------------------------------------------------
function Library:Toggle(state)
    if state == nil then state = not Library.Open end
    Library.Open = state
    if not state then
        if Library._activeDropdown    then Library._activeDropdown:Close()    end
        if Library._activeColorpicker then Library._activeColorpicker:Close() end
        if Library._listeningKeybind  then Library._listeningKeybind:Cancel() end
    end
    for _, w in ipairs(Library.Windows) do
        if w.Root then w.Root.Visible = state end
    end
    if Library.MobileButton then
        Library.MobileButton.Text = state and "×" or "≡"
    end
end

----------------------------------------------------------------------
-- MOBILE TOGGLE BUTTON
----------------------------------------------------------------------
local function makeMobileButton()
    if Library.MobileButton then return end
    local sg = getScreenGui()

    local btn = new("TextButton", {
        Parent           = sg,
        Name             = "ObscuraToggle",
        Size             = UDim2.fromOffset(40, 40),
        Position         = UDim2.new(0, 12, 0, 12),
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel  = 0,
        Text             = "×",
        TextColor3       = Theme.Text,
        Font             = FONT_B,
        TextSize         = 22,
        AutoButtonColor  = false,
        ZIndex           = 10000,
        Active           = true,
        Selectable       = false,
    })
    stroke(btn, Theme.BorderHi, 1)
    makeDraggable(btn)

    btn.MouseButton1Click:Connect(function()
        Library:Toggle()
    end)

    Library.MobileButton = btn
end

----------------------------------------------------------------------
-- DESTROY / UNLOAD
----------------------------------------------------------------------
function Library:Destroy()
    for _, bind in ipairs(Library.Keybinds) do
        if bind.Mode == "hold" and bind.State then
            safeCall(bind.Callback, false, bind)
        elseif bind.Mode == "toggle" and bind.State then
            safeCall(bind.Callback, false, bind)
        end
        bind.Enabled = false
    end
    for i = #Library.UnloadCallbacks, 1, -1 do
        safeCall(Library.UnloadCallbacks[i])
    end
    for _, c in ipairs(Library.Connections) do
        pcall(function() c:Disconnect() end)
    end
    Library.Connections = {}
    if Library.ScreenGui then
        pcall(function() Library.ScreenGui:Destroy() end)
        Library.ScreenGui = nil
    end
    Library.Windows           = {}
    Library.Flags             = {}
    Library.FlagCallbacks     = {}
    Library.FlagControls      = {}
    Library.UnloadCallbacks   = {}
    Library.Keybinds          = {}
    Library.ActiveListItems   = {}
    Library.MobileButton      = nil
    Library.NotifyHolder      = nil
    Library._activeDropdown   = nil
    Library._activeColorpicker= nil
    Library._listeningKeybind = nil
    Library._activeModal      = nil
end

----------------------------------------------------------------------
-- KEEP ACTIVE POPUP ANCHORED TO ITS BUTTON (window may move)
----------------------------------------------------------------------
register(RS.Heartbeat:Connect(function()
    local d = Library._activeDropdown
    if d and d.UpdatePosition then pcall(d.UpdatePosition, d) end
    local cp = Library._activeColorpicker
    if cp and cp.UpdatePosition then pcall(cp.UpdatePosition, cp) end
end))

----------------------------------------------------------------------
-- CLOSE OPEN POPUPS WHEN CLICKING OUTSIDE
----------------------------------------------------------------------
register(UIS.InputBegan:Connect(function(input, processed)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
   and input.UserInputType ~= Enum.UserInputType.Touch then return end

    local pos = input.Position
    if Library._activeDropdown then
        local d = Library._activeDropdown
        if d.List and d.Button and not isInside(d.List, pos) and not isInside(d.Button, pos) then
            d:Close()
        end
    end
    if Library._activeColorpicker then
        local cp = Library._activeColorpicker
        if cp.Popup and cp.Button and not isInside(cp.Popup, pos) and not isInside(cp.Button, pos) then
            cp:Close()
        end
    end
end))

register(UIS.InputBegan:Connect(function(input, processed)
    for _, bind in ipairs(Library.Keybinds) do
        if bind.Enabled and (bind.IgnoreProcessed or not processed) and isKeyPressed(bind.Key, input) then
            if bind.Mode == "toggle" then
                bind.State = not bind.State
                task.spawn(bind.Callback, bind.State, bind)
            elseif bind.Mode == "hold" then
                bind.State = true
                task.spawn(bind.Callback, true, bind)
            elseif bind.Mode == "always" or bind.Mode == "press" then
                task.spawn(bind.Callback, bind)
            end
        end
    end
end))

register(UIS.InputEnded:Connect(function(input)
    for _, bind in ipairs(Library.Keybinds) do
        if bind.Enabled and bind.Mode == "hold" and isKeyPressed(bind.Key, input) then
            bind.State = false
            task.spawn(bind.Callback, false, bind)
        end
    end
end))

----------------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------------
local Window = {}
Window.__index = Window

function Library:CreateWindow(opts)
    opts = opts or {}
    local title    = opts.Title    or "Obscura"
    local subtitle = opts.Subtitle or ("v" .. Library.Version)
    local size     = opts.Size     or UDim2.fromOffset(620, 460)
    local minSize  = opts.MinSize  or Vector2.new(480, 340)
    local toggleKey= opts.ToggleKey or Enum.KeyCode.RightShift
    local mobile   = opts.MobileButton ~= false
    local sidebarW = tonumber(opts.SidebarWidth) or 130
    local responsive = opts.Responsive ~= false
    local searchEnabled = opts.Search ~= false
    local titleIcon = opts.TitleIcon or opts.Icon

    local sg = getScreenGui()

    -- Root
    local root = new("Frame", {
        Parent           = sg,
        Name             = "Window",
        AnchorPoint      = Vector2.new(0.5, 0.5),
        Position         = UDim2.fromScale(0.5, 0.5),
        Size             = size,
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel  = 0,
        ClipsDescendants = false,
        Active           = true,
    })
    stroke(root, Theme.BorderHi, 1)

    -- Subtle inner contour
    local inner = new("Frame", {
        Parent           = root,
        Name             = "Inner",
        Size             = UDim2.new(1, -2, 1, -2),
        Position         = UDim2.fromOffset(1, 1),
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel  = 0,
    })

    -- Title bar (drag handle)
    local titleBar = new("Frame", {
        Parent           = inner,
        Name             = "TitleBar",
        Size             = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = Theme.Bg2,
        BorderSizePixel  = 0,
        Active           = true,
    })
    new("Frame", { -- bottom border
        Parent           = titleBar,
        Size             = UDim2.new(1, 0, 0, 1),
        Position         = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = Theme.Border,
        BorderSizePixel  = 0,
    })

    -- Accent bar
    new("Frame", {
        Parent           = titleBar,
        Size             = UDim2.fromOffset(3, 14),
        Position         = UDim2.new(0, 10, 0.5, -7),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
    })

    local titleX = 22
    local titleIconObj
    if titleIcon then
        titleIconObj = makeIcon(titleBar, titleIcon, {
            Position = UDim2.new(0, 22, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            Size = UDim2.fromOffset(14, 14),
            Color = Theme.Text,
        })
        titleX = 42
    end

    local titleLabel = new("TextLabel", {
        Parent           = titleBar,
        Name             = "Title",
        Position         = UDim2.new(0, titleX, 0, 0),
        Size             = UDim2.new(0.48, -titleX, 1, 0),
        BackgroundTransparency = 1,
        Font             = FONT_SB,
        TextSize         = TEXT_SIZE_TITLE,
        TextColor3       = Theme.Text,
        TextXAlignment   = Enum.TextXAlignment.Left,
        Text             = title,
        TextTruncate     = Enum.TextTruncate.AtEnd,
    })
    local subtitleLabel = new("TextLabel", {
        Parent           = titleBar,
        Name             = "Subtitle",
        Position         = UDim2.new(0.48, 8, 0, 0),
        Size             = UDim2.new(0.52, -110, 1, 0),
        BackgroundTransparency = 1,
        Font             = FONT,
        TextSize         = TEXT_SIZE_SMALL,
        TextColor3       = Theme.DimText,
        TextXAlignment   = Enum.TextXAlignment.Left,
        Text             = subtitle,
        TextTruncate     = Enum.TextTruncate.AtEnd,
    })

    -- Title bar buttons
    local btnHolder = new("Frame", {
        Parent                 = titleBar,
        AnchorPoint            = Vector2.new(1, 0.5),
        Position               = UDim2.new(1, -8, 0.5, 0),
        Size                   = UDim2.fromOffset(80, 22),
        BackgroundTransparency = 1,
    })
    listLayout(btnHolder, Enum.FillDirection.Horizontal, 4,
        Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)

    local function makeTitleBtn(symbol, order)
        local b = new("TextButton", {
            Parent           = btnHolder,
            LayoutOrder      = order,
            Size             = UDim2.fromOffset(22, 22),
            BackgroundColor3 = Theme.Bg3,
            BorderSizePixel  = 0,
            Text             = symbol,
            TextColor3       = Theme.SubText,
            Font             = FONT_M,
            TextSize         = 14,
            AutoButtonColor  = false,
        })
        stroke(b, Theme.Border, 1)
        b.MouseEnter:Connect(function()
            tween(b, 0.12, { BackgroundColor3 = Theme.Hover, TextColor3 = Theme.Text })
            b:FindFirstChildOfClass("UIStroke").Color = Theme.BorderHi
        end)
        b.MouseLeave:Connect(function()
            tween(b, 0.12, { BackgroundColor3 = Theme.Bg3, TextColor3 = Theme.SubText })
            b:FindFirstChildOfClass("UIStroke").Color = Theme.Border
        end)
        return b
    end

    local minBtn   = makeTitleBtn("–", 1)
    local closeBtn = makeTitleBtn("×", 2)

    minBtn.MouseButton1Click:Connect(function()
        Library:Toggle(false)
    end)
    closeBtn.MouseButton1Click:Connect(function()
        Library:Destroy()
    end)

    -- Body
    local body = new("Frame", {
        Parent           = inner,
        Name             = "Body",
        Position         = UDim2.fromOffset(0, 32),
        Size             = UDim2.new(1, 0, 1, -32),
        BackgroundTransparency = 1,
    })

    -- Sidebar
    local sidebar = new("Frame", {
        Parent           = body,
        Name             = "Sidebar",
        Size             = UDim2.new(0, sidebarW, 1, 0),
        BackgroundColor3 = Theme.Bg2,
        BorderSizePixel  = 0,
    })
    new("Frame", { -- right border
        Parent           = sidebar,
        Size             = UDim2.new(0, 1, 1, 0),
        Position         = UDim2.new(1, -1, 0, 0),
        BackgroundColor3 = Theme.Border,
        BorderSizePixel  = 0,
    })

    local searchFrame, searchBox
    if searchEnabled then
        searchFrame = new("Frame", {
            Parent           = sidebar,
            Name             = "Search",
            Size             = UDim2.new(1, 0, 0, 32),
            BackgroundColor3 = Theme.Bg2,
            BorderSizePixel  = 0,
        })
        local box = new("Frame", {
            Parent           = searchFrame,
            Size             = UDim2.new(1, -16, 0, 22),
            Position         = UDim2.fromOffset(8, 6),
            BackgroundColor3 = Theme.Bg3,
            BorderSizePixel  = 0,
        })
        stroke(box, Theme.Border, 1)
        searchBox = new("TextBox", {
            Parent                 = box,
            BackgroundTransparency = 1,
            Position               = UDim2.fromOffset(7, 0),
            Size                   = UDim2.new(1, -14, 1, 0),
            Font                   = FONT,
            TextSize               = TEXT_SIZE_SMALL,
            TextColor3             = Theme.Text,
            PlaceholderColor3      = Theme.DimText,
            PlaceholderText        = "Search",
            Text                   = "",
            ClearTextOnFocus       = false,
            TextXAlignment         = Enum.TextXAlignment.Left,
        })
    end

    local tabList = new("ScrollingFrame", {
        Parent                  = sidebar,
        Name                    = "TabList",
        Position                = searchEnabled and UDim2.fromOffset(0, 32) or UDim2.fromOffset(0, 0),
        Size                    = searchEnabled and UDim2.new(1, 0, 1, -72) or UDim2.new(1, 0, 1, -40),
        BackgroundTransparency  = 1,
        BorderSizePixel         = 0,
        ScrollBarThickness      = 0,
        ScrollingDirection      = Enum.ScrollingDirection.Y,
        CanvasSize              = UDim2.new(),
        AutomaticCanvasSize     = Enum.AutomaticSize.Y,
        ScrollBarImageColor3    = Theme.Border,
    })
    pad(tabList, 8, 8, 8, 8)
    listLayout(tabList, Enum.FillDirection.Vertical, 4)

    -- Footer
    local footer = new("Frame", {
        Parent           = sidebar,
        Name             = "Footer",
        Size             = UDim2.new(1, 0, 0, 40),
        Position         = UDim2.new(0, 0, 1, -40),
        BackgroundColor3 = Theme.Bg2,
        BorderSizePixel  = 0,
    })
    new("Frame", {
        Parent           = footer,
        Size             = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Border,
        BorderSizePixel  = 0,
    })
    new("TextLabel", {
        Parent                 = footer,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, -16, 1, 0),
        Position               = UDim2.fromOffset(12, 0),
        Font                   = FONT,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.DimText,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = LP and LP.DisplayName or "user",
    })

    -- Content holder
    local content = new("Frame", {
        Parent                 = body,
        Name                   = "Content",
        Position               = UDim2.fromOffset(sidebarW, 0),
        Size                   = UDim2.new(1, -sidebarW, 1, 0),
        BackgroundTransparency = 1,
    })

    -- Drag
    makeDraggable(root, titleBar)

    -- Toggle hotkey (PC)
    register(UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == toggleKey then
            Library:Toggle()
        end
    end))

    if mobile then makeMobileButton() end

    local self = setmetatable({
        Root      = root,
        Body      = body,
        Sidebar   = sidebar,
        TabList   = tabList,
        Content   = content,
        SearchBox = searchBox,
        TitleLabel = titleLabel,
        SubtitleLabel = subtitleLabel,
        TitleIcon = titleIconObj,
        MinSize   = minSize,
        BaseSize  = size,
        SidebarWidth = sidebarW,
        Responsive = responsive,
        Tabs      = {},
        ActiveTab = nil,
        Title     = title,
    }, Window)

    table.insert(Library.Windows, self)
    if searchBox then
        register(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            self:ApplySearch(searchBox.Text)
        end))
    end
    register(root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        self:UpdateLayout()
    end))
    if responsive then
        local elapsed = 0
        register(RS.Heartbeat:Connect(function(dt)
            elapsed += dt
            if elapsed >= 0.25 then
                elapsed = 0
                self:UpdateLayout()
            end
        end))
    end
    self:UpdateLayout()
    if opts.KeySystem then
        local keyOpts = opts.KeySystem
        local original = keyOpts.Callback
        root.Visible = false
        keyOpts.Callback = function(ok, value)
            if ok then
                root.Visible = true
                Library.Open = true
            end
            safeCall(original, ok, value)
        end
        Library:CreateKeySystem(keyOpts)
    end
    return self
end

----------------------------------------------------------------------
-- TAB
----------------------------------------------------------------------
local Tab = {}
Tab.__index = Tab

function Window:CreateTab(name, opts)
    opts = opts or {}
    name = tostring(name or "Tab")
    local icon = opts.Icon or opts.Image or opts.Symbol
    local iconPos = tostring(opts.IconPosition or opts.IconSide or "left"):lower()
    local tabHeight = (icon and (iconPos == "top" or iconPos == "bottom")) and 42 or 28

    -- Sidebar button
    local btn = new("TextButton", {
        Parent           = self.TabList,
        Name             = name,
        Size             = UDim2.new(1, 0, 0, tabHeight),
        BackgroundColor3 = Theme.Bg2,
        BorderSizePixel  = 0,
        Text             = "",
        AutoButtonColor  = false,
    })

    local indicator = new("Frame", {
        Parent           = btn,
        Name             = "Indicator",
        Size             = UDim2.new(0, 2, 1, -8),
        Position         = UDim2.new(0, 0, 0, 4),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        Visible          = false,
    })

    local labelPos = UDim2.fromOffset(12, 0)
    local labelSize = UDim2.new(1, -16, 1, 0)
    local labelAlign = Enum.TextXAlignment.Left
    local iconObj
    if icon then
        if iconPos == "right" then
            iconObj = makeIcon(btn, icon, {
                Position = UDim2.new(1, -18, 0.5, 0),
                AnchorPoint = Vector2.new(0.5, 0.5),
                Size = UDim2.fromOffset(14, 14),
            })
            labelSize = UDim2.new(1, -34, 1, 0)
        elseif iconPos == "top" then
            iconObj = makeIcon(btn, icon, {
                Position = UDim2.new(0.5, 0, 0, 6),
                AnchorPoint = Vector2.new(0.5, 0),
                Size = UDim2.fromOffset(14, 14),
            })
            labelPos = UDim2.fromOffset(0, 22)
            labelSize = UDim2.new(1, 0, 0, 18)
            labelAlign = Enum.TextXAlignment.Center
        elseif iconPos == "bottom" then
            iconObj = makeIcon(btn, icon, {
                Position = UDim2.new(0.5, 0, 1, -6),
                AnchorPoint = Vector2.new(0.5, 1),
                Size = UDim2.fromOffset(14, 14),
            })
            labelPos = UDim2.fromOffset(0, 2)
            labelSize = UDim2.new(1, 0, 0, 20)
            labelAlign = Enum.TextXAlignment.Center
        elseif iconPos == "only" then
            iconObj = makeIcon(btn, icon, {
                Position = UDim2.new(0.5, 0, 0.5, 0),
                AnchorPoint = Vector2.new(0.5, 0.5),
                Size = UDim2.fromOffset(16, 16),
            })
            labelSize = UDim2.new()
        else
            iconObj = makeIcon(btn, icon, {
                Position = UDim2.new(0, 16, 0.5, 0),
                AnchorPoint = Vector2.new(0.5, 0.5),
                Size = UDim2.fromOffset(14, 14),
            })
            labelPos = UDim2.fromOffset(28, 0)
            labelSize = UDim2.new(1, -32, 1, 0)
        end
    end

    local label = new("TextLabel", {
        Parent                 = btn,
        BackgroundTransparency = 1,
        Position               = labelPos,
        Size                   = labelSize,
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE,
        TextColor3             = Theme.SubText,
        TextXAlignment         = labelAlign,
        Text                   = name,
        TextTruncate           = Enum.TextTruncate.AtEnd,
    })

    -- Tab page
    local page = new("Frame", {
        Parent                 = self.Content,
        Name                   = name,
        Size                   = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible                = false,
    })
    pad(page, 10, 10, 10, 10)

    -- Two columns
    local left = new("ScrollingFrame", {
        Parent                 = page,
        Name                   = "Left",
        Size                   = UDim2.new(0.5, -5, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        ScrollBarThickness     = 2,
        ScrollBarImageColor3   = Theme.Border,
        CanvasSize             = UDim2.new(),
        AutomaticCanvasSize    = Enum.AutomaticSize.Y,
        ScrollingDirection     = Enum.ScrollingDirection.Y,
    })
    listLayout(left, Enum.FillDirection.Vertical, 8)

    local right = new("ScrollingFrame", {
        Parent                 = page,
        Name                   = "Right",
        Size                   = UDim2.new(0.5, -5, 1, 0),
        Position               = UDim2.new(0.5, 5, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        ScrollBarThickness     = 2,
        ScrollBarImageColor3   = Theme.Border,
        CanvasSize             = UDim2.new(),
        AutomaticCanvasSize    = Enum.AutomaticSize.Y,
        ScrollingDirection     = Enum.ScrollingDirection.Y,
    })
    listLayout(right, Enum.FillDirection.Vertical, 8)

    local tab = setmetatable({
        Window    = self,
        Name      = name,
        Button    = btn,
        Page      = page,
        Left      = left,
        Right     = right,
        Indicator = indicator,
        Label     = label,
        Icon      = iconObj,
        IconPosition = iconPos,
        IconDefaultPosition = iconObj and iconObj.Position or nil,
        IconDefaultAnchorPoint = iconObj and iconObj.AnchorPoint or nil,
        Sections  = {},
    }, Tab)

    btn.MouseEnter:Connect(function()
        if self.ActiveTab ~= tab then
            tween(label, 0.12, { TextColor3 = Theme.Text })
        end
    end)
    btn.MouseLeave:Connect(function()
        if self.ActiveTab ~= tab then
            tween(label, 0.12, { TextColor3 = Theme.SubText })
        end
    end)
    btn.MouseButton1Click:Connect(function()
        self:SelectTab(tab)
    end)

    table.insert(self.Tabs, tab)
    if not self.ActiveTab then self:SelectTab(tab) end
    return tab
end

function Window:SelectTab(tab)
    for _, t in ipairs(self.Tabs) do
        local active = (t == tab)
        t.Page.Visible = active
        t.Indicator.Visible = active
        tween(t.Label, 0.15, {
            TextColor3 = active and Theme.Text or Theme.SubText,
        })
        setIconColor(t.Icon, active and Theme.Text or Theme.SubText)
        t.Label.Font = active and FONT_SB or FONT_M
    end
    self.ActiveTab = tab
end

function Tab:UpdateLayout(stacked)
    if stacked then
        self.Left.Size = UDim2.new(1, 0, 0.5, -4)
        self.Right.Position = UDim2.new(0, 0, 0.5, 4)
        self.Right.Size = UDim2.new(1, 0, 0.5, -4)
    else
        self.Left.Size = UDim2.new(0.5, -5, 1, 0)
        self.Right.Position = UDim2.new(0.5, 5, 0, 0)
        self.Right.Size = UDim2.new(0.5, -5, 1, 0)
    end
end

function Window:UpdateLayout()
    if not self.Root or not self.Root.Parent then return end
    local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    if self.Responsive and self.BaseSize.X.Scale == 0 and self.BaseSize.Y.Scale == 0 then
        local maxW = math.max(320, viewport.X - 24)
        local maxH = math.max(260, viewport.Y - 24)
        local minW = math.min(self.MinSize.X, maxW)
        local minH = math.min(self.MinSize.Y, maxH)
        local w = clamp(self.BaseSize.X.Offset, minW, maxW)
        local h = clamp(self.BaseSize.Y.Offset, minH, maxH)
        self.Root.Size = UDim2.fromOffset(w, h)
    end
    local w = self.Root.AbsoluteSize.X
    local side = self.SidebarWidth
    if w < 440 then
        side = 84
    elseif w < 560 then
        side = 108
    end
    self.Sidebar.Size = UDim2.new(0, side, 1, 0)
    self.Content.Position = UDim2.fromOffset(side, 0)
    self.Content.Size = UDim2.new(1, -side, 1, 0)
    if self.SubtitleLabel then
        self.SubtitleLabel.Visible = w >= 500
    end
    if self.TitleLabel then
        local x = self.TitleLabel.Position.X.Offset
        self.TitleLabel.Size = (w >= 500)
            and UDim2.new(0.48, -x, 1, 0)
            or UDim2.new(1, -118, 1, 0)
    end
    local stacked = (w - side) < 390
    for _, tab in ipairs(self.Tabs) do
        if tab.Icon and tab.IconPosition ~= "only" then
            tab.Label.Visible = side > 88
            if side <= 88 then
                tab.Icon.Position = UDim2.new(0.5, 0, 0.5, 0)
                tab.Icon.AnchorPoint = Vector2.new(0.5, 0.5)
            else
                tab.Icon.Position = tab.IconDefaultPosition
                tab.Icon.AnchorPoint = tab.IconDefaultAnchorPoint
            end
        end
        tab:UpdateLayout(stacked)
    end
end

function Window:ApplySearch(query)
    query = tostring(query or "")
    local firstVisible = nil
    for _, tab in ipairs(self.Tabs) do
        local tabMatch = matchesText(tab.Name, query)
        local sectionMatch = false
        for _, section in ipairs(tab.Sections) do
            local visible = query == "" or tabMatch or matchesText(section.Name, query)
            section.Frame.Visible = visible
            if visible then sectionMatch = true end
        end
        local visible = query == "" or tabMatch or sectionMatch
        tab.Button.Visible = visible
        if visible and not firstVisible then firstVisible = tab end
    end
    if self.ActiveTab and not self.ActiveTab.Button.Visible and firstVisible then
        self:SelectTab(firstVisible)
    end
end

function Window:CreateSettingsTab(opts)
    opts = opts or {}
    local tab = self:CreateTab(opts.Name or "Settings", { Icon = opts.Icon or opts.TabIcon or "*" })
    local menu = tab:CreateSection(opts.MenuTitle or "Menu", "left")
    local colors = opts.Colors or { "Bg", "Bg2", "Bg3", "Hover", "Border", "BorderHi", "Text", "SubText", "Accent" }
    for _, key in ipairs(colors) do
        if Theme[key] then
            menu:AddColorpicker({
                Text = key,
                Default = Theme[key],
                Flag = "setting_theme_" .. key,
                Callback = function(color)
                    Library:SetTheme({ [key] = color })
                end,
            })
        end
    end
    menu:AddDropdown({
        Text = "Font",
        Options = opts.Fonts or { "Gotham", "GothamMedium", "GothamSemibold", "SourceSans", "RobotoMono" },
        Default = opts.DefaultFont or "Gotham",
        Flag = "setting_font",
        Callback = function(name)
            local enum = Enum.Font[name]
            if enum then Library:SetFont(enum) end
        end,
    })
    local setting = tab:CreateSection(opts.SettingTitle or "Setting", "right")
    setting:AddButton({
        Text = "Save setting",
        Callback = function()
            local ok, result = Library:SaveSetting(opts.Profile or Library.Settings.Profile)
            Library:Notify({ Title = "Setting", Text = ok and "Saved" or tostring(result), Duration = 3 })
        end,
    })
    setting:AddButton({
        Text = "Load setting",
        Callback = function()
            local ok, result = Library:LoadSetting(opts.Profile or Library.Settings.Profile)
            Library:Notify({ Title = "Setting", Text = ok and "Loaded" or tostring(result), Duration = 3 })
        end,
    })
    setting:AddButton({
        Text = "Unload",
        Callback = function()
            Library:Destroy()
        end,
    })
    return tab
end

----------------------------------------------------------------------
-- SECTION
----------------------------------------------------------------------
local Section = {}
Section.__index = Section

function Tab:CreateSection(name, side)
    side = (side or "left"):lower()
    local parent = (side == "right") and self.Right or self.Left

    local frame = new("Frame", {
        Parent              = parent,
        Name                = name or "Section",
        Size                = UDim2.new(1, 0, 0, 0),
        AutomaticSize       = Enum.AutomaticSize.Y,
        BackgroundColor3    = Theme.Bg2,
        BorderSizePixel     = 0,
    })
    stroke(frame, Theme.Border, 1)

    -- Header strip
    local header = new("Frame", {
        Parent           = frame,
        Size             = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = Theme.Bg3,
        BorderSizePixel  = 0,
    })
    new("Frame", {
        Parent           = header,
        Size             = UDim2.fromOffset(2, 12),
        Position         = UDim2.new(0, 8, 0.5, -6),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
    })
    new("TextLabel", {
        Parent                 = header,
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(16, 0),
        Size                   = UDim2.new(1, -22, 1, 0),
        Font                   = FONT_SB,
        TextSize               = TEXT_SIZE,
        TextColor3             = Theme.Text,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = (name or "Section"):upper(),
    })
    new("Frame", {
        Parent           = header,
        Size             = UDim2.new(1, 0, 0, 1),
        Position         = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = Theme.Border,
        BorderSizePixel  = 0,
    })

    -- Content
    local content = new("Frame", {
        Parent                 = frame,
        Name                   = "Content",
        Position               = UDim2.fromOffset(0, 26),
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
    })
    pad(content, 8, 8, 8, 8)
    listLayout(content, Enum.FillDirection.Vertical, 6)

    local section = setmetatable({
        Tab     = self,
        Frame   = frame,
        Content = content,
        Name    = name,
        Items   = {},
    }, Section)

    table.insert(self.Sections, section)
    return section
end

----------------------------------------------------------------------
-- ELEMENT BASE
----------------------------------------------------------------------
local ROW_H = 26

local function attachHover(btn, normal, hover, strokeInst)
    btn.MouseEnter:Connect(function()
        tween(btn, 0.12, { BackgroundColor3 = hover })
        if strokeInst then strokeInst.Color = Theme.BorderHi end
    end)
    btn.MouseLeave:Connect(function()
        tween(btn, 0.12, { BackgroundColor3 = normal })
        if strokeInst then strokeInst.Color = Theme.Border end
    end)
end

local function addPremiumBadge(parent, opts)
    opts = opts or {}
    if not opts.Premium and not opts.Locked then return nil end
    return new("TextLabel", {
        Parent                 = parent,
        AnchorPoint            = Vector2.new(1, 0.5),
        Position               = UDim2.new(1, -8, 0.5, 0),
        Size                   = UDim2.fromOffset(28, 14),
        BackgroundColor3       = Theme.Bg,
        BorderSizePixel        = 0,
        Font                   = FONT_B,
        TextSize               = 9,
        TextColor3             = Theme.Premium,
        Text                   = "PRO",
        ZIndex                 = parent.ZIndex + 1,
    })
end

----------------------------------------------------------------------
-- LABEL
----------------------------------------------------------------------
function Section:AddLabel(text)
    local lbl = new("TextLabel", {
        Parent                 = self.Content,
        Size                   = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        Font                   = FONT,
        TextSize               = TEXT_SIZE,
        TextColor3             = Theme.SubText,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextWrapped            = true,
        Text                   = tostring(text or ""),
    })
    local api = {}
    function api:Set(t) lbl.Text = tostring(t) end
    function api:SetColor(c) lbl.TextColor3 = c end
    return api
end

----------------------------------------------------------------------
-- PARAGRAPH
----------------------------------------------------------------------
function Section:AddParagraph(opts)
    opts = opts or {}
    local frame = new("Frame", {
        Parent           = self.Content,
        Size             = UDim2.new(1, 0, 0, 0),
        AutomaticSize    = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Bg3,
        BorderSizePixel  = 0,
    })
    stroke(frame, Theme.Border, 1)
    pad(frame, 8, 6, 8, 6)
    listLayout(frame, Enum.FillDirection.Vertical, 4)

    local title = new("TextLabel", {
        Parent                 = frame,
        Size                   = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        Font                   = FONT_SB,
        TextSize               = TEXT_SIZE,
        TextColor3             = Theme.Text,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = tostring(opts.Title or "Paragraph"),
    })
    local body = new("TextLabel", {
        Parent                 = frame,
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font                   = FONT,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.SubText,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextYAlignment         = Enum.TextYAlignment.Top,
        TextWrapped            = true,
        Text                   = tostring(opts.Text or ""),
    })

    local api = {}
    function api:SetTitle(t) title.Text = tostring(t) end
    function api:SetText(t)  body.Text  = tostring(t) end
    return api
end

----------------------------------------------------------------------
-- DIVIDER
----------------------------------------------------------------------
function Section:AddDivider()
    local frame = new("Frame", {
        Parent                 = self.Content,
        Size                   = UDim2.new(1, 0, 0, 6),
        BackgroundTransparency = 1,
    })
    new("Frame", {
        Parent           = frame,
        Size             = UDim2.new(1, 0, 0, 1),
        Position         = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = Theme.Border,
        BorderSizePixel  = 0,
    })
end

----------------------------------------------------------------------
-- BUTTON
----------------------------------------------------------------------
function Section:AddButton(opts)
    opts = opts or {}
    local text     = tostring(opts.Text or "Button")
    local callback = opts.Callback or function() end

    local btn = new("TextButton", {
        Parent           = self.Content,
        Size             = UDim2.new(1, 0, 0, ROW_H),
        BackgroundColor3 = Theme.Bg3,
        BorderSizePixel  = 0,
        Text             = "",
        AutoButtonColor  = false,
    })
    local s = stroke(btn, Theme.Border, 1)

    local label = new("TextLabel", {
        Parent                 = btn,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, -16, 1, 0),
        Position               = UDim2.fromOffset(8, 0),
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE,
        TextColor3             = Theme.Text,
        TextXAlignment         = Enum.TextXAlignment.Center,
        Text                   = text,
    })
    addPremiumBadge(btn, opts)

    -- chevron right
    new("TextLabel", {
        Parent                 = btn,
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(1, 0.5),
        Position               = UDim2.new(1, -8, 0.5, 0),
        Size                   = UDim2.fromOffset(10, 12),
        Font                   = FONT_B,
        TextSize               = 12,
        TextColor3             = Theme.DimText,
        Text                   = ">",
    })

    attachHover(btn, Theme.Bg3, Theme.Hover, s)

    btn.MouseButton1Click:Connect(function()
        if not Library:_premiumAllowed(opts) then return end
        -- click flash
        local orig = btn.BackgroundColor3
        btn.BackgroundColor3 = Theme.Accent
        label.TextColor3     = Theme.Bg
        task.delay(0.06, function()
            tween(btn,   0.18, { BackgroundColor3 = orig })
            tween(label, 0.18, { TextColor3 = Theme.Text })
        end)
        task.spawn(callback)
    end)

    local api = {}
    function api:SetText(t) label.Text = tostring(t); text = label.Text end
    function api:SetCallback(fn) callback = fn or function() end end
    function api:Fire()
        if not Library:_premiumAllowed(opts) then return end
        task.spawn(callback)
    end
    return api
end

----------------------------------------------------------------------
-- TOGGLE
----------------------------------------------------------------------
function Section:AddToggle(opts)
    opts = opts or {}
    local text     = tostring(opts.Text or "Toggle")
    local default  = opts.Default and true or false
    local flag     = opts.Flag
    local callback = opts.Callback or function() end
    default = readFlagDefault(flag, default) and true or false

    local btn = new("TextButton", {
        Parent           = self.Content,
        Size             = UDim2.new(1, 0, 0, ROW_H),
        BackgroundColor3 = Theme.Bg3,
        BorderSizePixel  = 0,
        Text             = "",
        AutoButtonColor  = false,
    })
    local s = stroke(btn, Theme.Border, 1)
    pad(btn, 8, 0, 8, 0)

    local box = new("Frame", {
        Parent           = btn,
        AnchorPoint      = Vector2.new(0, 0.5),
        Position         = UDim2.new(0, 0, 0.5, 0),
        Size             = UDim2.fromOffset(14, 14),
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel  = 0,
    })
    local boxStroke = stroke(box, Theme.Border, 1)
    local fill = new("Frame", {
        Parent           = box,
        Size             = UDim2.new(1, -4, 1, -4),
        Position         = UDim2.fromOffset(2, 2),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        Visible          = false,
    })

    local label = new("TextLabel", {
        Parent                 = btn,
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(22, 0),
        Size                   = UDim2.new(1, -22, 1, 0),
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE,
        TextColor3             = Theme.SubText,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = text,
    })
    addPremiumBadge(btn, opts)

    local state = default
    local api = {}

    local function render()
        fill.Visible      = state
        boxStroke.Color   = state and Theme.BorderHi or Theme.Border
        label.TextColor3  = state and Theme.Text     or Theme.SubText
    end

    function api:Set(v, silent)
        if not silent and v and not Library:_premiumAllowed(opts) then return end
        state = v and true or false
        render()
        if flag then Library:SetFlag(flag, state) end
        if opts.ActiveList ~= false then Library:SetActive(text, state) end
        if not silent then task.spawn(callback, state) end
    end
    function api:Get() return state end
    function api:Toggle() api:Set(not state) end
    function api:SetText(t) label.Text = tostring(t) end

    attachHover(btn, Theme.Bg3, Theme.Hover, s)

    btn.MouseButton1Click:Connect(function() api:Toggle() end)

    api:Set(default, true)
    Library:_registerFlagControl(flag, api)
    if opts.Unload ~= false then
        Library:OnUnload(function()
            if state then api:Set(false) end
        end)
    end
    return api
end

----------------------------------------------------------------------
-- SLIDER
----------------------------------------------------------------------
function Section:AddSlider(opts)
    opts = opts or {}
    local text     = tostring(opts.Text or "Slider")
    local minV     = tonumber(opts.Min) or 0
    local maxV     = tonumber(opts.Max) or 100
    local default  = clamp(tonumber(opts.Default) or minV, minV, maxV)
    local decimals = tonumber(opts.Decimals) or 0
    local suffix   = tostring(opts.Suffix or "")
    local flag     = opts.Flag
    local callback = opts.Callback or function() end
    default = clamp(tonumber(readFlagDefault(flag, default)) or default, minV, maxV)

    local frame = new("Frame", {
        Parent           = self.Content,
        Size             = UDim2.new(1, 0, 0, 38),
        BackgroundColor3 = Theme.Bg3,
        BorderSizePixel  = 0,
        Active           = true,
    })
    local s = stroke(frame, Theme.Border, 1)
    pad(frame, 8, 6, 8, 6)

    local label = new("TextLabel", {
        Parent                 = frame,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 12),
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.Text,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = text,
    })
    local valueLabel = new("TextLabel", {
        Parent                 = frame,
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(1, 0),
        Position               = UDim2.new(1, 0, 0, 0),
        Size                   = UDim2.new(0, 80, 0, 12),
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.SubText,
        TextXAlignment         = Enum.TextXAlignment.Right,
        Text                   = tostring(default) .. suffix,
    })
    addPremiumBadge(frame, opts)

    -- track
    local track = new("Frame", {
        Parent           = frame,
        Position         = UDim2.new(0, 0, 0, 18),
        Size             = UDim2.new(1, 0, 0, 8),
        BackgroundColor3 = Theme.Track,
        BorderSizePixel  = 0,
        Active           = true,
    })
    stroke(track, Theme.Border, 1)
    local fill = new("Frame", {
        Parent           = track,
        Size             = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
    })
    local thumb = new("Frame", {
        Parent           = track,
        AnchorPoint      = Vector2.new(0.5, 0.5),
        Position         = UDim2.new(0, 0, 0.5, 0),
        Size             = UDim2.fromOffset(3, 14),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
    })

    local value = default
    local api = {}

    local function render(snap)
        local range = maxV - minV
        local pct = range ~= 0 and (value - minV) / range or 0
        if snap then
            fill.Size      = UDim2.new(pct, 0, 1, 0)
            thumb.Position = UDim2.new(pct, 0, 0.5, 0)
        else
            tween(fill,  0.08, { Size = UDim2.new(pct, 0, 1, 0) })
            tween(thumb, 0.08, { Position = UDim2.new(pct, 0, 0.5, 0) })
        end
        valueLabel.Text = tostring(round(value, decimals)) .. suffix
    end

    function api:Set(v, silent)
        v = clamp(round(tonumber(v) or minV, decimals), minV, maxV)
        value = v
        render(true)
        if flag then Library:SetFlag(flag, value) end
        if not silent then task.spawn(callback, value) end
    end
    function api:Get() return value end
    function api:SetText(t) label.Text = tostring(t) end
    function api:SetRange(a, b) minV, maxV = a, b; api:Set(value, true) end

    -- input
    local dragging = false
    local function updateFromInput(input)
        if not Library:_premiumAllowed(opts) then return end
        local abs = track.AbsolutePosition.X
        local size = track.AbsoluteSize.X
        local x = clamp(input.Position.X - abs, 0, size)
        local pct = size > 0 and (x / size) or 0
        local v = minV + (maxV - minV) * pct
        api:Set(v)
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateFromInput(input)
        end
    end)
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateFromInput(input)
        end
    end)
    register(UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input)
        end
    end))
    register(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    attachHover(frame, Theme.Bg3, Theme.Hover, s)
    api:Set(default, true)
    Library:_registerFlagControl(flag, api)
    return api
end

----------------------------------------------------------------------
-- DROPDOWN (single select)
----------------------------------------------------------------------
function Section:AddDropdown(opts)
    opts = opts or {}
    local text     = tostring(opts.Text or "Dropdown")
    local options  = opts.Options or {}
    local default  = opts.Default
    local flag     = opts.Flag
    local callback = opts.Callback or function() end
    local provider = opts.Provider or opts.GetOptions or opts.DynamicOptions
    local refreshRate = tonumber(opts.RefreshRate or opts.UpdateRate) or 1
    default = readFlagDefault(flag, default)

    local frame = new("Frame", {
        Parent           = self.Content,
        Size             = UDim2.new(1, 0, 0, 38),
        BackgroundTransparency = 1,
    })

    local label = new("TextLabel", {
        Parent                 = frame,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 12),
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.Text,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = text,
    })

    local btn = new("TextButton", {
        Parent           = frame,
        Position         = UDim2.fromOffset(0, 14),
        Size             = UDim2.new(1, 0, 0, 24),
        BackgroundColor3 = Theme.Bg3,
        BorderSizePixel  = 0,
        Text             = "",
        AutoButtonColor  = false,
    })
    local s = stroke(btn, Theme.Border, 1)

    local valueLabel = new("TextLabel", {
        Parent                 = btn,
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(8, 0),
        Size                   = UDim2.new(1, -22, 1, 0),
        Font                   = FONT,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.SubText,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = "—",
    })

    local arrow = new("TextLabel", {
        Parent                 = btn,
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(1, 0.5),
        Position               = UDim2.new(1, -8, 0.5, 0),
        Size                   = UDim2.fromOffset(10, 10),
        Font                   = FONT_B,
        TextSize               = 12,
        TextColor3             = Theme.SubText,
        Text                   = "v",
    })
    addPremiumBadge(frame, opts)

    -- popup list
    local list = new("Frame", {
        Parent           = getScreenGui(),
        Visible          = false,
        BackgroundColor3 = Theme.Bg2,
        BorderSizePixel  = 0,
        ZIndex           = 1000,
    })
    stroke(list, Theme.BorderHi, 1)
    local listScroll = new("ScrollingFrame", {
        Parent                 = list,
        Size                   = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        ScrollBarThickness     = 2,
        ScrollBarImageColor3   = Theme.Border,
        CanvasSize             = UDim2.new(),
        AutomaticCanvasSize    = Enum.AutomaticSize.Y,
        ZIndex                 = 1000,
    })
    pad(listScroll, 4)
    local listLay = listLayout(listScroll, Enum.FillDirection.Vertical, 2)

    local current = nil
    local api = setmetatable({}, {})

    local function render()
        if current == nil then
            valueLabel.Text = "—"
            valueLabel.TextColor3 = Theme.SubText
        else
            valueLabel.Text = tostring(current)
            valueLabel.TextColor3 = Theme.Text
        end
    end

    function api:Set(v, silent)
        if v == nil then
            current = nil
        else
            local found = false
            for _, opt in ipairs(options) do
                if opt == v then found = true break end
            end
            current = found and v or current
        end
        render()
        if flag then Library:SetFlag(flag, current) end
        if not silent then task.spawn(callback, current) end
    end
    function api:Get() return current end

    function api:UpdatePosition()
        if not list.Visible then return end
        local absPos  = btn.AbsolutePosition
        local absSize = btn.AbsoluteSize
        local count   = #options
        local listH   = math.min(count * 24 + 8, 180)
        list.Position = UDim2.fromOffset(absPos.X, absPos.Y + absSize.Y + 4)
        list.Size     = UDim2.fromOffset(absSize.X, listH)
    end

    function api:Open()
        if Library._activeDropdown and Library._activeDropdown ~= api then
            Library._activeDropdown:Close()
        end
        Library._activeDropdown = api
        list.Visible = true
        api:UpdatePosition()
        arrow.Text = "^"
    end

    function api:Close()
        list.Visible = false
        arrow.Text = "v"
        if Library._activeDropdown == api then
            Library._activeDropdown = nil
        end
    end

    function api:Refresh(newOptions, keepSelection)
        options = newOptions or {}
        for _, c in ipairs(listScroll:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        for i, opt in ipairs(options) do
            local item = new("TextButton", {
                Parent           = listScroll,
                Size             = UDim2.new(1, 0, 0, 22),
                BackgroundColor3 = Theme.Bg2,
                BorderSizePixel  = 0,
                Text             = "",
                AutoButtonColor  = false,
                LayoutOrder      = i,
                ZIndex           = 1001,
            })
            local itemLbl = new("TextLabel", {
                Parent                 = item,
                BackgroundTransparency = 1,
                Position               = UDim2.fromOffset(8, 0),
                Size                   = UDim2.new(1, -16, 1, 0),
                Font                   = FONT,
                TextSize               = TEXT_SIZE_SMALL,
                TextColor3             = (current == opt) and Theme.Text or Theme.SubText,
                TextXAlignment         = Enum.TextXAlignment.Left,
                Text                   = tostring(opt),
                ZIndex                 = 1001,
            })
            item.MouseEnter:Connect(function()
                tween(item, 0.1, { BackgroundColor3 = Theme.Hover })
            end)
            item.MouseLeave:Connect(function()
                tween(item, 0.1, { BackgroundColor3 = Theme.Bg2 })
            end)
            item.MouseButton1Click:Connect(function()
                if not Library:_premiumAllowed(opts) then return end
                api:Set(opt)
                api:Close()
            end)
        end
        if keepSelection and current ~= nil then
            local found = false
            for _, opt in ipairs(options) do
                if opt == current then found = true break end
            end
            if not found then api:Set(nil, true) end
        elseif not keepSelection then
            api:Set(nil, true)
        end
        if list.Visible then api:UpdatePosition() end
    end
    api.SetOptions = api.Refresh

    btn.MouseEnter:Connect(function()
        tween(btn, 0.12, { BackgroundColor3 = Theme.Hover })
        s.Color = Theme.BorderHi
    end)
    btn.MouseLeave:Connect(function()
        tween(btn, 0.12, { BackgroundColor3 = Theme.Bg3 })
        s.Color = Theme.Border
    end)
    btn.MouseButton1Click:Connect(function()
        if list.Visible then api:Close() else api:Open() end
    end)

    api.Button = btn
    api.List = list

    api:Refresh(options, true)
    if default ~= nil then api:Set(default, true) end
    render()
    Library:_registerFlagControl(flag, api)
    if type(provider) == "function" then
        local elapsed = refreshRate
        local function refreshFromProvider()
            local newOptions = safeCall(provider, api)
            if type(newOptions) == "table" then
                api:Refresh(newOptions, true)
            end
        end
        refreshFromProvider()
        register(RS.Heartbeat:Connect(function(dt)
            elapsed += dt
            if elapsed >= refreshRate then
                elapsed = 0
                refreshFromProvider()
            end
        end))
    end
    return api
end

----------------------------------------------------------------------
-- MULTIDROPDOWN
----------------------------------------------------------------------
function Section:AddMultiDropdown(opts)
    opts = opts or {}
    local text     = tostring(opts.Text or "MultiDropdown")
    local options  = opts.Options or {}
    local default  = opts.Default or {}
    local maxSel   = tonumber(opts.Max) or math.huge
    local flag     = opts.Flag
    local callback = opts.Callback or function() end
    local provider = opts.Provider or opts.GetOptions or opts.DynamicOptions
    local refreshRate = tonumber(opts.RefreshRate or opts.UpdateRate) or 1
    default = readFlagDefault(flag, default) or {}

    local frame = new("Frame", {
        Parent                 = self.Content,
        Size                   = UDim2.new(1, 0, 0, 38),
        BackgroundTransparency = 1,
    })

    new("TextLabel", {
        Parent                 = frame,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 12),
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.Text,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = text,
    })

    local btn = new("TextButton", {
        Parent           = frame,
        Position         = UDim2.fromOffset(0, 14),
        Size             = UDim2.new(1, 0, 0, 24),
        BackgroundColor3 = Theme.Bg3,
        BorderSizePixel  = 0,
        Text             = "",
        AutoButtonColor  = false,
    })
    local s = stroke(btn, Theme.Border, 1)

    local valueLabel = new("TextLabel", {
        Parent                 = btn,
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(8, 0),
        Size                   = UDim2.new(1, -22, 1, 0),
        Font                   = FONT,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.SubText,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = "—",
        TextTruncate           = Enum.TextTruncate.AtEnd,
    })

    local arrow = new("TextLabel", {
        Parent                 = btn,
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(1, 0.5),
        Position               = UDim2.new(1, -8, 0.5, 0),
        Size                   = UDim2.fromOffset(10, 10),
        Font                   = FONT_B,
        TextSize               = 12,
        TextColor3             = Theme.SubText,
        Text                   = "v",
    })
    addPremiumBadge(frame, opts)

    local list = new("Frame", {
        Parent           = getScreenGui(),
        Visible          = false,
        BackgroundColor3 = Theme.Bg2,
        BorderSizePixel  = 0,
        ZIndex           = 1000,
    })
    stroke(list, Theme.BorderHi, 1)
    local listScroll = new("ScrollingFrame", {
        Parent                 = list,
        Size                   = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        ScrollBarThickness     = 2,
        ScrollBarImageColor3   = Theme.Border,
        CanvasSize             = UDim2.new(),
        AutomaticCanvasSize    = Enum.AutomaticSize.Y,
        ZIndex                 = 1000,
    })
    pad(listScroll, 4)
    listLayout(listScroll, Enum.FillDirection.Vertical, 2)

    local selected = {}
    local items = {}

    local api = {}

    local function render()
        local arr = {}
        for k, v in pairs(selected) do
            if v then table.insert(arr, k) end
        end
        if #arr == 0 then
            valueLabel.Text = "—"
            valueLabel.TextColor3 = Theme.SubText
        else
            table.sort(arr, function(a, b) return tostring(a) < tostring(b) end)
            valueLabel.Text = table.concat(arr, ", ")
            valueLabel.TextColor3 = Theme.Text
        end
        for opt, item in pairs(items) do
            if item and item.Box then
                item.Fill.Visible = selected[opt] and true or false
                item.Box:FindFirstChildOfClass("UIStroke").Color =
                    selected[opt] and Theme.BorderHi or Theme.Border
                item.Label.TextColor3 =
                    selected[opt] and Theme.Text or Theme.SubText
            end
        end
    end

    function api:Set(tbl, silent)
        selected = {}
        local source = type(tbl) == "table" and tbl or (tbl ~= nil and { tbl } or {})
        for _, v in ipairs(source) do selected[v] = true end
        render()
        if flag then Library:SetFlag(flag, self:Get()) end
        if not silent then task.spawn(callback, self:Get()) end
    end
    function api:Get()
        local arr = {}
        for k, v in pairs(selected) do if v then table.insert(arr, k) end end
        return arr
    end
    function api:Toggle(opt)
        if not Library:_premiumAllowed(opts) then return end
        if selected[opt] then
            selected[opt] = nil
        else
            local count = 0
            for _, v in pairs(selected) do if v then count += 1 end end
            if count >= maxSel then return end
            selected[opt] = true
        end
        render()
        if flag then Library:SetFlag(flag, self:Get()) end
        task.spawn(callback, self:Get())
    end

    function api:UpdatePosition()
        if not list.Visible then return end
        local absPos  = btn.AbsolutePosition
        local absSize = btn.AbsoluteSize
        local count   = #options
        local listH   = math.min(count * 24 + 8, 180)
        list.Position = UDim2.fromOffset(absPos.X, absPos.Y + absSize.Y + 4)
        list.Size     = UDim2.fromOffset(absSize.X, listH)
    end

    function api:Open()
        if Library._activeDropdown and Library._activeDropdown ~= api then
            Library._activeDropdown:Close()
        end
        Library._activeDropdown = api
        list.Visible = true
        api:UpdatePosition()
        arrow.Text   = "^"
    end
    function api:Close()
        list.Visible = false
        arrow.Text   = "v"
        if Library._activeDropdown == api then Library._activeDropdown = nil end
    end

    function api:Refresh(newOptions)
        options = newOptions or {}
        for _, c in ipairs(listScroll:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        items = {}
        for i, opt in ipairs(options) do
            local item = new("TextButton", {
                Parent           = listScroll,
                Size             = UDim2.new(1, 0, 0, 22),
                BackgroundColor3 = Theme.Bg2,
                BorderSizePixel  = 0,
                Text             = "",
                AutoButtonColor  = false,
                LayoutOrder      = i,
                ZIndex           = 1001,
            })
            local box = new("Frame", {
                Parent           = item,
                AnchorPoint      = Vector2.new(0, 0.5),
                Position         = UDim2.new(0, 6, 0.5, 0),
                Size             = UDim2.fromOffset(12, 12),
                BackgroundColor3 = Theme.Bg,
                BorderSizePixel  = 0,
                ZIndex           = 1001,
            })
            stroke(box, Theme.Border, 1)
            local f = new("Frame", {
                Parent           = box,
                Size             = UDim2.new(1, -4, 1, -4),
                Position         = UDim2.fromOffset(2, 2),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel  = 0,
                Visible          = false,
                ZIndex           = 1002,
            })
            local lbl = new("TextLabel", {
                Parent                 = item,
                BackgroundTransparency = 1,
                Position               = UDim2.fromOffset(24, 0),
                Size                   = UDim2.new(1, -28, 1, 0),
                Font                   = FONT,
                TextSize               = TEXT_SIZE_SMALL,
                TextColor3             = Theme.SubText,
                TextXAlignment         = Enum.TextXAlignment.Left,
                Text                   = tostring(opt),
                ZIndex                 = 1001,
            })
            item.MouseEnter:Connect(function() tween(item, 0.1, { BackgroundColor3 = Theme.Hover }) end)
            item.MouseLeave:Connect(function() tween(item, 0.1, { BackgroundColor3 = Theme.Bg2 }) end)
            item.MouseButton1Click:Connect(function() api:Toggle(opt) end)
            items[opt] = { Box = box, Fill = f, Label = lbl }
        end
        local valid = {}
        for _, opt in ipairs(options) do valid[opt] = true end
        for opt in pairs(selected) do
            if not valid[opt] then selected[opt] = nil end
        end
        render()
    end
    api.SetOptions = api.Refresh

    btn.MouseEnter:Connect(function() tween(btn, 0.12, { BackgroundColor3 = Theme.Hover }); s.Color = Theme.BorderHi end)
    btn.MouseLeave:Connect(function() tween(btn, 0.12, { BackgroundColor3 = Theme.Bg3 }); s.Color = Theme.Border end)
    btn.MouseButton1Click:Connect(function()
        if list.Visible then api:Close() else api:Open() end
    end)

    api.Button = btn
    api.List = list

    api:Refresh(options)
    api:Set(default, true)
    Library:_registerFlagControl(flag, api)
    if type(provider) == "function" then
        local elapsed = refreshRate
        local function refreshFromProvider()
            local newOptions = safeCall(provider, api)
            if type(newOptions) == "table" then
                api:Refresh(newOptions)
            end
        end
        refreshFromProvider()
        register(RS.Heartbeat:Connect(function(dt)
            elapsed += dt
            if elapsed >= refreshRate then
                elapsed = 0
                refreshFromProvider()
            end
        end))
    end
    return api
end

----------------------------------------------------------------------
-- TEXTBOX
----------------------------------------------------------------------
function Section:AddTextbox(opts)
    opts = opts or {}
    local text        = tostring(opts.Text or "Input")
    local placeholder = tostring(opts.Placeholder or "")
    local default     = tostring(opts.Default or "")
    local clearOnFocus= opts.ClearOnFocus and true or false
    local numeric     = opts.Numeric and true or false
    local flag        = opts.Flag
    local callback    = opts.Callback or function() end
    default = tostring(readFlagDefault(flag, default) or "")

    local frame = new("Frame", {
        Parent                 = self.Content,
        Size                   = UDim2.new(1, 0, 0, 38),
        BackgroundTransparency = 1,
    })

    new("TextLabel", {
        Parent                 = frame,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 12),
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.Text,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = text,
    })

    local box = new("Frame", {
        Parent           = frame,
        Position         = UDim2.fromOffset(0, 14),
        Size             = UDim2.new(1, 0, 0, 24),
        BackgroundColor3 = Theme.Bg3,
        BorderSizePixel  = 0,
    })
    local s = stroke(box, Theme.Border, 1)

    local input = new("TextBox", {
        Parent                 = box,
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(8, 0),
        Size                   = UDim2.new(1, -16, 1, 0),
        Font                   = FONT,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.Text,
        PlaceholderColor3      = Theme.DimText,
        PlaceholderText        = placeholder,
        Text                   = default,
        ClearTextOnFocus       = clearOnFocus,
        TextXAlignment         = Enum.TextXAlignment.Left,
        ClipsDescendants       = true,
    })

    local settingText = false
    local api = {}
    function api:Set(t, silent)
        t = tostring(t)
        if numeric then t = (tonumber(t) and t) or "" end
        settingText = true
        input.Text = t
        settingText = false
        if flag then Library:SetFlag(flag, t) end
        if not silent then task.spawn(callback, t) end
    end
    function api:Get() return input.Text end

    if opts.Realtime or opts.Live then
        register(input:GetPropertyChangedSignal("Text"):Connect(function()
            if settingText then return end
            if flag then Library:SetFlag(flag, input.Text) end
            task.spawn(callback, input.Text, false)
        end))
    end

    input.Focused:Connect(function() s.Color = Theme.BorderHi end)
    input.FocusLost:Connect(function(enter)
        s.Color = Theme.Border
        if not Library:_premiumAllowed(opts) then
            input.Text = default
            return
        end
        if numeric and tonumber(input.Text) == nil then
            input.Text = ""
        end
        if flag then Library:SetFlag(flag, input.Text) end
        task.spawn(callback, input.Text, enter)
    end)

    if default ~= "" and flag then Library:SetFlag(flag, default) end
    Library:_registerFlagControl(flag, api)
    return api
end

function Section:AddSearchBar(opts)
    opts = opts or {}
    opts.Text = opts.Text or "Search"
    opts.Placeholder = opts.Placeholder or "Search"
    opts.Realtime = true
    return self:AddTextbox(opts)
end

----------------------------------------------------------------------
-- KEYBIND
----------------------------------------------------------------------
function Section:AddKeybind(opts)
    opts = opts or {}
    local text        = tostring(opts.Text or "Keybind")
    local default     = opts.Default
    local mode        = (opts.Mode or "Toggle"):lower() -- "Toggle" | "Hold" | "Always"
    local flag        = opts.Flag
    local callback    = opts.Callback or function() end
    local onChanged   = opts.OnChanged or function() end
    default = readFlagDefault(flag, default)

    local frame = new("Frame", {
        Parent           = self.Content,
        Size             = UDim2.new(1, 0, 0, ROW_H),
        BackgroundColor3 = Theme.Bg3,
        BorderSizePixel  = 0,
    })
    local s = stroke(frame, Theme.Border, 1)
    pad(frame, 8, 0, 8, 0)

    local label = new("TextLabel", {
        Parent                 = frame,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, -90, 1, 0),
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE,
        TextColor3             = Theme.Text,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = text,
    })

    local btn = new("TextButton", {
        Parent           = frame,
        AnchorPoint      = Vector2.new(1, 0.5),
        Position         = UDim2.new(1, 0, 0.5, 0),
        Size             = UDim2.fromOffset(80, 18),
        BackgroundColor3 = Theme.Bg2,
        BorderSizePixel  = 0,
        Text             = keyToString(default),
        Font             = FONT_M,
        TextSize         = TEXT_SIZE_SMALL,
        TextColor3       = Theme.SubText,
        AutoButtonColor  = false,
    })
    local bs = stroke(btn, Theme.Border, 1)

    local key = default
    local listening = false
    local toggled = false

    local api = {}
    function api:Set(k, silent)
        key = k
        btn.Text = keyToString(key)
        if flag then Library:SetFlag(flag, key) end
        if not silent then task.spawn(onChanged, key) end
    end
    function api:Get() return key end
    function api:GetMode() return mode end
    function api:SetMode(m) mode = (m or "Toggle"):lower() end
    function api:Cancel()
        if not listening then return end
        listening = false
        btn.Text = keyToString(key)
        bs.Color = Theme.Border
        if Library._listeningKeybind == api then
            Library._listeningKeybind = nil
        end
    end

    btn.MouseButton1Click:Connect(function()
        if listening then
            -- Click the listen button again to cancel listening
            api:Cancel()
            return
        end
        if Library._listeningKeybind and Library._listeningKeybind ~= api then
            Library._listeningKeybind:Cancel()
        end
        listening = true
        Library._listeningKeybind = api
        btn.Text = "..."
        bs.Color = Theme.BorderHi
    end)

    register(UIS.InputBegan:Connect(function(input, processed)
        if listening then
            -- Skip UI-processed events (clicks that opened listening, TextBox keys, etc.)
            if processed then return end
            if input.UserInputType == Enum.UserInputType.Keyboard then
                if input.KeyCode == Enum.KeyCode.Escape then
                    api:Cancel()
                    return
                elseif input.KeyCode == Enum.KeyCode.Backspace then
                    api:Set(nil)
                else
                    api:Set(input.KeyCode)
                end
            elseif input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.MouseButton2
                or input.UserInputType == Enum.UserInputType.MouseButton3 then
                api:Set(input.UserInputType)
            else
                return
            end
            listening = false
            bs.Color = Theme.Border
            if Library._listeningKeybind == api then
                Library._listeningKeybind = nil
            end
            return
        end
        if processed then return end
        if isKeyPressed(key, input) then
            if not Library:_premiumAllowed(opts) then return end
            if mode == "toggle" then
                toggled = not toggled
                task.spawn(callback, toggled)
            elseif mode == "hold" then
                task.spawn(callback, true)
            elseif mode == "always" then
                task.spawn(callback)
            end
        end
    end))
    register(UIS.InputEnded:Connect(function(input)
        if mode == "hold" and isKeyPressed(key, input) then
            task.spawn(callback, false)
        end
    end))

    attachHover(frame, Theme.Bg3, Theme.Hover, s)
    if default and flag then Library:SetFlag(flag, default) end
    Library:_registerFlagControl(flag, api)
    Library:OnUnload(function()
        if toggled then
            toggled = false
            task.spawn(callback, false)
        end
    end)
    return api
end

----------------------------------------------------------------------
-- COLORPICKER (HSV + Alpha)
----------------------------------------------------------------------
function Section:AddColorpicker(opts)
    opts = opts or {}
    local text     = tostring(opts.Text or "Color")
    local default  = opts.Default or Color3.fromRGB(255, 255, 255)
    local hasAlpha = opts.Alpha ~= false
    local flag     = opts.Flag
    local callback = opts.Callback or function() end
    default = readFlagDefault(flag, default) or default
    if typeof(default) ~= "Color3" then default = Color3.fromRGB(255, 255, 255) end

    local frame = new("Frame", {
        Parent           = self.Content,
        Size             = UDim2.new(1, 0, 0, ROW_H),
        BackgroundColor3 = Theme.Bg3,
        BorderSizePixel  = 0,
    })
    local s = stroke(frame, Theme.Border, 1)
    pad(frame, 8, 0, 8, 0)

    local label = new("TextLabel", {
        Parent                 = frame,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, -38, 1, 0),
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE,
        TextColor3             = Theme.Text,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = text,
    })

    local swatch = new("TextButton", {
        Parent           = frame,
        AnchorPoint      = Vector2.new(1, 0.5),
        Position         = UDim2.new(1, 0, 0.5, 0),
        Size             = UDim2.fromOffset(28, 16),
        BackgroundColor3 = default,
        BorderSizePixel  = 0,
        Text             = "",
        AutoButtonColor  = false,
    })
    stroke(swatch, Theme.BorderHi, 1)

    -- Popup
    local popup = new("Frame", {
        Parent           = getScreenGui(),
        Visible          = false,
        Size             = UDim2.fromOffset(220, hasAlpha and 200 or 180),
        BackgroundColor3 = Theme.Bg2,
        BorderSizePixel  = 0,
        ZIndex           = 1500,
    })
    stroke(popup, Theme.BorderHi, 1)
    pad(popup, 8)

    -- SV plane: pure-hue base, white horizontal overlay (saturation),
    --           black vertical overlay (value)
    local sv = new("Frame", {
        Parent           = popup,
        Size             = UDim2.new(1, -16, 0, 120),
        BackgroundColor3 = Color3.fromRGB(255, 0, 0),
        BorderSizePixel  = 0,
        ZIndex           = 1501,
        Active           = true,
    })
    -- Saturation: white -> transparent (left -> right)
    local satOverlay = new("Frame", {
        Parent           = sv,
        Size             = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel  = 0,
        ZIndex           = 1502,
    })
    new("UIGradient", {
        Parent       = satOverlay,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
    })
    -- Value: transparent -> black (top -> bottom)
    local valOverlay = new("Frame", {
        Parent           = sv,
        Size             = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BorderSizePixel  = 0,
        ZIndex           = 1503,
    })
    new("UIGradient", {
        Parent       = valOverlay,
        Rotation     = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
        }),
    })
    local svCursor = new("Frame", {
        Parent           = sv,
        AnchorPoint      = Vector2.new(0.5, 0.5),
        Size             = UDim2.fromOffset(6, 6),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel  = 0,
        ZIndex           = 1504,
    })
    stroke(svCursor, Color3.fromRGB(0, 0, 0), 1)

    -- Hue bar
    local hue = new("Frame", {
        Parent           = popup,
        Position         = UDim2.fromOffset(0, 132),
        Size             = UDim2.new(1, -16, 0, 12),
        BorderSizePixel  = 0,
        ZIndex           = 1501,
    })
    new("UIGradient", {
        Parent = hue,
        Color  = ColorSequence.new({
            ColorSequenceKeypoint.new(0,    Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(1/6,  Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(2/6,  Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(3/6,  Color3.fromRGB(0, 255, 255)),
            ColorSequenceKeypoint.new(4/6,  Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(5/6,  Color3.fromRGB(255, 0, 255)),
            ColorSequenceKeypoint.new(1,    Color3.fromRGB(255, 0, 0)),
        }),
    })
    local hueCursor = new("Frame", {
        Parent           = hue,
        AnchorPoint      = Vector2.new(0.5, 0.5),
        Size             = UDim2.fromOffset(2, 16),
        Position         = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        ZIndex           = 1503,
    })
    stroke(hueCursor, Color3.fromRGB(0, 0, 0), 1)

    local alphaBar, alphaCursor
    if hasAlpha then
        alphaBar = new("Frame", {
            Parent           = popup,
            Position         = UDim2.fromOffset(0, 150),
            Size             = UDim2.new(1, -16, 0, 12),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel  = 0,
            ZIndex           = 1501,
        })
        new("UIGradient", {
            Parent = alphaBar,
            Color  = ColorSequence.new(Color3.fromRGB(0,0,0), Color3.fromRGB(255,255,255)),
        })
        alphaCursor = new("Frame", {
            Parent           = alphaBar,
            AnchorPoint      = Vector2.new(0.5, 0.5),
            Size             = UDim2.fromOffset(2, 16),
            Position         = UDim2.new(1, 0, 0.5, 0),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel  = 0,
            ZIndex           = 1503,
        })
        stroke(alphaCursor, Color3.fromRGB(0, 0, 0), 1)
    end

    -- Hex input
    local hex = new("TextBox", {
        Parent                 = popup,
        Position               = UDim2.fromOffset(0, hasAlpha and 170 or 150),
        Size                   = UDim2.new(1, -16, 0, 20),
        BackgroundColor3       = Theme.Bg3,
        BorderSizePixel        = 0,
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.Text,
        PlaceholderText        = "#FFFFFF",
        Text                   = "",
        ClearTextOnFocus       = false,
        ZIndex                 = 1501,
    })
    stroke(hex, Theme.Border, 1)

    -- State
    local h, s2, v = 0, 0, 1
    do
        local r, g, b = default.R, default.G, default.B
        h, s2, v = Color3.toHSV(default)
    end
    local alpha = 1

    local api = {}

    local function color()
        return Color3.fromHSV(h, s2, v)
    end
    local function rgbToHex(c)
        return string.format("#%02X%02X%02X", math.floor(c.R*255+0.5), math.floor(c.G*255+0.5), math.floor(c.B*255+0.5))
    end
    local function render()
        local c = color()
        sv.BackgroundColor3   = Color3.fromHSV(h, 1, 1)
        swatch.BackgroundColor3 = c
        svCursor.Position     = UDim2.fromScale(s2, 1 - v)
        hueCursor.Position    = UDim2.new(h, 0, 0.5, 0)
        if alphaCursor then alphaCursor.Position = UDim2.new(alpha, 0, 0.5, 0) end
        hex.Text = rgbToHex(c)
    end

    function api:Set(c, a, silent)
        if c then h, s2, v = Color3.toHSV(c) end
        if a ~= nil then alpha = clamp(a, 0, 1) end
        render()
        if flag then Library:SetFlag(flag, color()) end
        if not silent then task.spawn(callback, color(), alpha) end
    end
    function api:SetFlagValue(c, silent)
        api:Set(c, nil, silent)
    end
    function api:Get() return color(), alpha end

    function api:UpdatePosition()
        if not popup.Visible then return end
        local absPos  = swatch.AbsolutePosition
        local absSize = swatch.AbsoluteSize
        local px = absPos.X + absSize.X - popup.AbsoluteSize.X
        local py = absPos.Y + absSize.Y + 6
        popup.Position = UDim2.fromOffset(px, py)
    end

    function api:Open()
        if Library._activeColorpicker and Library._activeColorpicker ~= api then
            Library._activeColorpicker:Close()
        end
        Library._activeColorpicker = api
        popup.Visible = true
        api:UpdatePosition()
    end
    function api:Close()
        popup.Visible = false
        if Library._activeColorpicker == api then Library._activeColorpicker = nil end
    end

    swatch.MouseButton1Click:Connect(function()
        if not Library:_premiumAllowed(opts) then return end
        if popup.Visible then api:Close() else api:Open() end
    end)

    -- SV interaction
    local svDrag = false
    local function updateSV(input)
        local p = sv.AbsolutePosition
        local sz = sv.AbsoluteSize
        local x = clamp(input.Position.X - p.X, 0, sz.X)
        local y = clamp(input.Position.Y - p.Y, 0, sz.Y)
        s2 = (sz.X > 0) and x / sz.X or 0
        v  = 1 - ((sz.Y > 0) and y / sz.Y or 0)
        api:Set(nil)
    end
    sv.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            svDrag = true; updateSV(input)
        end
    end)
    register(UIS.InputChanged:Connect(function(input)
        if svDrag and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            updateSV(input)
        end
    end))
    register(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            svDrag = false
        end
    end))

    -- Hue
    local hueDrag = false
    local function updateHue(input)
        local p = hue.AbsolutePosition
        local sz = hue.AbsoluteSize
        local x = clamp(input.Position.X - p.X, 0, sz.X)
        h = (sz.X > 0) and x / sz.X or 0
        api:Set(nil)
    end
    hue.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            hueDrag = true; updateHue(input)
        end
    end)
    register(UIS.InputChanged:Connect(function(input)
        if hueDrag and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            updateHue(input)
        end
    end))
    register(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            hueDrag = false
        end
    end))

    if hasAlpha then
        local aDrag = false
        local function updateA(input)
            local p = alphaBar.AbsolutePosition
            local sz = alphaBar.AbsoluteSize
            local x = clamp(input.Position.X - p.X, 0, sz.X)
            alpha = (sz.X > 0) and x / sz.X or 0
            api:Set(nil, alpha)
        end
        alphaBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                aDrag = true; updateA(input)
            end
        end)
        register(UIS.InputChanged:Connect(function(input)
            if aDrag and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
                updateA(input)
            end
        end))
        register(UIS.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                aDrag = false
            end
        end))
    end

    hex.FocusLost:Connect(function()
        local txt = hex.Text:gsub("#", ""):gsub("%s", "")
        if #txt == 6 then
            local r = tonumber(txt:sub(1,2), 16)
            local g = tonumber(txt:sub(3,4), 16)
            local b = tonumber(txt:sub(5,6), 16)
            if r and g and b then
                api:Set(Color3.fromRGB(r, g, b))
                return
            end
        end
        render()
    end)

    attachHover(frame, Theme.Bg3, Theme.Hover, s)
    api.Button = swatch
    api.Popup  = popup
    api:Set(default, 1, true)
    Library:_registerFlagControl(flag, api)
    return api
end

function Library:CreateModal(opts)
    opts = opts or {}
    if Library._activeModal and opts.ClosePrevious ~= false then
        Library._activeModal:Close()
    end
    local sg = getScreenGui()
    local overlay = new("Frame", {
        Parent = sg,
        Name = "Modal",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = tonumber(opts.Dim) or 0.35,
        BorderSizePixel = 0,
        ZIndex = 7000,
    })
    local card = new("Frame", {
        Parent = overlay,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = opts.Size or UDim2.fromOffset(340, opts.Input and 190 or 160),
        BackgroundColor3 = Theme.Bg2,
        BorderSizePixel = 0,
        Active = true,
        ZIndex = 7001,
    })
    stroke(card, Theme.BorderHi, 1)
    pad(card, 12, 10, 12, 12)
    listLayout(card, Enum.FillDirection.Vertical, 8)
    local title = new("TextLabel", {
        Parent = card,
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Font = FONT_SB,
        TextSize = TEXT_SIZE_TITLE,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = tostring(opts.Title or "Modal"),
        ZIndex = 7002,
    })
    local body = new("TextLabel", {
        Parent = card,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font = FONT,
        TextSize = TEXT_SIZE_SMALL,
        TextColor3 = Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        Text = tostring(opts.Text or ""),
        ZIndex = 7002,
    })
    local inputBox
    if opts.Input then
        local box = new("Frame", {
            Parent = card,
            Size = UDim2.new(1, 0, 0, 28),
            BackgroundColor3 = Theme.Bg3,
            BorderSizePixel = 0,
            ZIndex = 7002,
        })
        stroke(box, Theme.Border, 1)
        inputBox = new("TextBox", {
            Parent = box,
            Position = UDim2.fromOffset(8, 0),
            Size = UDim2.new(1, -16, 1, 0),
            BackgroundTransparency = 1,
            Font = FONT,
            TextSize = TEXT_SIZE_SMALL,
            TextColor3 = Theme.Text,
            PlaceholderColor3 = Theme.DimText,
            PlaceholderText = tostring(opts.Placeholder or ""),
            Text = tostring(opts.Default or ""),
            ClearTextOnFocus = false,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 7003,
        })
    end
    local holder = new("Frame", {
        Parent = card,
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        ZIndex = 7002,
    })
    listLayout(holder, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
    local api = {}
    function api:Close()
        if Library._activeModal == api then Library._activeModal = nil end
        if overlay.Parent then overlay:Destroy() end
    end
    function api:GetInput()
        return inputBox and inputBox.Text or nil
    end
    function api:SetText(value)
        body.Text = tostring(value or "")
    end
    function api:SetTitle(value)
        title.Text = tostring(value or "")
    end
    for i, button in ipairs(opts.Buttons or { { Text = "OK", Close = true } }) do
        local b = new("TextButton", {
            Parent = holder,
            LayoutOrder = i,
            Size = UDim2.fromOffset(84, 24),
            BackgroundColor3 = Theme.Bg3,
            BorderSizePixel = 0,
            Font = FONT_M,
            TextSize = TEXT_SIZE_SMALL,
            TextColor3 = Theme.Text,
            Text = tostring(button.Text or "OK"),
            AutoButtonColor = false,
            ZIndex = 7003,
        })
        local bs = stroke(b, Theme.Border, 1)
        attachHover(b, Theme.Bg3, Theme.Hover, bs)
        b.MouseButton1Click:Connect(function()
            local close = button.Close ~= false
            if button.Callback then
                local result = safeCall(button.Callback, api:GetInput(), api)
                if result == false then close = false end
            end
            if close then api:Close() end
        end)
    end
    makeDraggable(card, card)
    Library._activeModal = api
    task.defer(function()
        if inputBox then inputBox:CaptureFocus() end
    end)
    return api
end

function Library:CreateKeySystem(opts)
    opts = opts or {}
    local keys = normalizeKeyList(opts.Keys or opts.Key)
    local required = opts.Required ~= false
    local callback = opts.Callback or function() end
    local caseSensitive = opts.CaseSensitive and true or false
    local api = { Authenticated = false }
    function api:Check(value)
        if #keys == 0 then return true end
        value = tostring(value or "")
        for _, key in ipairs(keys) do
            local a = tostring(key)
            local b = value
            if not caseSensitive then
                a = a:lower()
                b = b:lower()
            end
            if a == b then return true end
        end
        return false
    end
    function api:Success(value)
        self.Authenticated = true
        Library.KeyAuthenticated = true
        if opts.SaveKey and writefile then
            ensureSettingFolder()
            pcall(function() writefile(settingPath(opts.SaveName or "key"):gsub("%.json$", ".txt"), tostring(value or "")) end)
        end
        task.spawn(callback, true, value)
    end
    function api:Fail(value)
        task.spawn(callback, false, value)
        Library:Notify({ Title = "Key system", Text = "Invalid key", Duration = 3 })
    end
    if opts.Enabled == false or #keys == 0 then
        api:Success("")
        return api
    end
    if opts.SaveKey and readfile and isfile then
        local path = settingPath(opts.SaveName or "key"):gsub("%.json$", ".txt")
        if isfile(path) then
            local saved = readfile(path)
            if api:Check(saved) then
                api:Success(saved)
                return api
            end
        end
    end
    local modal
    local buttons = {
        {
            Text = tostring(opts.SubmitText or "Submit"),
            Close = false,
            Callback = function(value)
                if api:Check(value) then
                    api:Success(value)
                    if modal then modal:Close() end
                else
                    api:Fail(value)
                    return false
                end
            end,
        },
    }
    if not required then
        table.insert(buttons, {
            Text = tostring(opts.SkipText or "Skip"),
            Callback = function()
                api:Success("")
            end,
        })
    end
    modal = self:CreateModal({
        Title = opts.Title or "Key system",
        Text = opts.Text or "Enter key",
        Input = true,
        Placeholder = opts.Placeholder or "Key",
        Buttons = buttons,
        ClosePrevious = opts.ClosePrevious,
    })
    api.Modal = modal
    return api
end

function Library:SetActive(name, state, meta)
    name = tostring(name or "")
    if name == "" then return end
    if state then
        Library.ActiveListItems[name] = meta or true
    else
        Library.ActiveListItems[name] = nil
    end
    if Library.ActiveListApi then
        Library.ActiveListApi:Refresh()
    end
end

function Library:CreateActiveList(opts)
    opts = opts or {}
    local sg = getScreenGui()
    if Library.ActiveListHolder and Library.ActiveListHolder.Parent then
        Library.ActiveListHolder:Destroy()
    end
    local side = tostring(opts.Side or opts.Position or "right"):lower()
    local holder = new("Frame", {
        Parent = sg,
        Name = "ActiveList",
        AnchorPoint = Vector2.new(side == "left" and 0 or 1, 0),
        Position = side == "left" and UDim2.new(0, 12, 0, tonumber(opts.Top) or 58) or UDim2.new(1, -12, 0, tonumber(opts.Top) or 58),
        Size = UDim2.fromOffset(190, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Bg2,
        BackgroundTransparency = opts.Transparent and 1 or 0,
        BorderSizePixel = 0,
        ZIndex = 4500,
    })
    stroke(holder, Theme.Border, 1)
    pad(holder, 8, 6, 8, 6)
    listLayout(holder, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
    local title = new("TextLabel", {
        Parent = holder,
        Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1,
        Font = FONT_SB,
        TextSize = TEXT_SIZE_SMALL,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = tostring(opts.Title or "Enabled"),
        ZIndex = 4501,
    })
    local api = { Holder = holder, Title = title }
    function api:Refresh()
        for _, child in ipairs(holder:GetChildren()) do
            if child.Name == "Item" then child:Destroy() end
        end
        local names = {}
        for name in pairs(Library.ActiveListItems) do table.insert(names, name) end
        table.sort(names)
        holder.Visible = opts.HideEmpty and #names == 0 and false or true
        for _, name in ipairs(names) do
            new("TextLabel", {
                Parent = holder,
                Name = "Item",
                Size = UDim2.new(1, 0, 0, 14),
                BackgroundTransparency = 1,
                Font = FONT,
                TextSize = TEXT_SIZE_SMALL,
                TextColor3 = Theme.SubText,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = tostring(opts.Prefix or "> ") .. name,
                TextTruncate = Enum.TextTruncate.AtEnd,
                ZIndex = 4501,
            })
        end
    end
    function api:Destroy()
        if holder.Parent then holder:Destroy() end
        if Library.ActiveListApi == api then Library.ActiveListApi = nil end
    end
    Library.ActiveListHolder = holder
    Library.ActiveListApi = api
    api:Refresh()
    return api
end

function Library:CreateWatermark(opts)
    opts = opts or {}
    local sg = getScreenGui()
    local side = tostring(opts.Side or "left"):lower()
    local items = opts.Items or { "name", "fps", "time" }
    local label = new("TextLabel", {
        Parent = sg,
        Name = "Watermark",
        AnchorPoint = Vector2.new(side == "right" and 1 or 0, 0),
        Position = side == "right" and UDim2.new(1, -12, 0, 12) or UDim2.new(0, 12, 0, 12),
        Size = UDim2.fromOffset(280, 24),
        BackgroundColor3 = Theme.Bg2,
        BorderSizePixel = 0,
        Font = FONT_M,
        TextSize = TEXT_SIZE_SMALL,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "",
        ZIndex = 4600,
    })
    stroke(label, Theme.BorderHi, 1)
    pad(label, 8, 0, 8, 0)
    local fps = 0
    local acc = 0
    local frames = 0
    local api = { Label = label, Items = items }
    local function formatItem(item)
        if type(item) == "function" then
            return tostring(safeCall(item, api) or "")
        end
        item = tostring(item):lower()
        if item == "name" then return Library.Name end
        if item == "version" then return "v" .. Library.Version end
        if item == "fps" then return tostring(fps) .. " fps" end
        if item == "time" then return os.date("%H:%M:%S") end
        if item == "players" then return tostring(#Players:GetPlayers()) .. " players" end
        if item == "user" then return LP and LP.Name or "user" end
        return item
    end
    function api:Refresh()
        local parts = {}
        for _, item in ipairs(self.Items) do
            local text = formatItem(item)
            if text ~= "" then table.insert(parts, text) end
        end
        label.Text = table.concat(parts, " | ")
    end
    function api:SetItems(newItems)
        self.Items = newItems or self.Items
        self:Refresh()
    end
    function api:SetText(text)
        self.Items = { function() return text end }
        self:Refresh()
    end
    function api:Destroy()
        if label.Parent then label:Destroy() end
    end
    register(RS.Heartbeat:Connect(function(dt)
        acc += dt
        frames += 1
        if acc >= 0.5 then
            fps = math.floor(frames / acc + 0.5)
            acc = 0
            frames = 0
            api:Refresh()
        end
    end))
    api:Refresh()
    return api
end

function Section:AddMiniGraph(opts)
    opts = opts or {}
    local maxPoints = tonumber(opts.MaxPoints) or 32
    local minValue = tonumber(opts.Min) or 0
    local maxValue = tonumber(opts.Max) or 100
    local values = {}
    for _, v in ipairs(opts.Values or {}) do table.insert(values, tonumber(v) or 0) end
    local frame = new("Frame", {
        Parent = self.Content,
        Size = UDim2.new(1, 0, 0, 58),
        BackgroundColor3 = Theme.Bg3,
        BorderSizePixel = 0,
    })
    stroke(frame, Theme.Border, 1)
    pad(frame, 8, 6, 8, 6)
    local title = new("TextLabel", {
        Parent = frame,
        Size = UDim2.new(1, 0, 0, 12),
        BackgroundTransparency = 1,
        Font = FONT_M,
        TextSize = TEXT_SIZE_SMALL,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = tostring(opts.Text or "Graph"),
    })
    local plot = new("Frame", {
        Parent = frame,
        Position = UDim2.fromOffset(0, 18),
        Size = UDim2.new(1, 0, 1, -18),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    })
    listLayout(plot, Enum.FillDirection.Horizontal, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom)
    local api = {}
    local function render()
        for _, child in ipairs(plot:GetChildren()) do
            if child.Name == "Bar" then child:Destroy() end
        end
        local range = maxValue - minValue
        for i, value in ipairs(values) do
            local pct = range ~= 0 and clamp((value - minValue) / range, 0, 1) or 0
            new("Frame", {
                Parent = plot,
                Name = "Bar",
                LayoutOrder = i,
                Size = UDim2.new(1 / maxPoints, -2, pct, 0),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
            })
        end
    end
    function api:Push(value)
        table.insert(values, tonumber(value) or 0)
        while #values > maxPoints do table.remove(values, 1) end
        render()
    end
    function api:SetValues(newValues)
        values = {}
        for _, value in ipairs(newValues or {}) do table.insert(values, tonumber(value) or 0) end
        while #values > maxPoints do table.remove(values, 1) end
        render()
    end
    function api:SetRange(minV, maxV)
        minValue = tonumber(minV) or minValue
        maxValue = tonumber(maxV) or maxValue
        render()
    end
    function api:SetText(text)
        title.Text = tostring(text)
    end
    if type(opts.Provider) == "function" then
        local elapsed = tonumber(opts.RefreshRate) or 0.5
        register(RS.Heartbeat:Connect(function(dt)
            elapsed += dt
            if elapsed >= (tonumber(opts.RefreshRate) or 0.5) then
                elapsed = 0
                local value = safeCall(opts.Provider, api)
                if type(value) == "table" then api:SetValues(value) else api:Push(value) end
            end
        end))
    end
    render()
    return api
end

function Section:AddPlayerList(opts)
    opts = opts or {}
    local playerMap = {}
    local function collect()
        local out = {}
        playerMap = {}
        for _, player in ipairs(Players:GetPlayers()) do
            local label = opts.DisplayName and (player.DisplayName .. " (@" .. player.Name .. ")") or player.Name
            table.insert(out, label)
            playerMap[label] = player
        end
        table.sort(out)
        return out
    end
    opts.Text = opts.Text or "Players"
    opts.Options = collect()
    opts.Provider = collect
    opts.RefreshRate = opts.RefreshRate or 0.5
    local api
    if opts.Multi then
        api = self:AddMultiDropdown(opts)
    else
        api = self:AddDropdown(opts)
    end
    function api:GetPlayer()
        local selected = self:Get()
        if type(selected) == "table" then
            local out = {}
            for _, name in ipairs(selected) do
                if playerMap[name] then table.insert(out, playerMap[name]) end
            end
            return out
        end
        return playerMap[selected]
    end
    local function refresh()
        if api.Refresh then api:Refresh(collect(), true) end
    end
    register(Players.PlayerAdded:Connect(refresh))
    register(Players.PlayerRemoving:Connect(refresh))
    return api
end

----------------------------------------------------------------------
-- NOTIFICATIONS
----------------------------------------------------------------------
local function getNotifyHolder()
    local sg = getScreenGui()
    if Library.NotifyHolder and Library.NotifyHolder.Parent then
        return Library.NotifyHolder
    end
    local holder = new("Frame", {
        Parent                 = sg,
        Name                   = "Notifications",
        AnchorPoint            = Vector2.new(1, 0),
        Position               = UDim2.new(1, -12, 0, 12),
        Size                   = UDim2.fromOffset(280, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ZIndex                 = 5000,
    })
    listLayout(holder, Enum.FillDirection.Vertical, 6,
        Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Top)
    Library.NotifyHolder = holder
    return holder
end

function Library:Notify(opts)
    opts = opts or {}
    local title    = tostring(opts.Title or "Notification")
    local text     = tostring(opts.Text or "")
    local duration = tonumber(opts.Duration) or 4

    local holder = getNotifyHolder()

    local card = new("Frame", {
        Parent           = holder,
        Size             = UDim2.new(1, 0, 0, 0),
        AutomaticSize    = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Bg2,
        BorderSizePixel  = 0,
        ZIndex           = 5001,
    })
    stroke(card, Theme.BorderHi, 1)

    -- Accent bar
    local accent = new("Frame", {
        Parent           = card,
        Size             = UDim2.new(0, 2, 1, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        ZIndex           = 5002,
    })

    local content = new("Frame", {
        Parent                 = card,
        Name                   = "Content",
        Position               = UDim2.fromOffset(8, 0),
        Size                   = UDim2.new(1, -8, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ZIndex                 = 5002,
    })
    pad(content, 0, 8, 8, 8)
    listLayout(content, Enum.FillDirection.Vertical, 2)

    new("TextLabel", {
        Parent                 = content,
        Size                   = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1,
        Font                   = FONT_SB,
        TextSize               = TEXT_SIZE,
        TextColor3             = Theme.Text,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = title,
        ZIndex                 = 5002,
    })
    local body = new("TextLabel", {
        Parent                 = content,
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font                   = FONT,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.SubText,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextYAlignment         = Enum.TextYAlignment.Top,
        TextWrapped            = true,
        Text                   = text,
        ZIndex                 = 5002,
    })

    -- Progress bar
    local bar = new("Frame", {
        Parent           = card,
        AnchorPoint      = Vector2.new(0, 1),
        Position         = UDim2.new(0, 0, 1, 0),
        Size             = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        ZIndex           = 5002,
    })

    -- Helpers: animate / snap every visual part of the card.
    -- "Content" frame stays fully transparent (it's a layout container).
    local function setTrans(t)
        card.BackgroundTransparency = t
        for _, d in ipairs(card:GetDescendants()) do
            if d:IsA("TextLabel") then
                d.TextTransparency = t
            elseif d:IsA("UIStroke") then
                d.Transparency = t
            elseif d:IsA("Frame") and d.Name ~= "Content" then
                d.BackgroundTransparency = t
            end
        end
    end
    local function tweenTrans(t, dur)
        tween(card, dur, { BackgroundTransparency = t })
        for _, d in ipairs(card:GetDescendants()) do
            if d:IsA("TextLabel") then
                tween(d, dur, { TextTransparency = t })
            elseif d:IsA("UIStroke") then
                tween(d, dur, { Transparency = t })
            elseif d:IsA("Frame") and d.Name ~= "Content" then
                tween(d, dur, { BackgroundTransparency = t })
            end
        end
    end

    setTrans(1)
    tweenTrans(0, 0.2)

    tween(bar, duration, { Size = UDim2.new(0, 0, 0, 1) }, Enum.EasingStyle.Linear)

    task.delay(duration, function()
        tweenTrans(1, 0.2)
        task.wait(0.22)
        card:Destroy()
    end)

    return card
end

return Library
