#!/usr/bin/env python3
"""
resize_art.py - Resize and compress game art assets for Knight Wings.
Handles JPG (q85) for photos/cards/backgrounds and PNG (RGBA) for transparent sprites/icons/HUD.
"""

import argparse
from collections import deque
import os
import sys
import numpy as np
from PIL import Image, ImageOps

def key_out_background(img: Image.Image, key_color: str = "auto") -> Image.Image:
    """Key out solid white or green background using border flood-fill to preserve interior features."""
    img = img.convert("RGBA")
    arr = np.array(img, dtype=np.float32)
    h, w = arr.shape[:2]

    # If image already has transparent background on corners, skip keying and just crop
    corner_alphas = [arr[0, 0, 3], arr[0, -1, 3], arr[-1, 0, 3], arr[-1, -1, 3]]
    if np.mean(corner_alphas) < 50:
        bbox = img.getbbox()
        if bbox:
            pad = 8
            b_x0 = max(0, bbox[0] - pad)
            b_y0 = max(0, bbox[1] - pad)
            b_x1 = min(w, bbox[2] + pad)
            b_y1 = min(h, bbox[3] + pad)
            return img.crop((b_x0, b_y0, b_x1, b_y1))
        return img

    # Sample corners to detect background color
    corners = [arr[0, 0, :3], arr[0, -1, :3], arr[-1, 0, :3], arr[-1, -1, :3]]
    avg_corner = np.mean(corners, axis=0)

    if key_color == "auto":
        r, g, b = avg_corner
        if g > 120 and g - r > 25 and g - b > 25:
            mode = "green"
        elif np.all(avg_corner > 210):
            mode = "white"
        else:
            mode = "corner"
    else:
        mode = key_color

    mask = np.zeros((h, w), dtype=bool)
    visited = np.zeros((h, w), dtype=bool)
    q = deque()

    rgb = arr[:, :, :3]
    if mode == "green":
        r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
        bg_match = (g > 105) & (g - r > 20) & (g - b > 20)
    elif mode == "white":
        bg_match = np.all(rgb > 215, axis=2)
    else:
        dist = np.linalg.norm(rgb - avg_corner, axis=2)
        bg_match = dist < 45.0

    for x in range(w):
        if bg_match[0, x]: q.append((0, x)); visited[0, x] = True; mask[0, x] = True
        if bg_match[h - 1, x]: q.append((h - 1, x)); visited[h - 1, x] = True; mask[h - 1, x] = True
    for y in range(h):
        if bg_match[y, 0]: q.append((y, 0)); visited[y, 0] = True; mask[y, 0] = True
        if bg_match[y, w - 1]: q.append((y, w - 1)); visited[y, w - 1] = True; mask[y, w - 1] = True

    while q:
        cy, cx = q.popleft()
        for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            ny, nx = cy + dy, cx + dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx]:
                visited[ny, nx] = True
                if bg_match[ny, nx]:
                    mask[ny, nx] = True
                    q.append((ny, nx))

    alpha = np.where(mask, 0, 255).astype(np.uint8)
    out = img.copy()
    out.putalpha(Image.fromarray(alpha))

    # Optional: tight crop to foreground bbox with margin
    bbox = out.getbbox()
    if bbox:
        # Add slight padding if within bounds
        pad = 8
        b_x0 = max(0, bbox[0] - pad)
        b_y0 = max(0, bbox[1] - pad)
        b_x1 = min(w, bbox[2] + pad)
        b_y1 = min(h, bbox[3] + pad)
        out = out.crop((b_x0, b_y0, b_x1, b_y1))

    return out

def resize_image(
    input_path: str,
    output_path: str,
    target_width: int,
    target_height: int,
    fmt: str = None,
    mode: str = "crop",  # "crop" (aspect fill & center crop), "contain" (aspect fit), "stretch"
    quality: int = 85,
    key_color: str = "none" # "none", "auto", "white", "green"
) -> None:
    """Resize an image to target dimensions and save with optimal compression."""
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    
    with Image.open(input_path) as raw_img:
        if key_color != "none":
            img = key_out_background(raw_img, key_color=key_color)
        else:
            img = raw_img.copy()

        target_size = (target_width, target_height)
        
        # Determine format if not specified
        if not fmt:
            ext = os.path.splitext(output_path)[1].lower()
            if ext in [".jpg", ".jpeg"]:
                fmt = "JPEG"
            elif ext == ".png":
                fmt = "PNG"
            else:
                fmt = "JPEG"

        if mode == "crop":
            # Aspect fill and center crop to exact dimensions
            if fmt == "JPEG" and img.mode in ("RGBA", "LA", "P"):
                # Convert to RGB with black background if transparent
                bg = Image.new("RGB", img.size, (10, 15, 25))
                if img.mode == "RGBA":
                    bg.paste(img, mask=img.split()[3])
                else:
                    bg.paste(img.convert("RGBA"))
                img = bg
            elif fmt == "PNG" and img.mode != "RGBA":
                img = img.convert("RGBA")
            
            resized = ImageOps.fit(img, target_size, method=Image.Resampling.LANCZOS, centering=(0.5, 0.5))
        elif mode == "contain":
            # Fit inside box maintaining aspect ratio, transparent or black padding
            img_ratio = img.width / img.height
            target_ratio = target_width / target_height
            
            if img_ratio > target_ratio:
                new_w = target_width
                new_h = int(target_width / img_ratio)
            else:
                new_h = target_height
                new_w = int(target_height * img_ratio)
                
            temp = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
            
            if fmt == "PNG":
                resized = Image.new("RGBA", target_size, (0, 0, 0, 0))
                paste_x = (target_width - new_w) // 2
                paste_y = (target_height - new_h) // 2
                resized.paste(temp, (paste_x, paste_y), temp if temp.mode == "RGBA" else None)
            else:
                resized = Image.new("RGB", target_size, (10, 15, 25))
                paste_x = (target_width - new_w) // 2
                paste_y = (target_height - new_h) // 2
                resized.paste(temp, (paste_x, paste_y))
        else: # stretch
            if fmt == "JPEG" and img.mode != "RGB":
                img = img.convert("RGB")
            elif fmt == "PNG" and img.mode != "RGBA":
                img = img.convert("RGBA")
            resized = img.resize(target_size, Image.Resampling.LANCZOS)
            
        if fmt == "JPEG":
            if resized.mode != "RGB":
                resized = resized.convert("RGB")
            resized.save(output_path, "JPEG", quality=quality, optimize=True, progressive=True)
        elif fmt == "PNG":
            if resized.mode != "RGBA":
                resized = resized.convert("RGBA")
            resized.save(output_path, "PNG", optimize=True)
            
        print(f"Processed: {input_path} -> {output_path} ({target_width}x{target_height}, {fmt})")


def main():
    parser = argparse.ArgumentParser(description="Resize and compress game art assets.")
    parser.add_argument("--input", "-i", required=True, help="Input image path")
    parser.add_argument("--output", "-o", required=True, help="Output image path")
    parser.add_argument("--width", "-W", type=int, required=True, help="Target width")
    parser.add_argument("--height", "-H", type=int, required=True, help="Target height")
    parser.add_argument("--mode", "-m", choices=["crop", "contain", "stretch"], default="crop", help="Fitting mode")
    parser.add_argument("--quality", "-q", type=int, default=85, help="JPEG quality (default 85)")
    parser.add_argument("--key", "-k", choices=["none", "auto", "white", "green"], default="none", help="Key out solid background")
    args = parser.parse_args()

    resize_image(args.input, args.output, args.width, args.height, mode=args.mode, quality=args.quality, key_color=args.key)


if __name__ == "__main__":
    main()
