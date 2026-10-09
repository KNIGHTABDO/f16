#!/usr/bin/env python3
"""
generate_liveries.py - Generates 1024x1024 tileable camouflage and paint pattern textures
for shader overlay on fighter aircraft models.
"""

import math
import os
import numpy as np
from PIL import Image

def generate_periodic_noise(width=1024, height=1024, octaves=6, seed=42):
    """Generate perfectly seamless periodic noise using 2D Fourier harmonic synthesis."""
    np.random.seed(seed)
    noise = np.zeros((height, width), dtype=np.float32)
    
    # Generate random periodic harmonics
    for octave in range(1, octaves + 1):
        freq = 2 ** (octave - 1)
        amp = 1.0 / (freq ** 0.8)
        num_components = 8 * freq
        
        for _ in range(num_components):
            kx = np.random.randint(-2 * freq, 2 * freq + 1)
            ky = np.random.randint(-2 * freq, 2 * freq + 1)
            if kx == 0 and ky == 0:
                continue
            phase = np.random.uniform(0, 2 * np.pi)
            weight = amp * np.random.uniform(0.5, 1.5)
            
            x = np.linspace(0, 2 * np.pi * kx, width, endpoint=False)
            y = np.linspace(0, 2 * np.pi * ky, height, endpoint=False)
            xv, yv = np.meshgrid(x, y)
            noise += weight * np.sin(xv + yv + phase)
            
    # Normalize to [0, 1]
    noise = (noise - noise.min()) / (noise.max() - noise.min() + 1e-6)
    return noise

def generate_splinter_pattern(width=1024, height=1024, num_polys=32, seed=123):
    """Generate seamless angular geometric splinter camouflage."""
    np.random.seed(seed)
    # Generate periodic points on torus
    num_pts = num_polys
    pts_x = np.random.uniform(0, width, num_pts)
    pts_y = np.random.uniform(0, height, num_pts)
    
    # 3-tone color indices
    colors = np.random.randint(0, 3, num_pts)
    
    # Compute nearest neighbor on periodic boundary
    x = np.arange(width)
    y = np.arange(height)
    xv, yv = np.meshgrid(x, y)
    
    min_dist = np.full((height, width), float('inf'), dtype=np.float32)
    pattern = np.zeros((height, width), dtype=np.int32)
    
    # Check periodic offsets [-width, 0, width]
    for ox in [-width, 0, width]:
        for oy in [-height, 0, height]:
            for i in range(num_pts):
                px = pts_x[i] + ox
                py = pts_y[i] + oy
                # Anisotropic distance for sharp angular facets
                dx = (xv - px)
                dy = (yv - py)
                # Skew coordinates for sharp 45/60 degree splinter angles
                dist = np.abs(dx * 1.4 + dy * 0.8) + np.abs(dx * 0.8 - dy * 1.4)
                closer = dist < min_dist
                min_dist[closer] = dist[closer]
                pattern[closer] = colors[i]
                
    return pattern

def apply_palette(noise_or_pattern, palette, is_discrete=False):
    """
    Map noise or pattern array to RGB colors from palette.
    palette: list of RGB tuples e.g. [(r,g,b), ...]
    """
    h, w = noise_or_pattern.shape
    img_arr = np.zeros((h, w, 3), dtype=np.uint8)
    
    if is_discrete:
        for idx, col in enumerate(palette):
            mask = (noise_or_pattern == idx)
            img_arr[mask] = col
    else:
        # Quantize continuous noise into bands
        num_colors = len(palette)
        bands = np.clip((noise_or_pattern * num_colors).astype(int), 0, num_colors - 1)
        for idx, col in enumerate(palette):
            mask = (bands == idx)
            img_arr[mask] = col
            
    # Add subtle fine surface noise / grain for realism
    grain = (np.random.normal(0, 3, (h, w, 3))).astype(np.int16)
    blended = np.clip(img_arr.astype(np.int16) + grain, 0, 255).astype(np.uint8)
    return blended

def create_liveries(out_dir="game/assets/ui/liveries"):
    os.makedirs(out_dir, exist_ok=True)
    
    # 1. f16c: RMAF Grey & Desert Camo
    # RMAF Grey: Low-vis air-superiority grey and medium grey
    noise = generate_periodic_noise(seed=101)
    f16_rmaf = apply_palette(noise, [
        (140, 146, 154),  # Light tactical grey
        (95, 102, 112),   # Medium slate grey
        (65, 72, 82),     # Dark shadow grey
    ])
    
    # F-16 Desert Camo (Moroccan desert: sand, tan, reddish-brown)
    noise = generate_periodic_noise(seed=102)
    f16_desert = apply_palette(noise, [
        (214, 185, 140),  # Pale Sahara sand
        (175, 138, 92),   # Moroccan tan
        (120, 85, 55),    # Reddish earth brown
        (85, 60, 42),     # Dark arid rock
    ])
    
    # 2. ef2000: NATO Grey & Splinter
    noise = generate_periodic_noise(seed=201)
    ef2000_nato = apply_palette(noise, [
        (165, 172, 180),  # NATO airframe grey
        (125, 132, 142),  # Ghost grey
        (88, 94, 102),    # Charcoal grey
    ])
    
    # Eurofighter Splinter (Aggressor geometric)
    splinter = generate_splinter_pattern(num_polys=40, seed=202)
    ef2000_splinter = apply_palette(splinter, [
        (220, 225, 230),  # Arctic white-grey
        (120, 130, 145),  # Medium naval grey
        (45, 52, 62),     # Deep charcoal
    ], is_discrete=True)
    
    # 3. f35a: Stealth RAM & Aggressor
    # Stealth RAM (Geometric radar-absorbent coating facets)
    splinter = generate_splinter_pattern(num_polys=50, seed=301)
    f35_ram = apply_palette(splinter, [
        (68, 72, 78),     # Medium dark RAM coating
        (52, 55, 60),     # Dark slate RAM
        (40, 42, 46),     # Deep stealth black
    ], is_discrete=True)
    
    # F-35 Aggressor Splinter (Navy, slate, cyan-tinted grey)
    splinter = generate_splinter_pattern(num_polys=35, seed=302)
    f35_aggressor = apply_palette(splinter, [
        (170, 188, 200),  # Pale cyan-grey
        (80, 105, 130),   # Aggressor blue
        (35, 48, 68),     # Deep maritime navy
    ], is_discrete=True)
    
    # 4. mirage2000: Desert & Air Superiority
    noise = generate_periodic_noise(seed=401)
    mirage_desert = apply_palette(noise, [
        (225, 198, 150),  # Dune yellow
        (180, 142, 95),   # Ochre tan
        (135, 95, 62),    # Desert rock brown
    ])
    
    noise = generate_periodic_noise(seed=402)
    mirage_air = apply_palette(noise, [
        (160, 180, 198),  # French air-superiority sky blue
        (110, 132, 155),  # Medium horizon blue
        (75, 92, 110),    # Dark naval blue-grey
    ])
    
    # 5. rafale: Ocean Camo & Tiger Meet
    noise = generate_periodic_noise(seed=501)
    rafale_ocean = apply_palette(noise, [
        (145, 168, 185),  # Sea haze light grey
        (90, 115, 138),   # Atlantic navy
        (55, 75, 95),     # Deep ocean blue
        (35, 48, 65),     # Abyssal dark blue
    ])
    
    # Rafale Tiger Meet (Amber gold, bold tiger stripes on dark charcoal)
    # Generate tiger stripe noise by stretching periodic coordinates horizontally
    np.random.seed(502)
    x = np.linspace(0, 8 * np.pi, 1024, endpoint=False)
    y = np.linspace(0, 32 * np.pi, 1024, endpoint=False)
    xv, yv = np.meshgrid(x, y)
    tiger_noise = np.sin(yv + 2.5 * np.sin(xv)) + 0.5 * np.cos(2 * yv + xv)
    tiger_noise = (tiger_noise - tiger_noise.min()) / (tiger_noise.max() - tiger_noise.min())
    rafale_tiger = apply_palette(tiger_noise, [
        (35, 36, 40),     # Carbon black
        (65, 60, 50),     # Dark umber
        (190, 140, 50),   # Warm amber gold
        (235, 180, 60),   # Vibrant tiger yellow
    ])
    
    liveries = {
        "f16c_rmaf_grey.jpg": f16_rmaf,
        "f16c_desert_camo.jpg": f16_desert,
        "ef2000_nato_grey.jpg": ef2000_nato,
        "ef2000_splinter.jpg": ef2000_splinter,
        "f35a_stealth_ram.jpg": f35_ram,
        "f35a_aggressor.jpg": f35_aggressor,
        "mirage2000_desert.jpg": mirage_desert,
        "mirage2000_air_superiority.jpg": mirage_air,
        "rafale_ocean_camo.jpg": rafale_ocean,
        "rafale_tiger_meet.jpg": rafale_tiger,
    }
    
    print("Writing 1024x1024 tileable livery textures...")
    for filename, arr in liveries.items():
        img = Image.fromarray(arr)
        out_path = os.path.join(out_dir, filename)
        img.save(out_path, "JPEG", quality=85, optimize=True)
        print(f"  [x] {out_path} (1024x1024)")

if __name__ == "__main__":
    create_liveries()
