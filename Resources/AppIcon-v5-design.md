# 屏幕译图标 v5

- 方式：内置 image_gen，编辑 AppIcon-v4.png。
- 当前素材：AppIcon-v5.png；旧版素材保留。
- 调整：参考 macOS 26 的柔和渐变和玻璃光泽，将灰感较重的绿色与蓝色改为有分量的海玻璃绿和海洋蓝，并增加表面高光、边缘折射和圆润层次；保留无中心菱形、满幅不透明背景。
- 导出素材为 1254 × 1254、不含透明通道的 PNG；打包时生成标准尺寸。

## macOS 26 配色提示词

```text
Use case: precise-object-edit
Asset type: final production macOS 26 app icon source.
Input image 1 is the edit target. Keep its exact current geometry and composition: two large interlocking rounded language cards, "A" at upper-left, "中" at lower-right, no white diamond at their meeting point, warm full-bleed square background.
Primary change: recolor the two cards to feel at home in the macOS 26 visual language. The current sage and dusty blue look too gray and muted. Make them cleaner, fresher, and moderately colorful while remaining refined and comfortable.
Palette: upper-left card luminous sea-glass jade / teal-green, centered around #45A38B with gentle highlights around #6BB9A1. Lower-right card clear cornflower / ocean blue, centered around #4E83B8 with gentle highlights around #73A5D1. Medium saturation, soft and airy; richer than gray pastels, far calmer than neon. No coral, hot pink, electric blue, violet, or muddy gray.
Rendering: restrained macOS 26 influence — very soft light-to-dark tonal gradients, delicate translucent glass edge highlights, subtle depth and specular light, crisp bold glyphs. Avoid shiny plastic, heavy 3D, harsh shadows, dark outlines, texture, noise, or dramatic gloss.
Keep the "A" and "中" glyphs warm ivory-white and exactly legible. Preserve the natural continuous connection between both cards with no central gap, square, diamond, pin, or ornament.
Critical canvas constraints: the warm ivory background fills every pixel of the full square to all four edges and corners, opaque. Do not bake in an outer rounded rectangle, border, rim, extra tile, transparent padding, app mockup, or presentation frame. macOS will apply the final icon mask.
Output one square PNG only.
```

## 通透度修正提示词

```text
Use case: precise-object-edit
Asset type: final production macOS 26 app icon source.
Input image 1 is the edit target. Make ONE focused visual refinement: make the teal-green and blue language cards look lighter, clearer, and more translucent — like softly illuminated sea glass in the macOS 26 Liquid Glass visual language.
Keep the current clean teal and blue hues, but reduce their visual density. Add airy inner luminosity, a gentle transparent-glass feeling, soft bright edge refraction, and smoother light-to-dark gradients. The upper portions may be slightly lighter and clearer, with a subtle sense that warm ambient light passes through the material. Colors should feel fresh and lucid, not gray, chalky, opaque, muddy, neon, candy-like, or oversaturated.
Preserve the exact current geometry, size, diagonal composition, curled corners, warm ivory-white "A" and "中" glyphs, and the continuous connection between both cards. There must be no white central diamond, square, gap, pin, or ornament.
Keep the icon minimal and premium. No heavy shadows, thick outlines, texture, noise, plastic gloss, sparkles, extra highlights, or extra elements.
Critical canvas constraints: retain an opaque warm ivory background filling the entire square all the way to all four edges and corners. No outer rounded-rectangle tile, rim, border, mockup, or transparent padding. macOS will apply its own outer mask.
Output one square PNG only.
```

此稿因过于发白未采用。

## 最终玻璃光泽修正提示词

```text
Use case: precise-object-edit
Asset type: final production macOS 26 app icon source.
Input image 1 is the edit target. Use its medium-rich teal-green and ocean-blue colors as the base. Do NOT make the cards transparent, pale, washed out, frosted, milky, or pastel.
Primary change: give both colored language cards a polished Apple-style glass GLOSS and premium macOS app-icon finish while keeping the bodies visibly colored and substantial.
Rendering: add a controlled curved specular highlight across the upper-left portions, crisp luminous edge reflections, subtle internal refraction, a gentle glass lens depth, and small soft secondary reflections that follow the rounded geometry. The surfaces should look like solid colored glass with a clear polished coating — glossy and dimensional, not see-through. Keep highlights elegant and restrained, with smooth rich gradients and no harsh glare.
Color: upper-left retains clean jade/teal green; lower-right retains clear ocean/cornflower blue. Moderate saturation and good color presence, no gray cast, no neon, no violet, no candy-plastic look.
Preserve the exact current geometry, large scale, diagonal interlocking composition, curled corners, warm ivory-white "A" and "中" glyphs, and their sharp legibility. Keep the continuous natural join with no central white diamond, square, gap, pin, or ornament.
Critical canvas constraints: keep the warm ivory background opaque and filling the entire square to all four edges and corners. Do not draw an outer rounded rectangle, rim, extra tile, app mockup, or transparent padding. macOS applies the final outer mask.
No texture, noise, sparkles, metallic finish, heavy drop shadows, thick outlines, extra symbols, or additional text.
Output one square PNG only.
```
