-- LuaSupportsSVG demo (executor script)
-- Put LuaSupportsSVG.luau in your executor workspace as LuaSupportsSVG/LuaSupportsSVG.luau, then run this.

local SVG = loadstring(readfile("LuaSupportsSVG/LuaSupportsSVG.luau"), "LuaSupportsSVG")()

local host = gethui and gethui() or game:GetService("CoreGui")
local old = host:FindFirstChild("LuaSupportsSVG_Demo")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "LuaSupportsSVG_Demo"
gui.IgnoreGuiInset = true
gui.Parent = host

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(760, 420)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 36)
title.BackgroundTransparency = 1
title.Text = "LuaSupportsSVG demo - SVG rasterized in Luau -> EditableImage (click to close)"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.Parent = panel

local close = Instance.new("TextButton")
close.Size = UDim2.new(1, 0, 0, 36)
close.BackgroundTransparency = 1
close.Text = ""
close.Parent = panel
close.MouseButton1Click:Connect(function() gui:Destroy() end)

local grid = Instance.new("Frame")
grid.Size = UDim2.new(1, -20, 1, -50)
grid.Position = UDim2.fromOffset(10, 44)
grid.BackgroundTransparency = 1
grid.Parent = panel
local layout = Instance.new("UIGridLayout", grid)
layout.CellSize = UDim2.fromOffset(176, 176)
layout.CellPadding = UDim2.fromOffset(8, 8)

local samples = {
    -- gradients + rounded rect + ellipse
    [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">
      <defs>
        <linearGradient id="g1" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="#ff7a18"/><stop offset="100%" stop-color="#af002d"/>
        </linearGradient>
        <radialGradient id="g2"><stop offset="0" stop-color="white"/><stop offset="1" stop-color="#1e90ff" stop-opacity="0.2"/></radialGradient>
      </defs>
      <rect x="10" y="10" width="180" height="180" rx="28" fill="url(#g1)"/>
      <ellipse cx="100" cy="100" rx="70" ry="45" fill="url(#g2)" stroke="white" stroke-width="3"/>
    </svg>]],
    -- arcs, dashes, caps, CSS classes, star polygon
    [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">
      <style>.ring{fill:none;stroke:#2ecc71;stroke-width:14;stroke-linecap:round} #dash{stroke:#f1c40f;stroke-linecap:butt;stroke-dasharray:12 8}</style>
      <path class="ring" d="M100 20 A80 80 0 1 1 20 100"/>
      <path class="ring" id="dash" d="M20 100 A80 80 0 0 0 100 180"/>
      <path d="M60 140 Q100 60 140 140 T180 140" fill="none" stroke="#e74c3c" stroke-width="5" stroke-linejoin="round"/>
      <polygon points="100,70 118,110 160,112 126,138 138,180 100,156 62,180 74,138 40,112 82,110" fill="#9b59b6" fill-opacity="0.9" stroke="white" stroke-width="2"/>
    </svg>]],
    -- use/symbol, transforms, group opacity, evenodd
    [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">
      <defs><symbol id="pin" viewBox="0 0 24 24"><path d="M12 2C8 2 5 5 5 9c0 5 7 13 7 13s7-8 7-13c0-4-3-7-7-7z" fill="currentColor"/><circle cx="12" cy="9" r="3" fill="white"/></symbol></defs>
      <g transform="translate(100 100) rotate(20)" opacity="0.85">
        <rect x="-70" y="-70" width="140" height="140" fill="#34495e" stroke="#ecf0f1" stroke-width="4"/>
        <path d="M-40 -40 H40 V40 H-40 Z M-20 -20 V20 H20 V-20 Z" fill="#1abc9c" fill-rule="evenodd"/>
      </g>
      <use href="#pin" x="20" y="20" width="48" height="48" color="#e67e22"/>
      <use href="#pin" x="132" y="130" width="48" height="48" color="#3498db"/>
    </svg>]],
    -- Lucide-style icon tinted through currentColor
    [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M12 2 2 7l10 5 10-5-10-5Z"/><path d="m2 17 10 5 10-5"/><path d="m2 12 10 5 10-5"/>
    </svg>]],
}

for i, svg in ipairs(samples) do
    local cell = Instance.new("Frame")
    cell.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
    cell.BorderSizePixel = 0
    cell.LayoutOrder = i
    cell.Parent = grid
    Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 8)
    local t0 = os.clock()
    local ok, err = pcall(SVG.Render, svg, {
        Parent = cell,
        Width = 176, Height = 176,
        Size = UDim2.fromScale(1, 1),
        CurrentColor = i == 4 and Color3.fromRGB(255, 120, 200) or nil,
    })
    print(("[LuaSupportsSVG demo] sample %d: %s (%.1f ms)"):format(i, ok and "ok" or tostring(err), (os.clock() - t0) * 1000))
end

-- Frame fallback (works without EditableImage): pixel-art version of sample 1
local fb = SVG.RenderFrames(samples[1], { Parent = grid, Width = 176, Height = 176, Size = UDim2.fromScale(1, 1), FallbackResolution = 40 })
fb.LayoutOrder = 5

-- Load an SVG from the web and tint it
pcall(function()
    local rocket = SVG.FromURL("https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/rocket.svg")
    local cell = Instance.new("Frame")
    cell.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
    cell.BorderSizePixel = 0
    cell.LayoutOrder = 6
    cell.Parent = grid
    Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 8)
    SVG.Render(rocket, { Parent = cell, Width = 176, Height = 176, Size = UDim2.fromScale(1, 1), CurrentColor = Color3.fromRGB(120, 220, 255) })
end)

-- PNG export
if writefile then
    SVG.SavePNG(samples[3], "LuaSupportsSVG/demo_export.png", 256, 256)
    print("[LuaSupportsSVG demo] saved LuaSupportsSVG/demo_export.png")
end

print("[LuaSupportsSVG demo] capabilities:", game:GetService("HttpService"):JSONEncode(SVG.Supports()))
