# The cursor theme, drawn and baked: every cursor is a few layers on a 24-point grid, glass bodies
# under a dark line with a pale halo round the whole, as in the app's own drawings. A glass body is
# shaded from its distance field the way open Liquid Glass shaders shade theirs (a squircle bevel,
# its normals, Fresnel, a specular highlight and a rim light from the top left, a darker band on
# the far side), baked into the bitmap since a cursor cannot see what is behind it.
#
#   python3 make.py OUT
#
# writes OUT/<cursor>@<scale>x.png for each scale (frames stacked top to bottom) and OUT/cursors.json,
# which names the system cursors each one replaces, its hotspot and its frames (Sources/Noren/Cursors.swift).
import io
import json
import math
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

SCALES = (1, 2, 5, 10)
INK, HALO = "#2b2622", "#faf7f0"
LINE, HALO_WIDTH = 1.4, 4.0
BLUE, PURPLE = np.array([0x61, 0xAF, 0xEF]) / 255, np.array([0xC6, 0x78, 0xDD]) / 255
RED, GREEN = np.array([0xE0, 0x6C, 0x75]) / 255, np.array([0x3F, 0xB9, 0x50]) / 255
PAPER = np.array([0xFA, 0xF7, 0xF0]) / 255
# The light, from the top left and in front (x right, y down, z towards the eye)
LIGHT = np.array([-0.45, -0.65, 0.62]) / np.linalg.norm([-0.45, -0.65, 0.62])
GLASS = {
    "tint": 0.8,
    "bevel": 1.8,
    "height": 1.6,
    "fresnel": 0.35,
    "shine": 1.1,
    "shine_power": 16,
    "rim": 1.0,
    "rim_far": 0.4,
    "dark": 0.22,
    "shadow": 0.25,
}

# Shapes, closed paths on the 24 grid
ARROW = "M5.5 3.5 V19.5 L9.6 15.6 L12.4 21.4 L15.2 20.1 L12.5 14.4 H18 Z"
HAND = (
    "M8 12.5 V5.5 a1.75 1.75 0 0 1 3.5 0 V11 a1.6 1.6 0 0 1 3.2 .3 a1.6 1.6 0 0 1 3 .5"
    " a1.5 1.5 0 0 1 2.8 1 V16 a5.5 5.5 0 0 1 -5.5 5.5 h-1.8 a5.6 5.6 0 0 1 -4.6 -2.5 L5 15.7"
    " a1.6 1.6 0 0 1 2.7 -1.8 Z"
)
OPEN_HAND = (
    "M7.5 13 V8 a1.5 1.5 0 0 1 3 0 V6.5 a1.5 1.5 0 0 1 3 0 V7 a1.5 1.5 0 0 1 3 0 V9"
    " a1.5 1.5 0 0 1 3 0 V15 a6 6 0 0 1 -6 6 h-1 a5.6 5.6 0 0 1 -4.4 -2.2 L4.6 15.4"
    " a1.6 1.6 0 0 1 2.6 -1.9 Z"
)
FIST = (
    "M6.5 11.5 a1.6 1.6 0 0 1 3.2 0 a1.6 1.6 0 0 1 3.2 0 a1.6 1.6 0 0 1 3.2 0"
    " a1.6 1.6 0 0 1 3.2 0 V15.5 a5.5 5.5 0 0 1 -5.5 5.5 h-2 a5.5 5.5 0 0 1 -5.5 -5.5 Z"
)
DISK = "M5 12a7 7 0 1 0 14 0a7 7 0 1 0 -14 0z"
BOTH_WAYS = "M3.5 12 L7.8 7.8 V10.4 H16.2 V7.8 L20.5 12 L16.2 16.2 V13.6 H7.8 V16.2 Z"
ONE_WAY = "M7 10.4 H15.2 V7.8 L19.5 12 L15.2 16.2 V13.6 H7 Z"
FOUR_WAYS = (
    "M12 2.8 L15.6 6.4 H13.4 V10.6 H17.6 V8.4 L21.2 12 L17.6 15.6 V13.4 H13.4 V17.6 H15.6"
    " L12 21.2 L8.4 17.6 H10.6 V13.4 H6.4 V15.6 L2.8 12 L6.4 8.4 V10.6 H10.6 V6.4 H8.4 Z"
)
PLUS = "M10 4.5 H14 V10 H19.5 V14 H14 V19.5 H10 V14 H4.5 V10 H10 Z"
LENS = "M4 10a6 6 0 1 0 12 0a6 6 0 1 0 -12 0z"
# Open lines
IBEAM = (
    "M9 4.5 C11 4.5 12 5.3 12 7 C12 5.3 13 4.5 15 4.5 M12 7 V17 M9 19.5 C11 19.5 12 18.7 12 17 C12 18.7 13 19.5 15 19.5"
)
CROSS = "M12 3.5 V9 M12 15 V20.5 M3.5 12 H9 M15 12 H20.5"
BADGE_AT, BADGE_R = (17.2, 17.2), 4.2


def glass(path, tint="bp", turn=0):
    return {"kind": "glass", "path": path, "tint": tint, "turn": turn}


def line(path, turn=0, halo=True, width=LINE, color=INK, fill=None):
    return {"kind": "line", "path": path, "turn": turn, "halo": halo, "width": width, "color": color, "fill": fill}


def badge(glyph, tint="bp"):
    cx, cy = BADGE_AT
    r = BADGE_R
    disk = f"M{cx - r} {cy}a{r} {r} 0 1 0 {2 * r} 0a{r} {r} 0 1 0 {-2 * r} 0z"
    return [glass(disk, tint), line(at_badge(glyph), halo=False, width=1.3)]


def at_badge(path):
    """Moves a glyph drawn round (0, 0) onto the badge"""
    return f'<g transform="translate({BADGE_AT[0]} {BADGE_AT[1]})"><path d="{path}"/></g>'


ARROW_LAYERS = [glass(ARROW)]


def resize_one(turn):
    return [glass(ONE_WAY, turn=turn), line("M4.5 7.6 V16.4", turn=turn, width=1.8)]


def busy_frame(i, frames):
    a = 2 * math.pi * i / frames
    r = 3.6
    x0, y0 = 12 + r * math.sin(a), 12 - r * math.cos(a)
    x1, y1 = 12 + r * math.sin(a + 1.9), 12 - r * math.cos(a + 1.9)
    return [glass(DISK), line(f"M{x0:.3f} {y0:.3f} A{r} {r} 0 0 1 {x1:.3f} {y1:.3f}", halo=False, width=1.9)]


def cg(name):
    return f"com.apple.coregraphics.{name}"


def cursor(number):
    return f"com.apple.cursor.{number}"


# (file, the system cursors it replaces, hotspot, frames: lists of layers)
CURSORS = [
    ("arrow", [cg("Arrow"), cg("ArrowS")], (5.5, 3.5), [ARROW_LAYERS]),
    ("ibeam", [cg("IBeam"), cg("IBeamS"), cg("IBeamXOR")], (12, 12), [[line(IBEAM, width=1.8)]]),
    ("ibeam-horizontal", [cursor(26)], (12, 12), [[line(IBEAM, turn=90, width=1.8)]]),
    ("pointing", [cursor(13)], (9.75, 4), [[glass(HAND)]]),
    ("open-hand", [cursor(12)], (12, 12), [[glass(OPEN_HAND)]]),
    ("closed-hand", [cursor(11)], (12, 12), [[glass(FIST)]]),
    ("busy", [cg("Wait"), cursor(4)], (12, 12), [busy_frame(i, 12) for i in range(12)]),
    (
        "crosshair",
        [cursor(7), cursor(8)],
        (12, 12),
        [[line(CROSS, width=1.6), line("M12 11.2 a.8 .8 0 1 0 0 1.6 a.8 .8 0 1 0 0 -1.6z", fill=INK)]],
    ),
    ("cell", [cursor(41), cursor(20)], (12, 12), [[glass(PLUS)]]),
    ("move", [cg("Move"), cursor(39)], (12, 12), [[glass(FOUR_WAYS)]]),
    (
        "not-allowed",
        [cursor(3)],
        (5.5, 3.5),
        [ARROW_LAYERS + badge("M-2.2 2.2 L2.2 -2.2 M-3 0a3 3 0 1 0 6 0a3 3 0 1 0 -6 0z", RED)],
    ),
    ("copy", [cg("Copy"), cursor(5)], (5.5, 3.5), [ARROW_LAYERS + badge("M-2.2 0 H2.2 M0 -2.2 V2.2", GREEN)]),
    (
        "alias",
        [cg("Alias"), cursor(2)],
        (5.5, 3.5),
        [ARROW_LAYERS + badge("M-2 2.2 V0.5 a1.8 1.8 0 0 1 1.8 -1.8 H2 M0.6 -2.9 L2.2 -1.3 L0.6 0.3")],
    ),
    (
        "context-menu",
        [cg("ArrowCtx"), cursor(24)],
        (5.5, 3.5),
        [ARROW_LAYERS + badge("M-2.2 -1.6 H2.2 M-2.2 0 H2.2 M-2.2 1.6 H2.2")],
    ),
    (
        "help",
        [cursor(40)],
        (5.5, 3.5),
        [ARROW_LAYERS + badge("M-1.4 -1.1 a1.5 1.5 0 1 1 2.1 1.4 c-.5 .2 -.7 .5 -.7 1 M0 2.4 v.1")],
    ),
    ("poof", [cursor(25)], (5.5, 3.5), [ARROW_LAYERS + badge("M-1.8 -1.8 L1.8 1.8 M1.8 -1.8 L-1.8 1.8", RED)]),
    (
        "zoom-in",
        [cursor(42)],
        (10, 10),
        [[line("M14.3 14.3 L19.5 19.5", width=2.6), glass(LENS), line("M7.6 10 H12.4 M10 7.6 V12.4", halo=False)]],
    ),
    (
        "zoom-out",
        [cursor(43)],
        (10, 10),
        [[line("M14.3 14.3 L19.5 19.5", width=2.6), glass(LENS), line("M7.6 10 H12.4", halo=False)]],
    ),
    # Both ways: across (window and legacy names), up and down, and the diagonals
    ("resize-left-right", [cursor(19), cursor(28)], (12, 12), [[glass(BOTH_WAYS)]]),
    ("resize-up-down", [cursor(23), cursor(32)], (12, 12), [[glass(BOTH_WAYS, turn=90)]]),
    ("resize-northeast-southwest", [cursor(30)], (12, 12), [[glass(BOTH_WAYS, turn=-45)]]),
    ("resize-northwest-southeast", [cursor(34)], (12, 12), [[glass(BOTH_WAYS, turn=45)]]),
    # One way, against a bar: the edge that can only move one way
    ("resize-east", [cursor(18), cursor(27)], (12, 12), [resize_one(0)]),
    ("resize-southeast", [cursor(35)], (12, 12), [resize_one(45)]),
    ("resize-south", [cursor(22), cursor(36)], (12, 12), [resize_one(90)]),
    ("resize-southwest", [cursor(37)], (12, 12), [resize_one(135)]),
    ("resize-west", [cursor(17), cursor(38)], (12, 12), [resize_one(180)]),
    ("resize-northwest", [cursor(33)], (12, 12), [resize_one(225)]),
    ("resize-north", [cursor(21), cursor(31)], (12, 12), [resize_one(270)]),
    ("resize-northeast", [cursor(29)], (12, 12), [resize_one(315)]),
]
FRAME_SECONDS = 1 / 12


def svg(body, px):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{px}" height="{px}" viewBox="0 0 24 24">{body}</svg>'


def raster(body, px):
    out = subprocess.run(["rsvg-convert"], input=svg(body, px).encode(), capture_output=True, check=True)
    return np.asarray(Image.open(io.BytesIO(out.stdout)).convert("RGBA")).astype(np.float64) / 255


def drawn(layer, attributes):
    """The layer's path as SVG with `attributes`; a badge glyph comes already placed"""
    path = layer["path"]
    shape = (
        path.replace("<path ", f"<path {attributes} ") if path.startswith("<") else f'<path d="{path}" {attributes}/>'
    )
    return f'<g transform="rotate({layer["turn"]} 12 12)">{shape}</g>'


def over(below, above):
    a = above[..., 3:4]
    alpha = a + below[..., 3:4] * (1 - a)
    rgb = (above[..., :3] * a + below[..., :3] * below[..., 3:4] * (1 - a)) / np.maximum(alpha, 1e-9)
    return np.dstack([rgb, alpha])


def shaded(layer, size, unit):
    """The glass body of `layer`, size by size pixels at `unit` pixels a point"""
    fill = raster(drawn(layer, 'fill="#000"'), size)[..., 3]
    # Into the glass from the line's inner edge, in points
    depth = ndimage.distance_transform_edt(fill > 0.5) / unit - LINE / 2
    x = np.clip(depth / GLASS["bevel"], 0, 1)
    height = (1 - (1 - x) ** 4) ** 0.25 * GLASS["height"]
    dy, dx = np.gradient(ndimage.gaussian_filter(height, 0.6 * unit), 1 / unit)
    normal = np.stack([-dx, -dy, np.ones_like(height)], -1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    facing_eye = normal[..., 2]
    fresnel = (0.04 + 0.96 * (1 - facing_eye) ** 5)[..., None] * GLASS["fresnel"]
    yy, xx = np.mgrid[0:size, 0:size] / size
    if isinstance(layer["tint"], str):
        t = np.clip((xx + yy) / 2, 0, 1)[..., None]
        tint = BLUE * (1 - t) + PURPLE * t
    else:
        tint = np.broadcast_to(layer["tint"], (size, size, 3))
    rgb = PAPER * (1 - GLASS["tint"]) + tint * GLASS["tint"]
    rgb = rgb * (0.9 - 0.1 * normal[..., 1])[..., None]
    rgb = rgb * (1 - fresnel) + fresnel
    reflected = 2 * facing_eye[..., None] * normal - np.array([0, 0, 1])
    shine = np.clip((reflected * LIGHT).sum(-1), 0, 1) ** GLASS["shine_power"] * GLASS["shine"]
    rgb = rgb + shine[..., None] * np.array([1, 0.98, 0.94])
    # Which way each edge faces, against the light: the near side lights up, the far side glints
    # less and shades the glass a little inside it
    ey, ex = np.gradient(ndimage.gaussian_filter(depth, 1.2 * unit))
    toward = -(ex * LIGHT[0] + ey * LIGHT[1]) / (np.hypot(ex, ey) + 1e-9) / np.hypot(*LIGHT[:2])
    rim = (
        np.clip(1 - np.abs(depth - 0.25) / 0.35, 0, 1)
        * GLASS["rim"]
        * (np.clip(toward, 0, 1) + GLASS["rim_far"] * np.clip(-toward, 0, 1))
    )
    rgb = rgb * (1 - rim[..., None]) + rim[..., None]
    band = np.clip(1 - np.abs(depth - 1.1) / 0.7, 0, 1) * np.clip(-toward, 0, 1) * GLASS["dark"]
    rgb = rgb * (1 - band[..., None])
    if size >= 96 * 2:
        # A colour fringe at the bevel, blue towards the light and red away, only where it is
        # wide enough to see
        fringe = np.clip(1 - np.abs(depth - 0.6) / 0.25, 0, 1) * np.abs(toward) * 0.25
        rgb[..., 0] += fringe * (toward < 0) * 0.6
        rgb[..., 2] += fringe * (toward > 0) * 0.8
    return np.dstack([np.clip(rgb, 0, 1), (depth > -0.2) * fill])


def frame(layers, px):
    # Drawn larger and scaled down, so the lines stay smooth at 1x
    size = px * (4 if px < 48 else 2)
    unit = size / 24
    halos = [
        raster(
            drawn(
                layer,
                f'fill="{HALO}" stroke="{HALO}" stroke-width="{(layer.get("width") or LINE) + HALO_WIDTH - LINE}"'
                ' stroke-linecap="round" stroke-linejoin="round"',
            ),
            size,
        )
        for layer in layers
        if layer["kind"] == "glass" or layer["halo"]
    ]
    outline = np.max([h[..., 3] for h in halos], axis=0)
    soft = ndimage.shift(ndimage.gaussian_filter(outline, unit), (0.6 * unit, 0), order=1, mode="constant")
    image = np.dstack([np.zeros((size, size, 3)), soft * GLASS["shadow"]])
    halo_at = iter(halos)
    for layer in layers:
        if layer["kind"] == "glass" or layer["halo"]:
            image = over(image, next(halo_at))
        if layer["kind"] == "glass":
            image = over(image, shaded(layer, size, unit))
            stroke = drawn(layer, f'fill="none" stroke="{INK}" stroke-width="{LINE}" stroke-linejoin="round"')
        else:
            fill = layer["fill"] or "none"
            stroke = drawn(
                layer,
                f'fill="{fill}" stroke="{layer["color"]}" stroke-width="{layer["width"]}"'
                ' stroke-linecap="round" stroke-linejoin="round"',
            )
        image = over(image, raster(stroke, size))
    out = Image.fromarray((np.clip(image, 0, 1) * 255).round().astype(np.uint8), "RGBA")
    return out.resize((px, px), Image.LANCZOS)


def main(out):
    out.mkdir(parents=True, exist_ok=True)
    manifest = []
    for name, replaces, hotspot, frames in CURSORS:
        for scale in SCALES:
            px = 24 * scale
            strip = Image.new("RGBA", (px, px * len(frames)))
            for i, layers in enumerate(frames):
                strip.paste(frame(layers, px), (0, i * px))
            strip.save(out / f"{name}@{scale}x.png")
        manifest.append(
            {
                "file": name,
                "replaces": replaces,
                "hotspot": list(hotspot),
                "frames": len(frames),
                "frameSeconds": FRAME_SECONDS if len(frames) > 1 else 0,
            }
        )
    (out / "cursors.json").write_text(json.dumps({"size": 24, "scales": list(SCALES), "cursors": manifest}, indent=1))


if __name__ == "__main__":
    main(Path(sys.argv[1]))
