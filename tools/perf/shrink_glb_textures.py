#!/usr/bin/env python3
"""Shrink the embedded textures of GLB models for the iOS IPA.

    python3 tools/perf/shrink_glb_textures.py game/assets/models/aircraft/*/*.glb

Opaque images become JPEG (q85), images with real transparency stay PNG. Both are capped at 2048 px and only
replace the original when smaller. Buffer views that are not images are copied byte for byte, so accessors,
skins and animations do not change. Each file is re-parsed and checked before it replaces the original.
"""
import io
import json
import os
import struct
import sys

from PIL import Image

MAX_PX = 2048
JPEG_QUALITY = 85
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or length != len(data):
        raise ValueError("not a GLB v2 file")
    gltf, binary, off = None, b"", 12
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        body = data[off + 8 : off + 8 + clen]
        if ctype == JSON_CHUNK:
            gltf = json.loads(body.decode("utf-8"))
        elif ctype == BIN_CHUNK:
            binary = body
        off += 8 + clen
    if gltf is None:
        raise ValueError("no JSON chunk")
    return gltf, binary


def write_glb(path, gltf, binary):
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * (-len(js) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    out = struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<II", len(js), JSON_CHUNK) + js
    out += struct.pack("<II", len(binary), BIN_CHUNK) + binary
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(out)
    os.replace(tmp, path)


def view_bytes(binary, view):
    start = view.get("byteOffset", 0)
    return binary[start : start + view["byteLength"]]


def encode_image(raw):
    im = Image.open(io.BytesIO(raw))
    im.load()
    rgba = im.convert("RGBA") if (im.mode in ("RGBA", "LA", "PA") or "transparency" in im.info) else None
    has_alpha = rgba is not None and rgba.getchannel("A").getextrema()[0] < 255
    buf = io.BytesIO()
    if has_alpha:
        rgba.thumbnail((MAX_PX, MAX_PX), Image.LANCZOS)
        rgba.save(buf, "PNG", optimize=True)
        return buf.getvalue(), "image/png"
    rgb = im.convert("RGB")
    rgb.thumbnail((MAX_PX, MAX_PX), Image.LANCZOS)
    rgb.save(buf, "JPEG", quality=JPEG_QUALITY, optimize=True)
    return buf.getvalue(), "image/jpeg"


def shrink(path):
    gltf, binary = read_glb(path)
    buffers = gltf.get("buffers", [])
    if len(buffers) != 1 or "uri" in buffers[0] or not binary:
        raise ValueError("expects exactly one embedded buffer")
    views = gltf.get("bufferViews", [])
    original = [view_bytes(binary, v) for v in views]
    blobs = list(original)
    image_views = set()
    replaced = {}
    for img in gltf.get("images", []):
        if "bufferView" not in img:
            continue
        vid = img["bufferView"]
        image_views.add(vid)
        new, mime = encode_image(blobs[vid])
        if len(new) < len(blobs[vid]):
            blobs[vid] = new
            replaced[vid] = mime
            img["mimeType"] = mime
    out = bytearray()
    for v, blob in zip(views, blobs):
        out += b"\0" * (-len(out) % 4)
        v["byteOffset"] = len(out)
        v["byteLength"] = len(blob)
        out += blob
    buffers[0]["byteLength"] = len(out)
    write_glb(path, gltf, bytes(out))
    verify(path, original, image_views, replaced)


def verify(path, original, image_views, replaced):
    gltf, binary = read_glb(path)
    for i, v in enumerate(gltf["bufferViews"]):
        blob = view_bytes(binary, v)
        if i not in image_views:
            if blob != original[i]:
                raise ValueError("%s: buffer view %d changed" % (path, i))
            continue
        im = Image.open(io.BytesIO(blob))
        im.load()
        if i in replaced:
            if max(im.size) > MAX_PX or im.format != ("PNG" if replaced[i] == "image/png" else "JPEG"):
                raise ValueError("%s: replaced image %d is %s %s" % (path, i, im.format, im.size))


def main(paths):
    failed = 0
    for p in paths:
        before = os.path.getsize(p)
        try:
            shrink(p)
        except (ValueError, OSError) as e:
            print("FAILED %s: %s" % (p, e))
            failed += 1
            continue
        print("%s: %.2f -> %.2f MB" % (p, before / 1e6, os.path.getsize(p) / 1e6))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
