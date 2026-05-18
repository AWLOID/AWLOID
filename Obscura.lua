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
Library.Flags              = {}
Library.FlagCallbacks      = {}
Library.FlagBindings       = {}
Library.Connections        = {}
Library.Windows            = {}
Library.Notifications      = {}
Library.UnloadCallbacks    = {}
Library.Watermarks         = {}
Library.ActiveLists        = {}
Library.Configs            = {}
Library.CurrentConfig      = nil
Library.Premium            = false
Library.Open               = true
Library.Version            = "2.0.0"
Library.Name               = "Obscura"
Library._zCounter          = 10
Library._activeDropdown    = nil
Library._activeColorpicker = nil
Library._activeModal       = nil

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

function Library:_BindFlag(flag, api)
    if flag and api then
        Library.FlagBindings[flag] = api
    end
end

----------------------------------------------------------------------
-- THEME / FONT
----------------------------------------------------------------------
function Library:SetTheme(t)
    if type(t) ~= "table" then return end
    for k, v in pairs(t) do
        if Theme[k] ~= nil and typeof(v) == "Color3" then
            Theme[k] = v
        end
    end
end

function Library:GetTheme()
    local copy = {}
    for k, v in pairs(Theme) do copy[k] = v end
    return copy
end

function Library:SetFont(f)
    if typeof(f) == "EnumItem" and f.EnumType == Enum.Font then
        FONT = f; FONT_M = f; FONT_SB = f; FONT_B = f
    end
end

----------------------------------------------------------------------
-- PREMIUM SYSTEM
----------------------------------------------------------------------
function Library:SetPremium(state)
    Library.Premium = state and true or false
    if Library._premiumChanged then Library._premiumChanged() end
end

function Library:HasPremium()
    return Library.Premium
end

Library._premiumWatchers = {}
function Library:_WatchPremium(fn)
    table.insert(Library._premiumWatchers, fn)
    pcall(fn, Library.Premium)
end
Library._premiumChanged = function()
    for _, fn in ipairs(Library._premiumWatchers) do
        pcall(fn, Library.Premium)
    end
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
-- UNLOAD CALLBACKS
----------------------------------------------------------------------
function Library:OnUnload(fn)
    if type(fn) == "function" then
        table.insert(Library.UnloadCallbacks, fn)
    end
end

function Library:Destroy()
    for _, fn in ipairs(Library.UnloadCallbacks) do
        pcall(fn)
    end
    Library.UnloadCallbacks = {}

    for _, w in ipairs(Library.Watermarks) do
        pcall(function() w:Destroy() end)
    end
    Library.Watermarks = {}
    for _, a in ipairs(Library.ActiveLists) do
        pcall(function() a:Destroy() end)
    end
    Library.ActiveLists = {}

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
    Library.FlagBindings      = {}
    Library.MobileButton      = nil
    Library.NotifyHolder      = nil
    Library._activeDropdown   = nil
    Library._activeColorpicker= nil
    Library._activeModal      = nil
    Library._listeningKeybind = nil
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
    new("UISizeConstraint", {
        Parent  = root,
        MinSize = minSize,
    })

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

    local titleHolder = new("Frame", {
        Parent                 = titleBar,
        Name                   = "TitleHolder",
        Position               = UDim2.fromOffset(20, 0),
        Size                   = UDim2.new(1, -120, 1, 0),
        BackgroundTransparency = 1,
        ClipsDescendants       = true,
    })
    listLayout(titleHolder, Enum.FillDirection.Horizontal, 8,
        Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
    new("TextLabel", {
        Parent                 = titleHolder,
        Name                   = "Title",
        AutomaticSize          = Enum.AutomaticSize.X,
        Size                   = UDim2.new(0, 0, 1, 0),
        BackgroundTransparency = 1,
        Font                   = FONT_SB,
        TextSize               = TEXT_SIZE_TITLE,
        TextColor3             = Theme.Text,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = title,
        LayoutOrder            = 1,
    })
    new("TextLabel", {
        Parent                 = titleHolder,
        Name                   = "Subtitle",
        AutomaticSize          = Enum.AutomaticSize.X,
        Size                   = UDim2.new(0, 0, 1, 0),
        BackgroundTransparency = 1,
        Font                   = FONT,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.DimText,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = subtitle,
        LayoutOrder            = 2,
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
        Size             = UDim2.new(0, 130, 1, 0),
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

    local searchEnabled = opts.Search ~= false
    local searchHeight  = searchEnabled and 30 or 0

    local searchBar
    if searchEnabled then
        searchBar = new("Frame", {
            Parent           = sidebar,
            Name             = "SearchBar",
            Size             = UDim2.new(1, -16, 0, 22),
            Position         = UDim2.fromOffset(8, 6),
            BackgroundColor3 = Theme.Bg3,
            BorderSizePixel  = 0,
        })
        local sbStroke = stroke(searchBar, Theme.Border, 1)
        local searchInput = new("TextBox", {
            Parent                 = searchBar,
            BackgroundTransparency = 1,
            Position               = UDim2.fromOffset(8, 0),
            Size                   = UDim2.new(1, -16, 1, 0),
            Font                   = FONT,
            TextSize               = TEXT_SIZE_SMALL,
            TextColor3             = Theme.Text,
            PlaceholderColor3      = Theme.DimText,
            PlaceholderText        = "Search...",
            Text                   = "",
            ClearTextOnFocus       = false,
            TextXAlignment         = Enum.TextXAlignment.Left,
        })
        searchInput.Focused:Connect(function() sbStroke.Color = Theme.BorderHi end)
        searchInput.FocusLost:Connect(function() sbStroke.Color = Theme.Border end)
        searchBar._Input = searchInput
    end

    local tabList = new("ScrollingFrame", {
        Parent                  = sidebar,
        Name                    = "TabList",
        Size                    = UDim2.new(1, 0, 1, -40 - searchHeight),
        Position                = UDim2.fromOffset(0, searchHeight),
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
        Position               = UDim2.fromOffset(130, 0),
        Size                   = UDim2.new(1, -130, 1, 0),
        BackgroundTransparency = 1,
    })

    -- Drag
    makeDraggable(root, titleBar)

    -- Resize handle (bottom-right corner)
    local resizeHandle = new("TextButton", {
        Parent           = root,
        Name             = "ResizeHandle",
        AnchorPoint      = Vector2.new(1, 1),
        Position         = UDim2.new(1, 0, 1, 0),
        Size             = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        Text             = "",
        AutoButtonColor  = false,
        ZIndex           = 100,
    })
    local resizeIcon = new("TextLabel", {
        Parent                 = resizeHandle,
        Size                   = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Font                   = FONT,
        TextSize               = 12,
        TextColor3             = Theme.DimText,
        Text                   = "◢",
        ZIndex                 = 101,
    })

    do
        local resizing = false
        local resizeStartInput, sizeStart

        resizeHandle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                resizing = true
                resizeStartInput = input.Position
                sizeStart = root.AbsoluteSize
            end
        end)
        register(UIS.InputChanged:Connect(function(input)
            if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - resizeStartInput
                local newW = math.max(sizeStart.X + delta.X, minSize.X)
                local newH = math.max(sizeStart.Y + delta.Y, minSize.Y)
                root.Size = UDim2.fromOffset(newW, newH)
            end
        end))
        register(UIS.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                resizing = false
            end
        end))
    end

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
        SearchBar = searchBar,
        Tabs      = {},
        ActiveTab = nil,
        Title     = title,
    }, Window)

    if searchBar and searchBar._Input then
        searchBar._Input:GetPropertyChangedSignal("Text"):Connect(function()
            local q = searchBar._Input.Text:lower()
            for _, t in ipairs(self.Tabs) do
                if q == "" then
                    t.Button.Visible = true
                else
                    t.Button.Visible = t.Name:lower():find(q, 1, true) ~= nil
                end
            end
        end)
    end

    table.insert(Library.Windows, self)
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
    local icon         = opts.Icon
    local iconPos      = (opts.IconPosition or "left"):lower()
    local hasIcon      = icon and icon ~= ""
    local stacked      = (iconPos == "top" or iconPos == "bottom")
    local btnHeight    = stacked and 44 or 28

    local btn = new("TextButton", {
        Parent           = self.TabList,
        Name             = name,
        Size             = UDim2.new(1, 0, 0, btnHeight),
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

    local iconImg
    if hasIcon then
        iconImg = new("ImageLabel", {
            Parent                 = btn,
            BackgroundTransparency = 1,
            Image                  = tostring(icon),
            ImageColor3            = Theme.SubText,
            ScaleType              = Enum.ScaleType.Fit,
        })
    end

    local label = new("TextLabel", {
        Parent                 = btn,
        BackgroundTransparency = 1,
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE,
        TextColor3             = Theme.SubText,
        Text                   = name,
    })

    if not hasIcon then
        label.Position       = UDim2.fromOffset(12, 0)
        label.Size           = UDim2.new(1, -16, 1, 0)
        label.TextXAlignment = Enum.TextXAlignment.Left
    elseif iconPos == "left" then
        iconImg.Position = UDim2.fromOffset(10, (btnHeight - 14) / 2)
        iconImg.Size     = UDim2.fromOffset(14, 14)
        label.Position   = UDim2.fromOffset(30, 0)
        label.Size       = UDim2.new(1, -34, 1, 0)
        label.TextXAlignment = Enum.TextXAlignment.Left
    elseif iconPos == "right" then
        label.Position   = UDim2.fromOffset(12, 0)
        label.Size       = UDim2.new(1, -34, 1, 0)
        label.TextXAlignment = Enum.TextXAlignment.Left
        iconImg.AnchorPoint = Vector2.new(1, 0.5)
        iconImg.Position    = UDim2.new(1, -10, 0.5, 0)
        iconImg.Size        = UDim2.fromOffset(14, 14)
    elseif iconPos == "top" then
        iconImg.AnchorPoint = Vector2.new(0.5, 0)
        iconImg.Position    = UDim2.new(0.5, 0, 0, 6)
        iconImg.Size        = UDim2.fromOffset(16, 16)
        label.AnchorPoint   = Vector2.new(0.5, 1)
        label.Position      = UDim2.new(0.5, 0, 1, -4)
        label.Size          = UDim2.new(1, -8, 0, 14)
        label.TextXAlignment = Enum.TextXAlignment.Center
    elseif iconPos == "bottom" then
        label.Position      = UDim2.new(0, 0, 0, 4)
        label.Size          = UDim2.new(1, -8, 0, 14)
        label.AnchorPoint   = Vector2.new(0, 0)
        label.Position      = UDim2.fromOffset(4, 4)
        label.TextXAlignment = Enum.TextXAlignment.Center
        iconImg.AnchorPoint = Vector2.new(0.5, 1)
        iconImg.Position    = UDim2.new(0.5, 0, 1, -6)
        iconImg.Size        = UDim2.fromOffset(16, 16)
    end

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
        Icon      = iconImg,
        Sections  = {},
    }, Tab)

    btn.MouseEnter:Connect(function()
        if self.ActiveTab ~= tab then
            tween(label, 0.12, { TextColor3 = Theme.Text })
            if iconImg then tween(iconImg, 0.12, { ImageColor3 = Theme.Text }) end
        end
    end)
    btn.MouseLeave:Connect(function()
        if self.ActiveTab ~= tab then
            tween(label, 0.12, { TextColor3 = Theme.SubText })
            if iconImg then tween(iconImg, 0.12, { ImageColor3 = Theme.SubText }) end
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
        t.Label.Font = active and FONT_SB or FONT_M
        if t.Icon then
            tween(t.Icon, 0.15, { ImageColor3 = active and Theme.Accent or Theme.SubText })
        end
    end
    self.ActiveTab = tab
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

local function premiumGuard(opts)
    if not opts.Premium then return true end
    if Library.Premium then return true end
    Library:Modal({
        Title   = "Premium Required",
        Text    = "This feature requires Premium access. Use Library:SetPremium(true) to unlock or contact the developer to purchase.",
        Buttons = { { Text = "OK", Primary = true } },
    })
    return false
end

local function premiumBadge(parent)
    local b = new("TextLabel", {
        Parent                 = parent,
        AnchorPoint            = Vector2.new(1, 0.5),
        Position               = UDim2.new(1, -6, 0.5, 0),
        Size                   = UDim2.fromOffset(28, 12),
        BackgroundColor3       = Theme.Accent,
        BorderSizePixel        = 0,
        Font                   = FONT_B,
        TextSize               = 9,
        TextColor3             = Theme.Bg,
        Text                   = "PRO",
        ZIndex                 = (parent.ZIndex or 1) + 1,
    })
    return b
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
        Size                   = UDim2.new(1, opts.Premium and -50 or -16, 1, 0),
        Position               = UDim2.fromOffset(8, 0),
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE,
        TextColor3             = Theme.Text,
        TextXAlignment         = Enum.TextXAlignment.Center,
        Text                   = text,
    })

    if opts.Premium then
        premiumBadge(btn)
    else
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
    end

    attachHover(btn, Theme.Bg3, Theme.Hover, s)

    btn.MouseButton1Click:Connect(function()
        if not premiumGuard(opts) then return end
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
    function api:Fire() task.spawn(callback) end
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

    local state = default
    local api = {}

    local function render()
        fill.Visible      = state
        boxStroke.Color   = state and Theme.BorderHi or Theme.Border
        label.TextColor3  = state and Theme.Text     or Theme.SubText
    end

    function api:Set(v, silent)
        state = v and true or false
        render()
        if flag then Library:SetFlag(flag, state) end
        if not silent then task.spawn(callback, state) end
    end
    function api:Get() return state end
    function api:Toggle() api:Set(not state) end
    function api:SetText(t) label.Text = tostring(t) end

    attachHover(btn, Theme.Bg3, Theme.Hover, s)

    btn.MouseButton1Click:Connect(function()
        if not premiumGuard(opts) then return end
        api:Toggle()
    end)

    if opts.Premium then premiumBadge(btn) end

    Library:_BindFlag(flag, api)
    api:Set(default, true)
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
        local pct = (value - minV) / (maxV - minV)
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
            if not premiumGuard(opts) then return end
            dragging = true
            updateFromInput(input)
        end
    end)
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            if not premiumGuard(opts) then return end
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

    if opts.Premium then premiumBadge(frame) end

    attachHover(frame, Theme.Bg3, Theme.Hover, s)
    Library:_BindFlag(flag, api)
    api:Set(default, true)
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
                api:Set(opt)
                api:Close()
            end)
        end
        if not keepSelection then api:Set(nil, true) end
    end

    btn.MouseEnter:Connect(function()
        tween(btn, 0.12, { BackgroundColor3 = Theme.Hover })
        s.Color = Theme.BorderHi
    end)
    btn.MouseLeave:Connect(function()
        tween(btn, 0.12, { BackgroundColor3 = Theme.Bg3 })
        s.Color = Theme.Border
    end)
    btn.MouseButton1Click:Connect(function()
        if not premiumGuard(opts) then return end
        if list.Visible then api:Close() else api:Open() end
    end)

    if opts.Premium then premiumBadge(frame) end

    api.Button = btn
    api.List = list

    Library:_BindFlag(flag, api)
    api:Refresh(options, true)
    if default ~= nil then api:Set(default, true) end
    render()
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
        for _, v in ipairs(tbl or {}) do selected[v] = true end
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
        render()
    end

    btn.MouseEnter:Connect(function() tween(btn, 0.12, { BackgroundColor3 = Theme.Hover }); s.Color = Theme.BorderHi end)
    btn.MouseLeave:Connect(function() tween(btn, 0.12, { BackgroundColor3 = Theme.Bg3 }); s.Color = Theme.Border end)
    btn.MouseButton1Click:Connect(function()
        if not premiumGuard(opts) then return end
        if list.Visible then api:Close() else api:Open() end
    end)

    if opts.Premium then premiumBadge(frame) end

    api.Button = btn
    api.List = list

    Library:_BindFlag(flag, api)
    api:Refresh(options)
    api:Set(default, true)
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

    local api = {}
    function api:Set(t, silent)
        t = tostring(t)
        if numeric then t = (tonumber(t) and t) or "" end
        input.Text = t
        if flag then Library:SetFlag(flag, t) end
        if not silent then task.spawn(callback, t) end
    end
    function api:Get() return input.Text end

    input.Focused:Connect(function()
        if not premiumGuard(opts) then
            input:ReleaseFocus()
            return
        end
        s.Color = Theme.BorderHi
    end)
    input.FocusLost:Connect(function(enter)
        s.Color = Theme.Border
        if numeric and tonumber(input.Text) == nil then
            input.Text = ""
        end
        if flag then Library:SetFlag(flag, input.Text) end
        task.spawn(callback, input.Text, enter)
    end)

    if opts.Premium then premiumBadge(box) end
    Library:_BindFlag(flag, api)
    if default ~= "" and flag then Library:SetFlag(flag, default) end
    return api
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
            if not premiumGuard(opts) then return end
            task.spawn(callback, false)
        end
    end))

    if opts.Premium then premiumBadge(frame) end
    attachHover(frame, Theme.Bg3, Theme.Hover, s)
    Library:_BindFlag(flag, api)
    if default and flag then Library:SetFlag(flag, default) end
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
        -- Handle api:Set(color, silent) call pattern (e.g. from LoadConfig)
        if type(a) == "boolean" and silent == nil then
            silent = a
            a = nil
        end
        if c then h, s2, v = Color3.toHSV(c) end
        if a ~= nil then alpha = clamp(a, 0, 1) end
        render()
        if flag then Library:SetFlag(flag, color()) end
        if not silent then task.spawn(callback, color(), alpha) end
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

    if opts.Premium then premiumBadge(frame) end

    attachHover(frame, Theme.Bg3, Theme.Hover, s)
    Library:_BindFlag(flag, api)
    api.Button = swatch
    api.Popup  = popup
    api:Set(default, 1, true)
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

----------------------------------------------------------------------
-- MODAL
----------------------------------------------------------------------
function Library:Modal(opts)
    opts = opts or {}
    local title = tostring(opts.Title or "Modal")
    local text = tostring(opts.Text or "")
    local buttons = opts.Buttons or {{ Text = "OK", Primary = true }}

    local sg = getScreenGui()

    if Library._activeModal then
        pcall(function() Library._activeModal:Destroy() end)
        Library._activeModal = nil
    end

    local overlay = new("Frame", {
        Parent           = sg,
        Size             = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.45,
        BorderSizePixel  = 0,
        ZIndex           = 8000,
    })
    Library._activeModal = overlay

    local card = new("Frame", {
        Parent           = overlay,
        AnchorPoint      = Vector2.new(0.5, 0.5),
        Position         = UDim2.fromScale(0.5, 0.5),
        Size             = UDim2.fromOffset(360, 0),
        AutomaticSize    = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel  = 0,
        ZIndex           = 8001,
    })
    stroke(card, Theme.BorderHi, 1)
    new("Frame", {
        Parent           = card,
        Size             = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        ZIndex           = 8002,
    })

    local content = new("Frame", {
        Parent                 = card,
        Position               = UDim2.fromOffset(0, 2),
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ZIndex                 = 8002,
    })
    pad(content, 16, 14, 16, 14)
    listLayout(content, Enum.FillDirection.Vertical, 10)

    new("TextLabel", {
        Parent                 = content,
        Size                   = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        Font                   = FONT_SB,
        TextSize               = TEXT_SIZE_TITLE,
        TextColor3             = Theme.Text,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = title,
        LayoutOrder            = 1,
        ZIndex                 = 8002,
    })
    if text ~= "" then
        new("TextLabel", {
            Parent                 = content,
            Size                   = UDim2.new(1, 0, 0, 0),
            AutomaticSize          = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Font                   = FONT,
            TextSize               = TEXT_SIZE,
            TextColor3             = Theme.SubText,
            TextXAlignment         = Enum.TextXAlignment.Left,
            TextYAlignment         = Enum.TextYAlignment.Top,
            TextWrapped            = true,
            Text                   = text,
            LayoutOrder            = 2,
            ZIndex                 = 8002,
        })
    end

    local btnRow = new("Frame", {
        Parent                 = content,
        Size                   = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        LayoutOrder            = 3,
        ZIndex                 = 8002,
    })
    listLayout(btnRow, Enum.FillDirection.Horizontal, 6,
        Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)

    local function closeModal()
        if Library._activeModal == overlay then Library._activeModal = nil end
        overlay:Destroy()
    end

    for i, b in ipairs(buttons) do
        local bg = b.Primary and Theme.Accent or Theme.Bg3
        local fg = b.Primary and Theme.Bg or Theme.Text
        local btn = new("TextButton", {
            Parent           = btnRow,
            Size             = UDim2.fromOffset(90, 26),
            BackgroundColor3 = bg,
            BorderSizePixel  = 0,
            Text             = tostring(b.Text or "OK"),
            Font             = FONT_M,
            TextSize         = TEXT_SIZE_SMALL,
            TextColor3       = fg,
            AutoButtonColor  = false,
            LayoutOrder      = i,
            ZIndex           = 8003,
        })
        stroke(btn, Theme.BorderHi, 1)
        btn.MouseEnter:Connect(function()
            tween(btn, 0.1, { BackgroundColor3 = b.Primary and Theme.Accent or Theme.Hover })
        end)
        btn.MouseLeave:Connect(function()
            tween(btn, 0.1, { BackgroundColor3 = bg })
        end)
        btn.MouseButton1Click:Connect(function()
            if b.Callback then pcall(b.Callback) end
            closeModal()
        end)
    end

    return overlay
end

----------------------------------------------------------------------
-- KEY SYSTEM
----------------------------------------------------------------------
function Library:KeySystem(opts)
    opts = opts or {}
    local title    = tostring(opts.Title or "Key System")
    local subtitle = tostring(opts.Subtitle or "Enter your key to continue")
    local keys     = opts.Keys or {}
    local note     = opts.Note
    local allowSkip= opts.AllowSkip and true or false
    local getKeyUrl= opts.GetKeyUrl
    local saveFlag = opts.SaveFile
    local onSuccess= opts.OnSuccess
    local onFailure= opts.OnFailure
    local copyText = opts.CopyText

    if saveFlag and readfile and isfile then
        local path = "Obscura/" .. saveFlag .. ".key"
        local ok, saved = pcall(function()
            if isfile(path) then return readfile(path) end
        end)
        if ok and saved then
            for _, k in ipairs(keys) do
                if k == saved then
                    if onSuccess then pcall(onSuccess) end
                    return true
                end
            end
        end
    end

    local sg = getScreenGui()
    local overlay = new("Frame", {
        Parent           = sg,
        Size             = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.35,
        BorderSizePixel  = 0,
        ZIndex           = 8500,
    })
    local card = new("Frame", {
        Parent           = overlay,
        AnchorPoint      = Vector2.new(0.5, 0.5),
        Position         = UDim2.fromScale(0.5, 0.5),
        Size             = UDim2.fromOffset(320, 0),
        AutomaticSize    = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel  = 0,
        ZIndex           = 8501,
    })
    stroke(card, Theme.BorderHi, 1)
    new("Frame", {
        Parent           = card,
        Size             = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        ZIndex           = 8502,
    })

    local body = new("Frame", {
        Parent                 = card,
        Position               = UDim2.fromOffset(0, 2),
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ZIndex                 = 8502,
    })
    pad(body, 18, 16, 18, 16)
    listLayout(body, Enum.FillDirection.Vertical, 8)

    new("TextLabel", {
        Parent                 = body,
        Size                   = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Font                   = FONT_SB,
        TextSize               = TEXT_SIZE_TITLE + 2,
        TextColor3             = Theme.Text,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = title,
        LayoutOrder            = 1,
        ZIndex                 = 8502,
    })
    new("TextLabel", {
        Parent                 = body,
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font                   = FONT,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.SubText,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextWrapped            = true,
        Text                   = subtitle,
        LayoutOrder            = 2,
        ZIndex                 = 8502,
    })

    local box = new("Frame", {
        Parent           = body,
        Size             = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = Theme.Bg3,
        BorderSizePixel  = 0,
        LayoutOrder      = 3,
        ZIndex           = 8502,
    })
    local boxStroke = stroke(box, Theme.Border, 1)
    local input = new("TextBox", {
        Parent                 = box,
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(8, 0),
        Size                   = UDim2.new(1, -16, 1, 0),
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE,
        TextColor3             = Theme.Text,
        PlaceholderColor3      = Theme.DimText,
        PlaceholderText        = "Key...",
        Text                   = "",
        ClearTextOnFocus       = false,
        TextXAlignment         = Enum.TextXAlignment.Left,
        ZIndex                 = 8503,
    })
    input.Focused:Connect(function() boxStroke.Color = Theme.BorderHi end)
    input.FocusLost:Connect(function() boxStroke.Color = Theme.Border end)

    if note then
        new("TextLabel", {
            Parent                 = body,
            Size                   = UDim2.new(1, 0, 0, 0),
            AutomaticSize          = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Font                   = FONT,
            TextSize               = TEXT_SIZE_SMALL,
            TextColor3             = Theme.DimText,
            TextXAlignment         = Enum.TextXAlignment.Left,
            TextWrapped            = true,
            Text                   = tostring(note),
            LayoutOrder            = 4,
            ZIndex                 = 8502,
        })
    end

    local btnRow = new("Frame", {
        Parent                 = body,
        Size                   = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        LayoutOrder            = 5,
        ZIndex                 = 8502,
    })
    listLayout(btnRow, Enum.FillDirection.Horizontal, 6,
        Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)

    local result = Instance.new("BindableEvent")
    local validated = false
    local resolveValue = false

    local function makeBtn(text_, primary, order)
        local bg = primary and Theme.Accent or Theme.Bg3
        local fg = primary and Theme.Bg or Theme.Text
        local b = new("TextButton", {
            Parent           = btnRow,
            Size             = UDim2.fromOffset(80, 24),
            BackgroundColor3 = bg,
            BorderSizePixel  = 0,
            Text             = text_,
            Font             = FONT_M,
            TextSize         = TEXT_SIZE_SMALL,
            TextColor3       = fg,
            AutoButtonColor  = false,
            LayoutOrder      = order,
            ZIndex           = 8503,
        })
        stroke(b, Theme.BorderHi, 1)
        b.MouseEnter:Connect(function() tween(b, 0.1, { BackgroundColor3 = primary and Theme.Accent or Theme.Hover }) end)
        b.MouseLeave:Connect(function() tween(b, 0.1, { BackgroundColor3 = bg }) end)
        return b
    end

    if getKeyUrl then
        local linkBtn = makeBtn("Get Key", false, 1)
        linkBtn.MouseButton1Click:Connect(function()
            if setclipboard then
                setclipboard(copyText or getKeyUrl)
            end
            Library:Notify({
                Title = "Get Key",
                Text  = "Link copied: " .. getKeyUrl,
                Duration = 5,
            })
        end)
    end

    if allowSkip then
        local skipBtn = makeBtn("Skip", false, 2)
        skipBtn.MouseButton1Click:Connect(function()
            validated = true; resolveValue = true
            overlay:Destroy()
            if onSuccess then pcall(onSuccess) end
            result:Fire()
        end)
    end

    local submit = makeBtn("Submit", true, 3)
    local function trySubmit()
        local k = input.Text
        for _, valid in ipairs(keys) do
            if k == valid then
                validated = true; resolveValue = true
                if saveFlag and writefile and makefolder and isfolder then
                    pcall(function()
                        if not isfolder("Obscura") then makefolder("Obscura") end
                        writefile("Obscura/" .. saveFlag .. ".key", k)
                    end)
                end
                overlay:Destroy()
                if onSuccess then pcall(onSuccess) end
                result:Fire()
                return
            end
        end
        if onFailure then pcall(onFailure) end
        boxStroke.Color = Color3.fromRGB(255, 80, 80)
        local origPos = card.Position
        for i = 1, 6 do
            card.Position = UDim2.new(0.5, (i % 2 == 0) and -6 or 6, 0.5, 0)
            task.wait(0.04)
        end
        card.Position = origPos
        task.delay(0.6, function() if boxStroke and boxStroke.Parent then boxStroke.Color = Theme.Border end end)
    end
    submit.MouseButton1Click:Connect(trySubmit)
    input.FocusLost:Connect(function(enter)
        if enter then trySubmit() end
    end)

    result.Event:Wait()
    result:Destroy()
    return resolveValue
end

----------------------------------------------------------------------
-- WATERMARK
----------------------------------------------------------------------
function Library:CreateWatermark(opts)
    opts = opts or {}
    local format   = opts.Text or "Obscura | {fps} fps | {time}"
    local position = (opts.Position or "topleft"):lower()
    local sg       = getScreenGui()

    local frame = new("Frame", {
        Parent           = sg,
        Size             = UDim2.fromOffset(0, 24),
        AutomaticSize    = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel  = 0,
        ZIndex           = 9000,
    })
    stroke(frame, Theme.BorderHi, 1)
    new("Frame", {
        Parent           = frame,
        Size             = UDim2.new(1, 0, 0, 1),
        Position         = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        ZIndex           = 9001,
    })

    local label = new("TextLabel", {
        Parent                 = frame,
        AutomaticSize          = Enum.AutomaticSize.X,
        Size                   = UDim2.new(0, 0, 1, 0),
        BackgroundTransparency = 1,
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.Text,
        Text                   = " ",
        ZIndex                 = 9001,
    })
    pad(label, 8, 0, 8, 0)

    local function updatePos()
        if position == "topleft" then
            frame.AnchorPoint = Vector2.new(0, 0)
            frame.Position    = UDim2.new(0, 12, 0, 12)
        elseif position == "topright" then
            frame.AnchorPoint = Vector2.new(1, 0)
            frame.Position    = UDim2.new(1, -12, 0, 12)
        elseif position == "topcenter" then
            frame.AnchorPoint = Vector2.new(0.5, 0)
            frame.Position    = UDim2.new(0.5, 0, 0, 12)
        elseif position == "bottomleft" then
            frame.AnchorPoint = Vector2.new(0, 1)
            frame.Position    = UDim2.new(0, 12, 1, -12)
        elseif position == "bottomright" then
            frame.AnchorPoint = Vector2.new(1, 1)
            frame.Position    = UDim2.new(1, -12, 1, -12)
        elseif position == "bottomcenter" then
            frame.AnchorPoint = Vector2.new(0.5, 1)
            frame.Position    = UDim2.new(0.5, 0, 1, -12)
        end
    end
    updatePos()

    local fps, frames, lastT = 60, 0, tick()
    local custom = {}

    local function formatText()
        local n = os.date("*t")
        local timeStr = string.format("%02d:%02d:%02d", n.hour, n.min, n.sec)
        local fpsStr  = tostring(math.floor(fps + 0.5))
        local pingStr = "0"
        pcall(function()
            local stat = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]
            pingStr = tostring(math.floor(stat:GetValue() + 0.5))
        end)
        local userStr = LP and LP.DisplayName or "user"
        local gameStr = tostring(game.PlaceId)
        local result_ = format
            :gsub("{fps}", fpsStr)
            :gsub("{time}", timeStr)
            :gsub("{ping}", pingStr)
            :gsub("{user}", userStr)
            :gsub("{game}", gameStr)
            :gsub("{version}", Library.Version)
            :gsub("{name}", Library.Name)
        for k, v in pairs(custom) do
            result_ = result_:gsub("{" .. k .. "}", tostring(type(v) == "function" and v() or v))
        end
        return result_
    end

    local conn = RS.RenderStepped:Connect(function(dt)
        frames = frames + 1
        local now = tick()
        if now - lastT >= 0.3 then
            fps = frames / (now - lastT)
            frames = 0
            lastT = now
        end
        label.Text = formatText()
    end)
    table.insert(Library.Connections, conn)

    local api = {}
    function api:SetText(t)     format = tostring(t or "") end
    function api:SetPosition(p) position = (p or "topleft"):lower(); updatePos() end
    function api:SetVisible(v)  frame.Visible = v and true or false end
    function api:SetVar(k, v)   custom[k] = v end
    function api:Destroy()
        if conn then pcall(function() conn:Disconnect() end) end
        if frame and frame.Parent then frame:Destroy() end
        for i, w in ipairs(Library.Watermarks) do
            if w == api then table.remove(Library.Watermarks, i); break end
        end
    end
    table.insert(Library.Watermarks, api)
    return api
end

----------------------------------------------------------------------
-- ACTIVE LIST (shown enabled features in real-time)
----------------------------------------------------------------------
function Library:CreateActiveList(opts)
    opts = opts or {}
    local title    = tostring(opts.Title or "ACTIVE")
    local position = (opts.Position or "topright"):lower()
    local sg       = getScreenGui()

    local frame = new("Frame", {
        Parent           = sg,
        Size             = UDim2.fromOffset(170, 0),
        AutomaticSize    = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel  = 0,
        ZIndex           = 7000,
        Visible          = true,
    })
    stroke(frame, Theme.BorderHi, 1)
    new("Frame", {
        Parent           = frame,
        Size             = UDim2.new(0, 2, 1, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        ZIndex           = 7001,
    })

    local header = new("TextLabel", {
        Parent                 = frame,
        Position               = UDim2.fromOffset(8, 0),
        Size                   = UDim2.new(1, -8, 0, 20),
        BackgroundTransparency = 1,
        Font                   = FONT_SB,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.Text,
        Text                   = title,
        TextXAlignment         = Enum.TextXAlignment.Left,
        ZIndex                 = 7001,
    })

    local list = new("Frame", {
        Parent                 = frame,
        Position               = UDim2.fromOffset(8, 20),
        Size                   = UDim2.new(1, -16, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ZIndex                 = 7001,
    })
    pad(list, 0, 0, 0, 6)
    listLayout(list, Enum.FillDirection.Vertical, 2)

    local function updatePos()
        if position == "topleft" then
            frame.AnchorPoint = Vector2.new(0, 0); frame.Position = UDim2.new(0, 12, 0, 12)
        elseif position == "topright" then
            frame.AnchorPoint = Vector2.new(1, 0); frame.Position = UDim2.new(1, -12, 0, 12)
        elseif position == "bottomleft" then
            frame.AnchorPoint = Vector2.new(0, 1); frame.Position = UDim2.new(0, 12, 1, -12)
        elseif position == "bottomright" then
            frame.AnchorPoint = Vector2.new(1, 1); frame.Position = UDim2.new(1, -12, 1, -12)
        elseif position == "topcenter" then
            frame.AnchorPoint = Vector2.new(0.5, 0); frame.Position = UDim2.new(0.5, 0, 0, 12)
        elseif position == "left" then
            frame.AnchorPoint = Vector2.new(0, 0.5); frame.Position = UDim2.new(0, 12, 0.5, 0)
        elseif position == "right" then
            frame.AnchorPoint = Vector2.new(1, 0.5); frame.Position = UDim2.new(1, -12, 0.5, 0)
        end
    end
    updatePos()

    local entries = {}
    local conn
    conn = RS.Heartbeat:Connect(function()
        local anyVisible = false
        for _, e in pairs(entries) do
            local active = false
            local ok, v = pcall(e.GetActive)
            if ok and v then active = true end
            e.Frame.Visible = active
            if active then anyVisible = true end
            if e.GetText then
                local ok2, t = pcall(e.GetText)
                if ok2 and t then e.Label.Text = tostring(t) end
            end
        end
        frame.Visible = anyVisible
    end)
    table.insert(Library.Connections, conn)

    local api = {}
    function api:Add(name, getActive, getText)
        if entries[name] then return end
        local row = new("Frame", {
            Parent                 = list,
            Size                   = UDim2.new(1, 0, 0, 16),
            BackgroundTransparency = 1,
            Visible                = false,
            ZIndex                 = 7002,
        })
        new("Frame", {
            Parent           = row,
            AnchorPoint      = Vector2.new(0, 0.5),
            Position         = UDim2.new(0, 0, 0.5, 0),
            Size             = UDim2.fromOffset(4, 4),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel  = 0,
            ZIndex           = 7002,
        })
        local lbl = new("TextLabel", {
            Parent                 = row,
            Position               = UDim2.fromOffset(10, 0),
            Size                   = UDim2.new(1, -10, 1, 0),
            BackgroundTransparency = 1,
            Font                   = FONT,
            TextSize               = TEXT_SIZE_SMALL,
            TextColor3             = Theme.Text,
            TextXAlignment         = Enum.TextXAlignment.Left,
            Text                   = tostring((getText and getText()) or name),
            ZIndex                 = 7002,
        })
        entries[name] = { Frame = row, GetActive = getActive or function() return true end, GetText = getText, Label = lbl }
    end
    function api:Remove(name)
        if entries[name] then
            entries[name].Frame:Destroy()
            entries[name] = nil
        end
    end
    function api:SetPosition(p) position = (p or "topright"):lower(); updatePos() end
    function api:SetVisible(v)  frame.Visible = v and true or false end
    function api:Destroy()
        if conn then pcall(function() conn:Disconnect() end) end
        if frame and frame.Parent then frame:Destroy() end
        for i, a in ipairs(Library.ActiveLists) do
            if a == api then table.remove(Library.ActiveLists, i); break end
        end
    end
    table.insert(Library.ActiveLists, api)
    return api
end

----------------------------------------------------------------------
-- CONFIG SYSTEM (file IO if executor supports it, in-memory fallback)
----------------------------------------------------------------------
local function _hasFileIO()
    return writefile and readfile and isfile and makefolder and isfolder and listfiles and delfile
end

local function _ensureConfigFolder(folder)
    folder = folder or "Obscura/Configs"
    if not _hasFileIO() then return false end
    pcall(function()
        if not isfolder("Obscura") then makefolder("Obscura") end
        if not isfolder(folder) then makefolder(folder) end
    end)
    return true
end

local function _encodeValue(v)
    if typeof(v) == "Color3" then
        return { __t = "Color3", r = v.R, g = v.G, b = v.B }
    elseif typeof(v) == "EnumItem" then
        if v.EnumType == Enum.KeyCode then
            return { __t = "KeyCode", n = v.Name }
        elseif v.EnumType == Enum.UserInputType then
            return { __t = "UserInputType", n = v.Name }
        end
    elseif type(v) == "boolean" or type(v) == "number" or type(v) == "string" then
        return v
    elseif type(v) == "table" then
        local arr = {}
        for i, item in ipairs(v) do arr[i] = tostring(item) end
        return arr
    end
    return nil
end

local function _decodeValue(v)
    if type(v) == "table" and v.__t then
        if v.__t == "Color3" then return Color3.new(v.r, v.g, v.b)
        elseif v.__t == "Color3A" then return Color3.new(v.r, v.g, v.b), v.a
        elseif v.__t == "KeyCode" then return Enum.KeyCode[v.n]
        elseif v.__t == "UserInputType" then return Enum.UserInputType[v.n]
        end
    end
    return v
end

function Library:GetConfigFolder()
    return "Obscura/Configs"
end

function Library:SaveConfig(name)
    name = tostring(name or "default")
    local data = {}
    -- Use FlagBindings to get accurate values (e.g. colorpicker with alpha)
    for k, api in pairs(Library.FlagBindings) do
        if api and api.Get then
            local ok, v1, v2 = pcall(api.Get, api)
            if ok then
                if typeof(v1) == "Color3" and type(v2) == "number" then
                    data[k] = { __t = "Color3A", r = v1.R, g = v1.G, b = v1.B, a = v2 }
                else
                    local enc = _encodeValue(v1)
                    if enc ~= nil then data[k] = enc end
                end
            end
        end
    end
    -- Also save flags without bindings
    for k, v in pairs(Library.Flags) do
        if data[k] == nil then
            local enc = _encodeValue(v)
            if enc ~= nil then data[k] = enc end
        end
    end
    local json = HttpService:JSONEncode(data)
    Library.Configs[name] = json
    if _ensureConfigFolder() then
        pcall(function()
            writefile(Library:GetConfigFolder() .. "/" .. name .. ".json", json)
        end)
    end
    Library.CurrentConfig = name
    return true
end

function Library:LoadConfig(name)
    name = tostring(name or "default")
    local json
    if _hasFileIO() then
        pcall(function()
            local path = Library:GetConfigFolder() .. "/" .. name .. ".json"
            if isfile(path) then json = readfile(path) end
        end)
    end
    if not json then json = Library.Configs[name] end
    if not json then return false end

    local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
    if not ok or type(data) ~= "table" then return false end

    for k, v in pairs(data) do
        local api = Library.FlagBindings[k]
        if api and api.Set then
            if type(v) == "table" and v.__t == "Color3A" then
                -- Colorpicker with alpha
                local c = Color3.new(v.r, v.g, v.b)
                pcall(api.Set, api, c, v.a, true)
                Library.Flags[k] = c
            else
                local decoded = _decodeValue(v)
                Library.Flags[k] = decoded
                pcall(api.Set, api, decoded, true)
            end
        else
            local decoded = _decodeValue(v)
            Library.Flags[k] = decoded
        end
    end
    -- Fire flag callbacks after all values are set
    for k, v in pairs(data) do
        local decoded
        if type(v) == "table" and v.__t == "Color3A" then
            decoded = Color3.new(v.r, v.g, v.b)
        else
            decoded = _decodeValue(v)
        end
        local list = Library.FlagCallbacks[k]
        if list then
            for _, fn in ipairs(list) do
                task.spawn(fn, decoded)
            end
        end
    end
    Library.CurrentConfig = name
    return true
end

function Library:ListConfigs()
    local arr = {}
    local seen = {}
    if _hasFileIO() then
        pcall(function()
            local folder = Library:GetConfigFolder()
            if isfolder(folder) then
                for _, file in ipairs(listfiles(folder)) do
                    local n = file:match("([^/\\]+)%.json$")
                    if n and not seen[n] then
                        table.insert(arr, n); seen[n] = true
                    end
                end
            end
        end)
    end
    for k in pairs(Library.Configs) do
        if not seen[k] then table.insert(arr, k); seen[k] = true end
    end
    table.sort(arr)
    return arr
end

function Library:DeleteConfig(name)
    name = tostring(name or "")
    if _hasFileIO() then
        pcall(function()
            local path = Library:GetConfigFolder() .. "/" .. name .. ".json"
            if isfile(path) then delfile(path) end
        end)
    end
    Library.Configs[name] = nil
    if Library.CurrentConfig == name then Library.CurrentConfig = nil end
end

----------------------------------------------------------------------
-- PLAYER DROPDOWN (real-time roster)
----------------------------------------------------------------------
function Section:AddPlayerDropdown(opts)
    opts = opts or {}
    opts.Options = {}
    opts.Text    = opts.Text or "Player"
    local includeSelf = opts.IncludeSelf and true or false

    local function roster()
        local arr = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if includeSelf or p ~= LP then
                table.insert(arr, p.Name)
            end
        end
        table.sort(arr)
        return arr
    end

    local api = self:AddDropdown(opts)
    api:Refresh(roster(), true)

    local function update() api:Refresh(roster(), true) end
    table.insert(Library.Connections, Players.PlayerAdded:Connect(update))
    table.insert(Library.Connections, Players.PlayerRemoving:Connect(update))

    function api:GetPlayer()
        local n = api:Get()
        if not n then return nil end
        return Players:FindFirstChild(n)
    end
    return api
end

----------------------------------------------------------------------
-- MINI GRAPH (bar chart, push samples in real time)
----------------------------------------------------------------------
function Section:AddGraph(opts)
    opts = opts or {}
    local text    = tostring(opts.Text or "Graph")
    local maxSamples = tonumber(opts.Samples) or 60
    local minV    = tonumber(opts.Min) or 0
    local maxV    = tonumber(opts.Max) or 100
    local height  = tonumber(opts.Height) or 60

    local frame = new("Frame", {
        Parent           = self.Content,
        Size             = UDim2.new(1, 0, 0, 18 + height + 4),
        BackgroundColor3 = Theme.Bg3,
        BorderSizePixel  = 0,
    })
    stroke(frame, Theme.Border, 1)
    pad(frame, 6, 4, 6, 4)

    local label = new("TextLabel", {
        Parent                 = frame,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, -60, 0, 14),
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.Text,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = text,
    })
    local valueLbl = new("TextLabel", {
        Parent                 = frame,
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(1, 0),
        Position               = UDim2.new(1, 0, 0, 0),
        Size                   = UDim2.new(0, 60, 0, 14),
        Font                   = FONT_M,
        TextSize               = TEXT_SIZE_SMALL,
        TextColor3             = Theme.SubText,
        TextXAlignment         = Enum.TextXAlignment.Right,
        Text                   = "0",
    })

    local plot = new("Frame", {
        Parent           = frame,
        Position         = UDim2.fromOffset(0, 16),
        Size             = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel  = 0,
    })
    stroke(plot, Theme.Border, 1)

    local bars = {}
    for i = 1, maxSamples do
        bars[i] = new("Frame", {
            Parent           = plot,
            Size             = UDim2.new(1 / maxSamples, -1, 0, 0),
            Position         = UDim2.new((i - 1) / maxSamples, 0, 1, 0),
            AnchorPoint      = Vector2.new(0, 1),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel  = 0,
        })
    end

    local samples = {}
    for i = 1, maxSamples do samples[i] = minV end

    local function render()
        local span = maxV - minV
        if span <= 0 then span = 1 end
        for i, s in ipairs(samples) do
            local pct = clamp((s - minV) / span, 0, 1)
            bars[i].Size = UDim2.new(1 / maxSamples, -1, pct, 0)
        end
        valueLbl.Text = tostring(round(samples[#samples], 2))
    end
    render()

    local api = {}
    function api:Push(v)
        v = tonumber(v) or 0
        table.remove(samples, 1)
        table.insert(samples, v)
        render()
    end
    function api:SetRange(a, b) minV, maxV = a, b; render() end
    function api:Clear()
        for i = 1, maxSamples do samples[i] = minV end
        render()
    end
    function api:SetText(t) label.Text = tostring(t) end
    return api
end

return Library

