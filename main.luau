local LuaSupportsSVG = {}
LuaSupportsSVG.Version = "1.0.0"

LuaSupportsSVG.TriangleAsset = "rbxassetid://319692171"
LuaSupportsSVG.MaxImageSize = 1024

LuaSupportsSVG.DefaultQuality = 4

local floor, ceil, sqrt, abs, min, max = math.floor, math.ceil, math.sqrt, math.abs, math.min, math.max
local sin, cos, atan2, pi = math.sin, math.cos, math.atan2, math.pi
local huge = math.huge


local insert = table.insert

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end


    return v
end

local function trim(s)

    return (s:gsub("^%s+", ""):gsub("%s+$", ""))

end

local function warnf(fmt, ...)
    if LuaSupportsSVG.Silent then return end
    warn(("[LuaSupportsSVG] " .. fmt):format(...))

end

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " " }

local function decodeEntities(s)

    if not s:find("&", 1, true) then return s end
    return (s:gsub("&(#?[%w]+);", function(e)
        if ENTITIES[e] then return ENTITIES[e] end
        if e:sub(1, 1) == "#" then
            local code
            if e:sub(2, 2):lower() == "x" then


                code = tonumber(e:sub(3), 16)
            else

                code = tonumber(e:sub(2))

            end

            if code then
                local ok, ch = pcall(utf8.char, code)
                if ok then return ch end

            end
        end
        return nil
    end))
end

local function stripNamespace(name)

    local short = name:match("^[%w_%-]+:(.+)$")


    return short or name

end

local function parseXML(src)
    local root = { tag = "#document", attrs = {}, children = {} }
    local stack = { root }
    local i, n = 1, #src

    local function pushText(text, raw)
        if text:match("%S") then
            insert(stack[#stack].children, { tag = "#text", text = raw and text or decodeEntities(text), attrs = {}, children = {}, parent = stack[#stack] })

        end
    end

    while i <= n do
        local lt = src:find("<", i, true)

        if not lt then
            pushText(src:sub(i))
            break
        end
        if lt > i then pushText(src:sub(i, lt - 1)) end

        if src:sub(lt, lt + 3) == "<!--" then

            local e = src:find("-->", lt + 4, true)
            i = (e or n) + 3

        elseif src:sub(lt, lt + 8) == "<![CDATA[" then
            local e = src:find("]]>", lt + 9, true)
            pushText(src:sub(lt + 9, (e or (n + 1)) - 1), true)

            i = (e or n) + 3
        elseif src:sub(lt, lt + 1) == "<?" then


            local e = src:find("?>", lt + 2, true)
            i = (e or n) + 2
        elseif src:sub(lt, lt + 1) == "<!" then

            local depth, j = 0, lt + 2
            while j <= n do
                local c = src:sub(j, j)
                if c == "[" then depth += 1
                elseif c == "]" then depth -= 1
                elseif c == ">" and depth <= 0 then break end
                j += 1
            end
            i = j + 1
        elseif src:sub(lt, lt + 1) == "</" then
            local e = src:find(">", lt, true) or n
            local name = src:sub(lt + 2, e - 1):match("^%s*([^%s]+)")

            name = name and stripNamespace(name)
            for k = #stack, 2, -1 do
                if stack[k].tag == name then
                    for _ = #stack, k, -1 do table.remove(stack) end
                    break

                end
            end
            i = e + 1


        else

            local j, quote = lt + 1, nil
            while j <= n do

                local c = src:sub(j, j)

                if quote then


                    if c == quote then quote = nil end
                elseif c == '"' or c == "'" then

                    quote = c

                elseif c == ">" then
                    break
                end

                j += 1
            end
            local inner = src:sub(lt + 1, j - 1)
            local selfClose = inner:sub(-1) == "/"
            if selfClose then inner = inner:sub(1, -2) end
            local name, rest = inner:match("^%s*([^%s/>]+)(.*)$")

            if name then
                local el = { tag = stripNamespace(name), attrs = {}, children = {}, parent = stack[#stack] }
                for key, _, val in rest:gmatch("([%w_:%-%.]+)%s*=%s*([\"'])(.-)%2") do
                    el.attrs[key] = decodeEntities(val)
                end

                insert(stack[#stack].children, el)

                if not selfClose then insert(stack, el) end

            end

            i = j + 1
        end
    end

    return root


end

local function textContent(el)
    local parts = {}
    for _, c in ipairs(el.children) do
        if c.tag == "#text" then insert(parts, c.text) else insert(parts, textContent(c)) end
    end
    return table.concat(parts)
end

local function parseDeclarations(text, into)
    into = into or {}
    for decl in text:gmatch("[^;]+") do


        local k, v = decl:match("^%s*([%w%-]+)%s*:%s*(.-)%s*$")
        if k and v and v ~= "" then
            v = v:gsub("%s*!important%s*$", "")
            into[k:lower()] = v
        end
    end
    return into

end

local function parseStyleSheet(css, rules)
    css = css:gsub("/%*.-%*/", "")

    for selectors, body in css:gmatch("([^{}]+)%{([^}]*)%}") do

        local decls = parseDeclarations(body)

        for sel in selectors:gmatch("[^,]+") do

            sel = trim(sel)
            if sel ~= "" then


                local tag, cls, id = nil, nil, nil


                local specificity = 0

                tag = sel:match("^([%w%-]+)")

                cls = sel:match("%.([%w_%-]+)")
                id = sel:match("#([%w_%-]+)")


                if id then specificity = 100 end
                if cls then specificity += 10 end
                if tag then specificity += 1 end

                if tag or cls or id then

                    insert(rules, { tag = tag, class = cls, id = id, decls = decls, specificity = specificity, order = #rules })
                end
            end

        end
    end
end

local function matchesRule(rule, el)
    if rule.tag and rule.tag ~= el.tag then return false end
    if rule.id and el.attrs.id ~= rule.id then return false end

    if rule.class then

        local classes = el.attrs.class
        if not classes then return false end

        local found = false
        for c in classes:gmatch("[^%s]+") do

            if c == rule.class then found = true break end


        end
        if not found then return false end
    end

    return true
end

local NAMED_COLORS = {


    aliceblue = "f0f8ff", antiquewhite = "faebd7", aqua = "00ffff", aquamarine = "7fffd4", azure = "f0ffff",
    beige = "f5f5dc", bisque = "ffe4c4", black = "000000", blanchedalmond = "ffebcd", blue = "0000ff",
    blueviolet = "8a2be2", brown = "a52a2a", burlywood = "deb887", cadetblue = "5f9ea0", chartreuse = "7fff00",
    chocolate = "d2691e", coral = "ff7f50", cornflowerblue = "6495ed", cornsilk = "fff8dc", crimson = "dc143c",
    cyan = "00ffff", darkblue = "00008b", darkcyan = "008b8b", darkgoldenrod = "b8860b", darkgray = "a9a9a9",

    darkgreen = "006400", darkgrey = "a9a9a9", darkkhaki = "bdb76b", darkmagenta = "8b008b", darkolivegreen = "556b2f",
    darkorange = "ff8c00", darkorchid = "9932cc", darkred = "8b0000", darksalmon = "e9967a", darkseagreen = "8fbc8f",

    darkslateblue = "483d8b", darkslategray = "2f4f4f", darkslategrey = "2f4f4f", darkturquoise = "00ced1",
    darkviolet = "9400d3", deeppink = "ff1493", deepskyblue = "00bfff", dimgray = "696969", dimgrey = "696969",
    dodgerblue = "1e90ff", firebrick = "b22222", floralwhite = "fffaf0", forestgreen = "228b22", fuchsia = "ff00ff",
    gainsboro = "dcdcdc", ghostwhite = "f8f8ff", gold = "ffd700", goldenrod = "daa520", gray = "808080",
    green = "008000", greenyellow = "adff2f", grey = "808080", honeydew = "f0fff0", hotpink = "ff69b4",

    indianred = "cd5c5c", indigo = "4b0082", ivory = "fffff0", khaki = "f0e68c", lavender = "e6e6fa",
    lavenderblush = "fff0f5", lawngreen = "7cfc00", lemonchiffon = "fffacd", lightblue = "add8e6", lightcoral = "f08080",
    lightcyan = "e0ffff", lightgoldenrodyellow = "fafad2", lightgray = "d3d3d3", lightgreen = "90ee90", lightgrey = "d3d3d3",
    lightpink = "ffb6c1", lightsalmon = "ffa07a", lightseagreen = "20b2aa", lightskyblue = "87cefa", lightslategray = "778899",
    lightslategrey = "778899", lightsteelblue = "b0c4de", lightyellow = "ffffe0", lime = "00ff00", limegreen = "32cd32",
    linen = "faf0e6", magenta = "ff00ff", maroon = "800000", mediumaquamarine = "66cdaa", mediumblue = "0000cd",
    mediumorchid = "ba55d3", mediumpurple = "9370db", mediumseagreen = "3cb371", mediumslateblue = "7b68ee",

    mediumspringgreen = "00fa9a", mediumturquoise = "48d1cc", mediumvioletred = "c71585", midnightblue = "191970",
    mintcream = "f5fffa", mistyrose = "ffe4e1", moccasin = "ffe4b5", navajowhite = "ffdead", navy = "000080",
    oldlace = "fdf5e6", olive = "808000", olivedrab = "6b8e23", orange = "ffa500", orangered = "ff4500",


    orchid = "da70d6", palegoldenrod = "eee8aa", palegreen = "98fb98", paleturquoise = "afeeee", palevioletred = "db7093",


    papayawhip = "ffefd5", peachpuff = "ffdab9", peru = "cd853f", pink = "ffc0cb", plum = "dda0dd",

    powderblue = "b0e0e6", purple = "800080", rebeccapurple = "663399", red = "ff0000", rosybrown = "bc8f8f",

    royalblue = "4169e1", saddlebrown = "8b4513", salmon = "fa8072", sandybrown = "f4a460", seagreen = "2e8b57",
    seashell = "fff5ee", sienna = "a0522d", silver = "c0c0c0", skyblue = "87ceeb", slateblue = "6a5acd",
    slategray = "708090", slategrey = "708090", snow = "fffafa", springgreen = "00ff7f", steelblue = "4682b4",
    tan = "d2b48c", teal = "008080", thistle = "d8bfd8", tomato = "ff6347", turquoise = "40e0d0",
    violet = "ee82ee", wheat = "f5deb3", white = "ffffff", whitesmoke = "f5f5f5", yellow = "ffff00", yellowgreen = "9acd32",
}

local function hslToRgb(h, s, l)
    h = (h % 360) / 360
    local function hue2rgb(p, q, t)

        if t < 0 then t += 1 end

        if t > 1 then t -= 1 end

        if t < 1 / 6 then return p + (q - p) * 6 * t end

        if t < 1 / 2 then return q end
        if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
        return p
    end
    if s == 0 then return l, l, l end
    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q

    return hue2rgb(p, q, h + 1 / 3), hue2rgb(p, q, h), hue2rgb(p, q, h - 1 / 3)
end

local function parseColorComponent(v, scale)
    v = trim(v)
    if v:sub(-1) == "%" then
        return clamp(tonumber(v:sub(1, -2)) or 0, 0, 100) / 100
    end

    return clamp((tonumber(v) or 0) / scale, 0, 1)
end

local function parseColor(str, currentColor)
    if str == nil then return nil end
    str = trim(str):lower()
    if str == "" or str == "none" then return nil end
    if str == "transparent" then return 0, 0, 0, 0 end
    if str == "currentcolor" then
        if currentColor then return currentColor[1], currentColor[2], currentColor[3], currentColor[4] end
        return 0, 0, 0, 1

    end

    local url = str:match("^url%(%s*[\"']?#([^\"'%)%s]+)[\"']?%s*%)")

    if url then return { url = url } end

    if str:sub(1, 1) == "#" then
        local hex = str:sub(2)
        if #hex == 3 or #hex == 4 then

            hex = hex:gsub(".", "%0%0")
        end
        if #hex == 6 or #hex == 8 then
            local r = tonumber(hex:sub(1, 2), 16)
            local g = tonumber(hex:sub(3, 4), 16)
            local b = tonumber(hex:sub(5, 6), 16)

            local a = #hex == 8 and tonumber(hex:sub(7, 8), 16) or 255


            if r and g and b and a then
                return r / 255, g / 255, b / 255, a / 255
            end
        end
        return nil
    end

    local fn, args = str:match("^([%a]+)%s*%((.-)%)$")
    if fn then
        local parts = {}

        for p in args:gmatch("[^,%s/]+") do insert(parts, p) end

        if (fn == "rgb" or fn == "rgba") and #parts >= 3 then

            local r = parseColorComponent(parts[1], 255)

            local g = parseColorComponent(parts[2], 255)
            local b = parseColorComponent(parts[3], 255)

            local a = parts[4] and parseColorComponent(parts[4], 1) or 1
            return r, g, b, a

        elseif (fn == "hsl" or fn == "hsla") and #parts >= 3 then
            local h = tonumber((parts[1]:gsub("deg", ""))) or 0
            local s = parseColorComponent(parts[2], 100)
            local l = parseColorComponent(parts[3], 100)
            local a = parts[4] and parseColorComponent(parts[4], 1) or 1
            local r, g, b = hslToRgb(h, s, l)
            return r, g, b, a
        end
    end

    local named = NAMED_COLORS[str]
    if named then
        return tonumber(named:sub(1, 2), 16) / 255, tonumber(named:sub(3, 4), 16) / 255, tonumber(named:sub(5, 6), 16) / 255, 1


    end
    return nil

end

local UNIT_SCALE = { px = 1, pt = 4 / 3, pc = 16, mm = 96 / 25.4, cm = 96 / 2.54, ["in"] = 96, em = 16, ex = 8, rem = 16 }

local function parseLength(str, reference, default)


    if str == nil then return default end
    if type(str) == "number" then return str end

    str = trim(str)
    local num, unit = str:match("^([%+%-]?%d*%.?%d+[eE]?[%+%-]?%d*)%s*(%%?%a*)$")
    local v = tonumber(num)
    if not v then return default end
    if unit == "%" then
        return v / 100 * (reference or 100)
    end
    return v * (UNIT_SCALE[unit] or 1)

end

local function parseNumberList(str)
    local out = {}

    if not str then return out end

    for num in str:gmatch("[%+%-]?%d*%.?%d+[eE]?[%+%-]?%d*") do
        insert(out, tonumber(num))
    end
    return out
end

local Matrix = {}

function Matrix.identity()
    return { 1, 0, 0, 1, 0, 0 }
end

function Matrix.mul(m, n)
    return {
        m[1] * n[1] + m[3] * n[2],
        m[2] * n[1] + m[4] * n[2],
        m[1] * n[3] + m[3] * n[4],
        m[2] * n[3] + m[4] * n[4],
        m[1] * n[5] + m[3] * n[6] + m[5],
        m[2] * n[5] + m[4] * n[6] + m[6],
    }
end

function Matrix.apply(m, x, y)
    return m[1] * x + m[3] * y + m[5], m[2] * x + m[4] * y + m[6]
end

function Matrix.inverse(m)

    local det = m[1] * m[4] - m[2] * m[3]
    if abs(det) < 1e-12 then return nil end
    return {
        m[4] / det, -m[2] / det, -m[3] / det, m[1] / det,

        (m[3] * m[6] - m[4] * m[5]) / det,

        (m[2] * m[5] - m[1] * m[6]) / det,
    }

end

function Matrix.translate(tx, ty) return { 1, 0, 0, 1, tx, ty or 0 } end

function Matrix.scale(sx, sy) return { sx, 0, 0, sy or sx, 0, 0 } end

function Matrix.rotate(deg, cx, cy)
    local r = deg * pi / 180
    local c, s = cos(r), sin(r)
    local m = { c, s, -s, c, 0, 0 }

    if cx then
        m = Matrix.mul(Matrix.translate(cx, cy or 0), Matrix.mul(m, Matrix.translate(-cx, -(cy or 0))))
    end

    return m
end
function Matrix.skewX(deg) return { 1, 0, math.tan(deg * pi / 180), 1, 0, 0 } end

function Matrix.skewY(deg) return { 1, math.tan(deg * pi / 180), 0, 1, 0, 0 } end

function Matrix.scaleFactor(m)
    return sqrt(abs(m[1] * m[4] - m[2] * m[3]))
end

local function parseTransform(str)
    local m = Matrix.identity()
    if not str then return m end
    for name, args in str:gmatch("([%a]+)%s*%(([^%)]*)%)") do

        local v = parseNumberList(args)
        local t
        name = name:lower()
        if name == "matrix" and #v >= 6 then

            t = { v[1], v[2], v[3], v[4], v[5], v[6] }
        elseif name == "translate" then
            t = Matrix.translate(v[1] or 0, v[2] or 0)


        elseif name == "scale" then
            t = Matrix.scale(v[1] or 1, v[2] or v[1] or 1)
        elseif name == "rotate" then


            t = Matrix.rotate(v[1] or 0, v[2], v[3])
        elseif name == "skewx" then
            t = Matrix.skewX(v[1] or 0)
        elseif name == "skewy" then

            t = Matrix.skewY(v[1] or 0)
        end
        if t then m = Matrix.mul(m, t) end
    end

    return m

end

local Path = {}

local function tokenizePath(d)


    local tokens = {}
    local i, n = 1, #d

    while i <= n do

        local c = d:sub(i, i)
        if c:match("[%a]") and c ~= "e" and c ~= "E" then
            insert(tokens, c)
            i += 1

        elseif c:match("[%d%.%-%+]") then

            local s, e = d:find("^[%+%-]?%d*%.?%d*", i)

            local numStr = d:sub(s, e)
            local j = e + 1
            local ex = d:match("^[eE][%+%-]?%d+", j)
            if ex then numStr ..= ex; j += #ex end

            local v = tonumber(numStr)


            if v then insert(tokens, v) end
            if j <= i then j = i + 1 end
            i = j

        else
            i += 1
        end
    end

    return tokens
end

local function arcToCubics(segs, x1, y1, rx, ry, phiDeg, largeArc, sweep, x2, y2)

    if x1 == x2 and y1 == y2 then return end
    rx, ry = abs(rx), abs(ry)
    if rx == 0 or ry == 0 then
        insert(segs, { "L", x2, y2 })
        return
    end

    local phi = phiDeg * pi / 180

    local cphi, sphi = cos(phi), sin(phi)
    local dx, dy = (x1 - x2) / 2, (y1 - y2) / 2

    local x1p = cphi * dx + sphi * dy

    local y1p = -sphi * dx + cphi * dy

    local lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)


    if lambda > 1 then

        local s = sqrt(lambda)
        rx, ry = rx * s, ry * s
    end
    local rx2, ry2 = rx * rx, ry * ry

    local num = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p
    local den = rx2 * y1p * y1p + ry2 * x1p * x1p

    local coef = (den == 0) and 0 or sqrt(max(0, num / den))
    if largeArc == sweep then coef = -coef end


    local cxp = coef * (rx * y1p / ry)

    local cyp = coef * -(ry * x1p / rx)


    local cx = cphi * cxp - sphi * cyp + (x1 + x2) / 2
    local cy = sphi * cxp + cphi * cyp + (y1 + y2) / 2

    local function angle(ux, uy, vx, vy)
        local dot = ux * vx + uy * vy

        local len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
        local a = math.acos(clamp(dot / len, -1, 1))
        if ux * vy - uy * vx < 0 then a = -a end

        return a
    end
    local theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    local dtheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dtheta > 0 then dtheta -= 2 * pi
    elseif sweep and dtheta < 0 then dtheta += 2 * pi end

    local nSegs = max(1, ceil(abs(dtheta) / (pi / 2) - 1e-9))
    local delta = dtheta / nSegs
    local t = 4 / 3 * math.tan(delta / 4)
    local th = theta1
    for _ = 1, nSegs do
        local c1, s1 = cos(th), sin(th)
        local c2, s2 = cos(th + delta), sin(th + delta)

        local p1x, p1y = c1 - t * s1, s1 + t * c1
        local p2x, p2y = c2 + t * s2, s2 - t * c2
        local function map(px, py)
            px, py = px * rx, py * ry


            return cphi * px - sphi * py + cx, sphi * px + cphi * py + cy

        end

        local ax, ay = map(p1x, p1y)
        local bx, by = map(p2x, p2y)

        local ex, ey = map(c2, s2)

        insert(segs, { "C", ax, ay, bx, by, ex, ey })

        th += delta
    end

    local last = segs[#segs]
    last[6], last[7] = x2, y2
end

function Path.parse(d)

    local segs = {}

    if not d then return segs end

    local tokens = tokenizePath(d)
    local i, n = 1, #tokens

    local cmd = nil
    local cx, cy = 0, 0

    local sx, sy = 0, 0
    local lcx, lcy = nil, nil
    local lqx, lqy = nil, nil

    local function num()
        local v = tokens[i]

        if type(v) ~= "number" then return nil end
        i += 1
        return v
    end

    while i <= n do


        local tok = tokens[i]
        if type(tok) == "string" then
            cmd = tok
            i += 1

        elseif cmd == nil then
            i += 1


        end

        if cmd == nil then continue end

        local rel = cmd:lower() == cmd and cmd ~= "Z" and cmd ~= "z"
        local C = cmd:upper()


        local prevI = i

        if C == "M" then


            local x, y = num(), num()
            if x == nil or y == nil then break end

            if rel then x += cx; y += cy end
            cx, cy = x, y
            sx, sy = x, y
            insert(segs, { "M", x, y })
            cmd = rel and "l" or "L"
            lcx, lqx = nil, nil
        elseif C == "L" then
            local x, y = num(), num()
            if x == nil or y == nil then break end
            if rel then x += cx; y += cy end

            cx, cy = x, y
            insert(segs, { "L", x, y })
            lcx, lqx = nil, nil


        elseif C == "H" then
            local x = num()
            if x == nil then break end
            if rel then x += cx end
            cx = x
            insert(segs, { "L", cx, cy })

            lcx, lqx = nil, nil
        elseif C == "V" then
            local y = num()
            if y == nil then break end
            if rel then y += cy end
            cy = y
            insert(segs, { "L", cx, cy })
            lcx, lqx = nil, nil
        elseif C == "C" then
            local x1, y1, x2, y2, x, y = num(), num(), num(), num(), num(), num()

            if y == nil then break end


            if rel then x1 += cx; y1 += cy; x2 += cx; y2 += cy; x += cx; y += cy end

            insert(segs, { "C", x1, y1, x2, y2, x, y })
            lcx, lcy = x2, y2

            lqx = nil
            cx, cy = x, y
        elseif C == "S" then
            local x2, y2, x, y = num(), num(), num(), num()
            if y == nil then break end
            if rel then x2 += cx; y2 += cy; x += cx; y += cy end
            local x1, y1 = cx, cy


            if lcx then x1, y1 = 2 * cx - lcx, 2 * cy - lcy end
            insert(segs, { "C", x1, y1, x2, y2, x, y })
            lcx, lcy = x2, y2
            lqx = nil
            cx, cy = x, y
        elseif C == "Q" then

            local qx, qy, x, y = num(), num(), num(), num()
            if y == nil then break end

            if rel then qx += cx; qy += cy; x += cx; y += cy end

            insert(segs, { "C", cx + 2 / 3 * (qx - cx), cy + 2 / 3 * (qy - cy), x + 2 / 3 * (qx - x), y + 2 / 3 * (qy - y), x, y })

            lqx, lqy = qx, qy
            lcx = nil

            cx, cy = x, y
        elseif C == "T" then
            local x, y = num(), num()
            if y == nil then break end
            if rel then x += cx; y += cy end
            local qx, qy = cx, cy
            if lqx then qx, qy = 2 * cx - lqx, 2 * cy - lqy end
            insert(segs, { "C", cx + 2 / 3 * (qx - cx), cy + 2 / 3 * (qy - cy), x + 2 / 3 * (qx - x), y + 2 / 3 * (qy - y), x, y })
            lqx, lqy = qx, qy
            lcx = nil

            cx, cy = x, y

        elseif C == "A" then

            local rx, ry, rot, la, sw, x, y = num(), num(), num(), num(), num(), num(), num()
            if y == nil then break end
            if rel then x += cx; y += cy end
            arcToCubics(segs, cx, cy, rx, ry, rot, la ~= 0, sw ~= 0, x, y)


            cx, cy = x, y

            lcx, lqx = nil, nil

        elseif C == "Z" then
            insert(segs, { "Z" })
            cx, cy = sx, sy
            lcx, lqx = nil, nil

            if type(tokens[i]) == "number" then cmd = nil end

        else
            i += 1
        end
        if i == prevI and C ~= "Z" then i += 1 end

    end
    return segs

end

function Path.rect(x, y, w, h, rx, ry)
    if w <= 0 or h <= 0 then return {} end
    rx = rx or 0; ry = ry or rx


    if rx == 0 and ry > 0 then rx = ry end
    if ry == 0 and rx > 0 then ry = rx end
    rx = min(rx, w / 2); ry = min(ry, h / 2)
    if rx <= 0 or ry <= 0 then
        return { { "M", x, y }, { "L", x + w, y }, { "L", x + w, y + h }, { "L", x, y + h }, { "Z" } }

    end

    local k = 0.5522847498
    local segs = {}

    insert(segs, { "M", x + rx, y })
    insert(segs, { "L", x + w - rx, y })

    insert(segs, { "C", x + w - rx + rx * k, y, x + w, y + ry - ry * k, x + w, y + ry })
    insert(segs, { "L", x + w, y + h - ry })
    insert(segs, { "C", x + w, y + h - ry + ry * k, x + w - rx + rx * k, y + h, x + w - rx, y + h })

    insert(segs, { "L", x + rx, y + h })
    insert(segs, { "C", x + rx - rx * k, y + h, x, y + h - ry + ry * k, x, y + h - ry })
    insert(segs, { "L", x, y + ry })
    insert(segs, { "C", x, y + ry - ry * k, x + rx - rx * k, y, x + rx, y })
    insert(segs, { "Z" })

    return segs
end

function Path.ellipse(cx, cy, rx, ry)
    if rx <= 0 or ry <= 0 then return {} end


    local k = 0.5522847498


    return {
        { "M", cx + rx, cy },
        { "C", cx + rx, cy + ry * k, cx + rx * k, cy + ry, cx, cy + ry },
        { "C", cx - rx * k, cy + ry, cx - rx, cy + ry * k, cx - rx, cy },

        { "C", cx - rx, cy - ry * k, cx - rx * k, cy - ry, cx, cy - ry },
        { "C", cx + rx * k, cy - ry, cx + rx, cy - ry * k, cx + rx, cy },
        { "Z" },
    }


end

function Path.polyline(points, close)
    local segs = {}
    for i = 1, #points - 1, 2 do

        insert(segs, { i == 1 and "M" or "L", points[i], points[i + 1] })
    end
    if close and #segs > 0 then insert(segs, { "Z" }) end
    return segs

end

function Path.bounds(segs)
    local x0, y0, x1, y1 = huge, huge, -huge, -huge
    for _, s in ipairs(segs) do
        for i = 2, #s, 2 do
            local x, y = s[i], s[i + 1]
            if x < x0 then x0 = x end
            if y < y0 then y0 = y end

            if x > x1 then x1 = x end


            if y > y1 then y1 = y end

        end
    end

    if x0 == huge then return nil end
    return x0, y0, x1, y1

end

function Path.flatten(segs, m, tolerance)

    tolerance = tolerance or 0.25
    local polys = {}

    local cur = nil
    local cx, cy = 0, 0

    local function startPoly(x, y)
        cur = { points = { x, y }, closed = false }
        insert(polys, cur)
    end

    for _, s in ipairs(segs) do
        local c = s[1]
        if c == "M" then
            local x, y = Matrix.apply(m, s[2], s[3])
            startPoly(x, y)
            cx, cy = x, y


        elseif c == "L" then
            local x, y = Matrix.apply(m, s[2], s[3])
            if not cur then startPoly(cx, cy) end
            local pts = cur.points
            pts[#pts + 1] = x; pts[#pts + 1] = y

            cx, cy = x, y


        elseif c == "C" then
            local x1, y1 = Matrix.apply(m, s[2], s[3])

            local x2, y2 = Matrix.apply(m, s[4], s[5])
            local x3, y3 = Matrix.apply(m, s[6], s[7])
            if not cur then startPoly(cx, cy) end

            local pts = cur.points
            local dd = sqrt((x1 - cx) ^ 2 + (y1 - cy) ^ 2) + sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) + sqrt((x3 - x2) ^ 2 + (y3 - y2) ^ 2)
            local nSeg = clamp(ceil(sqrt(dd / tolerance * 0.3)), 1, 200)

            for k = 1, nSeg do
                local t = k / nSeg
                local mt = 1 - t
                local a, b, cc, d = mt * mt * mt, 3 * mt * mt * t, 3 * mt * t * t, t * t * t
                pts[#pts + 1] = a * cx + b * x1 + cc * x2 + d * x3

                pts[#pts + 1] = a * cy + b * y1 + cc * y2 + d * y3

            end

            cx, cy = x3, y3
        elseif c == "Z" then
            if cur then

                cur.closed = true
                cx, cy = cur.points[1], cur.points[2]
                cur = nil
            end

        end

    end

    return polys
end

local Geometry = {}

local function signedArea(pts)

    local a = 0

    local n = #pts

    for i = 1, n - 1, 2 do
        local j = i + 2
        if j > n then j = 1 end
        local x1, y1 = pts[i], pts[i + 1]
        local x2, y2 = pts[j], pts[j + 1]
        a += x1 * y2 - x2 * y1
    end
    return a / 2
end

local function orient(pts)

    if signedArea(pts) < 0 then

        local n = #pts
        local out = table.create(n)

        for i = n - 1, 1, -2 do
            out[#out + 1] = pts[i]
            out[#out + 1] = pts[i + 1]
        end

        return out

    end

    return pts
end

local function circlePoly(cx, cy, r)
    local n = clamp(ceil(r * 2.5), 8, 64)
    local pts = table.create(n * 2)
    for k = 0, n - 1 do
        local a = k / n * 2 * pi


        pts[#pts + 1] = cx + cos(a) * r


        pts[#pts + 1] = cy + sin(a) * r
    end
    return pts
end

function Geometry.dash(poly, pattern, offset)
    local total = 0


    for _, v in ipairs(pattern) do total += v end
    if total <= 0 then return { poly } end
    local pts = poly.points
    if poly.closed then
        pts = table.clone(pts)
        pts[#pts + 1] = pts[1]

        pts[#pts + 1] = pts[2]

    end

    local out = {}
    local idx, remaining, on = 1, pattern[1], true

    local off = (offset or 0) % total
    while off > 0 do
        if off >= remaining then
            off -= remaining
            idx = idx % #pattern + 1
            remaining = pattern[idx]
            on = not on
        else


            remaining -= off
            off = 0

        end
    end
    local cur = on and { points = { pts[1], pts[2] }, closed = false } or nil
    for i = 1, #pts - 3, 2 do

        local x1, y1, x2, y2 = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]

        local segLen = sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        local pos = 0
        while segLen - pos > remaining do

            pos += remaining

            local t = pos / segLen
            local px, py = x1 + (x2 - x1) * t, y1 + (y2 - y1) * t
            if on then
                cur.points[#cur.points + 1] = px

                cur.points[#cur.points + 1] = py
                insert(out, cur)


                cur = nil
            else
                cur = { points = { px, py }, closed = false }
            end
            on = not on
            idx = idx % #pattern + 1
            remaining = pattern[idx]

            if remaining <= 0 then remaining = 0.0001 end

        end
        remaining -= (segLen - pos)
        if on and cur then
            cur.points[#cur.points + 1] = x2


            cur.points[#cur.points + 1] = y2
        end
    end
    if cur and #cur.points >= 4 then insert(out, cur) end

    return out
end

function Geometry.strokePolygons(poly, width, cap, join, miterLimit, out)
    out = out or {}

    local hw = width / 2


    local pts = poly.points

    local clean = { pts[1], pts[2] }
    for i = 3, #pts - 1, 2 do
        local lx, ly = clean[#clean - 1], clean[#clean]
        if abs(pts[i] - lx) > 1e-6 or abs(pts[i + 1] - ly) > 1e-6 then

            clean[#clean + 1] = pts[i]
            clean[#clean + 1] = pts[i + 1]
        end
    end

    local closed = poly.closed
    if closed and #clean >= 4 and abs(clean[1] - clean[#clean - 1]) < 1e-6 and abs(clean[2] - clean[#clean]) < 1e-6 then
        clean[#clean] = nil; clean[#clean] = nil
    end

    local n = #clean / 2

    if n == 1 then
        if cap == "round" then

            insert(out, circlePoly(clean[1], clean[2], hw))
        elseif cap == "square" then
            local x, y = clean[1], clean[2]

            insert(out, { x - hw, y - hw, x + hw, y - hw, x + hw, y + hw, x - hw, y + hw })

        end
        return out
    end
    if closed and n < 3 then closed = false end

    local segCount = closed and n or (n - 1)

    for s = 1, segCount do
        local i = (s - 1) * 2 + 1

        local j = (s % n) * 2 + 1
        local x1, y1, x2, y2 = clean[i], clean[i + 1], clean[j], clean[j + 1]

        local dx, dy = x2 - x1, y2 - y1


        local len = sqrt(dx * dx + dy * dy)

        if len > 0 then
            local nx, ny = -dy / len * hw, dx / len * hw
            local ex, ey = 0, 0
            if not closed and cap == "square" then
                ex, ey = dx / len * hw, dy / len * hw
            end
            local sx1, sy1, sx2, sy2 = x1, y1, x2, y2
            if not closed and cap == "square" then

                if s == 1 then sx1, sy1 = x1 - ex, y1 - ey end
                if s == segCount then sx2, sy2 = x2 + ex, y2 + ey end
            end


            insert(out, orient({ sx1 + nx, sy1 + ny, sx2 + nx, sy2 + ny, sx2 - nx, sy2 - ny, sx1 - nx, sy1 - ny }))
        end
    end

    local firstJoin = closed and 1 or 2
    local lastJoin = closed and n or (n - 1)
    for v = firstJoin, lastJoin do

        local pi_ = ((v - 2) % n) * 2 + 1


        local ci = (v - 1) * 2 + 1

        local ni = (v % n) * 2 + 1
        local px, py = clean[pi_], clean[pi_ + 1]
        local x, y = clean[ci], clean[ci + 1]

        local nx_, ny_ = clean[ni], clean[ni + 1]
        local d1x, d1y = x - px, y - py

        local d2x, d2y = nx_ - x, ny_ - y
        local l1, l2 = sqrt(d1x * d1x + d1y * d1y), sqrt(d2x * d2x + d2y * d2y)
        if l1 > 0 and l2 > 0 then
            if join == "round" then
                insert(out, circlePoly(x, y, hw))


            else
                d1x, d1y, d2x, d2y = d1x / l1, d1y / l1, d2x / l2, d2y / l2
                local cross = d1x * d2y - d1y * d2x
                if abs(cross) > 1e-6 then

                    local sgn = cross > 0 and -1 or 1

                    local n1x, n1y = -d1y * hw * sgn, d1x * hw * sgn
                    local n2x, n2y = -d2y * hw * sgn, d2x * hw * sgn
                    local ax, ay = x + n1x, y + n1y


                    local bx, by = x + n2x, y + n2y
                    local added = false
                    if join == "miter" then
                        local cosTheta = d1x * d2x + d1y * d2y


                        local theta = math.acos(clamp(cosTheta, -1, 1))


                        local halfInner = (pi - theta) / 2

                        local miterLen = 1 / max(sin(halfInner), 1e-6)
                        if miterLen <= (miterLimit or 4) then

                            local mx, my = (n1x + n2x), (n1y + n2y)

                            local ml = sqrt(mx * mx + my * my)
                            if ml > 1e-9 then
                                local d = hw * miterLen
                                mx, my = x + mx / ml * d, y + my / ml * d

                                insert(out, orient({ x, y, ax, ay, mx, my, bx, by }))
                                added = true
                            end

                        end
                    end
                    if not added then

                        insert(out, orient({ x, y, ax, ay, bx, by }))


                    end
                end
            end
        end
    end

    if not closed and cap == "round" then


        insert(out, circlePoly(clean[1], clean[2], hw))

        insert(out, circlePoly(clean[#clean - 1], clean[#clean], hw))
    end
    return out
end

local Raster = {}
Raster.__index = Raster

function Raster.new(w, h)

    local self = setmetatable({}, Raster)
    self.width, self.height = w, h
    self.buf = buffer.create(w * h * 4)
    return self

end

function Raster:clear(r, g, b, a)
    local buf = self.buf
    if not r or a == 0 then
        buffer.fill(buf, 0, 0)
        return
    end
    local R, G, B, A = floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5), floor((a or 1) * 255 + 0.5)
    for i = 0, self.width * self.height - 1 do
        local o = i * 4
        buffer.writeu8(buf, o, R); buffer.writeu8(buf, o + 1, G)

        buffer.writeu8(buf, o + 2, B); buffer.writeu8(buf, o + 3, A)

    end
end

local function blendPixel(buf, o, r, g, b, a)

    if a <= 0 then return end

    if a > 1 then a = 1 end


    local da = buffer.readu8(buf, o + 3) / 255
    if da <= 0 or a >= 0.999 then
        buffer.writeu8(buf, o, floor(r * 255 + 0.5))
        buffer.writeu8(buf, o + 1, floor(g * 255 + 0.5))
        buffer.writeu8(buf, o + 2, floor(b * 255 + 0.5))
        buffer.writeu8(buf, o + 3, floor(a * 255 + 0.5))

        return

    end

    local dr, dg, db = buffer.readu8(buf, o) / 255, buffer.readu8(buf, o + 1) / 255, buffer.readu8(buf, o + 2) / 255
    local oa = a + da * (1 - a)
    local w = da * (1 - a)
    buffer.writeu8(buf, o, floor((r * a + dr * w) / oa * 255 + 0.5))

    buffer.writeu8(buf, o + 1, floor((g * a + dg * w) / oa * 255 + 0.5))
    buffer.writeu8(buf, o + 2, floor((b * a + db * w) / oa * 255 + 0.5))
    buffer.writeu8(buf, o + 3, floor(oa * 255 + 0.5))
end

function Raster:compositeLayer(layer, opacity)
    local src, dst = layer.buf, self.buf
    for i = 0, self.width * self.height - 1 do
        local o = i * 4

        local a = buffer.readu8(src, o + 3)
        if a > 0 then

            blendPixel(dst, o, buffer.readu8(src, o) / 255, buffer.readu8(src, o + 1) / 255, buffer.readu8(src, o + 2) / 255, a / 255 * opacity)
        end
    end
end

function Raster:fillPolygons(polys, paint, fillRule, quality)

    local S = clamp(quality or LuaSupportsSVG.DefaultQuality, 1, 16)

    local w, h = self.width, self.height

    local buf = self.buf

    local evenOdd = fillRule == "evenodd"

    local edges = {}
    local minY, maxY = huge, -huge
    for _, pts in ipairs(polys) do
        local n = #pts
        if n >= 6 then
            for i = 1, n - 1, 2 do
                local j = i + 2

                if j > n then j = 1 end
                local x1, y1, x2, y2 = pts[i], pts[i + 1], pts[j], pts[j + 1]
                if y1 ~= y2 and y1 == y1 and y2 == y2 then
                    local dir = 1

                    if y1 > y2 then
                        x1, y1, x2, y2 = x2, y2, x1, y1
                        dir = -1
                    end
                    edges[#edges + 1] = { y1, y2, x1, (x2 - x1) / (y2 - y1), dir }


                    if y1 < minY then minY = y1 end

                    if y2 > maxY then maxY = y2 end

                end

            end
        end
    end
    if #edges == 0 then return end
    table.sort(edges, function(a, b) return a[1] < b[1] end)

    local shader = paint.shader
    local pr, pg, pb, pa = paint[1], paint[2], paint[3], paint[4] or 1
    local invS = 1 / S

    local rowStart = max(0, floor(minY))

    local rowEnd = min(h - 1, ceil(maxY))
    local cov = table.create(w + 2, 0)
    local active = {}

    local nextEdge = 1
    local xs = {}

    for py = rowStart, rowEnd do
        local touchedMin, touchedMax = huge, -huge

        for s = 0, S - 1 do
            local sy = py + (s + 0.5) * invS

            while nextEdge <= #edges and edges[nextEdge][1] <= sy do

                active[#active + 1] = edges[nextEdge]

                nextEdge += 1

            end

            local nx = 0
            local k = 1
            while k <= #active do

                local e = active[k]


                if e[2] <= sy then
                    active[k] = active[#active]
                    active[#active] = nil

                else
                    if e[1] <= sy then

                        nx += 1
                        xs[nx] = { e[3] + (sy - e[1]) * e[4], e[5] }
                    end

                    k += 1

                end
            end
            if nx >= 2 then

                for a = 2, nx do
                    local v = xs[a]

                    local b = a - 1

                    while b >= 1 and xs[b][1] > v[1] do
                        xs[b + 1] = xs[b]
                        b -= 1

                    end
                    xs[b + 1] = v
                end
                local wind = 0
                for a = 1, nx - 1 do
                    if evenOdd then wind = (wind + 1) % 2 else wind += xs[a][2] end
                    if wind ~= 0 then
                        local xa, xb = xs[a][1], xs[a + 1][1]
                        if xa < 0 then xa = 0 end
                        if xb > w then xb = w end

                        if xb > xa then
                            local ia, ib = floor(xa), floor(xb)

                            if ia < touchedMin then touchedMin = ia end


                            if ib > touchedMax then touchedMax = ib end
                            if ia == ib then
                                cov[ia + 1] += (xb - xa) * invS
                            else
                                cov[ia + 1] += (ia + 1 - xa) * invS
                                for px = ia + 1, ib - 1 do
                                    cov[px + 1] += invS

                                end


                                if ib < w then cov[ib + 1] += (xb - ib) * invS end
                            end
                        end
                    end

                end
            end
        end
        if touchedMin ~= huge then

            if touchedMax > w - 1 then touchedMax = w - 1 end

            local rowOff = py * w * 4
            for px = touchedMin, touchedMax do
                local c = cov[px + 1]

                if c > 0.0005 then
                    if c > 1 then c = 1 end
                    if shader then
                        local r, g, b, a = shader(px + 0.5, py + 0.5)

                        if a and a > 0 then

                            blendPixel(buf, rowOff + px * 4, r, g, b, c * a * pa)
                        end
                    else
                        blendPixel(buf, rowOff + px * 4, pr, pg, pb, c * pa)


                    end
                end
                cov[px + 1] = 0
            end
        end
    end

end

local INHERITED = {
    fill = true, ["fill-opacity"] = true, ["fill-rule"] = true,

    stroke = true, ["stroke-width"] = true, ["stroke-opacity"] = true,
    ["stroke-linecap"] = true, ["stroke-linejoin"] = true, ["stroke-miterlimit"] = true,
    ["stroke-dasharray"] = true, ["stroke-dashoffset"] = true,
    color = true, visibility = true,

}

local PRESENTATION = {
    "fill", "fill-opacity", "fill-rule", "stroke", "stroke-width", "stroke-opacity",
    "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "stroke-dasharray",
    "stroke-dashoffset", "color", "opacity", "visibility", "display",

    "stop-color", "stop-opacity", "transform",

}

local function computeStyle(el, parentStyle, rules)
    local style = {}
    for k, v in pairs(parentStyle) do


        if INHERITED[k] then style[k] = v end
    end
    local own = {}


    for _, k in ipairs(PRESENTATION) do
        local v = el.attrs[k]

        if v ~= nil then own[k] = v end
    end
    if rules and #rules > 0 then
        local matched = {}
        for _, rule in ipairs(rules) do
            if matchesRule(rule, el) then insert(matched, rule) end
        end
        table.sort(matched, function(a, b)
            if a.specificity ~= b.specificity then return a.specificity < b.specificity end
            return a.order < b.order
        end)


        for _, rule in ipairs(matched) do
            for k, v in pairs(rule.decls) do own[k] = v end
        end

    end
    if el.attrs.style then parseDeclarations(el.attrs.style, own) end
    for k, v in pairs(own) do
        v = trim(v)

        if v == "inherit" then

        else
            style[k] = v

        end

    end
    return style

end

local Renderer = {}
Renderer.__index = Renderer

local function collectIds(el, ids)
    if el.attrs and el.attrs.id then ids[el.attrs.id] = el end


    for _, c in ipairs(el.children) do collectIds(c, ids) end
end

local function collectStyles(el, rules)

    if el.tag == "style" then
        parseStyleSheet(textContent(el), rules)
    end
    for _, c in ipairs(el.children) do collectStyles(c, rules) end


end

local function findRootSvg(doc)
    for _, c in ipairs(doc.children) do
        if c.tag == "svg" then return c end
    end

    for _, c in ipairs(doc.children) do
        local r = findRootSvg(c)
        if r then return r end
    end
    return nil

end

function LuaSupportsSVG.Parse(svgText)
    assert(type(svgText) == "string", "LuaSupportsSVG.Parse expects a string")
    local xml = parseXML(svgText)
    local root = findRootSvg(xml)
    if not root then error("LuaSupportsSVG: no <svg> root element found") end

    local ids, rules = {}, {}
    collectIds(root, ids)
    collectStyles(root, rules)

    local vb = parseNumberList(root.attrs.viewBox)

    local width = parseLength(root.attrs.width, nil, nil)
    local height = parseLength(root.attrs.height, nil, nil)
    local viewBox = (#vb == 4 and vb[3] > 0 and vb[4] > 0) and { vb[1], vb[2], vb[3], vb[4] } or nil

    if root.attrs.width and root.attrs.width:find("%%") then width = nil end
    if root.attrs.height and root.attrs.height:find("%%") then height = nil end

    if not width and not height then
        if viewBox then width, height = viewBox[3], viewBox[4] else width, height = 300, 150 end

    elseif not width then
        width = viewBox and height * viewBox[3] / viewBox[4] or height
    elseif not height then

        height = viewBox and width * viewBox[4] / viewBox[3] or width

    end
    return {
        root = root,


        xml = xml,

        ids = ids,

        rules = rules,
        width = width,
        height = height,
        viewBox = viewBox or { 0, 0, width, height },

        preserveAspectRatio = root.attrs.preserveAspectRatio or "xMidYMid meet",
    }

end

local function viewBoxMatrix(viewBox, par, vpX, vpY, vpW, vpH)
    local vx, vy, vw, vh = viewBox[1], viewBox[2], viewBox[3], viewBox[4]
    par = par or "xMidYMid meet"
    local align, meetOrSlice = par:match("^%s*(%S+)%s*(%S*)")
    local sx, sy = vpW / vw, vpH / vh
    if align ~= "none" then
        local s = (meetOrSlice == "slice") and max(sx, sy) or min(sx, sy)
        sx, sy = s, s

    end
    local tx, ty = vpX - vx * sx, vpY - vy * sy
    if align ~= "none" then
        local extraW, extraH = vpW - vw * sx, vpH - vh * sy
        align = align or "xMidYMid"

        if align:find("xMid") then tx += extraW / 2 elseif align:find("xMax") then tx += extraW end
        if align:find("YMid") then ty += extraH / 2 elseif align:find("YMax") then ty += extraH end
    end
    return { sx, 0, 0, sy, tx, ty }
end

function Renderer.new(doc, raster, options)
    local self = setmetatable({}, Renderer)

    self.doc = doc
    self.raster = raster


    self.options = options or {}
    self.quality = self.options.Quality or LuaSupportsSVG.DefaultQuality

    self.depth = 0
    self.target = raster
    return self
end

local function resolveHref(el)
    return el.attrs.href or el.attrs["xlink:href"]
end

function Renderer:makeGradient(id, bbox, ctm, style)


    local el = self.doc.ids[id]


    if not el or (el.tag ~= "linearGradient" and el.tag ~= "radialGradient") then return nil end

    local chain, seen = {}, {}

    local cur = el
    while cur and not seen[cur] and #chain < 16 do
        seen[cur] = true
        insert(chain, cur)
        local href = resolveHref(cur)

        cur = href and self.doc.ids[href:gsub("^#", "")] or nil

    end
    local function attr(name)


        for _, g in ipairs(chain) do


            if g.attrs[name] ~= nil then return g.attrs[name] end
        end

        return nil
    end

    local stopsEl
    for _, g in ipairs(chain) do
        for _, c in ipairs(g.children) do

            if c.tag == "stop" then stopsEl = g break end
        end
        if stopsEl then break end

    end
    if not stopsEl then return nil end

    local stops = {}

    for _, c in ipairs(stopsEl.children) do

        if c.tag == "stop" then

            local st = computeStyle(c, style, self.doc.rules)
            local off = c.attrs.offset or "0"
            local o = off:find("%%") and (tonumber(off:match("[%d%.]+")) or 0) / 100 or (tonumber(off) or 0)
            local r, g, b, a = parseColor(st["stop-color"] or "black", style.__currentColor)
            if type(r) == "table" then r, g, b, a = 0, 0, 0, 1 end

            if r == nil then r, g, b, a = 0, 0, 0, 0 end


            a = (a or 1) * (tonumber(st["stop-opacity"]) or 1)
            insert(stops, { clamp(o, 0, 1), r, g, b, a })
        end
    end
    if #stops == 0 then return nil end
    for i = 2, #stops do
        if stops[i][1] < stops[i - 1][1] then stops[i][1] = stops[i - 1][1] end
    end

    local units = attr("gradientUnits") or "objectBoundingBox"

    local gtrans = parseTransform(attr("gradientTransform"))
    local spread = attr("spreadMethod") or "pad"

    local toDevice = ctm


    local bx, by, bw, bh = bbox[1], bbox[2], bbox[3] - bbox[1], bbox[4] - bbox[2]
    local ref = 1
    if units == "objectBoundingBox" then

        if bw <= 0 then bw = 1e-6 end


        if bh <= 0 then bh = 1e-6 end
        toDevice = Matrix.mul(ctm, { bw, 0, 0, bh, bx, by })


    else
        ref = nil
    end

    toDevice = Matrix.mul(toDevice, gtrans)

    local inv = Matrix.inverse(toDevice)
    if not inv then return nil end

    local function sample(t)
        if spread == "repeat" then t = t % 1
        elseif spread == "reflect" then t = t % 2; if t > 1 then t = 2 - t end
        else t = clamp(t, 0, 1) end

        if t <= stops[1][1] then local s = stops[1] return s[2], s[3], s[4], s[5] end
        for i = 2, #stops do
            local s1, s2 = stops[i - 1], stops[i]


            if t <= s2[1] then
                local span = s2[1] - s1[1]
                local f = span > 0 and (t - s1[1]) / span or 1
                return s1[2] + (s2[2] - s1[2]) * f, s1[3] + (s2[3] - s1[3]) * f, s1[4] + (s2[4] - s1[4]) * f, s1[5] + (s2[5] - s1[5]) * f


            end
        end
        local s = stops[#stops]
        return s[2], s[3], s[4], s[5]
    end

    local function len(v, default, refLen)
        if v == nil then return default end

        if units == "objectBoundingBox" then

            if v:find("%%") then return (tonumber(v:match("[%d%.%-]+")) or 0) / 100 end

            return tonumber(v) or default


        end
        return parseLength(v, refLen, default)
    end

    if el.tag == "linearGradient" then
        local x1 = len(attr("x1"), 0, self.doc.viewBox[3])
        local y1 = len(attr("y1"), 0, self.doc.viewBox[4])
        local x2 = len(attr("x2"), 1, self.doc.viewBox[3])

        local y2 = len(attr("y2"), 0, self.doc.viewBox[4])
        if units ~= "objectBoundingBox" and attr("x2") == nil then x2 = self.doc.viewBox[3] end
        local dx, dy = x2 - x1, y2 - y1
        local dd = dx * dx + dy * dy
        return function(px, py)

            local ux, uy = Matrix.apply(inv, px, py)
            local t = dd > 0 and ((ux - x1) * dx + (uy - y1) * dy) / dd or 0
            return sample(t)

        end
    else


        local cx = len(attr("cx"), 0.5, self.doc.viewBox[3])

        local cy = len(attr("cy"), 0.5, self.doc.viewBox[4])

        local r = len(attr("r"), 0.5, self.doc.viewBox[3])
        local fx = len(attr("fx"), cx, self.doc.viewBox[3])
        local fy = len(attr("fy"), cy, self.doc.viewBox[4])
        if units ~= "objectBoundingBox" and attr("r") == nil then r = self.doc.viewBox[3] / 2 end
        if r <= 0 then return nil end
        return function(px, py)
            local ux, uy = Matrix.apply(inv, px, py)

            local t
            if fx == cx and fy == cy then
                t = sqrt((ux - cx) ^ 2 + (uy - cy) ^ 2) / r
            else

                local dx, dy = ux - fx, uy - fy
                local ex, ey = fx - cx, fy - cy
                local a = dx * dx + dy * dy
                if a < 1e-12 then
                    t = 0
                else
                    local b = 2 * (dx * ex + dy * ey)
                    local c = ex * ex + ey * ey - r * r
                    local disc = b * b - 4 * a * c
                    local s = disc > 0 and (-b + sqrt(disc)) / (2 * a) or 1
                    t = s > 0 and 1 / s or 1

                end
            end

            return sample(t)
        end

    end


end

function Renderer:resolvePaint(value, opacity, bbox, ctm, style)

    local r, g, b, a = parseColor(value, style.__currentColor)
    if r == nil then return nil end
    if type(r) == "table" then

        local shader = self:makeGradient(r.url, bbox, ctm, style)


        if shader then return { 1, 1, 1, opacity, shader = shader } end

        local fallback = value:match("%)%s*(.+)$")


        if fallback then
            r, g, b, a = parseColor(fallback, style.__currentColor)
            if type(r) == "table" or r == nil then return nil end
        else
            return nil

        end
    end
    return { r, g, b, (a or 1) * opacity }
end

function Renderer:drawPath(segs, style, ctm)
    if #segs == 0 then return end
    local opacity = clamp(tonumber(style.opacity) or 1, 0, 1)

    if opacity <= 0 then return end
    local bbox = { Path.bounds(segs) }
    if not bbox[1] then return end

    local fillValue = style.fill or "black"
    local fillOpacity = clamp(tonumber(style["fill-opacity"]) or 1, 0, 1) * opacity

    local strokeValue = style.stroke or "none"

    local strokeOpacity = clamp(tonumber(style["stroke-opacity"]) or 1, 0, 1) * opacity

    local scale = Matrix.scaleFactor(ctm)


    local strokeWidth = parseLength(style["stroke-width"], self.doc.viewBox[3], 1) * scale

    local polys = Path.flatten(segs, ctm, 0.2)

    local fillPaint = self:resolvePaint(fillValue, fillOpacity, bbox, ctm, style)
    if fillPaint and fillPaint[4] > 0 then
        local fillPolys = {}
        for _, p in ipairs(polys) do
            if #p.points >= 6 then insert(fillPolys, p.points) end
        end

        if #fillPolys > 0 then

            self.target:fillPolygons(fillPolys, fillPaint, style["fill-rule"] or "nonzero", self.quality)

        end
    end

    if strokeWidth > 0 and strokeValue ~= "none" then

        local strokePaint = self:resolvePaint(strokeValue, strokeOpacity, bbox, ctm, style)
        if strokePaint and strokePaint[4] > 0 then
            if strokeWidth < 0.8 then

                strokePaint[4] *= strokeWidth / 0.8


                strokeWidth = 0.8

            end

            local cap = style["stroke-linecap"] or "butt"
            local join = style["stroke-linejoin"] or "miter"
            local miter = tonumber(style["stroke-miterlimit"]) or 4
            local dashes = nil
            local da = style["stroke-dasharray"]
            if da and da ~= "none" then
                dashes = {}
                for _, v in ipairs(parseNumberList(da)) do insert(dashes, v * scale) end


                if #dashes % 2 == 1 then
                    local n = #dashes
                    for i = 1, n do dashes[n + i] = dashes[i] end
                end
                local allZero = true
                for _, v in ipairs(dashes) do if v > 0 then allZero = false end end
                if allZero or #dashes == 0 then dashes = nil end

            end
            local strokePolys = {}

            for _, p in ipairs(polys) do
                if dashes then

                    local offset = parseLength(style["stroke-dashoffset"], nil, 0) * scale


                    for _, piece in ipairs(Geometry.dash(p, dashes, offset)) do

                        Geometry.strokePolygons(piece, strokeWidth, cap, join, miter, strokePolys)
                    end
                else


                    Geometry.strokePolygons(p, strokeWidth, cap, join, miter, strokePolys)
                end
            end
            if #strokePolys > 0 then

                self.target:fillPolygons(strokePolys, strokePaint, "nonzero", self.quality)
            end
        end
    end

end

local SKIP_TAGS = {
    defs = true, style = true, title = true, desc = true, metadata = true,

    linearGradient = true, radialGradient = true, clipPath = true, mask = true,

    pattern = true, filter = true, symbol = true, marker = true, ["#text"] = true,
    script = true, text = true, image = true, foreignObject = true, ["switch"] = false,
}

function Renderer:renderElement(el, parentStyle, parentCtm, extra)

    if SKIP_TAGS[el.tag] then return end
    self.depth += 1

    if self.depth > 64 then self.depth -= 1 return end

    local style = computeStyle(el, parentStyle, self.doc.rules)
    style.__currentColor = parentStyle.__currentColor
    if style.color then
        local r, g, b, a = parseColor(style.color)
        if type(r) == "number" then style.__currentColor = { r, g, b, a } end
    end

    if style.display == "none" or style.visibility == "hidden" or style.visibility == "collapse" then
        self.depth -= 1
        return
    end

    local ctm = Matrix.mul(parentCtm, parseTransform(el.attrs.transform))

    if extra then ctm = Matrix.mul(ctm, extra) end
    local tag = el.tag


    local vbW, vbH = self.doc.viewBox[3], self.doc.viewBox[4]

    local isGroup = tag == "g" or tag == "svg" or tag == "use" or tag == "switch" or tag == "a"

    local groupOpacity = clamp(tonumber(style.opacity) or 1, 0, 1)

    local prevTarget = self.target
    local layer = nil
    if isGroup and groupOpacity < 1 then
        layer = Raster.new(self.raster.width, self.raster.height)
        self.target = layer

        style.opacity = nil
    end
    local childStyle = style
    if isGroup then
        childStyle = table.clone(style)
        childStyle.opacity = nil
    end

    if tag == "g" or tag == "a" then
        for _, c in ipairs(el.children) do self:renderElement(c, childStyle, ctm) end

    elseif tag == "switch" then
        for _, c in ipairs(el.children) do
            if c.tag ~= "#text" then self:renderElement(c, childStyle, ctm) break end
        end

    elseif tag == "svg" then
        local x = parseLength(el.attrs.x, vbW, 0)
        local y = parseLength(el.attrs.y, vbH, 0)
        local w = parseLength(el.attrs.width, vbW, nil)

        local h = parseLength(el.attrs.height, vbH, nil)
        local inner = ctm
        local vb = parseNumberList(el.attrs.viewBox)

        if el ~= self.doc.root then

            if #vb == 4 and vb[3] > 0 and vb[4] > 0 then
                inner = Matrix.mul(ctm, viewBoxMatrix(vb, el.attrs.preserveAspectRatio, x, y, w or vb[3], h or vb[4]))
            else
                inner = Matrix.mul(ctm, Matrix.translate(x, y))

            end

        end

        for _, c in ipairs(el.children) do self:renderElement(c, childStyle, inner) end
    elseif tag == "use" then
        local href = resolveHref(el)

        local target = href and self.doc.ids[href:gsub("^#", "")]
        if target and target ~= el then

            local x = parseLength(el.attrs.x, vbW, 0)
            local y = parseLength(el.attrs.y, vbH, 0)
            local useCtm = Matrix.mul(ctm, Matrix.translate(x, y))

            if target.tag == "symbol" then
                local vb = parseNumberList(target.attrs.viewBox)

                local w = parseLength(el.attrs.width or target.attrs.width, vbW, nil)
                local h = parseLength(el.attrs.height or target.attrs.height, vbH, nil)
                local symCtm = useCtm
                if #vb == 4 and vb[3] > 0 and vb[4] > 0 then
                    symCtm = Matrix.mul(useCtm, viewBoxMatrix(vb, target.attrs.preserveAspectRatio, 0, 0, w or vb[3], h or vb[4]))
                end

                local symStyle = computeStyle(target, childStyle, self.doc.rules)
                symStyle.__currentColor = childStyle.__currentColor

                for _, c in ipairs(target.children) do self:renderElement(c, symStyle, symCtm) end

            else
                self:renderElement(target, childStyle, useCtm)


            end
        end
    elseif tag == "rect" then
        local x = parseLength(el.attrs.x, vbW, 0)
        local y = parseLength(el.attrs.y, vbH, 0)
        local w = parseLength(el.attrs.width, vbW, 0)
        local h = parseLength(el.attrs.height, vbH, 0)

        local rx = parseLength(el.attrs.rx, vbW, nil)
        local ry = parseLength(el.attrs.ry, vbH, nil)
        if rx == nil and ry == nil then rx, ry = 0, 0 end
        self:drawPath(Path.rect(x, y, w, h, rx or ry, ry or rx), style, ctm)
    elseif tag == "circle" then
        local cx = parseLength(el.attrs.cx, vbW, 0)
        local cy = parseLength(el.attrs.cy, vbH, 0)
        local r = parseLength(el.attrs.r, vbW, 0)
        self:drawPath(Path.ellipse(cx, cy, r, r), style, ctm)

    elseif tag == "ellipse" then
        local cx = parseLength(el.attrs.cx, vbW, 0)
        local cy = parseLength(el.attrs.cy, vbH, 0)
        local rx = parseLength(el.attrs.rx, vbW, nil)
        local ry = parseLength(el.attrs.ry, vbH, nil)
        rx = rx or ry or 0; ry = ry or rx
        self:drawPath(Path.ellipse(cx, cy, rx, ry), style, ctm)
    elseif tag == "line" then
        local x1 = parseLength(el.attrs.x1, vbW, 0)
        local y1 = parseLength(el.attrs.y1, vbH, 0)
        local x2 = parseLength(el.attrs.x2, vbW, 0)

        local y2 = parseLength(el.attrs.y2, vbH, 0)
        local s = table.clone(style)
        s.fill = "none"
        self:drawPath({ { "M", x1, y1 }, { "L", x2, y2 } }, s, ctm)
    elseif tag == "polyline" or tag == "polygon" then

        local pts = parseNumberList(el.attrs.points)
        local s = style
        if tag == "polyline" then
            s = table.clone(style)
            s.fill = style.fill or "black"
        end
        self:drawPath(Path.polyline(pts, tag == "polygon"), s, ctm)

    elseif tag == "path" then
        self:drawPath(Path.parse(el.attrs.d), style, ctm)
    end

    if layer then
        self.target = prevTarget
        prevTarget:compositeLayer(layer, groupOpacity)
    end


    self.depth -= 1
end

function LuaSupportsSVG.Rasterize(svg, width, height, options)

    options = options or {}
    local doc = type(svg) == "string" and LuaSupportsSVG.Parse(svg) or svg
    width = floor((width or doc.width) + 0.5)
    height = floor((height or doc.height) + 0.5)

    local maxSize = options.MaxSize or LuaSupportsSVG.MaxImageSize
    if width > maxSize or height > maxSize then
        local s = min(maxSize / width, maxSize / height)
        width, height = max(1, floor(width * s)), max(1, floor(height * s))
    end
    width, height = max(1, width), max(1, height)

    local raster = Raster.new(width, height)
    if options.Background then
        local bg = options.Background
        raster:clear(bg[1], bg[2], bg[3], bg[4] or 1)
    end

    local par = doc.preserveAspectRatio

    if options.Fit == "none" then par = "none"
    elseif options.Fit == "slice" then par = "xMidYMid slice" end
    local base = viewBoxMatrix(doc.viewBox, par, 0, 0, width, height)

    local renderer = Renderer.new(doc, raster, options)
    local rootStyle = { fill = "black", __currentColor = { 0, 0, 0, 1 } }

    renderer:renderElement(doc.root, rootStyle, base)

    raster.doc = doc
    return raster
end

LuaSupportsSVG.Path = Path


LuaSupportsSVG.Matrix = Matrix

LuaSupportsSVG.Raster = Raster
LuaSupportsSVG.ParseColor = parseColor


LuaSupportsSVG.ParseXML = parseXML

local CRC_TABLE = nil
local function buildCrcTable()
    CRC_TABLE = table.create(256)
    for i = 0, 255 do
        local c = i

        for _ = 1, 8 do

            if bit32.band(c, 1) == 1 then
                c = bit32.bxor(0xEDB88320, bit32.rshift(c, 1))
            else
                c = bit32.rshift(c, 1)

            end
        end
        CRC_TABLE[i + 1] = c

    end

end

local function crc32(buf, offset, length)
    if not CRC_TABLE then buildCrcTable() end
    local c = 0xFFFFFFFF
    for i = offset, offset + length - 1 do
        c = bit32.bxor(CRC_TABLE[bit32.band(bit32.bxor(c, buffer.readu8(buf, i)), 0xFF) + 1], bit32.rshift(c, 8))
    end

    return bit32.bxor(c, 0xFFFFFFFF)
end

local function writeU32BE(buf, o, v)
    buffer.writeu8(buf, o, bit32.rshift(v, 24))
    buffer.writeu8(buf, o + 1, bit32.band(bit32.rshift(v, 16), 0xFF))
    buffer.writeu8(buf, o + 2, bit32.band(bit32.rshift(v, 8), 0xFF))
    buffer.writeu8(buf, o + 3, bit32.band(v, 0xFF))
end

function LuaSupportsSVG.EncodePNG(raster)

    local w, h, src = raster.width, raster.height, raster.buf
    local rowLen = 1 + w * 4

    local rawLen = rowLen * h
    local blockCount = max(1, ceil(rawLen / 65535))
    local zlibLen = 2 + rawLen + blockCount * 5 + 4
    local total = 8 + (12 + 13) + (12 + zlibLen) + 12

    local out = buffer.create(total)
    local o = 0

    for _, b in ipairs({ 137, 80, 78, 71, 13, 10, 26, 10 }) do buffer.writeu8(out, o, b) o += 1 end

    writeU32BE(out, o, 13); o += 4

    local ihdrStart = o
    buffer.writestring(out, o, "IHDR"); o += 4

    writeU32BE(out, o, w); o += 4


    writeU32BE(out, o, h); o += 4
    buffer.writeu8(out, o, 8); buffer.writeu8(out, o + 1, 6)

    buffer.writeu8(out, o + 2, 0); buffer.writeu8(out, o + 3, 0); buffer.writeu8(out, o + 4, 0)

    o += 5
    writeU32BE(out, o, crc32(out, ihdrStart, 17)); o += 4

    writeU32BE(out, o, zlibLen); o += 4
    local idatStart = o
    buffer.writestring(out, o, "IDAT"); o += 4
    buffer.writeu8(out, o, 0x78); buffer.writeu8(out, o + 1, 0x01); o += 2

    local a, bsum = 1, 0
    local remaining = rawLen
    local rawPos = 0
    local rowIdx, colIdx = 0, -1
    while remaining > 0 do


        local len = min(65535, remaining)
        remaining -= len
        buffer.writeu8(out, o, remaining == 0 and 1 or 0); o += 1
        buffer.writeu8(out, o, bit32.band(len, 0xFF)); buffer.writeu8(out, o + 1, bit32.rshift(len, 8)); o += 2

        local nlen = bit32.bxor(len, 0xFFFF)
        buffer.writeu8(out, o, bit32.band(nlen, 0xFF)); buffer.writeu8(out, o + 1, bit32.rshift(nlen, 8)); o += 2
        for _ = 1, len do


            local byte


            if colIdx < 0 then
                byte = 0
            else

                byte = buffer.readu8(src, (rowIdx * w) * 4 + colIdx)

            end

            colIdx += 1

            if colIdx >= w * 4 then colIdx = -1; rowIdx += 1 end
            buffer.writeu8(out, o, byte); o += 1
            a = (a + byte) % 65521

            bsum = (bsum + a) % 65521
            rawPos += 1
        end

    end
    writeU32BE(out, o, bit32.bor(bit32.lshift(bsum, 16), a)); o += 4
    writeU32BE(out, o, crc32(out, idatStart, zlibLen + 4)); o += 4

    writeU32BE(out, o, 0); o += 4
    local iendStart = o
    buffer.writestring(out, o, "IEND"); o += 4
    writeU32BE(out, o, crc32(out, iendStart, 4)); o += 4
    return buffer.tostring(out)
end

function LuaSupportsSVG.ToPNG(svg, width, height, options)

    return LuaSupportsSVG.EncodePNG(LuaSupportsSVG.Rasterize(svg, width, height, options))
end

local isRoblox = (typeof ~= nil) and (game ~= nil)

local function toColorTable(c)
    if c == nil then return nil end
    if typeof(c) == "Color3" then return { c.R, c.G, c.B, 1 } end
    if type(c) == "string" then
        local r, g, b, a = parseColor(c)
        if type(r) == "number" then return { r, g, b, a or 1 } end

        return nil

    end

    return c
end

local function pickSize(doc, options)


    local w, h = options.Width, options.Height
    if w and not h then h = w * doc.height / doc.width end

    if h and not w then w = h * doc.width / doc.height end
    if not w then w, h = doc.width, doc.height end
    local scale = options.Scale or 1
    return w * scale, h * scale
end

local function normalizeOptions(doc, options)


    options = options and table.clone(options) or {}
    options.Background = toColorTable(options.Background)
    if options.CurrentColor then
        options.CurrentColor = toColorTable(options.CurrentColor)
    end
    return options
end

local baseRasterize = LuaSupportsSVG.Rasterize
function LuaSupportsSVG.Rasterize(svg, width, height, options)
    options = options or {}

    local doc = type(svg) == "string" and LuaSupportsSVG.Parse(svg) or svg
    if options.CurrentColor then
        local cc = toColorTable(options.CurrentColor)


        if cc then
            doc.root.attrs.color = ("rgba(%d,%d,%d,%s)"):format(floor(cc[1] * 255 + 0.5), floor(cc[2] * 255 + 0.5), floor(cc[3] * 255 + 0.5), tostring(cc[4] or 1))
        end
    end
    return baseRasterize(doc, width, height, options)
end

function LuaSupportsSVG.Supports()
    local caps = { Parse = true, Rasterize = true, PNG = true, EditableImage = false, Drawing = false, Http = false, Files = false }
    if isRoblox then
        caps.EditableImage = pcall(function()


            local img = game:GetService("AssetService"):CreateEditableImage({ Size = Vector2.new(2, 2) })
            local lbl = Instance.new("ImageLabel")
            lbl.ImageContent = Content.fromObject(img)
            lbl:Destroy()
        end)
        caps.Drawing = (Drawing ~= nil) and pcall(function() return Drawing.new ~= nil end)
        caps.Http = (game.HttpGet ~= nil) or pcall(function() return game:GetService("HttpService").HttpEnabled end)
        caps.Files = (readfile ~= nil) and (writefile ~= nil)
    end

    return caps
end

local function httpGet(url)
    if game.HttpGet then
        local ok, res = pcall(game.HttpGet, game, url)
        if ok and res then return res end

    end
    return game:GetService("HttpService"):GetAsync(url)
end

function LuaSupportsSVG.FromURL(url)
    local text = httpGet(url)

    if not text or not text:find("<svg", 1, true) then
        error("LuaSupportsSVG.FromURL: response does not look like SVG: " .. tostring(url))
    end
    return text
end

function LuaSupportsSVG.FromFile(path)
    assert(readfile, "LuaSupportsSVG.FromFile requires readfile (executor environment)")
    return readfile(path)

end

LuaSupportsSVG._images = setmetatable({}, { __mode = "k" })

function LuaSupportsSVG.ToEditableImage(raster)
    local AssetService = game:GetService("AssetService")
    local img = AssetService:CreateEditableImage({ Size = Vector2.new(raster.width, raster.height) })
    img:WritePixelsBuffer(Vector2.zero, Vector2.new(raster.width, raster.height), raster.buf)


    return img
end

local function applyRasterToLabel(label, raster)
    local img = LuaSupportsSVG.ToEditableImage(raster)
    label.ImageContent = Content.fromObject(img)


    LuaSupportsSVG._images[label] = img
    return img


end

function LuaSupportsSVG.RenderFrames(svg, options)

    options = options or {}
    local doc = type(svg) == "string" and LuaSupportsSVG.Parse(svg) or svg
    local opts = normalizeOptions(doc, options)
    local res = opts.FallbackResolution or 48
    local w, h = pickSize(doc, opts)
    local pw, ph
    if w >= h then pw, ph = res, max(1, floor(res * h / w + 0.5)) else ph, pw = res, max(1, floor(res * w / h + 0.5)) end
    opts.Quality = opts.Quality or 2
    local raster = LuaSupportsSVG.Rasterize(doc, pw, ph, opts)

    local container = options.Container or Instance.new("Frame")
    if not options.Container then
        container.Name = options.Name or "SVG"
        container.BackgroundTransparency = 1

        container.Size = options.Size or UDim2.fromOffset(w, h)
        container.Position = options.Position or UDim2.new()
        container.AnchorPoint = options.AnchorPoint or Vector2.zero
    end

    container.ClipsDescendants = false

    local buf = raster.buf

    local count = 0


    for y = 0, ph - 1 do
        local x = 0
        while x < pw do
            local o = (y * pw + x) * 4
            local a = buffer.readu8(buf, o + 3)
            if a < 8 then
                x += 1
            else

                local r, g, b = buffer.readu8(buf, o), buffer.readu8(buf, o + 1), buffer.readu8(buf, o + 2)
                local run = 1
                while x + run < pw do
                    local o2 = (y * pw + x + run) * 4
                    local a2 = buffer.readu8(buf, o2 + 3)
                    if abs(a2 - a) > 12 or abs(buffer.readu8(buf, o2) - r) > 12 or abs(buffer.readu8(buf, o2 + 1) - g) > 12 or abs(buffer.readu8(buf, o2 + 2) - b) > 12 then
                        break


                    end
                    run += 1


                end

                local f = Instance.new("Frame")
                f.BorderSizePixel = 0
                f.BackgroundColor3 = Color3.fromRGB(r, g, b)
                f.BackgroundTransparency = 1 - a / 255
                f.Position = UDim2.fromScale(x / pw, y / ph)


                f.Size = UDim2.fromScale(run / pw, 1 / ph)
                f.Parent = container
                count += 1
                x += run
            end
        end
    end

    container:SetAttribute("LuaSupportsSVG_Frames", count)
    if options.Parent then container.Parent = options.Parent end

    return container, raster

end

function LuaSupportsSVG.Render(svg, options)


    assert(isRoblox, "LuaSupportsSVG.Render requires Roblox; use Rasterize/ToPNG elsewhere")


    options = options or {}
    local doc = type(svg) == "string" and LuaSupportsSVG.Parse(svg) or svg

    local opts = normalizeOptions(doc, options)
    local w, h = pickSize(doc, opts)

    local raster = LuaSupportsSVG.Rasterize(doc, w, h, opts)

    local label = options.Label or Instance.new("ImageLabel")
    label.Name = options.Name or label.Name

    if not options.Label then


        label.Name = options.Name or "SVG"
        label.BackgroundTransparency = 1

        label.BorderSizePixel = 0
        label.Size = options.Size or UDim2.fromOffset(raster.width, raster.height)

        label.Position = options.Position or UDim2.new()


        label.AnchorPoint = options.AnchorPoint or Vector2.zero
        label.ScaleType = options.ScaleType or Enum.ScaleType.Fit
    end

    local ok, err = pcall(applyRasterToLabel, label, raster)
    if not ok then
        if options.Fallback == false then

            error("LuaSupportsSVG: EditableImage unavailable: " .. tostring(err))
        end
        warnf("EditableImage unavailable (%s); using Frame fallback", tostring(err))
        local fb = table.clone(options)
        fb.Container = label

        fb.Parent = nil
        LuaSupportsSVG.RenderFrames(doc, fb)
    end


    label:SetAttribute("LuaSupportsSVG", LuaSupportsSVG.Version)


    if options.Parent then label.Parent = options.Parent end
    return label, raster
end

function LuaSupportsSVG.Update(label, svg, options)

    options = options and table.clone(options) or {}
    options.Label = label
    options.Parent = nil

    for _, c in ipairs(label:GetChildren()) do
        if c:IsA("Frame") and c.Name == "Frame" then c:Destroy() end
    end


    return LuaSupportsSVG.Render(svg, options)
end

function LuaSupportsSVG.RenderDrawing(svg, options)
    assert(Drawing, "LuaSupportsSVG.RenderDrawing requires the Drawing API")
    options = options or {}
    local doc = type(svg) == "string" and LuaSupportsSVG.Parse(svg) or svg

    local opts = normalizeOptions(doc, options)
    local w, h = pickSize(doc, opts)
    local raster = LuaSupportsSVG.Rasterize(doc, w, h, opts)
    local png = LuaSupportsSVG.EncodePNG(raster)
    local img = Drawing.new("Image")
    img.Data = png
    img.Size = options.DisplaySize or Vector2.new(raster.width, raster.height)
    img.Position = options.Position or Vector2.new(0, 0)
    img.Transparency = options.Transparency or 1
    if options.ZIndex then img.ZIndex = options.ZIndex end
    img.Visible = true

    return img, raster

end

function LuaSupportsSVG.SavePNG(svg, path, width, height, options)
    assert(writefile, "LuaSupportsSVG.SavePNG requires writefile (executor environment)")
    writefile(path, LuaSupportsSVG.ToPNG(svg, width, height, options))
    return path
end

function Raster:getPixel(x, y)
    local o = (y * self.width + x) * 4
    return buffer.readu8(self.buf, o), buffer.readu8(self.buf, o + 1), buffer.readu8(self.buf, o + 2), buffer.readu8(self.buf, o + 3)
end

if isRoblox and getgenv then
    getgenv().LuaSupportsSVG = LuaSupportsSVG
end

return LuaSupportsSVG
