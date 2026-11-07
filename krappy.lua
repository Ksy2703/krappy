local P  = game:GetService("Players")
local U  = game:GetService("UserInputService")
local R  = game:GetService("RunService")
local TS = game:GetService("TweenService")
local CG = game:GetService("CoreGui")
local HS = game:GetService("HapticService")
local LP = P.LocalPlayer
local Mouse = LP:GetMouse()


local PROJECT_NAME = "KrapyUrban"
local VERSION = "v35-SilentAim"
local LOGO_IMAGE = ""
local REG = (getgenv and getgenv()) or _G


if REG.__ucUnload then
    pcall(REG.__ucUnload)
    REG.__ucUnload = nil
end


do
    local parents = {}
    pcall(function() table.insert(parents, CG) end)
    local pg = LP:FindFirstChild("PlayerGui")
    if pg then table.insert(parents, pg) end
    for _, parent in ipairs(parents) do
        for _, nm in ipairs({ "UC_Menu", "UC_Overlay", "UC_Float" }) do
            local inst = parent:FindFirstChild(nm)
            if inst then pcall(function() inst:Destroy() end) end
        end
    end
    pcall(function() R:UnbindFromRenderStep("UC_Aim") end)
end


local DRAWINGS = {}
local function mkDrawing(kind)
    local success, d = pcall(function() return Drawing.new(kind) end)
    if success and d then
        table.insert(DRAWINGS, d)
        return d
    end
    return nil
end


local cfg = {
    esp = true, silentAim = true, spd = 16, spdOn = false,
    fov = 150, pred = 0.12, predOn = false, part = "Head",
    showFov = true, teamCheck = false, maxDist = 800,
    maxAimDist = 500, boxStyle = "full",
    color = Color3.fromRGB(120, 200, 255), tracerFrom = "bottom",
    jumpOn = false, jump = 50, key = Enum.KeyCode.E,
    wallCheck = false, menuKey = Enum.KeyCode.Insert,
    padUse = true, padVibrate = false,
}


local el = { box = true, tracer = true, name = true, dist = true, health = true, skel = true, dot = true }


local function gui(name, enabled)
    local g = Instance.new("ScreenGui")
    g.Name = name
    g.ResetOnSpawn = false
    g.DisplayOrder = 50
    local ok = pcall(function() g.Parent = CG end)
    if not ok or not g.Parent then g.Parent = LP:WaitForChild("PlayerGui") end
    g.Enabled = enabled ~= false
    return g
end


local gMenu    = gui("UC_Menu")
local gOverlay = gui("UC_Overlay")
local gFloat   = gui("UC_Float")


local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundTransparency = 1
overlay.Parent = gOverlay


-- ============================================================
--  TEMA
-- ============================================================
local Lib = { isOpen = true }


local T = {
    bg = Color3.fromRGB(12, 12, 16),
    panel = Color3.fromRGB(19, 19, 25),
    bar = Color3.fromRGB(10, 10, 14),
    elem = Color3.fromRGB(30, 30, 38),
    hover = Color3.fromRGB(58, 30, 36),
    accent = Color3.fromRGB(235, 45, 65),
    pink = Color3.fromRGB(255, 55, 75),
    text = Color3.fromRGB(242, 242, 247),
    dim = Color3.fromRGB(148, 148, 160),
    line = Color3.fromRGB(52, 35, 42),
    ok = Color3.fromRGB(75, 220, 135),
    font = Enum.Font.Gotham,
    bold = Enum.Font.GothamBold,
}


local conns = {}
local function cn(sig, fn)
    local c = sig:Connect(fn)
    table.insert(conns, c)
    return c
end


local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end
local function corner(o, r) mk("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o) end
local function stroke(o, c, th) mk("UIStroke", { Color = c or T.line, Thickness = th or 1 }, o) end


local function hoverFx(o, on, target)
    cn(o.MouseEnter, function()
        TS:Create(o, TweenInfo.new(0.12), { BackgroundTransparency = on }):Play()
    end)
    cn(o.MouseLeave, function()
        TS:Create(o, TweenInfo.new(0.12), { BackgroundTransparency = target or 1 }):Play()
    end)
end


local drag = nil
cn(U.InputChanged, function(i)
    if not drag then return end
    if i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch then
        drag.move(i.Position)
    end
end)
cn(U.InputEnded, function(i)
    if not drag then return end
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        drag = nil
    end
end)


local notifHolder
local function notify(text, color)
    if not notifHolder or not notifHolder.Parent then return end
    local f = mk("Frame", {
        Size = UDim2.fromOffset(210, 28), BackgroundColor3 = T.panel, BorderSizePixel = 0,
    }, notifHolder)
    corner(f, 6)
    stroke(f, color or T.accent, 1)
    mk("TextLabel", {
        Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0),
        BackgroundTransparency = 1, Text = text, Font = T.font, TextSize = 11,
        TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
    }, f)
    task.delay(2.2, function()
        if f.Parent then f:Destroy() end
    end)
end
Lib.notify = notify


-- ============================================================
--  RAYCAST / LOS
-- ============================================================
local rparams = RaycastParams.new()
rparams.FilterType = Enum.RaycastFilterType.Exclude


local function hasLOS(cam, part, char)
    if not cfg.wallCheck then return true end
    local filt = { char }
    local me = LP.Character
    if me then table.insert(filt, me) end
    rparams.FilterDescendantsInstances = filt
    local origin = cam.CFrame.Position
    local hit = workspace:Raycast(origin, part.Position - origin, rparams)
    if not hit then return true end
    return hit.Instance:IsDescendantOf(char)
end


local Win, Page = {}, {}
Win.__index = Win
Page.__index = Page


function Lib.newWindow(o)
    o = o or {}
    local self = setmetatable({}, Win)
    local menuGui  = o.parent or gMenu
    local floatGui = o.floatParent or gFloat


    local win = mk("Frame", {
        Size = UDim2.fromOffset(o.width or 385, o.height or 470),
        Position = UDim2.new(0.5, -192.5, 0.5, -235),
        BackgroundColor3 = T.panel, BorderSizePixel = 0, Active = true,
    }, menuGui)
    corner(win, 10)
    stroke(win, T.line, 1)
    self.win = win


    self.scale = mk("UIScale", {}, win)
    local function fit()
        local cam = workspace.CurrentCamera
        if not cam then return end
        self.scale.Scale = math.clamp(cam.ViewportSize.Y / 820, 0.72, 1.1)
    end
    fit()
    cn(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), fit)


    local bar = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = T.bar, BorderSizePixel = 0,
    }, win)
    corner(bar, 10)
    mk("Frame", {
        Size = UDim2.new(1, 0, 0, 10), Position = UDim2.new(0, 0, 1, -10),
        BackgroundColor3 = T.bar, BorderSizePixel = 0,
    }, bar)


    local logo = mk("ImageLabel", {
        Name = "ProjectLogo",
        Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(8, 6),
        BackgroundColor3 = T.elem, BackgroundTransparency = 0,
        BorderSizePixel = 0, Image = LOGO_IMAGE,
        ScaleType = Enum.ScaleType.Fit,
    }, bar)
    corner(logo, 6)
    stroke(logo, T.accent, 1)
    if LOGO_IMAGE == "" then
        logo.Image = ""
        mk("TextLabel", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
            Text = "K", Font = T.bold, TextSize = 15,
            TextColor3 = T.accent, TextXAlignment = Enum.TextXAlignment.Center,
        }, logo)
    end
    mk("TextLabel", {
        Size = UDim2.new(1, -145, 1, 0), Position = UDim2.fromOffset(39, 0),
        BackgroundTransparency = 1, Text = (o.title or PROJECT_NAME),
        Font = T.bold, TextSize = 12, TextColor3 = T.text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, bar)
    mk("TextLabel", {
        Size = UDim2.fromOffset(50, 36), Position = UDim2.new(1, -122, 0, 0),
        BackgroundTransparency = 1, Text = o.version or "", Font = T.font, TextSize = 10,
        TextColor3 = T.dim, TextXAlignment = Enum.TextXAlignment.Right,
    }, bar)


    cn(bar.InputBegan, function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1
        and i.UserInputType ~= Enum.UserInputType.Touch then return end
        local start, base = i.Position, win.Position
        drag = {
            move = function(p)
                local d = p - start
                local cam = workspace.CurrentCamera
                local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
                local sz = win.AbsoluteSize
                win.Position = UDim2.new(0,
                    math.clamp(base.X.Offset + d.X, -sz.X + 60, vp.X - 60),
                    0, math.clamp(base.Y.Offset + d.Y, 0, vp.Y - 36))
            end,
        }
    end)


    local mini = mk("TextButton", {
        Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, -52, 0, 8),
        BackgroundColor3 = T.elem, Text = "-", Font = T.bold, TextSize = 13,
        TextColor3 = T.text, BorderSizePixel = 0, AutoButtonColor = false,
    }, bar)
    corner(mini, 4)
    local close = mk("TextButton", {
        Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, -28, 0, 8),
        BackgroundColor3 = T.elem, Text = "X", Font = T.bold, TextSize = 11,
        TextColor3 = T.text, BorderSizePixel = 0, AutoButtonColor = false,
    }, bar)
    corner(close, 4)
    for _, b in ipairs({ mini, close }) do
        cn(b.MouseEnter, function() b.BackgroundColor3 = T.hover end)
        cn(b.MouseLeave, function() b.BackgroundColor3 = T.elem end)
    end


    local float = mk("TextButton", {
        Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(20, 120),
        BackgroundColor3 = T.panel, Text = "U", Font = T.bold, TextSize = 17,
        TextColor3 = T.accent, BorderSizePixel = 0, AutoButtonColor = false,
    }, floatGui)
    corner(float, 23)
    stroke(float, T.accent, 1)


    function Lib.setOpen(open)
        Lib.isOpen = open
        menuGui.Enabled = open
        floatGui.Enabled = not open
    end
    Lib.setOpen(true)


    mini.MouseButton1Click:Connect(function() Lib.setOpen(false) end)
    close.MouseButton1Click:Connect(function() Lib.setOpen(false) end)


    local fstart, fbase, fmoved
    cn(float.InputBegan, function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1
        and i.UserInputType ~= Enum.UserInputType.Touch then return end
        fstart, fbase, fmoved = i.Position, float.Position, false
        drag = {
            move = function(p)
                local d = p - fstart
                if d.Magnitude > 5 then fmoved = true end
                local cam = workspace.CurrentCamera
                local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
                float.Position = UDim2.new(0, math.clamp(fbase.X.Offset + d.X, 0, vp.X - 46),
                    0, math.clamp(fbase.Y.Offset + d.Y, 0, vp.Y - 46))
            end,
        }
    end)
    float.MouseButton1Click:Connect(function()
        if not fmoved then Lib.setOpen(true) end
    end)


    notifHolder = mk("Frame", {
        Size = UDim2.fromOffset(210, 240), Position = UDim2.new(1, -230, 0, 20), BackgroundTransparency = 1,
    }, o.notifParent or gOverlay)
    mk("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Right }, notifHolder)


    local tabBar = mk("Frame", {
        Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 44), BackgroundTransparency = 1,
    }, win)
    mk("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, tabBar)


    local pages, current = {}, nil
    local tabBtns = {}


    function Win:tab(name)
        local btn = mk("TextButton", {
            Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = T.elem, Text = name, Font = T.bold, TextSize = 9.5,
            TextColor3 = T.dim, BorderSizePixel = 0, AutoButtonColor = false,
        }, tabBar)
        corner(btn, 5)
        mk("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, btn)
        table.insert(tabBtns, btn)


        local page = mk("ScrollingFrame", {
            Size = UDim2.new(1, -16, 1, -80), Position = UDim2.fromOffset(8, 76),
            BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
            ScrollBarThickness = 3, ScrollBarImageColor3 = T.line,
            CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        }, win)
        mk("UIListLayout", { Padding = UDim.new(0, 7) }, page)
        mk("UIPadding", { PaddingBottom = UDim.new(0, 14) }, page)


        local obj = setmetatable({ page = page }, Win)
        pages[btn] = obj


        btn.MouseButton1Click:Connect(function()
            for b, p in pairs(pages) do
                p.page.Visible = false
                b.BackgroundColor3 = T.elem
                b.TextColor3 = T.dim
            end
            page.Visible = true
            btn.BackgroundColor3 = T.accent
            btn.TextColor3 = T.bg
            current = name
        end)


        if not current then
            current = name
            page.Visible = true
            btn.BackgroundColor3 = T.accent
            btn.TextColor3 = T.bg
        end
        return obj
    end


    cn(U.InputBegan, function(i, gp)
        if gp then return end
        if i.KeyCode == cfg.menuKey then Lib.setOpen(not Lib.isOpen) end
    end)


    return self
end


function Win.section(self, name, open)
    local box = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = T.bg, BorderSizePixel = 0,
    }, self.page)
    corner(box, 7)
    stroke(box, T.line, 1)
    mk("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 0),
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
    }, box)


    local head = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1,
        BackgroundColor3 = T.panel, BackgroundTransparency = 0.2, BorderSizePixel = 0,
    }, box)
    corner(head, 7)


    mk("Frame", {
        Size = UDim2.fromOffset(3, 14), Position = UDim2.fromOffset(9, 8),
        BackgroundColor3 = T.accent, BorderSizePixel = 0,
    }, head)


    local arrow = mk("TextLabel", {
        Size = UDim2.fromOffset(12, 30), Position = UDim2.fromOffset(16, 0),
        BackgroundTransparency = 1, Text = open ~= false and "v" or ">",
        Font = T.bold, TextSize = 10, TextColor3 = T.accent,
    }, head)


    mk("TextLabel", {
        Size = UDim2.new(1, -48, 0, 30), Position = UDim2.fromOffset(32, 0),
        BackgroundTransparency = 1, Text = name, Font = T.bold, TextSize = 12,
        TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
    }, head)


    local body = mk("Frame", {
        Size = UDim2.new(1, -18, 0, 0), LayoutOrder = 2,
        AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        Visible = open ~= false,
    }, box)
    mk("UIListLayout", { Padding = UDim.new(0, 4) }, body)
    mk("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8) }, body)


    local click = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Text = "",
    }, head)
    click.MouseButton1Click:Connect(function()
        body.Visible = not body.Visible
        arrow.Text = body.Visible and "v" or ">"
    end)
    cn(click.MouseEnter, function() head.BackgroundTransparency = 0.05 end)
    cn(click.MouseLeave, function() head.BackgroundTransparency = 0.2 end)


    return setmetatable({ body = body }, Page)
end


function Page.label(self, text)
    return mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, 15), BackgroundTransparency = 1, Text = text,
        Font = T.font, TextSize = 10, TextColor3 = T.dim, TextXAlignment = Enum.TextXAlignment.Left,
    }, self.body)
end


function Page.divider(self)
    local d = mk("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.line, BorderSizePixel = 0 }, self.body)
    return d
end


function Page.button(self, text, fn)
    local b = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = T.elem, Text = text,
        Font = T.font, TextSize = 11, TextColor3 = T.text, BorderSizePixel = 0, AutoButtonColor = false,
    }, self.body)
    corner(b, 5)
    b.MouseEnter:Connect(function() b.BackgroundColor3 = T.hover end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = T.elem end)
    b.MouseButton1Click:Connect(fn)
    return b
end


function Page.toggle(self, text, initial, cb)
    local wrap = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 26), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
    }, self.body)
    mk("UIListLayout", { Padding = UDim.new(0, 2) }, wrap)


    local row = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = T.elem, BackgroundTransparency = 1,
    }, wrap)
    corner(row, 5)
    hoverFx(row, 0.65)


    mk("TextLabel", {
        Size = UDim2.new(1, -50, 1, 0), Position = UDim2.fromOffset(8, 0),
        BackgroundTransparency = 1, Text = text, Font = T.font, TextSize = 11,
        TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
    }, row)


    local state = initial and true or false
    local track = mk("Frame", {
        Size = UDim2.fromOffset(34, 18), Position = UDim2.new(1, -42, 0.5, -9),
        BackgroundColor3 = state and T.accent or T.elem, BorderSizePixel = 0,
    }, row)
    corner(track, 9)
    stroke(track, T.line, 1)
    local knob = mk("Frame", {
        Size = UDim2.fromOffset(12, 12), Position = UDim2.fromOffset(state and 18 or 3, 3),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, track)
    corner(knob, 6)


    local body = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Visible = state,
    }, wrap)
    mk("UIListLayout", { Padding = UDim.new(0, 4) }, body)
    mk("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingBottom = UDim.new(0, 4) }, body)


    local api = { body = body }
    api.page = setmetatable({ body = body }, Page)


    function api.set(v, silent)
        state = v and true or false
        body.Visible = state
        TS:Create(knob, TweenInfo.new(0.14), { Position = UDim2.fromOffset(state and 18 or 3, 3) }):Play()
        TS:Create(track, TweenInfo.new(0.14), { BackgroundColor3 = state and T.accent or T.elem }):Play()
        if cb and not silent then cb(state) end
    end


    local click = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Text = "",
    }, row)
    click.MouseButton1Click:Connect(function() api.set(not state) end)
    return api
end


function Page.slider(self, text, min, max, def, decimals, cb)
    local row = mk("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1 }, self.body)


    mk("TextLabel", {
        Size = UDim2.new(1, -56, 0, 14), BackgroundTransparency = 1, Text = text,
        Font = T.font, TextSize = 11, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
    }, row)


    local chip = mk("Frame", {
        Size = UDim2.fromOffset(48, 15), Position = UDim2.new(1, -48, 0, 0),
        BackgroundColor3 = T.elem, BorderSizePixel = 0,
    }, row)
    corner(chip, 4)
    local val = mk("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = tostring(def),
        Font = T.bold, TextSize = 10, TextColor3 = T.accent,
    }, chip)


    local track = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 5), Position = UDim2.fromOffset(0, 21),
        BackgroundColor3 = T.elem, BorderSizePixel = 0,
    }, row)
    corner(track, 3)


    local fill = mk("Frame", {
        Size = UDim2.new((def - min) / (max - min), 0, 1, 0),
        BackgroundColor3 = T.accent, BorderSizePixel = 0,
    }, track)
    corner(fill, 3)


    local thumb = mk("Frame", {
        Size = UDim2.fromOffset(11, 11), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new((def - min) / (max - min), 0, 0.5, 0),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, track)
    corner(thumb, 6)


    local m = 10 ^ (decimals or 0)
    local function apply(x)
        local pct = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        local v = math.floor((min + (max - min) * pct) * m + 0.5) / m
        fill.Size = UDim2.new(pct, 0, 1, 0)
        thumb.Position = UDim2.new(pct, 0, 0.5, 0)
        val.Text = tostring(v)
        if cb then cb(v) end
    end


    local hit = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 15),
        BackgroundTransparency = 1, Text = "",
    }, row)
    cn(hit.InputBegan, function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1
        and i.UserInputType ~= Enum.UserInputType.Touch then return end
        apply(i.Position.X)
        drag = { move = function(p) apply(p.X) end }
    end)


    return { set = function(v)
        local pct = math.clamp((v - min) / (max - min), 0, 1)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        thumb.Position = UDim2.new(pct, 0, 0.5, 0)
        val.Text = tostring(v)
        if cb then cb(v) end
    end }
end


function Page.dropdown(self, text, options, def, cb)
    local wrap = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 26), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
    }, self.body)
    mk("UIListLayout", { Padding = UDim.new(0, 2) }, wrap)


    local row = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = T.elem, BackgroundTransparency = 1,
    }, wrap)
    corner(row, 5)
    hoverFx(row, 0.65)


    mk("TextLabel", {
        Size = UDim2.new(1, -104, 1, 0), Position = UDim2.fromOffset(8, 0),
        BackgroundTransparency = 1, Text = text, Font = T.font, TextSize = 11,
        TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
    }, row)


    local btn = mk("TextButton", {
        Size = UDim2.fromOffset(96, 19), Position = UDim2.new(1, -104, 0.5, -9.5),
        BackgroundColor3 = T.elem, Text = "", BorderSizePixel = 0, AutoButtonColor = false,
    }, row)
    corner(btn, 4)
    stroke(btn, T.line, 1)
    local lbl = mk("TextLabel", {
        Size = UDim2.new(1, -18, 1, 0), Position = UDim2.fromOffset(6, 0),
        BackgroundTransparency = 1, Text = tostring(def), Font = T.font, TextSize = 10,
        TextColor3 = T.accent, TextXAlignment = Enum.TextXAlignment.Left,
    }, btn)
    mk("TextLabel", {
        Size = UDim2.fromOffset(12, 19), Position = UDim2.new(1, -15, 0, 0),
        BackgroundTransparency = 1, Text = "v", Font = T.bold, TextSize = 9, TextColor3 = T.dim,
    }, btn)


    local body = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Visible = false,
    }, wrap)
    mk("UIListLayout", { Padding = UDim.new(0, 2) }, body)
    mk("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingBottom = UDim.new(0, 4) }, body)


    local api = {}
    function api.set(v)
        lbl.Text = tostring(v)
        if cb then cb(v) end
    end


    for _, opt in ipairs(options) do
        local ob = mk("TextButton", {
            Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = T.bg, Text = tostring(opt),
            Font = T.font, TextSize = 10, TextColor3 = T.text, BorderSizePixel = 0,
            AutoButtonColor = false,
        }, body)
        corner(ob, 4)
        ob.MouseEnter:Connect(function() ob.BackgroundColor3 = T.hover end)
        ob.MouseLeave:Connect(function() ob.BackgroundColor3 = T.bg end)
        ob.MouseButton1Click:Connect(function()
            api.set(opt)
            body.Visible = false
        end)
    end


    btn.MouseButton1Click:Connect(function()
        body.Visible = not body.Visible
    end)
    return api
end


function Page.keybind(self, text, def, cb)
    local row = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = T.elem, BackgroundTransparency = 1,
    }, self.body)
    corner(row, 5)
    hoverFx(row, 0.65)


    mk("TextLabel", {
        Size = UDim2.new(1, -104, 1, 0), Position = UDim2.fromOffset(8, 0),
        BackgroundTransparency = 1, Text = text, Font = T.font, TextSize = 11,
        TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
    }, row)


    local btn = mk("TextButton", {
        Size = UDim2.fromOffset(96, 19), Position = UDim2.new(1, -104, 0.5, -9.5),
        BackgroundColor3 = T.elem, Text = def and def.Name or "-", Font = T.font, TextSize = 10,
        TextColor3 = T.accent, BorderSizePixel = 0, AutoButtonColor = false,
    }, row)
    corner(btn, 4)
    stroke(btn, T.line, 1)


    local api, listening = {}, false
    function api.set(v)
        btn.Text = v and v.Name or "-"
        if cb then cb(v) end
    end


    btn.MouseButton1Click:Connect(function()
        listening = true
        btn.Text = "..."
    end)
    cn(U.InputBegan, function(i, gp)
        if not listening or gp then return end
        listening = false
        if i.KeyCode == Enum.KeyCode.Escape then
            btn.Text = def and def.Name or "-"
            return
        end
        api.set(i.KeyCode)
    end)
    return api
end


function Lib.destroy()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    table.clear(conns)
end


-- ============================================================
--  CONSTRUCCIÓN DE MENÚ (PESTAÑAS)
-- ============================================================
local win = Lib.newWindow({
    title = PROJECT_NAME, version = VERSION,
    parent = gMenu, floatParent = gFloat, notifParent = gOverlay,
    width = 385, height = 470,
})


local tv = win:tab("VISUALS")
local sEsp = tv:section("ESP", true)
sEsp:toggle("ESP activo", cfg.esp, function(v) cfg.esp = v end)
sEsp:toggle("Caja", el.box, function(v) el.box = v end)
sEsp:toggle("Trazadora", el.tracer, function(v) el.tracer = v end)
sEsp:toggle("Nombre", el.name, function(v) el.name = v end)
sEsp:toggle("Distancia", el.dist, function(v) el.dist = v end)
sEsp:toggle("Vida", el.health, function(v) el.health = v end)
sEsp:toggle("Esqueleto", el.skel, function(v) el.skel = v end)
sEsp:toggle("Punto de cabeza", el.dot, function(v) el.dot = v end)


local sEspLook = tv:section("ESTILO", true)
sEspLook:dropdown("Estilo de caja", { "Completa", "Esquinas" }, "Completa", function(v)
    cfg.boxStyle = (v == "Esquinas") and "corner" or "full"
end)
sEspLook:dropdown("Origen trazadora", { "Abajo", "Centro" }, "Abajo", function(v)
    cfg.tracerFrom = (v == "Centro") and "center" or "bottom"
end)
sEspLook:dropdown("Color", { "Rojo", "Verde", "Blanco", "Rosa", "Amarillo" }, "Rojo", function(v)
    local map = {
        Rojo = Color3.fromRGB(235, 45, 65),
        Verde = Color3.fromRGB(90, 255, 140),
        Blanco = Color3.fromRGB(240, 240, 240),
        Rosa = Color3.fromRGB(255, 130, 200),
        Amarillo = Color3.fromRGB(255, 225, 90),
    }
    if map[v] then cfg.color = map[v] end
end)
sEspLook:slider("Distancia máxima", 50, 2000, cfg.maxDist, 0, function(v) cfg.maxDist = v end)


local ta = win:tab("SILENT AIM")
local sAim = ta:section("SILENT CONFIG", true)
sAim:toggle("Silent Aim Activo", cfg.silentAim, function(v) cfg.silentAim = v end)
sAim:toggle("Wall check", cfg.wallCheck, function(v) cfg.wallCheck = v end)
sAim:dropdown("Zona", { "Cabeza", "Cuerpo" }, "Cabeza", function(v)
    cfg.part = (v == "Cabeza") and "Head" or "Torso"
end)
sAim:toggle("Círculo FOV", cfg.showFov, function(v) cfg.showFov = v end)
sAim:slider("FOV de Silent", 30, 700, cfg.fov, 0, function(v) cfg.fov = v end)
sAim:slider("Distancia máx.", 50, 1500, cfg.maxAimDist, 0, function(v) cfg.maxAimDist = v end)


local tf = win:tab("FILTERS")
local sFil = tf:section("EQUIPO", true)
sFil:toggle("Ignorar equipo (ESP)", cfg.teamCheck, function(v) cfg.teamCheck = v end)
sFil:toggle("Ignorar equipo (SILENT)", cfg.teamCheck, function(v) cfg.teamCheck = v end)


local tpTab = win:tab("PLAYERS")
local sList = tpTab:section("JUGADORES EN LÍNEA", true)

local playerButtonsContainer = sList.body

local function refreshPlayerList()
    for _, child in ipairs(playerButtonsContainer:GetChildren()) do
        if child:IsA("Frame") and child.Name == "PlayerRow" then
            child:Destroy()
        end
    end

    for _, pl in ipairs(P:GetPlayers()) do
        if pl ~= LP then
            local row = mk("Frame", {
                Name = "PlayerRow",
                Size = UDim2.new(1, 0, 0, 32),
                BackgroundColor3 = T.elem,
                BackgroundTransparency = 0.5,
                BorderSizePixel = 0,
            }, playerButtonsContainer)
            corner(row, 5)
            hoverFx(row, 0.2)

            mk("TextLabel", {
                Size = UDim2.new(1, -60, 1, 0),
                Position = UDim2.fromOffset(8, 0),
                BackgroundTransparency = 1,
                Text = pl.Name,
                Font = T.font,
                TextSize = 11,
                TextColor3 = T.text,
                TextXAlignment = Enum.TextXAlignment.Left,
            }, row)

            local copyBtn = mk("TextButton", {
                Size = UDim2.fromOffset(50, 20),
                Position = UDim2.new(1, -58, 0.5, -10),
                BackgroundColor3 = T.panel,
                Text = "Copiar",
                Font = T.bold,
                TextSize = 9,
                TextColor3 = T.dim,
                BorderSizePixel = 0,
                AutoButtonColor = false,
            }, row)
            corner(copyBtn, 4)

            copyBtn.MouseButton1Click:Connect(function()
                pcall(function() setclipboard(pl.Name) end)
                notify("Nombre copiado: " .. pl.Name, T.ok)
            end)
        end
    end
end

cn(P.PlayerAdded, function() task.wait(0.5) refreshPlayerList() end)
cn(P.PlayerRemoving, function() task.wait(0.5) refreshPlayerList() end)
task.spawn(refreshPlayerList)


local tm = win:tab("MISC")
local sMisc = tm:section("MOVIMIENTO", true)


local baseSpeed, baseJump = nil, nil
local spdSlider, jumpSlider


local function currentHumanoid()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end


local spdTog = sMisc:toggle("Velocidad", cfg.spdOn, function(v)
    cfg.spdOn = v
    local h = currentHumanoid()
    if v then
        if h then
            baseSpeed = h.WalkSpeed
            if spdSlider then spdSlider.set(h.WalkSpeed) end
        end
    else
        if h and baseSpeed then h.WalkSpeed = baseSpeed end
        baseSpeed = nil
    end
end)
spdSlider = spdTog.page:slider("Cantidad", 8, 200, cfg.spd, 0, function(v) cfg.spd = v end)


local jumpTog = sMisc:toggle("Forzar salto", cfg.jumpOn, function(v)
    cfg.jumpOn = v
    local h = currentHumanoid()
    if v then
        if h then
            if not h.UseJumpPower then h.UseJumpPower = true end
            baseJump = h.JumpPower
        end
    else
        if h and baseJump then h.JumpPower = baseJump end
        baseJump = nil
    end
end)
jumpSlider = jumpTog.page:slider("Fuerza", 50, 200, cfg.jump, 0, function(v) cfg.jump = v end)


local sConf = tm:section("CONFIG", true)
sConf:keybind("Abrir/cerrar menú", cfg.menuKey, function(k) cfg.menuKey = k end)
sConf:divider()
sConf:button("Descargar script (unload)", function()
    if REG.__ucUnload then pcall(REG.__ucUnload) end
end)
sConf:label(PROJECT_NAME .. " · " .. VERSION)


-- ============================================================
--  VISUALES Y ESP
-- ============================================================
local fovCircle = mkDrawing("Circle")
if fovCircle then
    fovCircle.Thickness = 1
    fovCircle.NumSides = 64
    fovCircle.Filled = false
end


local draws = {}


local function makeLabel(color, size, anchor)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.GothamBold
    l.TextSize = size
    l.TextColor3 = color
    l.TextStrokeTransparency = 0.35
    l.Size = UDim2.fromOffset(200, 16)
    l.AnchorPoint = anchor
    l.Visible = false
    l.Parent = overlay
    return l
end


local function makeVisuals(pl)
    if pl == LP or draws[pl] then return end
    local d = { box = {}, health = {}, skel = {}, tracer = mkDrawing("Line") }
    for i = 1, 8 do d.box[i] = mkDrawing("Line") end
    for i = 1, 2 do d.health[i] = mkDrawing("Line") end
    for i = 1, 20 do d.skel[i] = mkDrawing("Line") end
    d.dot = mkDrawing("Circle")
    if d.dot then
        d.dot.Filled = true
        d.dot.NumSides = 12
        d.dot.Thickness = 1
    end
    d.name = makeLabel(Color3.new(1, 1, 1), 12, Vector2.new(0.5, 1))
    d.dist = makeLabel(Color3.fromRGB(180, 225, 255), 11, Vector2.new(0.5, 0))
    draws[pl] = d
end


local function killVisuals(pl)
    local d = draws[pl]
    if not d then return end
    pcall(function()
        for _, l in ipairs(d.box) do l:Remove() end
        for _, l in ipairs(d.health) do l:Remove() end
        for _, l in ipairs(d.skel) do l:Remove() end
        if d.tracer then d.tracer:Remove() end
        if d.dot then d.dot:Remove() end
        d.name:Destroy()
        d.dist:Destroy()
    end)
    draws[pl] = nil
end


for _, pl in ipairs(P:GetPlayers()) do makeVisuals(pl) end
P.PlayerAdded:Connect(makeVisuals)
P.PlayerRemoving:Connect(killVisuals)


local OFF8 = {}
for _, x in ipairs({ -0.5, 0.5 }) do
    for _, y in ipairs({ -0.5, 0.5 }) do
        for _, z in ipairs({ -0.5, 0.5 }) do
            table.insert(OFF8, Vector3.new(x, y, z))
        end
    end
end


local BONES = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" },
    { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
    { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}


-- ============================================================
--  OBTENCIÓN DE OBJETIVO PARA SILENT AIM
-- ============================================================
local function targetAlive(part)
    if not part or not part.Parent then return false end
    local model = part:FindFirstAncestorOfClass("Model")
    local h = model and model:FindFirstChildOfClass("Humanoid")
    return h ~= nil and h.Health > 0
end

local function getSilentTarget()
    if not cfg.silentAim then return nil end
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)

    local bestPart, bestDist = nil, math.huge
    local myChar = LP.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local myPos = myRoot and myRoot.Position

    for _, pl in ipairs(P:GetPlayers()) do
        if pl ~= LP then
            local c = pl.Character
            local h = c and c:FindFirstChildOfClass("Humanoid")
            local root = c and c:FindFirstChild("HumanoidRootPart")
            local team = cfg.teamCheck and pl.Team and LP.Team and pl.Team == LP.Team
            local near = (not myPos) or (root and (root.Position - myPos).Magnitude <= cfg.maxAimDist)
            
            if h and h.Health > 0 and not team and near then
                local part
                if cfg.part == "Head" then
                    part = c:FindFirstChild("Head")
                else
                    part = c:FindFirstChild("UpperTorso") or c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso")
                end
                if part and hasLOS(cam, part, c) then
                    local sp, on = cam:WorldToViewportPoint(part.Position)
                    if on then
                        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                        if d < cfg.fov and d < bestDist then
                            bestPart, bestDist = part, d
                        end
                    end
                end
            end
        end
    end
    return bestPart
end


-- ============================================================
--  HOOK DE SILENT AIM (METAMETHOD)
-- ============================================================
pcall(function()
    local mt = getrawmetatable(game)
    setreadonly(mt, false)
    local oldNamecall = mt.__namecall

    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        
        if cfg.silentAim and (method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRay" or method == "Raycast") then
            local targetPart = getSilentTarget()
            if targetPart and self == workspace then
                if method == "Raycast" then
                    local origin = args[1]
                    local direction = (targetPart.Position - origin).Unit * args[2].Magnitude
                    args[2] = direction
                    return oldNamecall(self, unpack(args))
                elseif method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" then
                    local ray = args[1]
                    local newRay = Ray.new(ray.Origin, (targetPart.Position - ray.Origin).Unit * ray.Direction.Magnitude)
                    args[1] = newRay
                    return oldNamecall(self, unpack(args))
                end
            end
        end
        return oldNamecall(self, ...)
    end)
    setreadonly(mt, true)
end)


-- ============================================================
--  BUCLE VISUAL ESP & FOV
-- ============================================================
R.RenderStepped:Connect(function()
    local cam = workspace.CurrentCamera
    if not cam then return end

    local col = cfg.color

    if fovCircle then
        fovCircle.Visible = cfg.silentAim and cfg.showFov
        fovCircle.Position = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
        fovCircle.Radius = cfg.fov
        fovCircle.Color = col
    end

    local myChar = LP.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local myPos = myRoot and myRoot.Position

    for pl, d in pairs(draws) do
        local c = pl.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        local root = c and c:FindFirstChild("HumanoidRootPart")
        local head = c and c:FindFirstChild("Head")
        local dist = (root and myPos) and (root.Position - myPos).Magnitude or 0
        local team = cfg.teamCheck and pl.Team and LP.Team and pl.Team == LP.Team
        local valid = cfg.esp and c and h and h.Health > 0 and root and head and not team and dist <= cfg.maxDist

        local pos, on = nil, false
        if valid then pos, on = cam:WorldToViewportPoint(head.Position) end

        for _, l in ipairs(d.box) do l.Visible = false end
        for _, l in ipairs(d.health) do l.Visible = false end
        for _, l in ipairs(d.skel) do l.Visible = false end
        if d.tracer then d.tracer.Visible = false end
        if d.dot then d.dot.Visible = false end
        d.name.Visible = false
        d.dist.Visible = false

        if valid and on then
            local cf, size = c:GetBoundingBox()
            local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
            local okBox = el.box or el.health
            if okBox then
                for _, off in ipairs(OFF8) do
                    local sp, so = cam:WorldToViewportPoint(cf * Vector3.new(size.X * off.X, size.Y * off.Y, size.Z * off.Z))
                    if not so then okBox = false break end
                    if sp.X < minX then minX = sp.X end
                    if sp.X > maxX then maxX = sp.X end
                    if sp.Y < minY then minY = sp.Y end
                    if sp.Y > maxY then maxY = sp.Y end
                end
            end

            if okBox then
                if el.box then
                    if cfg.boxStyle == "corner" then
                        local ln = math.max(math.min(maxX - minX, maxY - minY) * 0.22, 4)
                        local segs = {
                            { minX, minY, minX + ln, minY }, { minX, minY, minX, minY + ln },
                            { maxX, minY, maxX - ln, minY }, { maxX, minY, maxX, minY + ln },
                            { minX, maxY, minX + ln, maxY }, { minX, maxY, minX, minY - ln },
                            { maxX, maxY, maxX - ln, maxY }, { maxX, maxY, maxX, maxX - ln },
                        }
                        for i, l in ipairs(d.box) do
                            local s = segs[i]
                            l.From, l.To = Vector2.new(s[1], s[2]), Vector2.new(s[3], s[4])
                            l.Color, l.Thickness, l.Visible = col, 1, true
                        end
                    else
                        local corners = {
                            { Vector2.new(minX, minY), Vector2.new(maxX, minY) },
                            { Vector2.new(minX, maxY), Vector2.new(maxX, maxY) },
                            { Vector2.new(minX, minY), Vector2.new(minX, maxY) },
                            { Vector2.new(maxX, minY), Vector2.new(maxX, maxY) },
                        }
                        for i = 1, 4 do
                            local l = d.box[i]
                            l.From, l.To = corners[i][1], corners[i][2]
                            l.Color, l.Thickness, l.Visible = col, 1, true
                        end
                    end
                end

                if el.health then
                    local frac = math.clamp(h.Health / math.max(h.MaxHealth, 1), 0, 1)
                    d.health[1].From = Vector2.new(minX - 6, minY)
                    d.health[1].To = Vector2.new(minX - 6, maxY)
                    d.health[1].Color = Color3.fromRGB(35, 35, 35)
                    d.health[1].Thickness = 3
                    d.health[1].Visible = true
                    d.health[2].From = Vector2.new(minX - 6, maxY - (maxY - minY) * frac)
                    d.health[2].To = Vector2.new(minX - 6, maxY)
                    d.health[2].Color = Color3.fromRGB(0, 255, 90):Lerp(Color3.fromRGB(255, 40, 40), 1 - frac)
                    d.health[2].Thickness = 3
                    d.health[2].Visible = true
                end

                if el.dot and d.dot then
                    d.dot.Position = Vector2.new(pos.X, minY - 9)
                    d.dot.Radius = 3
                    d.dot.Color = col
                    d.dot.Visible = true
                end

                if el.name then
                    d.name.Text = pl.Name
                    d.name.Position = UDim2.fromOffset(pos.X, minY - 3)
                    d.name.Visible = true
                end

                if el.dist then
                    d.dist.Text = math.floor(dist) .. "m"
                    d.dist.Position = UDim2.fromOffset(pos.X, maxY + 3)
                    d.dist.Visible = true
                end
            end

            if el.tracer and d.tracer then
                if cfg.tracerFrom == "center" then
                    d.tracer.From = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
                else
                    d.tracer.From = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y)
                end
                d.tracer.To = Vector2.new(pos.X, pos.Y)
                d.tracer.Color = col
                d.tracer.Thickness = 1
                d.tracer.Visible = true
            end

            if el.skel then
                local idx = 1
                for _, pair in ipairs(BONES) do
                    local a, b = c:FindFirstChild(pair[1]), c:FindFirstChild(pair[2])
                    if a and b and idx <= #d.skel then
                        local p1, o1 = cam:WorldToViewportPoint(a.Position)
                        local p2, o2 = cam:WorldToViewportPoint(b.Position)
                        if o1 and o2 then
                            local l = d.skel[idx]
                            l.From, l.To = Vector2.new(p1.X, p1.Y), Vector2.new(p2.X, p2.Y)
                            l.Color, l.Thickness, l.Visible = col, 1, true
                            idx = idx + 1
                        end
                    end
                end
            end
        end
    end
end)


-- ============================================================
--  MOVIMIENTO (HUMANOID)
-- ============================================================
R.RenderStepped:Connect(function()
    local h = currentHumanoid()
    if not h then return end
    if cfg.spdOn then
        if baseSpeed == nil then baseSpeed = h.WalkSpeed end
        if h.WalkSpeed ~= cfg.spd then h.WalkSpeed = cfg.spd end
    else
        if h.WalkSpeed ~= cfg.spd then baseSpeed = h.WalkSpeed end
    end
    if cfg.jumpOn then
        if not h.UseJumpPower then h.UseJumpPower = true end
        if h.JumpPower ~= cfg.jump then h.JumpPower = cfg.jump end
    end
end)


-- ============================================================
--  DESCARGA / UNLOAD
-- ============================================================
REG.__ucUnload = function()
    pcall(Lib.destroy)
    for _, d in ipairs(DRAWINGS) do pcall(function() d:Remove() end) end
    table.clear(DRAWINGS)
    for pl in pairs(draws) do killVisuals(pl) end
    for _, g in ipairs({ gMenu, gOverlay, gFloat }) do pcall(function() g:Destroy() end) end
    local hum = currentHumanoid()
    if hum then
        pcall(function()
            if cfg.spdOn and baseSpeed then hum.WalkSpeed = baseSpeed end
            if cfg.jumpOn then hum.JumpPower = baseJump or 50 end
        end)
    end
    print("[UC] descargado")
end


print("[" .. PROJECT_NAME .. "] " .. VERSION .. " cargado con éxito en Xeno")
