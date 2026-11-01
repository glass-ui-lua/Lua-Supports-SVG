# LuaSupportsSVG

SVG support for Lua / Luau. Parses SVG markup, rasterizes it into real anti-aliased RGBA pixels entirely in Luau, and turns the result into real graphics in Roblox: an `ImageLabel` backed by an `EditableImage`, a `Drawing.Image` overlay, a PNG file, or a Frame-based fallback for environments without `EditableImage`.

No external assets, no uploads, no HTTP needed. One file: `LuaSupportsSVG.luau` (~2100 lines).

## Quick start

```lua
local SVG = loadstring(game:HttpGet("https://raw.githubusercontent.com/glass-ui-lua/Lua-Supports-SVG/refs/heads/main/main.luau"))()

local label = SVG.Render([[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <rect x="10" y="10" width="80" height="80" rx="12" fill="#3498db" stroke="black" stroke-width="4"/>
  <circle cx="50" cy="50" r="20" fill="red" fill-opacity="0.8"/>
</svg>]], {
    Parent = someFrame,
    Width = 256, Height = 256,          -- raster resolution
    Size = UDim2.fromOffset(128, 128),  -- on-screen size
})
```

`Render` returns the `ImageLabel` and the `Raster` it was built from.

## API

### Rendering (Roblox)

`SVG.Render(svg, options) -> ImageLabel, Raster`
Rasterizes and shows the SVG in an ImageLabel via EditableImage. Falls back to `RenderFrames` automatically if EditableImage is unavailable (set `Fallback = false` to error instead).

| Option | Type | Meaning |
| --- | --- | --- |
| `Parent` | Instance | Where to parent the label |
| `Width`, `Height` | number | Raster size in pixels (default: the SVG's own size; max 1024) |
| `Scale` | number | Multiply the natural size (use 2 for sharper HiDPI output) |
| `Size`, `Position`, `AnchorPoint` | UDim2 / Vector2 | Normal GUI properties |
| `Name` | string | Label name |
| `Background` | Color3 or CSS color | Opaque background (default transparent) |
| `CurrentColor` | Color3 or CSS color | Value for `currentColor` (tint icon packs like Lucide) |
| `Quality` | 1..16 | Vertical anti-aliasing samples per pixel (default 4) |
| `Fit` | "meet" / "slice" / "none" | Overrides preserveAspectRatio |
| `ScaleType` | Enum.ScaleType | Default Fit |
| `Label` | ImageLabel / ImageButton | Reuse an existing label instead of creating one |

`SVG.Update(label, svg, options)` re-renders into a label made by `Render`.

`SVG.RenderFrames(svg, options) -> Frame, Raster`
Pixel-art approximation built from run-length `Frame`s. Works anywhere (no EditableImage). `FallbackResolution` (default 48) sets the grid.

`SVG.RenderDrawing(svg, options) -> DrawingImage, Raster`
Executor `Drawing.new("Image")` overlay fed with PNG bytes. Options: `Position` (Vector2), `DisplaySize` (Vector2), `Width`/`Height`, `Transparency`, `ZIndex`, plus the raster options above.

`SVG.ToEditableImage(raster) -> EditableImage`

### Rasterizing (works in any Luau with the `buffer` library)

`SVG.Parse(text) -> doc` parsed document: `root`, `ids`, `rules`, `width`, `height`, `viewBox`.

`SVG.Rasterize(svg, width, height, options) -> Raster` where `Raster` has `width`, `height`, `buf` (RGBA8 `buffer`, straight alpha) and `:getPixel(x, y)`.

`SVG.EncodePNG(raster) -> string`, `SVG.ToPNG(svg, w, h, options) -> string`, `SVG.SavePNG(svg, path, w, h, options)` (uses `writefile`).

### Loading

`SVG.FromURL(url)` (uses `game:HttpGet` when available, else HttpService), `SVG.FromFile(path)` (`readfile`).

`SVG.Supports()` returns `{ EditableImage, Drawing, Http, Files, PNG, ... }` booleans for the current environment.

Internals are exposed for advanced use: `SVG.Path` (parse / flatten / bounds), `SVG.Matrix`, `SVG.Raster`, `SVG.ParseColor`, `SVG.ParseXML`.

## Supported SVG

Elements: `svg` (nested too), `g`, `a`, `switch`, `defs`, `use`, `symbol`, `rect` (rx/ry), `circle`, `ellipse`, `line`, `polyline`, `polygon`, `path` (M L H V C S Q T A Z, absolute and relative), `linearGradient`, `radialGradient` (fx/fy focal, spreadMethod pad/repeat/reflect, gradientUnits, gradientTransform, `href` stop inheritance), `style`.

Styling: presentation attributes, `style=""`, `<style>` sheets with `tag`, `.class`, `#id`, `tag.class` selectors and `!important`; `fill`, `fill-rule` (nonzero / evenodd), `fill-opacity`, `stroke`, `stroke-width`, `stroke-opacity`, `stroke-linecap` (butt / round / square), `stroke-linejoin` (miter / round / bevel), `stroke-miterlimit`, `stroke-dasharray`, `stroke-dashoffset`, `opacity` (true group opacity via layers), `display`, `visibility`, `color` / `currentColor`.

Colors: named (all 147), `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()`, `hsl()`, `hsla()`, `transparent`, `url(#id)` with fallback color.

Geometry: `transform` (matrix, translate, scale, rotate with center, skewX, skewY), `viewBox`, `preserveAspectRatio` (all alignments, meet / slice / none), lengths in px, pt, pc, mm, cm, in, em, %.

Not supported (silently skipped): `text`, `image`, filters, masks, `clipPath`, patterns, markers, animation, scripting.

## Performance

Measured in a live Roblox client: simple 100x100 icon in about 5 ms, the 4-sample demo cards (176x176) in 5 to 20 ms each, the official SVG logo at 512x512 in about 360 ms. Lower `Quality` (for example 2) roughly halves the time; render once and reuse the label where possible.

## How it works

1. A small XML parser builds the tree; `<style>` blocks are parsed into rules.
2. Every shape becomes a path of M / L / C / Z segments (arcs are converted to cubics).
3. Paths are transformed by the current matrix and flattened to polylines in pixel space.
4. Strokes are converted to polygons (segment quads plus joins and caps) and unioned with the nonzero rule; dashes are cut along the polyline first.
5. A scanline rasterizer with exact horizontal coverage and N vertical sub-samples fills polygons into an RGBA8 `buffer`, blending with straight-alpha "over". Gradients are evaluated per pixel by inverse-mapping into gradient space.
6. The buffer goes to `EditableImage:WritePixelsBuffer` and `Content.fromObject`, or is wrapped as PNG (stored deflate + CRC32 + Adler32) for `Drawing.Image` and files.

## Files

- `LuaSupportsSVG.luau` - the library
- `demo.luau` - executor demo showing gradients, arcs, dashes, symbols, evenodd, icon tinting, the Frame fallback and PNG export

MIT License.
