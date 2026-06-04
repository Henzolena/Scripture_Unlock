"""
Scripture Unlock – App Icon Generator
Produces three 1024×1024 PNGs:
  icon_light.png   (light mode)
  icon_dark.png    (dark mode)
  icon_tinted.png  (tinted / monochrome mask)
"""

import numpy as np
from PIL import Image, ImageFilter

SIZE = 1024

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

def hex_to_f(h: str) -> np.ndarray:
    h = h.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return np.array([r, g, b], dtype=np.float32) / 255.0

def lerp(a, b, t):
    return a * (1 - t) + b * t

def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3 - 2 * t)

# ──────────────────────────────────────────────────────────────────────────────
# Coordinate grid   xn / yn  ∈ [−1, 1]
# ──────────────────────────────────────────────────────────────────────────────
_y, _x = np.mgrid[0:SIZE, 0:SIZE]
xn = (_x - SIZE / 2.0) / (SIZE / 2.0)
yn = (_y - SIZE / 2.0) / (SIZE / 2.0)

# ──────────────────────────────────────────────────────────────────────────────
# Cross SDF  (returns negative inside, positive outside)
# ──────────────────────────────────────────────────────────────────────────────
def cross_sdf(arm_w, vert_h, horiz_w):
    dx_v = np.abs(xn) - arm_w;   dy_v = np.abs(yn) - vert_h
    dx_h = np.abs(xn) - horiz_w; dy_h = np.abs(yn) - arm_w
    sdf_v = np.maximum(dx_v, dy_v)
    sdf_h = np.maximum(dx_h, dy_h)
    return np.minimum(sdf_v, sdf_h)

# Diamond (45°-rotated square) SDF — for the arm-end caps
def diamond_sdf(cx, cy, half):
    return (np.abs(xn - cx) + np.abs(yn - cy)) - half

# Circle SDF
def circle_sdf(cx, cy, r):
    return np.sqrt((xn - cx) ** 2 + (yn - cy) ** 2) - r

def mask_from_sdf(sdf, smooth=0.018):
    return smoothstep(smooth, -smooth, sdf)

# ──────────────────────────────────────────────────────────────────────────────
# Main render function
# ──────────────────────────────────────────────────────────────────────────────
def render(dark=False, tinted=False) -> Image.Image:
    # ── Background ────────────────────────────────────────────────────────────
    if tinted:
        bg_c = hex_to_f("111827")
        bg_e = hex_to_f("050810")
    elif dark:
        bg_c = hex_to_f("0D1B3E")
        bg_e = hex_to_f("050810")
    else:
        bg_c = hex_to_f("1E3A5F")
        bg_e = hex_to_f("08101E")

    # Radial gradient — light source slightly above center
    dist_bg = np.sqrt(xn ** 2 + (yn + 0.15) ** 2)
    t_bg    = smoothstep(0.0, 1.6, dist_bg)[:, :, None]
    bg      = lerp(bg_c, bg_e, t_bg)

    # Subtle warm-gold vignette inner glow (center highlight)
    inner_glow = smoothstep(1.0, 0.0, dist_bg)
    inner_glow_color = hex_to_f("2A4A7F")
    bg = bg + inner_glow[:, :, None] * (inner_glow_color - bg) * 0.4

    # ── Cross geometry ─────────────────────────────────────────────────────────
    ARM_W   = 0.110   # arm half-width
    VERT_H  = 0.420   # vertical arm half-height
    HORIZ_W = 0.350   # horizontal arm half-width
    CAP_D   = 0.095   # diamond end-cap half-size
    CIR_R   = 0.078   # center circle radius
    CIR_R2  = 0.048   # inner circle cut-out radius

    sdf_cross  = cross_sdf(ARM_W, VERT_H, HORIZ_W)

    # Four diamond caps at arm ends
    sdf_top    = diamond_sdf(0.0,  -VERT_H,  CAP_D)
    sdf_bot    = diamond_sdf(0.0,   VERT_H,  CAP_D)
    sdf_left   = diamond_sdf(-HORIZ_W, 0.0,  CAP_D)
    sdf_right  = diamond_sdf( HORIZ_W, 0.0,  CAP_D)

    # Center circle
    sdf_circ   = circle_sdf(0.0, 0.0, CIR_R)
    sdf_hole   = circle_sdf(0.0, 0.0, CIR_R2)

    # Union of all shapes
    sdf_union = np.minimum(
        np.minimum(
            np.minimum(sdf_cross, sdf_top),
            np.minimum(sdf_bot, sdf_left)
        ),
        np.minimum(sdf_right, sdf_circ)
    )
    # Subtract inner circle for the ring effect
    sdf_final = np.maximum(sdf_union, -sdf_hole)

    # Masks
    cross_mask = mask_from_sdf(sdf_final, smooth=0.012)
    glow_mask  = mask_from_sdf(sdf_final, smooth=0.11) * (1 - cross_mask)

    # ── Colors ────────────────────────────────────────────────────────────────
    if tinted:
        # Monochrome white — iOS uses this as a tint mask
        cross_col = np.ones((SIZE, SIZE, 3), dtype=np.float32)
        glow_col  = np.ones((SIZE, SIZE, 3), dtype=np.float32)
    else:
        # Gold gradient: light-gold at top, richer gold at bottom
        gold_a = hex_to_f("EDD98A")   # light warm gold
        gold_b = hex_to_f("B8913A")   # rich amber gold
        t_gold = smoothstep(-0.7, 0.7, yn)[:, :, None]
        cross_col = lerp(gold_a, gold_b, t_gold)

        # Thin specular highlight on left edge
        highlight = smoothstep(ARM_W + 0.02, ARM_W - 0.06, np.abs(xn)) * \
                    smoothstep(0.2, -0.2, yn) * (1 - mask_from_sdf(sdf_final + 0.04))
        cross_col = lerp(cross_col, np.ones_like(cross_col) * 0.98, highlight[:, :, None] * 0.25)

        glow_col  = hex_to_f("C9A961")

    # ── Glow (outer bloom) ────────────────────────────────────────────────────
    glow_strength = 0.55 if not tinted else 0.2
    canvas = bg + glow_col * glow_mask[:, :, None] * glow_strength

    # ── Composite cross onto canvas ───────────────────────────────────────────
    canvas = lerp(canvas, cross_col, cross_mask[:, :, None])

    # ── Fine inner grid lines on the cross (lattice pattern, Ethiopian style) ─
    if not tinted:
        grid_spacing = 0.055
        grid_thick   = 0.008
        gx = np.abs((xn % grid_spacing) - grid_spacing / 2)
        gy = np.abs((yn % grid_spacing) - grid_spacing / 2)
        grid_sdf = np.minimum(gx, gy) - grid_thick
        grid_mask = mask_from_sdf(grid_sdf, smooth=0.005) * (1 - mask_from_sdf(sdf_final + 0.002))
        canvas = lerp(canvas, hex_to_f("1E3A5F") + 0.05, grid_mask[:, :, None] * 0.35)

    # ── Border / edge darkening ────────────────────────────────────────────────
    edge_dist = 1.0 - np.sqrt(xn ** 2 + yn ** 2)
    edge_vign = smoothstep(0.0, 0.4, edge_dist)
    canvas = canvas * (0.65 + 0.35 * edge_vign[:, :, None])

    # ── Finalize ───────────────────────────────────────────────────────────────
    canvas = np.clip(canvas, 0, 1)
    arr    = (canvas * 255).astype(np.uint8)
    return Image.fromarray(arr, "RGB")


# ──────────────────────────────────────────────────────────────────────────────
# Generate all three variants
# ──────────────────────────────────────────────────────────────────────────────
out = "/Users/henokrobale/CascadeProjects/Scripture_Unlock/Scripture_Unlock/Assets.xcassets/AppIcon.appiconset"

print("Rendering light icon…")
render(dark=False).save(f"{out}/icon_light.png")

print("Rendering dark icon…")
render(dark=True).save(f"{out}/icon_dark.png")

print("Rendering tinted icon…")
render(tinted=True).save(f"{out}/icon_tinted.png")

print("✓ All icons written to AppIcon.appiconset/")
