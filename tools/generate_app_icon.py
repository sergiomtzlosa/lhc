#!/usr/bin/env python3
"""Generate the LHC Interactive application icon and .icns bundle."""

from __future__ import annotations

import math
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "LHC" / "Resources"
ICONSET = ROOT / "build" / "AppIcon.iconset"
MASTER = ROOT / "build" / "AppIcon-1024.png"

S = 2048          # supersampled master
UNIT = S / 1024.0


def px(value: float) -> int:
    return round(value * UNIT)


def rounded_mask(box, radius):
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def make_background():
    top = (16, 35, 57)
    bottom = (3, 7, 12)
    gradient = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(gradient)
    for y in range(S):
        t = y / (S - 1)
        # Ease the gradient so most of the icon stays deep and velvety.
        t = t ** 1.35
        color = lerp(top, bottom, t)
        draw.line((0, y, S, y), fill=color + (255,))
    return gradient


def make_icon() -> Image.Image:
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # Soft drop shadow behind the squircle.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (px(98), px(112), px(926), px(940)), radius=px(190), fill=(0, 0, 0, 170)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(px(22)))
    canvas.alpha_composite(shadow)

    mask = rounded_mask((px(100), px(100), px(924), px(924)), px(185))
    background = make_background()

    # Colour washes: a cool glow behind the ring and a violet event flash.
    wash = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    wash_draw = ImageDraw.Draw(wash)
    wash_draw.ellipse(
        (px(130), px(100), px(900), px(870)), fill=(22, 97, 150, 54)
    )
    wash_draw.ellipse(
        (px(360), px(280), px(1060), px(1000)), fill=(91, 22, 126, 46)
    )
    wash = wash.filter(ImageFilter.GaussianBlur(px(95)))
    background.alpha_composite(wash)
    background.putalpha(mask)
    canvas.alpha_composite(background)

    # Glassy inner bevel.
    bevel = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bevel_draw = ImageDraw.Draw(bevel)
    bevel_draw.rounded_rectangle(
        (px(105), px(105), px(919), px(919)),
        radius=px(181),
        outline=(125, 203, 235, 54),
        width=px(2),
    )
    bevel_draw.rounded_rectangle(
        (px(115), px(115), px(909), px(909)),
        radius=px(170),
        outline=(255, 255, 255, 13),
        width=px(1),
    )
    bevel.putalpha(Image.composite(bevel.getchannel("A"), Image.new("L", (S, S), 0), mask))
    canvas.alpha_composite(bevel)

    ring_cx, ring_cy = px(512), px(476)
    ring_r = px(274)
    ring_box = (ring_cx - ring_r, ring_cy - ring_r, ring_cx + ring_r, ring_cy + ring_r)

    # A diffuse halo around the accelerator ring.
    halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    halo_draw = ImageDraw.Draw(halo)
    halo_draw.ellipse(
        (ring_cx - ring_r - px(28), ring_cy - ring_r - px(28),
         ring_cx + ring_r + px(28), ring_cy + ring_r + px(28)),
        outline=(30, 119, 184, 80), width=px(32),
    )
    halo = halo.filter(ImageFilter.GaussianBlur(px(24)))
    canvas.alpha_composite(Image.composite(halo, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))

    draw = ImageDraw.Draw(canvas)

    # Main cryostat / tunnel.
    draw.ellipse(ring_box, outline=(15, 27, 42, 255), width=px(31))
    draw.ellipse(ring_box, outline=(76, 103, 129, 210), width=px(17))
    draw.ellipse(ring_box, outline=(24, 45, 66, 255), width=px(9))

    # Twin beam rails: cyan and magenta.
    beam_cyan = (ring_cx - ring_r + px(11), ring_cy - ring_r + px(11),
                 ring_cx + ring_r - px(11), ring_cy + ring_r - px(11))
    beam_magenta = (ring_cx - ring_r + px(22), ring_cy - ring_r + px(22),
                    ring_cx + ring_r - px(22), ring_cy + ring_r - px(22))
    beam_glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(beam_glow)
    gd.ellipse(beam_cyan, outline=(55, 230, 255, 230), width=px(8))
    gd.ellipse(beam_magenta, outline=(255, 61, 185, 230), width=px(8))
    beam_glow = beam_glow.filter(ImageFilter.GaussianBlur(px(7)))
    canvas.alpha_composite(beam_glow)
    draw.ellipse(beam_cyan, outline=(154, 245, 255, 255), width=px(3))
    draw.ellipse(beam_magenta, outline=(255, 163, 221, 255), width=px(3))

    # Magnets: alternating blue dipoles and occasional red quadrupoles.
    magnet_count = 32
    for i in range(magnet_count):
        angle = (i / magnet_count) * math.tau - math.pi / 2
        x = ring_cx + ring_r * math.cos(angle)
        y = ring_cy + ring_r * math.sin(angle)
        is_quad = i % 8 == 5
        colour = (223, 49, 65, 255) if is_quad else (34, 105, 228, 255)
        edge = (255, 122, 139, 255) if is_quad else (105, 173, 255, 255)
        block = Image.new("RGBA", (px(42), px(27)), (0, 0, 0, 0))
        bd = ImageDraw.Draw(block)
        bd.rounded_rectangle(
            (px(2), px(2), px(40), px(25)), radius=px(5), fill=colour,
            outline=edge, width=px(2)
        )
        bd.line((px(7), px(7), px(35), px(7)), fill=(255, 255, 255, 90), width=px(1))
        block = block.rotate(-math.degrees(angle), resample=Image.Resampling.BICUBIC)
        canvas.alpha_composite(block, (round(x - block.width / 2), round(y - block.height / 2)))

    def detector_badge(cx, cy, width, height, accent, inner):
        box = (round(cx - width / 2), round(cy - height / 2),
               round(cx + width / 2), round(cy + height / 2))
        draw.rounded_rectangle(box, radius=px(11), fill=(6, 13, 22, 245),
                               outline=accent, width=px(4))
        inset = (box[0] + px(8), box[1] + px(8), box[2] - px(8), box[3] - px(8))
        draw.rounded_rectangle(inset, radius=px(6), fill=(13, 25, 38, 255),
                               outline=inner, width=px(2))
        for offset in (-1, 0, 1):
            y = (box[1] + box[3]) / 2 + offset * px(12)
            draw.line((inset[0] + px(4), y, inset[2] - px(4), y),
                      fill=inner, width=px(2))

    # ATLAS blue toroid, CMS red barrel, ALICE gold/green stack, LHCb green tail.
    detector_badge(ring_cx, ring_cy - ring_r, 138, 70, (79, 166, 255, 255), (151, 213, 255, 255))
    detector_badge(ring_cx + ring_r, ring_cy, 70, 138, (255, 76, 86, 255), (255, 183, 180, 255))
    detector_badge(ring_cx, ring_cy + ring_r, 150, 72, (255, 190, 69, 255), (255, 234, 155, 255))
    detector_badge(ring_cx - ring_r, ring_cy, 70, 138, (74, 230, 155, 255), (159, 255, 215, 255))

    # Central collision event display.
    cx, cy = px(512), px(476)
    star_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(star_layer)
    for i in range(18):
        angle = (i / 18.0) * math.tau + 0.11
        inner = px(12)
        outer = px(57 + (i % 5) * 12)
        colour = (117, 240, 255, 205) if i % 2 == 0 else (255, 105, 201, 190)
        sd.line((cx + math.cos(angle) * inner, cy + math.sin(angle) * inner,
                 cx + math.cos(angle) * outer, cy + math.sin(angle) * outer),
                fill=colour, width=px(3))
        dot_r = px(3.5)
        sd.ellipse((cx + math.cos(angle) * outer - dot_r,
                    cy + math.sin(angle) * outer - dot_r,
                    cx + math.cos(angle) * outer + dot_r,
                    cy + math.sin(angle) * outer + dot_r),
                   fill=colour)
    star_layer = star_layer.filter(ImageFilter.GaussianBlur(px(1.2)))
    canvas.alpha_composite(star_layer)

    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((cx - px(35), cy - px(35), cx + px(35), cy + px(35)),
               fill=(206, 250, 255, 225))
    glow = glow.filter(ImageFilter.GaussianBlur(px(27)))
    canvas.alpha_composite(glow)
    draw.ellipse((cx - px(10), cy - px(10), cx + px(10), cy + px(10)),
                 fill=(255, 255, 255, 255))

    # Wordmark.
    font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", px(76))
    text = "LHC"
    tracking = px(12)
    widths = [draw.textlength(ch, font=font) for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    x = (S - total) / 2
    baseline_y = px(824)
    for ch, width in zip(text, widths):
        draw.text((x, baseline_y), ch, font=font, fill=(208, 238, 255, 255),
                  stroke_width=px(1), stroke_fill=(95, 164, 214, 180))
        x += width + tracking
    # Keep the wordmark in the lower third, inside the glass lip.
    canvas = canvas.filter(ImageFilter.SMOOTH)

    return canvas.resize((1024, 1024), Image.Resampling.LANCZOS)


def main():
    RESOURCES.mkdir(parents=True, exist_ok=True)
    MASTER.parent.mkdir(parents=True, exist_ok=True)
    ICONSET.mkdir(parents=True, exist_ok=True)

    icon = make_icon()
    icon.save(MASTER)

    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for name, size in sizes.items():
        icon.resize((size, size), Image.Resampling.LANCZOS).save(ICONSET / name)

    subprocess.run(
        ["iconutil", "-c", "icns", str(ICONSET), "-o", str(RESOURCES / "AppIcon.icns")],
        check=True,
    )
    print(f"Wrote {RESOURCES / 'AppIcon.icns'}")


if __name__ == "__main__":
    main()
