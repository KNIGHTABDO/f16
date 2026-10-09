#!/usr/bin/env python3
"""
resize_art.py - Resize and compress game art assets for Knight Wings.
Handles JPG (q85) for photos/cards/backgrounds and PNG (RGBA) for transparent sprites/icons/HUD.
"""

import argparse
import os
import sys
from PIL import Image, ImageOps

def resize_image(
    input_path: str,
    output_path: str,
    target_width: int,
    target_height: int,
    fmt: str = None,
    mode: str = "crop",  # "crop" (aspect fill & center crop), "contain" (aspect fit), "stretch"
    quality: int = 85
) -> None:
    """Resize an image to target dimensions and save with optimal compression."""
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    
    with Image.open(input_path) as img:
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
    args = parser.parse_args()

    resize_image(args.input, args.output, args.width, args.height, mode=args.mode, quality=args.quality)


if __name__ == "__main__":
    main()
