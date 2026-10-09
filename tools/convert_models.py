#!/usr/bin/env python3
"""Knight Wings model converter: FlightGear AC3D (+ FG model XML) -> binary glTF (.glb) for Godot 4.

Runs inside Blender 4.0 headless, one model per process:

    blender -b -P tools/convert_models.py -- --id f16c              # convert, write .glb and the model_info.json entry
    blender -b -P tools/convert_models.py -- --id f16c --inspect    # print the AC3D tree, animations, bboxes; write nothing

Recipes (sources, part rules, hinges, fit length) live in tools/models.json.
Output frame: Godot (+X right wing, +Y up, -Z nose), meters, origin per recipe.

Coordinate chain: AC3D raw -> `remap` (AC3D -> Godot axes) -> `scale` -> origin shift.
FlightGear body frame (XML offsets, animation centers/axes): x aft, y right, z up -> `body_remap`.
"""
import bpy
import json
import math
import os
import re
import sys
import xml.etree.ElementTree as ET

# ---------------------------------------------------------------- paths / args

ROOT = os.environ.get("KW_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS_JSON = os.path.join(ROOT, "tools", "models.json")
MODEL_INFO = os.path.join(ROOT, "game", "data", "model_info.json")
TEX_CACHE = os.path.join(ROOT, "tools", "cache", "models", "tex")

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg_value(name, default=None):
    if name in ARGV:
        return ARGV[ARGV.index(name) + 1]
    return default


MODEL_ID = arg_value("--id")
INSPECT = "--inspect" in ARGV
if not MODEL_ID:
    sys.exit("usage: blender -b -P tools/convert_models.py -- --id <model id> [--inspect]")

# ---------------------------------------------------------------- tunables

METALLIC_AIRFRAME = 0.25
ROUGHNESS_AIRFRAME = 0.5
METALLIC_GLASS = 0.0
ROUGHNESS_GLASS = 0.05
GLASS_ALPHA = 0.3
SMOOTH_ANGLE_DEG = 35.0
DEFAULT_MAX_TEX = 2048
DEFAULT_MAX_TRIS = 60000
DEFAULT_GLASS_RE = r"canopy|glass|window|windscreen"

# ---------------------------------------------------------------- small 3x3 / affine math (row-major tuples)

I3 = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)


def m3mul(a, b):
    return tuple(sum(a[3 * i + k] * b[3 * k + j] for k in range(3)) for i in range(3) for j in range(3))


def m3vec(a, v):
    return (a[0] * v[0] + a[1] * v[1] + a[2] * v[2],
            a[3] * v[0] + a[4] * v[1] + a[5] * v[2],
            a[6] * v[0] + a[7] * v[1] + a[8] * v[2])


def m3t(a):
    return tuple(a[3 * j + i] for i in range(3) for j in range(3))


def fg_rot(kind, deg):
    """Body-frame rotation (x aft, y right, z up) for an FG <offsets> angle, in FG's sense:
    roll right-wing-down, pitch nose-up, heading clockwise seen from above."""
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    if kind == "roll":
        return (1.0, 0.0, 0.0, 0.0, c, s, 0.0, -s, c)
    if kind == "pitch":
        return (c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c)
    if kind == "heading":
        return (c, s, 0.0, -s, c, 0.0, 0.0, 0.0, 1.0)
    sys.exit("unknown rotation kind: %s" % kind)


def vadd(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vsub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vscale(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def vlen(a):
    return math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


def vnorm(a):
    l = vlen(a)
    return (a[0] / l, a[1] / l, a[2] / l) if l > 1e-12 else (0.0, 0.0, 0.0)


def det3(m):
    return (m[0] * (m[4] * m[8] - m[5] * m[7])
            - m[1] * (m[3] * m[8] - m[5] * m[6])
            + m[2] * (m[3] * m[7] - m[4] * m[6]))


def parse_remap(spec):
    """['+y', '+z', '+x'] -> row-major 3x3: godot_x = +y, godot_y = +z, godot_z = +x."""
    out = []
    for s in spec:
        sign = -1.0 if s.startswith("-") else 1.0
        axis = {"x": 0, "y": 1, "z": 2}[s.lstrip("+-").lower()]
        row = [0.0, 0.0, 0.0]
        row[axis] = sign
        out.extend(row)
    m = tuple(out)
    assert abs(abs(det3(m)) - 1.0) < 1e-9, "remap must be a signed permutation"
    assert det3(m) > 0, "remap must keep handedness (det +1), or the mesh is inside out: %s" % (spec,)
    return m


def to_blender(g):
    """Godot (x, y, z) -> Blender (x, -z, y) so that export_yup=True lands back on Godot axes."""
    return (g[0], -g[2], g[1])


# ---------------------------------------------------------------- AC3D parser

TOKEN_RE = re.compile(r'"([^"]*)"|(\S+)')


def tokens(line):
    return [m.group(1) if m.group(1) is not None else m.group(2) for m in TOKEN_RE.finditer(line)]


def to_int(s):
    try:
        return int(s, 0)
    except ValueError:
        return int(s)


MAT_KEYS = ("rgb", "amb", "emis", "spec", "shi", "trans")


def parse_material(t):
    m = {"name": "", "rgb": (1.0, 1.0, 1.0), "shi": 0.0, "trans": 0.0}
    i = 1
    if i < len(t) and t[i] not in MAT_KEYS:
        m["name"] = t[i]
        i += 1
    while i < len(t):
        k = t[i]
        if k in ("rgb", "amb", "emis", "spec") and i + 3 < len(t):
            vals = tuple(float(x) for x in t[i + 1:i + 4])
            if k == "rgb":
                m["rgb"] = vals
            i += 4
        elif k in ("shi", "trans") and i + 1 < len(t):
            m[k] = float(t[i + 1])
            i += 2
        else:
            i += 1
    return m


class AC3DFile:
    """Minimal AC3D (AC3Db) reader: materials, object tree with vertices and surfaces."""

    def __init__(self, path):
        self.path = path
        with open(path, "rb") as f:
            self.lines = f.read().decode("latin-1").splitlines()
        if not self.lines or not self.lines[0].startswith("AC3D"):
            raise ValueError("not an AC3D file: %s" % path)
        self.pos = 1
        self.cur = 0
        self.materials = []
        self.roots = []
        while True:
            t = self._next()
            if t is None:
                break
            if not t:
                continue
            if t[0] == "MATERIAL":
                self.materials.append(parse_material(t))
            elif t[0] == "OBJECT":
                self.roots.append(self._object(t))

    def _next(self):
        while self.pos < len(self.lines):
            self.cur = self.pos
            s = self.lines[self.pos].strip()
            self.pos += 1
            if s:
                return tokens(s)
        return None

    def _object(self, t):
        obj = {"type": t[1] if len(t) > 1 else "world", "name": "", "tex": None,
               "rot": I3, "loc": (0.0, 0.0, 0.0), "verts": [], "surfs": [], "kids": []}
        while True:
            t = self._next()
            if t is None:
                break
            if not t:
                continue
            k = t[0]
            if k == "name":
                obj["name"] = t[1] if len(t) > 1 else ""
            elif k == "data":
                n = to_int(t[1])
                if n > 0:
                    self.pos += 1  # the data block is a single line in practice
            elif k == "texture":
                obj["tex"] = t[1] if len(t) > 1 else None
            elif k == "rot":
                obj["rot"] = tuple(float(x) for x in t[1:10])
            elif k == "loc":
                obj["loc"] = tuple(float(x) for x in t[1:4])
            elif k == "numvert":
                last_v = (0.0, 0.0, 0.0)
                for _ in range(to_int(t[1])):
                    v = self._next()
                    pt = (float(v[0]), float(v[1]), float(v[2]))
                    if max(abs(c) for c in pt) > 500.0:
                        pt = last_v
                    else:
                        last_v = pt
                    obj["verts"].append(pt)
            elif k == "numsurf":
                for _ in range(to_int(t[1])):
                    flags, mat, refs = 0, 0, []
                    while True:
                        s = self._next()
                        if s is None:
                            break
                        if s[0] == "SURF":
                            flags = to_int(s[1])
                        elif s[0] == "mat":
                            mat = to_int(s[1])
                        elif s[0] == "refs":
                            count = to_int(s[1])
                            break
                    for _ in range(count):
                        r = self._next()
                        refs.append((to_int(r[0]), float(r[1]), float(r[2])))
                    obj["surfs"].append((flags, mat, refs))
            elif k == "kids":
                for _ in range(to_int(t[1])):
                    h = self._next()
                    while h is not None and not h:
                        h = self._next()
                    if h is not None and h[0] == "OBJECT":
                        obj["kids"].append(self._object(h))
                return obj
            elif k == "OBJECT":
                self.pos = self.cur  # sibling without a kids line: rewind and let the caller read it
                return obj
        return obj


def flatten(obj, R, t, out, anc=()):
    """Walk the AC3D tree; append (obj, R_world, t_world, ancestor names nearest first) for every object (affine, AC3D raw frame)."""
    Rw = m3mul(R, obj["rot"])
    tw = vadd(m3vec(R, obj["loc"]), t)
    out.append((obj, Rw, tw, anc))
    for k in obj["kids"]:
        flatten(k, Rw, tw, out, (obj["name"] or "",) + anc)


# ---------------------------------------------------------------- FlightGear model XML

def xf(node, name, default=0.0):
    if node is None:
        return default
    v = node.findtext(name)
    if v in (None, ""):
        return default
    s = v.strip().replace(",", ".")
    try:
        return float(s)
    except ValueError:
        clean = re.sub(r"[^0-9eE\.\-+]", "", s)
        try:
            return float(clean)
        except ValueError:
            return default


def parse_animations(root):
    # FG groups: <animation><name>G</name><object-name>..</object-name></animation> (no type). An animation
    # that names a group moves all of its member objects.
    groups = {}
    for a in root.iter("animation"):
        gname = (a.findtext("name") or "").strip()
        if gname and a.find("type") is None:
            groups[gname] = [(o.text or "").strip() for o in a.findall("object-name")]
    anims = []
    for a in root.iter("animation"):
        objs = []
        for o in a.findall("object-name"):
            n = (o.text or "").strip()
            objs.extend(groups.get(n, [n]))
        # No <factor>: the degrees come from the largest <interpolation> entry (e.g. gear retraction)
        factor = xf(a, "factor", None)
        if factor is None:
            deps = [xf(e, "dep", 0.0) for e in a.iter("entry")]
            factor = max(deps, key=abs) if deps else 1.0
        d = {
            "type": (a.findtext("type") or "").strip(),
            "objects": objs,
            "property": (a.findtext("property") or "").strip(),
            "factor": factor,
            "offset": xf(a, "offset-deg", 0.0),
            "axis": None,
            "center": None,
        }
        ax = a.find("axis")
        if ax is not None:
            if ax.find("x1-m") is not None:
                x1, y1, z1 = xf(ax, "x1-m"), xf(ax, "y1-m"), xf(ax, "z1-m")
                x2, y2, z2 = xf(ax, "x2-m"), xf(ax, "y2-m"), xf(ax, "z2-m")
                d["axis"] = (x2 - x1, y2 - y1, z2 - z1)
                if d["center"] is None:
                    d["center"] = (x1, y1, z1)
            else:
                d["axis"] = (xf(ax, "x"), xf(ax, "y"), xf(ax, "z"))
        ce = a.find("center")
        if ce is not None:
            d["center"] = (xf(ce, "x-m"), xf(ce, "y-m"), xf(ce, "z-m"))
        anims.append(d)
    return anims


def resolve_fg_path(base, rel):
    """FG model XML paths are relative to the FlightGear aircraft root ('Aircraft/f16/Models/x.ac'),
    so try the XML's own folder first, then the part after 'Models/', then a basename search."""
    rel = rel.strip()
    cand = os.path.join(base, rel)
    if os.path.exists(cand):
        return cand
    if "Models/" in rel:
        cand = os.path.join(SRC_ROOT, rel.split("Models/", 1)[1])
        if os.path.exists(cand):
            return cand
    found = find_by_basename(rel)
    if found is None:
        print("WARN unresolved FG path:", rel)
    return found or cand


def parse_xml_components(path, out, depth=0, include=None):
    """Return [(ac_path, body_offset, None)] for an FG model XML. Top level: the main <path> plus the
    <model> entries whose <name> is in `include`. Nested XMLs (depth > 0) contribute all their parts."""
    if path.lower().endswith(".ac"):
        out.append((path, (0.0, 0.0, 0.0), None))
        return out
    root = ET.parse(path).getroot()
    base = os.path.dirname(path)
    main = root.findtext("path")
    if main:
        out.append((resolve_fg_path(base, main), (0.0, 0.0, 0.0), root))
    for m in root.findall("model"):
        # Unnamed <model> entries (B-17 gun turrets) match on their file name instead
        name = (m.findtext("name") or "").strip() or os.path.splitext(os.path.basename(m.findtext("path") or ""))[0]
        if depth == 0 and (include is None or name not in include):
            continue
        p = m.findtext("path")
        if not p:
            continue
        off = m.find("offsets")
        body = (xf(off, "x-m"), xf(off, "y-m"), xf(off, "z-m"))
        if depth == 0 and name in OFFSET_OVERRIDES:
            body = tuple(float(c) for c in OFFSET_OVERRIDES[name])
        sub = resolve_fg_path(base, p)
        if not os.path.exists(sub):
            continue
        if sub.lower().endswith(".xml") and depth < 3:
            for ac, b, _ in parse_xml_components(sub, [], depth + 1):
                out.append((ac, vadd(body, b), None))
        else:
            out.append((sub, body, None))
    return out


# ---------------------------------------------------------------- recipe

with open(MODELS_JSON, "r", encoding="utf-8") as f:
    ALL_MODELS = json.load(f)["models"]
CFG = ALL_MODELS[MODEL_ID]
SRC_ROOT = os.path.join(ROOT, CFG["src"])
REMAP = parse_remap(CFG["remap"])
BODY_REMAP = parse_remap(CFG.get("body_remap", ["+y", "+z", "+x"]))
MAX_TEX = int(CFG.get("max_tex", DEFAULT_MAX_TEX))
MAX_TRIS = int(CFG.get("max_tris", DEFAULT_MAX_TRIS))
GLASS_RE = re.compile(CFG.get("glass", DEFAULT_GLASS_RE), re.I)
RULES = [(b, re.compile(rx, re.I)) for b, rx in CFG.get("rules", [])]
ANIM_FOR_BUCKET = CFG.get("anim", {})  # bucket -> FG animation object name providing the hinge
GEAR_BUCKET = CFG.get("gear_bucket", "gear")
ORIGIN_MODE = CFG.get("origin", "center")  # center | bottom | none
OFFSET_OVERRIDES = CFG.get("offset_overrides", {})  # top-level XML <model> name -> body offset
MANUAL_HINGES = CFG.get("hinges", {})  # bucket -> hinge (body frame) for animations not present in the XML

# ---------------------------------------------------------------- collect geometry

def find_file(rel):
    """Resolve a path from the recipe. Falls back to a basename search inside the source clone."""
    p = os.path.join(SRC_ROOT, rel)
    if os.path.exists(p):
        return p
    return None


def find_by_basename(name, cache={}):
    if not cache:
        for dp, _, fns in os.walk(SRC_ROOT):
            for fn in fns:
                cache.setdefault(fn.lower(), os.path.join(dp, fn))
    return cache.get(os.path.basename(name).lower())


entry = CFG["entry"]
entry_path = find_file(entry)
if entry_path is None:
    sys.exit("entry not found: %s (run tools/fetch_models.sh %s)" % (entry, MODEL_ID))

components = parse_xml_components(entry_path, [], 0, set(CFG.get("include_models", [])))
# Extra AC3D files placed at an explicit body-frame offset with a forced bucket (rotor discs whose XML nests
# blades with zero heading offsets, so the nested XML cannot place them). Optional "rot": [[kind, deg], ...]
# is applied in list order about the origin before the offset (a blade's heading, then its parent's pitch/roll)
FORCED_BUCKET = {}
for x in CFG.get("extra_ac", []):
    ac_abs = os.path.normpath(os.path.join(SRC_ROOT, x["path"]))
    Mb = I3
    for kind, deg in x.get("rot", []):
        Mb = m3mul(fg_rot(kind, float(deg)), Mb)
    Mg = m3mul(m3mul(BODY_REMAP, Mb), m3t(BODY_REMAP))  # body-frame rotation expressed in Godot frame
    components.append((ac_abs, tuple(float(c) for c in x["offset"]), Mg))
    FORCED_BUCKET[ac_abs] = x["bucket"]
ANIMS = []
if entry_path.lower().endswith(".xml"):
    ANIMS = parse_animations(ET.parse(entry_path).getroot())

geos = []        # one per AC3D poly object: dict(name, tex, verts (godot, unscaled), surfs, mats, src)
tex_paths = {}
for ac_rel, body_off, rot_g in components:
    ac_path = ac_rel
    if not os.path.exists(ac_path):
        alt = find_by_basename(ac_rel)
        if alt is None:
            print("WARN missing component", ac_rel)
            continue
        ac_path = alt
    ac = AC3DFile(ac_path)
    off_g = m3vec(BODY_REMAP, body_off)
    flat = []
    for r in ac.roots:
        flatten(r, I3, (0.0, 0.0, 0.0), flat)
    for obj, Rw, tw, anc in flat:
        if obj["type"] != "poly" or not obj["verts"] or not obj["surfs"]:
            continue
        Rg = m3mul(REMAP, Rw)
        tg = m3vec(REMAP, tw)
        if isinstance(rot_g, tuple):  # extra_ac rotation (3rd field is otherwise the XML root); applied before offset
            Rg = m3mul(rot_g, Rg)
            tg = m3vec(rot_g, tg)
        tg = vadd(tg, off_g)
        verts = [vadd(m3vec(Rg, v), tg) for v in obj["verts"]]
        geos.append({
            "name": obj["name"] or "obj%d" % len(geos),
            "anc": tuple(n for n in anc if n),
            "tex": obj["tex"],
            "verts": verts,
            "surfs": obj["surfs"],
            "mats": ac.materials,
            "src": ac_path,
        })

if not geos:
    sys.exit("no geometry found for %s" % MODEL_ID)


def bucket_of(name):
    for b, rx in RULES:
        if rx.search(name):
            return b
    return "airframe"


# drop_groups: regexes on AC3D ancestor names. Drops whole groups of generic-named polys (e.g. a cockpit
# interior whose parts are all called "object") that name rules cannot separate.
DROP_GROUP_RES = [re.compile(rx, re.I) for rx in CFG.get("drop_groups", [])]

for g in geos:
    dropped = any(rx.search(n) for n in g["anc"] for rx in DROP_GROUP_RES)
    g["bucket"] = FORCED_BUCKET.get(os.path.normpath(g["src"])) or ("_drop" if dropped else bucket_of(g["name"]))
live = [g for g in geos if not g["bucket"].startswith("_")]


def bbox(points):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    zs = [p[2] for p in points]
    return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


def all_points(gs):
    return [v for g in gs for v in g["verts"]]


# ---------------------------------------------------------------- scale and origin

lo, hi = bbox(all_points(live))
ext = vsub(hi, lo)
if "fit_length_m" in CFG:
    fit_axis = {"x": 0, "y": 1, "z": 2}[CFG.get("fit_axis", "z")]
    S = float(CFG["fit_length_m"]) / ext[fit_axis]
else:
    S = float(CFG.get("scale", 1.0))

# Apply scale to every vertex now, so the rest works in final (scaled, pre-shift) meters.
for g in geos:
    g["verts"] = [vscale(v, S) for v in g["verts"]]
live = [g for g in geos if not g["bucket"].startswith("_")]
lo, hi = bbox(all_points(live))
if ORIGIN_MODE == "center":
    SHIFT = vscale(vadd(lo, hi), -0.5)
elif ORIGIN_MODE == "bottom":
    SHIFT = (-(lo[0] + hi[0]) * 0.5, -lo[1], -(lo[2] + hi[2]) * 0.5)
else:
    SHIFT = (0.0, 0.0, 0.0)
print("[%s] origin SHIFT (Godot frame m, added to every vertex) = (%.3f, %.3f, %.3f)" % ((MODEL_ID,) + tuple(SHIFT)))
for g in geos:
    g["verts"] = [vadd(v, SHIFT) for v in g["verts"]]
live = [g for g in geos if not g["bucket"].startswith("_")]
lo, hi = bbox(all_points(live))
EXT = vsub(hi, lo)
print("[%s] scale S=%.5f  extents x(span)=%.3f y(height)=%.3f z(length)=%.3f" % (MODEL_ID, S, EXT[0], EXT[1], EXT[2]))


def hinge_for_name(name):
    """Hinge for the FG animation that moves AC3D object `name`: center, axis (positive input -> positive
    rotation about axis, right-hand rule, Godot frame), max_deg. None if the object is not animated."""
    cands = [a for a in ANIMS if name in a["objects"] and a["axis"] and a["center"] is not None]
    rot = [a for a in cands if a["type"] == "rotate"]
    pick = (rot or cands or [None])[0]
    if pick is None:
        return None
    c = vadd(vscale(m3vec(BODY_REMAP, pick["center"]), S), SHIFT)
    ax = vnorm(m3vec(BODY_REMAP, pick["axis"]))
    if pick["factor"] < 0:
        ax = vscale(ax, -1.0)
    return {"center": c, "axis": ax, "max_deg": round(abs(pick["factor"]), 2),
            "offset_deg": round(float(pick["offset"]), 2),
            "property": pick["property"], "anim": name, "type": pick["type"]}


def manual_hinge(key, gs=None):
    h = MANUAL_HINGES[key]
    ax = vnorm(m3vec(BODY_REMAP, tuple(h["axis"])))
    c0 = vadd(vscale(m3vec(BODY_REMAP, tuple(h["center"])), S), SHIFT)
    if gs:
        # Any point on the hinge line gives the same rotation; take the one nearest the surface
        # so the node origin sits inside the part.
        pts = all_points(gs)
        cen = tuple(sum(p[i] for p in pts) / len(pts) for i in range(3))
        t = sum((cen[i] - c0[i]) * ax[i] for i in range(3))
        c0 = vadd(c0, vscale(ax, t))
    return {"center": c0, "axis": ax, "max_deg": round(float(h["max_deg"]), 2),
            "property": h["property"], "anim": "manual", "type": "rotate", "rotor": bool(h.get("rotor"))}


def hinge_for_bucket(bucket, gs=None):
    if bucket in MANUAL_HINGES:
        return manual_hinge(bucket, gs)
    name = ANIM_FOR_BUCKET.get(bucket)
    if name is None:
        return None
    h = hinge_for_name(name)
    if h is None:
        print("WARN no animation for object '%s' (bucket %s)" % (name, bucket))
    return h


def gear_hinge(key, gs):
    return manual_hinge(key, gs) if key in MANUAL_HINGES else hinge_for_name(key)


def anim_key(g):
    """Nearest animated AC3D object that moves this geo: the poly itself, then its ancestors. None if static."""
    for n in (g["name"],) + g["anc"]:
        if n in MANUAL_HINGES or hinge_for_name(n) is not None:
            return n
    return None


def gear_groups(gs):
    """Gear geos grouped into one node per animated object, so a door's inside panel follows its parent's hinge.
    Static parts (no animation) share one node, gear_static, at the origin."""
    groups = {}
    for g in gs:
        groups.setdefault(anim_key(g) or "static", []).append(g)
    return sorted(groups.items())


# ---------------------------------------------------------------- inspect mode

if INSPECT:
    def show(obj, depth):
        if obj["type"] == "poly" and obj["verts"]:
            pts = obj["verts"]
            print("  " * depth + "poly %-28s v=%-6d s=%-6d tex=%s" % (
                obj["name"], len(pts), len(obj["surfs"]), obj["tex"]))
        else:
            print("  " * depth + "%s %s kids=%d" % (obj["type"], obj["name"], len(obj["kids"])))
        for k in obj["kids"]:
            show(k, depth + 1)
    print("components:")
    for ac_rel, off, _ in components:
        print("  ", ac_rel, "body_off", tuple(round(x, 3) for x in off))
    for ac_rel, off, _ in components:
        p = ac_rel if os.path.exists(ac_rel) else find_by_basename(ac_rel)
        if p is None:
            continue
        ac = AC3DFile(p)
        print("== %s  materials=%d" % (os.path.basename(p), len(ac.materials)))
        for r in ac.roots:
            show(r, 1)
    print("animations (body frame):")
    for a in ANIMS:
        print("  %-10s objs=%s prop=%s factor=%s off=%s axis=%s center=%s" % (
            a["type"], a["objects"], a["property"], a["factor"], a["offset"], a["axis"], a["center"]))
    print("remap %s  body_remap %s" % (REMAP, BODY_REMAP))
    print("bucket bboxes (final m):")
    by = {}
    for g in geos:
        by.setdefault(g["bucket"], []).append(g)
    for b, gs in sorted(by.items()):
        l, h = bbox(all_points(gs))
        print("  %-14s n=%-4d lo=(%.2f,%.2f,%.2f) hi=(%.2f,%.2f,%.2f)" % (
            b, len(gs), l[0], l[1], l[2], h[0], h[1], h[2]))
    print("resolved hinges (final m):")
    for b in sorted(ANIM_FOR_BUCKET):
        h = hinge_for_bucket(b, by.get(b))
        if h:
            print("  %-14s %-8s center=(%.2f,%.2f,%.2f) axis=(%.2f,%.2f,%.2f) max=%s prop=%s" % (
                b, h["type"], h["center"][0], h["center"][1], h["center"][2], h["axis"][0], h["axis"][1],
                h["axis"][2], h["max_deg"], h["property"]))
    for key, parts in gear_groups([g for g in geos if g["bucket"] == GEAR_BUCKET]):
        h = gear_hinge(key, parts)
        if h:
            print("  %-14s %-8s center=(%.2f,%.2f,%.2f) axis=(%.2f,%.2f,%.2f) max=%s prop=%s" % (
                key, h["type"], h["center"][0], h["center"][1], h["center"][2], h["axis"][0],
                h["axis"][1], h["axis"][2], h["max_deg"], h["property"]))
    print("objects matching --objs (final m):")
    for g in geos:
        if re.search(arg_value("--objs", "^$"), g["name"], re.I):
            l, h = bbox(g["verts"])
            print("  %-14s %-14s lo=(%.2f,%.2f,%.2f) hi=(%.2f,%.2f,%.2f)" % (
                g["name"], g["bucket"], l[0], l[1], l[2], h[0], h[1], h[2]))
    sys.exit(0)

# ---------------------------------------------------------------- Blender build

bpy.ops.wm.read_factory_settings(use_empty=True)
os.makedirs(TEX_CACHE + "/" + MODEL_ID, exist_ok=True)

IMAGES = {}
MATERIALS = {}


def load_image(rel_tex, src_file):
    """Find the texture, downscale to MAX_TEX, cache a re-encoded copy and return the bpy image."""
    if not rel_tex:
        return None
    cand = os.path.join(os.path.dirname(src_file), rel_tex)
    if not os.path.exists(cand):
        cand = find_by_basename(rel_tex)
    if cand is None or not os.path.exists(cand):
        print("WARN texture not found:", rel_tex)
        return None
    if cand in IMAGES:
        return IMAGES[cand]
    try:
        img = bpy.data.images.load(cand, check_existing=True)
    except RuntimeError:
        png = os.path.splitext(cand)[0] + ".png"
        if not os.path.exists(png):
            print("WARN cannot load texture:", cand)
            return None
        img = bpy.data.images.load(png, check_existing=True)
    try:
        # Blender can reject some valid files (e.g. SGI .rgb) with "does not have any image data"
        # only when the pixels are touched, so the whole decode/downscale/save runs guarded.
        w, h = img.size
        if w == 0 or h == 0:
            raise RuntimeError("no image data")
        if max(w, h) > MAX_TEX:
            k = MAX_TEX / float(max(w, h))
            img.scale(max(1, int(w * k)), max(1, int(h * k)))
        has_alpha = img.depth == 32 or img.channels == 4
        base = os.path.splitext(os.path.basename(cand))[0]
        out = os.path.join(TEX_CACHE, MODEL_ID, base + (".png" if has_alpha else ".jpg"))
        img.filepath_raw = out
        img.file_format = "PNG" if has_alpha else "JPEG"
        img.save()
        img.filepath = out
        img["has_alpha"] = bool(has_alpha)
    except RuntimeError as exc:
        print("WARN texture unusable, left untextured:", cand, exc)
        try:
            bpy.data.images.remove(img)
        except Exception:
            pass
        IMAGES[cand] = None
        return None
    IMAGES[cand] = img
    return img


def material_for(face_tex, face_src, mat, two_sided, glass):
    key = (face_tex, face_src, mat["rgb"], two_sided, glass)
    if key in MATERIALS:
        return MATERIALS[key]
    img = load_image(face_tex, face_src) if face_tex else None
    name = "%s_%d" % (os.path.splitext(os.path.basename(face_tex or "plain"))[0], len(MATERIALS))
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    rgb = mat["rgb"]
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Metallic"].default_value = METALLIC_GLASS if glass else METALLIC_AIRFRAME
    bsdf.inputs["Roughness"].default_value = ROUGHNESS_GLASS if glass else ROUGHNESS_AIRFRAME
    if img is not None:
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = img
        tn.location = (-500, 200)
        color_out = tn.outputs["Color"]
        if max(rgb) < 0.98 or min(rgb) < 0.98:
            mix = nt.nodes.new("ShaderNodeMixRGB")
            mix.blend_type = "MULTIPLY"
            mix.inputs["Fac"].default_value = 1.0
            mix.inputs[2].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
            mix.location = (-250, 200)
            nt.links.new(color_out, mix.inputs[1])
            color_out = mix.outputs[0]
        nt.links.new(color_out, bsdf.inputs["Base Color"])
        if glass:
            bsdf.inputs["Alpha"].default_value = GLASS_ALPHA
            m.blend_method = "BLEND"
        elif img["has_alpha"]:
            nt.links.new(tn.outputs["Alpha"], bsdf.inputs["Alpha"])
            m.blend_method = "CLIP"
            m.alpha_threshold = 0.5
    elif glass:
        bsdf.inputs["Alpha"].default_value = GLASS_ALPHA
        m.blend_method = "BLEND"
    m.use_backface_culling = not two_sided
    MATERIALS[key] = m
    return m


def face_list(g):
    """Triangulation-free faces: list of (indices, uvs, material key info, smooth) for a geo object."""
    out = []
    n = len(g["verts"])
    glass = bool(GLASS_RE.search(g["name"])) or g["bucket"] == "canopy"
    for flags, mi, refs in g["surfs"]:
        if (flags & 0xF) != 0 or len(refs) < 3:
            continue  # lines and closed lines are not surfaces
        idx = [r[0] for r in refs]
        if any(i < 0 or i >= n for i in idx) or len(set(idx)) != len(idx):
            continue
        mat = g["mats"][mi] if 0 <= mi < len(g["mats"]) else {"rgb": (1.0, 1.0, 1.0), "trans": 0.0}
        is_glass = glass or mat.get("trans", 0.0) >= 0.5
        two_sided = bool(flags & 0x10)
        out.append((idx, [(r[1], r[2]) for r in refs], g["tex"], g["src"], mat, two_sided, is_glass,
                    bool(flags & 0x20)))
    return out


def build_mesh(name, geo_list, origin):
    """Build one Blender mesh object from geo objects. Vertices are shifted by -origin, object placed at origin."""
    verts = []
    faces = []
    uvs = []
    mats = []
    smooth = []
    for g in geo_list:
        base = len(verts)
        verts.extend(vsub(v, origin) for v in g["verts"])
        for idx, uv, tex, src, mat, two_sided, is_glass, sm in face_list(g):
            faces.append([base + i for i in idx])
            uvs.append(uv)
            mats.append(material_for(tex, src, mat, two_sided, is_glass))
            smooth.append(sm)
    if not faces:
        return None
    me = bpy.data.meshes.new(name)
    me.from_pydata([to_blender(v) for v in verts], [], faces)
    me.update()
    assert len(me.polygons) == len(faces), "polygon count mismatch in %s" % name
    slot_of = {}
    for m in mats:
        if m.name not in slot_of:
            slot_of[m.name] = len(me.materials)
            me.materials.append(m)
    me.polygons.foreach_set("material_index", [slot_of[m.name] for m in mats])
    me.polygons.foreach_set("use_smooth", smooth)
    layer = me.uv_layers.new(name="UVMap")
    for poly, uv in zip(me.polygons, uvs):
        for j, (u, v) in enumerate(uv):
            layer.data[poly.loop_start + j].uv = (u, v)
    if any(smooth):
        try:
            me.use_auto_smooth = True
            me.auto_smooth_angle = math.radians(SMOOTH_ANGLE_DEG)
        except (AttributeError, TypeError):
            pass
    me.validate()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.location = to_blender(origin)
    return ob


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def sanitize(name):
    s = re.sub(r"[^A-Za-z0-9_]+", "_", name).strip("_")
    return s or "part"


# group geos by bucket
by_bucket = {}
for g in live:
    by_bucket.setdefault(g["bucket"], []).append(g)

built = {}
info_controls = {}
info_rotors = {}
gear_nodes = []
gear_parent = None
if GEAR_BUCKET in by_bucket:
    gear_parent = bpy.data.objects.new(GEAR_BUCKET, None)
    bpy.context.collection.objects.link(gear_parent)
    gear_parent.location = (0.0, 0.0, 0.0)

for bucket, gs in sorted(by_bucket.items()):
    if bucket == GEAR_BUCKET:
        # MANUAL_HINGES may override a gear node by its object name (FG's right-gear group has the left-side centre)
        for key, parts in gear_groups(gs):
            node = "gear_" + sanitize(key)
            hinge = gear_hinge(key, parts)
            origin = hinge["center"] if hinge else (0.0, 0.0, 0.0)
            ob = build_mesh(node, parts, origin)
            if ob is None:
                continue
            ob.parent = gear_parent  # gear_parent sits at the origin, so local == world
            gear_nodes.append(node)
            if hinge and hinge.get("type") == "spin":
                info_rotors[node] = hinge
            elif hinge:
                info_controls[node] = hinge
        continue
    hinge = hinge_for_bucket(bucket, gs) if (bucket in ANIM_FOR_BUCKET or bucket in MANUAL_HINGES) else None
    origin = hinge["center"] if hinge else (0.0, 0.0, 0.0)
    ob = build_mesh(bucket, gs, origin)
    if ob is None:
        print("WARN empty bucket", bucket)
        continue
    built[bucket] = ob
    if hinge and (hinge.get("rotor") or hinge.get("type") == "spin"):
        info_rotors[bucket] = hinge
    elif hinge:
        info_controls[bucket] = hinge

# ---------------------------------------------------------------- triangle budget

objs = [o for o in bpy.data.objects if o.type == "MESH"]
total = sum(tri_count(o) for o in objs)
print("triangles before decimation: %d (budget %d)" % (total, MAX_TRIS))
if total > MAX_TRIS:
    ratio = MAX_TRIS * 0.95 / total
    for o in objs:
        bpy.context.view_layer.objects.active = o
        mod = o.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = ratio
        bpy.ops.object.modifier_apply(modifier=mod.name)
    total = sum(tri_count(o) for o in objs)
    print("triangles after decimation (ratio %.3f): %d" % (ratio, total))

# ---------------------------------------------------------------- measured reference points (final coords)

def pts_of(names_re):
    rx = re.compile(names_re, re.I)
    out = []
    for g in live:
        if rx.search(g["name"]) or rx.search(g["bucket"]):
            out.extend(g["verts"])
    return out


info = {"source": CFG.get("source", ""), "license": CFG.get("license", ""),
        "scale_fix": round(S, 6), "origin": ORIGIN_MODE,
        "size_m": {"span": round(EXT[0], 3), "height": round(EXT[1], 3), "length": round(EXT[2], 3)}}

if "cockpit" in CFG:
    cp = pts_of(CFG["cockpit"])
    if cp:
        cx = sum(p[0] for p in cp) / len(cp)
        cy = sum(p[1] for p in cp) / len(cp)
        cz = sum(p[2] for p in cp) / len(cp)
        info["cockpit_eye"] = [0.0, round(cy, 3), round(cz, 3)]

if "wing" in CFG:
    wp = pts_of(CFG["wing"])
    if wp:
        left = min(wp, key=lambda p: p[0])
        right = max(wp, key=lambda p: p[0])
        info["wingtips"] = [[round(c, 3) for c in left], [round(c, 3) for c in right]]

if "nozzle" in CFG:
    rx = re.compile(CFG["nozzle"], re.I)
    noz = []
    for g in live:
        if rx.search(g["name"]):
            noz.append(g)
    if noz:
        pts = all_points(noz)
        zmax = max(p[2] for p in pts)
        ring = [p for p in pts if p[2] > zmax - 0.02 * EXT[2]]
        c = (sum(p[0] for p in ring) / len(ring), sum(p[1] for p in ring) / len(ring), zmax)
        r = sum(math.hypot(p[0] - c[0], p[1] - c[1]) for p in ring) / len(ring)
        info["nozzles"] = [{"pos": [round(c[0], 3), round(c[1], 3), round(c[2], 3)], "radius": round(r, 3)}]

if "muzzles" in CFG:
    mp = pts_of(CFG["muzzles"])
    if mp:
        info["muzzles"] = [[round(sum(p[i] for p in mp) / len(mp), 3) for i in range(3)]]
elif "muzzles_raw" in CFG:
    info["muzzles"] = CFG["muzzles_raw"]

info["gear_nodes"] = gear_nodes
info["control_surfaces"] = {}
for k, h in sorted(info_controls.items()):
    info["control_surfaces"][k] = {
        "hinge": [round(c, 3) for c in h["center"]],
        "axis": [round(c, 4) for c in h["axis"]],
        "max_deg": h["max_deg"],
        "property": h["property"],
    }
    if h.get("offset_deg"):
        # Rest-position offset of the FG animation (e.g. Rafale landing gear -90): input 0 sits at this angle
        info["control_surfaces"][k]["offset_deg"] = h["offset_deg"]
if info_rotors:
    info["rotors"] = {k: {"hub": [round(c, 3) for c in h["center"]], "axis": [round(c, 4) for c in h["axis"]],
                          "property": h["property"]} for k, h in sorted(info_rotors.items())}
info["triangles"] = total

# ---------------------------------------------------------------- export

out_rel = CFG["out"]
out_path = os.path.join(ROOT, out_rel)
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format="GLB",
    export_yup=True,
    export_apply=True,
    use_selection=False,
    export_materials="EXPORT",
    export_image_format="AUTO",
    export_cameras=False,
    export_lights=False,
    export_animations=False,
)
size_mb = os.path.getsize(out_path) / 1e6
print("wrote %s (%.2f MB)" % (out_rel, size_mb))

# ---------------------------------------------------------------- model_info.json (merge one entry)

db = {}
if os.path.exists(MODEL_INFO):
    with open(MODEL_INFO, "r", encoding="utf-8") as f:
        db = json.load(f)
db[MODEL_ID] = info
with open(MODEL_INFO, "w", encoding="utf-8") as f:
    json.dump(db, f, indent=2, sort_keys=False)
    f.write("\n")
print(json.dumps(info, indent=1)[:1500])
