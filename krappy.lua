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
        TextColor3 = T.