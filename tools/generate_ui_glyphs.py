#!/usr/bin/env python3
"""
generate_ui_glyphs.py - Generates razor-sharp, pixel-perfect transparent PNG icons and HUD symbols.
Uses 4x supersampling with PIL and Lanczos filtering for clean anti-aliasing.
"""

import math
import os
from PIL import Image, ImageDraw

def create_canvas(size, scale=4):
    ss = size * scale
    img = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    return img, draw, ss, scale

def finalize(img, size):
    return img.resize((size, size), Image.Resampling.LANCZOS)

# ----------------- ICONS (256x256, White on Transparent) -----------------

def icon_settings():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2
    # 8-toothed gear
    r_outer = 90 * sc
    r_inner = 70 * sc
    r_hole = 35 * sc
    teeth = 8
    points = []
    for i in range(teeth * 2):
        angle = i * (2 * math.pi / (teeth * 2))
        r = r_outer if i % 2 == 0 else r_inner
        a1 = angle - 0.12
        a2 = angle + 0.12
        points.append((cx + r * math.cos(a1), cy + r * math.sin(a1)))
        points.append((cx + r * math.cos(a2), cy + r * math.sin(a2)))
    d.polygon(points, fill=(255, 255, 255, 255))
    # Punch center hole
    d.ellipse([cx - r_hole, cy - r_hole, cx + r_hole, cy + r_hole], fill=(0, 0, 0, 0))
    return finalize(img, 256)

def icon_radio():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2 + 30 * sc
    # Central antenna mast
    d.line([(cx, cy + 50 * sc), (cx, cy - 70 * sc)], fill=(255, 255, 255, 255), width=10 * sc)
    d.ellipse([cx - 14 * sc, cy - 84 * sc, cx + 14 * sc, cy - 56 * sc], fill=(255, 255, 255, 255))
    # Radiating waves
    for r in [40 * sc, 70 * sc, 100 * sc]:
        d.arc([cx - r, cy - 70 * sc - r, cx + r, cy - 70 * sc + r], start=215, end=325, fill=(255, 255, 255, 255), width=8 * sc)
    return finalize(img, 256)

def icon_hangar():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2
    # Arch outline
    w, h = 95 * sc, 75 * sc
    # Hangar dome / arch
    d.ellipse([cx - w, cy - h + 10 * sc, cx + w, cy + h + 10 * sc], fill=(255, 255, 255, 255))
    # Ground cut
    d.rectangle([0, cy + 60 * sc, s, s], fill=(0, 0, 0, 0))
    # Cutout interior arch
    iw, ih = 70 * sc, 55 * sc
    d.ellipse([cx - iw, cy - ih + 20 * sc, cx + iw, cy + ih + 20 * sc], fill=(0, 0, 0, 0))
    d.rectangle([0, cy + 60 * sc, s, s], fill=(0, 0, 0, 0))
    # Runway floor line
    d.line([(cx - 105 * sc, cy + 60 * sc), (cx + 105 * sc, cy + 60 * sc)], fill=(255, 255, 255, 255), width=10 * sc)
    return finalize(img, 256)

def icon_map():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2
    # Folded map (3 panels)
    pts = [
        (cx - 85 * sc, cy - 65 * sc), (cx - 25 * sc, cy - 85 * sc), (cx + 35 * sc, cy - 65 * sc), (cx + 85 * sc, cy - 85 * sc),
        (cx + 85 * sc, cy + 65 * sc), (cx + 35 * sc, cy + 85 * sc), (cx - 25 * sc, cy + 65 * sc), (cx - 85 * sc, cy + 85 * sc)
    ]
    # Panel 1
    d.polygon([pts[0], pts[1], pts[6], pts[7]], fill=(240, 240, 240, 255))
    # Panel 2 (slightly darker for fold effect)
    d.polygon([pts[1], pts[2], pts[5], pts[6]], fill=(190, 190, 190, 255))
    # Panel 3
    d.polygon([pts[2], pts[3], pts[4], pts[5]], fill=(255, 255, 255, 255))
    return finalize(img, 256)

def icon_play():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2
    pts = [(cx - 50 * sc, cy - 75 * sc), (cx + 65 * sc, cy), (cx - 50 * sc, cy + 75 * sc)]
    d.polygon(pts, fill=(255, 255, 255, 255))
    return finalize(img, 256)

def icon_pause():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2
    w, h = 24 * sc, 130 * sc
    d.rounded_rectangle([cx - 45 * sc - w/2, cy - h/2, cx - 45 * sc + w/2, cy + h/2], radius=6*sc, fill=(255, 255, 255, 255))
    d.rounded_rectangle([cx + 45 * sc - w/2, cy - h/2, cx + 45 * sc + w/2, cy + h/2], radius=6*sc, fill=(255, 255, 255, 255))
    return finalize(img, 256)

def icon_missile():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2
    # Missile angled 45 degrees
    # We draw vertical then rotate
    m_img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    md = ImageDraw.Draw(m_img)
    # Nose cone
    md.polygon([(cx, cy - 95 * sc), (cx - 16 * sc, cy - 50 * sc), (cx + 16 * sc, cy - 50 * sc)], fill=(255, 255, 255, 255))
    # Body
    md.rectangle([cx - 16 * sc, cy - 50 * sc, cx + 16 * sc, cy + 65 * sc], fill=(255, 255, 255, 255))
    # Fins front
    md.polygon([(cx - 36 * sc, cy - 25 * sc), (cx - 16 * sc, cy - 38 * sc), (cx - 16 * sc, cy - 15 * sc)], fill=(255, 255, 255, 255))
    md.polygon([(cx + 36 * sc, cy - 25 * sc), (cx + 16 * sc, cy - 38 * sc), (cx + 16 * sc, cy - 15 * sc)], fill=(255, 255, 255, 255))
    # Fins rear
    md.polygon([(cx - 48 * sc, cy + 70 * sc), (cx - 16 * sc, cy + 40 * sc), (cx - 16 * sc, cy + 68 * sc)], fill=(255, 255, 255, 255))
    md.polygon([(cx + 48 * sc, cy + 70 * sc), (cx + 16 * sc, cy + 40 * sc), (cx + 16 * sc, cy + 68 * sc)], fill=(255, 255, 255, 255))
    # Rotate 45 deg
    rotated = m_img.rotate(45, resample=Image.Resampling.BICUBIC)
    return finalize(rotated, 256)

def icon_bomb():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2
    b_img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    bd = ImageDraw.Draw(b_img)
    # Tear-drop bomb body
    bd.ellipse([cx - 32 * sc, cy - 75 * sc, cx + 32 * sc, cy + 30 * sc], fill=(255, 255, 255, 255))
    # Tail assembly
    bd.rectangle([cx - 15 * sc, cy + 20 * sc, cx + 15 * sc, cy + 60 * sc], fill=(255, 255, 255, 255))
    # Tail fins
    bd.polygon([(cx - 45 * sc, cy + 70 * sc), (cx - 12 * sc, cy + 25 * sc), (cx - 12 * sc, cy + 65 * sc)], fill=(255, 255, 255, 255))
    bd.polygon([(cx + 45 * sc, cy + 70 * sc), (cx + 12 * sc, cy + 25 * sc), (cx + 12 * sc, cy + 65 * sc)], fill=(255, 255, 255, 255))
    bd.rectangle([cx - 35 * sc, cy + 62 * sc, cx + 35 * sc, cy + 70 * sc], fill=(255, 255, 255, 255))
    rotated = b_img.rotate(45, resample=Image.Resampling.BICUBIC)
    return finalize(rotated, 256)

def icon_gun():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2
    # Crosshair with gun barrels
    d.ellipse([cx - 75 * sc, cy - 75 * sc, cx + 75 * sc, cy + 75 * sc], outline=(255, 255, 255, 255), width=10 * sc)
    d.line([(cx - 95 * sc, cy), (cx - 40 * sc, cy)], fill=(255, 255, 255, 255), width=10 * sc)
    d.line([(cx + 40 * sc, cy), (cx + 95 * sc, cy)], fill=(255, 255, 255, 255), width=10 * sc)
    d.line([(cx, cy - 95 * sc), (cx, cy - 40 * sc)], fill=(255, 255, 255, 255), width=10 * sc)
    d.line([(cx, cy + 40 * sc), (cx, cy + 95 * sc)], fill=(255, 255, 255, 255), width=10 * sc)
    d.ellipse([cx - 14 * sc, cy - 14 * sc, cx + 14 * sc, cy + 14 * sc], fill=(255, 255, 255, 255))
    return finalize(img, 256)

def icon_flare():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2
    # Spark / burst rays
    num_rays = 8
    for i in range(num_rays):
        a = i * (2 * math.pi / num_rays)
        r_in = 30 * sc
        r_out = 90 * sc if i % 2 == 0 else 60 * sc
        x1, y1 = cx + r_in * math.cos(a), cy + r_in * math.sin(a)
        x2, y2 = cx + r_out * math.cos(a), cy + r_out * math.sin(a)
        d.line([(x1, y1), (x2, y2)], fill=(255, 255, 255, 255), width=10 * sc)
    d.ellipse([cx - 20 * sc, cy - 20 * sc, cx + 20 * sc, cy + 20 * sc], fill=(255, 255, 255, 255))
    return finalize(img, 256)

def icon_rocket():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2
    r_img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    rd = ImageDraw.Draw(r_img)
    # Conical nose
    rd.polygon([(cx, cy - 95 * sc), (cx - 14 * sc, cy - 50 * sc), (cx + 14 * sc, cy - 50 * sc)], fill=(255, 255, 255, 255))
    # Body
    rd.rectangle([cx - 14 * sc, cy - 50 * sc, cx + 14 * sc, cy + 40 * sc], fill=(255, 255, 255, 255))
    # Fins
    rd.polygon([(cx - 38 * sc, cy + 42 * sc), (cx - 14 * sc, cy + 10 * sc), (cx - 14 * sc, cy + 40 * sc)], fill=(255, 255, 255, 255))
    rd.polygon([(cx + 38 * sc, cy + 42 * sc), (cx + 14 * sc, cy + 10 * sc), (cx + 14 * sc, cy + 40 * sc)], fill=(255, 255, 255, 255))
    # Exhaust flame
    rd.polygon([(cx - 10 * sc, cy + 42 * sc), (cx, cy + 90 * sc), (cx + 10 * sc, cy + 42 * sc)], fill=(255, 255, 255, 255))
    rotated = r_img.rotate(45, resample=Image.Resampling.BICUBIC)
    return finalize(rotated, 256)

def icon_radar():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2
    # Concentric radar rings and sweep line
    d.ellipse([cx - 85 * sc, cy - 85 * sc, cx + 85 * sc, cy + 85 * sc], outline=(255, 255, 255, 255), width=8 * sc)
    d.ellipse([cx - 50 * sc, cy - 50 * sc, cx + 50 * sc, cy + 50 * sc], outline=(255, 255, 255, 255), width=8 * sc)
    d.ellipse([cx - 12 * sc, cy - 12 * sc, cx + 12 * sc, cy + 12 * sc], fill=(255, 255, 255, 255))
    # Sweep line 45 deg
    d.line([(cx, cy), (cx + 60 * sc, cy - 60 * sc)], fill=(255, 255, 255, 255), width=10 * sc)
    # Cross hairs
    d.line([(cx - 85 * sc, cy), (cx + 85 * sc, cy)], fill=(255, 255, 255, 255), width=4 * sc)
    d.line([(cx, cy - 85 * sc), (cx, cy + 85 * sc)], fill=(255, 255, 255, 255), width=4 * sc)
    return finalize(img, 256)

def icon_fuel():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2 + 5 * sc
    # Fuel droplet
    pts = [(cx, cy - 80 * sc), (cx + 55 * sc, cy + 10 * sc), (cx, cy + 75 * sc), (cx - 55 * sc, cy + 10 * sc)]
    d.polygon(pts, fill=(255, 255, 255, 255))
    d.ellipse([cx - 55 * sc, cy - 10 * sc, cx + 55 * sc, cy + 75 * sc], fill=(255, 255, 255, 255))
    return finalize(img, 256)

def icon_gear():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2
    # Landing gear strut and wheel
    d.rounded_rectangle([cx - 10 * sc, cy - 85 * sc, cx + 10 * sc, cy + 20 * sc], radius=5*sc, fill=(255, 255, 255, 255))
    # Wheel hub & tire
    d.ellipse([cx - 50 * sc, cy, cx + 50 * sc, cy + 85 * sc], fill=(255, 255, 255, 255))
    d.ellipse([cx - 20 * sc, cy + 25 * sc, cx + 20 * sc, cy + 60 * sc], fill=(0, 0, 0, 0))
    # Support strut
    d.line([(cx - 40 * sc, cy - 40 * sc), (cx, cy - 10 * sc)], fill=(255, 255, 255, 255), width=10 * sc)
    return finalize(img, 256)

def icon_camera():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2 + 5 * sc
    # Camera body
    d.rounded_rectangle([cx - 80 * sc, cy - 45 * sc, cx + 80 * sc, cy + 65 * sc], radius=15*sc, fill=(255, 255, 255, 255))
    # Top prism
    d.polygon([(cx - 35 * sc, cy - 45 * sc), (cx - 22 * sc, cy - 72 * sc), (cx + 22 * sc, cy - 72 * sc), (cx + 35 * sc, cy - 45 * sc)], fill=(255, 255, 255, 255))
    # Lens
    d.ellipse([cx - 40 * sc, cy - 30 * sc, cx + 40 * sc, cy + 50 * sc], fill=(0, 0, 0, 0))
    d.ellipse([cx - 25 * sc, cy - 15 * sc, cx + 25 * sc, cy + 35 * sc], fill=(255, 255, 255, 255))
    return finalize(img, 256)

def icon_trophy():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2
    # Cup body
    d.polygon([(cx - 50 * sc, cy - 75 * sc), (cx + 50 * sc, cy - 75 * sc), (cx + 35 * sc, cy + 10 * sc), (cx - 35 * sc, cy + 10 * sc)], fill=(255, 255, 255, 255))
    d.ellipse([cx - 35 * sc, cy - 5 * sc, cx + 35 * sc, cy + 25 * sc], fill=(255, 255, 255, 255))
    # Stem
    d.rectangle([cx - 10 * sc, cy + 20 * sc, cx + 10 * sc, cy + 55 * sc], fill=(255, 255, 255, 255))
    # Base
    d.polygon([(cx - 45 * sc, cy + 75 * sc), (cx + 45 * sc, cy + 75 * sc), (cx + 30 * sc, cy + 55 * sc), (cx - 30 * sc, cy + 55 * sc)], fill=(255, 255, 255, 255))
    # Handles
    d.arc([cx - 75 * sc, cy - 70 * sc, cx - 35 * sc, cy - 10 * sc], start=90, end=270, fill=(255, 255, 255, 255), width=8 * sc)
    d.arc([cx + 35 * sc, cy - 70 * sc, cx + 75 * sc, cy - 10 * sc], start=270, end=90, fill=(255, 255, 255, 255), width=8 * sc)
    return finalize(img, 256)

def icon_credits():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2
    # ID / badge / profile card
    d.rounded_rectangle([cx - 70 * sc, cy - 80 * sc, cx + 70 * sc, cy + 80 * sc], radius=15*sc, outline=(255, 255, 255, 255), width=10*sc)
    # User head
    d.ellipse([cx - 25 * sc, cy - 50 * sc, cx + 25 * sc, cy], fill=(255, 255, 255, 255))
    # User shoulders
    d.ellipse([cx - 45 * sc, cy + 15 * sc, cx + 45 * sc, cy + 65 * sc], fill=(255, 255, 255, 255))
    return finalize(img, 256)

def icon_lock():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2 + 10 * sc
    # Shackle
    d.arc([cx - 40 * sc, cy - 90 * sc, cx + 40 * sc, cy - 10 * sc], start=180, end=0, fill=(255, 255, 255, 255), width=16 * sc)
    # Body
    d.rounded_rectangle([cx - 55 * sc, cy - 20 * sc, cx + 55 * sc, cy + 65 * sc], radius=12*sc, fill=(255, 255, 255, 255))
    # Keyhole
    d.ellipse([cx - 10 * sc, cy + 5 * sc, cx + 10 * sc, cy + 25 * sc], fill=(0, 0, 0, 0))
    d.polygon([(cx - 6 * sc, cy + 20 * sc), (cx + 6 * sc, cy + 20 * sc), (cx + 9 * sc, cy + 45 * sc), (cx - 9 * sc, cy + 45 * sc)], fill=(0, 0, 0, 0))
    return finalize(img, 256)

def icon_back():
    img, d, s, sc = create_canvas(256)
    cx, cy = s / 2, s / 2
    # Left arrow
    pts = [(cx - 20 * sc, cy - 65 * sc), (cx - 75 * sc, cy), (cx - 20 * sc, cy + 65 * sc)]
    d.polygon(pts, fill=(255, 255, 255, 255))
    d.rectangle([cx - 30 * sc, cy - 20 * sc, cx + 65 * sc, cy + 20 * sc], fill=(255, 255, 255, 255))
    return finalize(img, 256)

# ----------------- HUD SYMBOLS (128x128, Green #3CFF6A on Transparent) -----------------

HUD_COLOR = (60, 255, 106, 255)

def hud_rwr_threat_air():
    img, d, s, sc = create_canvas(128)
    cx, cy = s / 2, s / 2
    # Triangle/chevron pointing up with 'A'
    pts = [(cx, cy - 45 * sc), (cx - 40 * sc, cy + 35 * sc), (cx + 40 * sc, cy + 35 * sc)]
    d.polygon(pts, outline=HUD_COLOR, width=6 * sc)
    # 'A' inside
    d.line([(cx, cy - 15 * sc), (cx - 15 * sc, cy + 20 * sc)], fill=HUD_COLOR, width=4 * sc)
    d.line([(cx, cy - 15 * sc), (cx + 15 * sc, cy + 20 * sc)], fill=HUD_COLOR, width=4 * sc)
    d.line([(cx - 9 * sc, cy + 5 * sc), (cx + 9 * sc, cy + 5 * sc)], fill=HUD_COLOR, width=4 * sc)
    return finalize(img, 128)

def hud_rwr_threat_sam():
    img, d, s, sc = create_canvas(128)
    cx, cy = s / 2, s / 2
    # Hexagon outline
    r = 44 * sc
    pts = [(cx + r * math.cos(i * math.pi / 3), cy + r * math.sin(i * math.pi / 3)) for i in range(6)]
    d.polygon(pts, outline=HUD_COLOR, width=6 * sc)
    # 'S' inside
    d.line([(cx + 15 * sc, cy - 20 * sc), (cx - 15 * sc, cy - 20 * sc), (cx - 15 * sc, cy), (cx + 15 * sc, cy), (cx + 15 * sc, cy + 20 * sc), (cx - 15 * sc, cy + 20 * sc)], fill=HUD_COLOR, width=5 * sc)
    return finalize(img, 128)

def hud_target_box():
    img, d, s, sc = create_canvas(128)
    cx, cy = s / 2, s / 2
    # Segmented square bracket corners
    b = 40 * sc
    arm = 18 * sc
    w = 6 * sc
    # Top-Left
    d.line([(cx - b, cy - b), (cx - b + arm, cy - b)], fill=HUD_COLOR, width=w)
    d.line([(cx - b, cy - b), (cx - b, cy - b + arm)], fill=HUD_COLOR, width=w)
    # Top-Right
    d.line([(cx + b, cy - b), (cx + b - arm, cy - b)], fill=HUD_COLOR, width=w)
    d.line([(cx + b, cy - b), (cx + b, cy - b + arm)], fill=HUD_COLOR, width=w)
    # Bottom-Left
    d.line([(cx - b, cy + b), (cx - b + arm, cy + b)], fill=HUD_COLOR, width=w)
    d.line([(cx - b, cy + b), (cx - b, cy + b - arm)], fill=HUD_COLOR, width=w)
    # Bottom-Right
    d.line([(cx + b, cy + b), (cx + b - arm, cy + b)], fill=HUD_COLOR, width=w)
    d.line([(cx + b, cy + b), (cx + b, cy + b - arm)], fill=HUD_COLOR, width=w)
    # Center dot
    d.ellipse([cx - 3 * sc, cy - 3 * sc, cx + 3 * sc, cy + 3 * sc], fill=HUD_COLOR)
    return finalize(img, 128)

def hud_lock_diamond():
    img, d, s, sc = create_canvas(128)
    cx, cy = s / 2, s / 2
    r = 42 * sc
    pts = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
    d.polygon(pts, outline=HUD_COLOR, width=6 * sc)
    # Crosshair tick marks
    d.line([(cx, cy - 12 * sc), (cx, cy + 12 * sc)], fill=HUD_COLOR, width=4 * sc)
    d.line([(cx - 12 * sc, cy), (cx + 12 * sc, cy)], fill=HUD_COLOR, width=4 * sc)
    return finalize(img, 128)

def hud_missile_warning():
    img, d, s, sc = create_canvas(128)
    cx, cy = s / 2, s / 2
    # Inverted hazard triangle
    pts = [(cx - 45 * sc, cy - 38 * sc), (cx + 45 * sc, cy - 38 * sc), (cx, cy + 42 * sc)]
    d.polygon(pts, outline=HUD_COLOR, width=6 * sc)
    # Exclamation mark
    d.line([(cx, cy - 25 * sc), (cx, cy + 8 * sc)], fill=HUD_COLOR, width=6 * sc)
    d.ellipse([cx - 4 * sc, cy + 18 * sc, cx + 4 * sc, cy + 26 * sc], fill=HUD_COLOR)
    return finalize(img, 128)


def generate_all(base_dir="game/assets/ui"):
    icons = {
        "settings": icon_settings,
        "radio": icon_radio,
        "hangar": icon_hangar,
        "map": icon_map,
        "play": icon_play,
        "pause": icon_pause,
        "missile": icon_missile,
        "bomb": icon_bomb,
        "gun": icon_gun,
        "flare": icon_flare,
        "rocket": icon_rocket,
        "radar": icon_radar,
        "fuel": icon_fuel,
        "gear": icon_gear,
        "camera": icon_camera,
        "trophy": icon_trophy,
        "credits": icon_credits,
        "lock": icon_lock,
        "back": icon_back,
    }
    
    hud = {
        "rwr_threat_air": hud_rwr_threat_air,
        "rwr_threat_sam": hud_rwr_threat_sam,
        "target_box": hud_target_box,
        "lock_diamond": hud_lock_diamond,
        "missile_warning": hud_missile_warning,
    }

    icon_dir = os.path.join(base_dir, "icons")
    hud_dir = os.path.join(base_dir, "hud")
    os.makedirs(icon_dir, exist_ok=True)
    os.makedirs(hud_dir, exist_ok=True)

    print("Generating icons (256x256 transparent PNG)...")
    for name, fn in icons.items():
        out_path = os.path.join(icon_dir, f"{name}.png")
        img = fn()
        img.save(out_path, "PNG", optimize=True)
        print(f"  [x] {out_path}")

    print("Generating HUD symbols (128x128 transparent PNG)...")
    for name, fn in hud.items():
        out_path = os.path.join(hud_dir, f"{name}.png")
        img = fn()
        img.save(out_path, "PNG", optimize=True)
        print(f"  [x] {out_path}")

if __name__ == "__main__":
    generate_all()
