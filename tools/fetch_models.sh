#!/usr/bin/env bash
# Fetch the FlightGear model sources listed in tools/models.json into tools/cache/models/ (gitignored).
# Only the model folders are checked out (sparse, blobless clones); repos are never cloned in full.
#
#   tools/fetch_models.sh                # every model in models.json
#   tools/fetch_models.sh f16c f14b      # only these model ids
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/tools/cache/models"
mkdir -p "$CACHE"

# One line per unique source clone: src<TAB>repo<TAB>branch<TAB>sparse-paths(comma separated)
SOURCES="$(python3 - "$ROOT/tools/models.json" "$@" <<'PY'
import json, sys
db = json.load(open(sys.argv[1], encoding="utf-8"))["models"]
ids = sys.argv[2:] or list(db)
seen = {}
for mid in ids:
    cfg = db[mid]
    if "repo" not in cfg:
        continue
    src = cfg["src"]
    if src in seen:
        seen[src][3].update(cfg.get("sparse", []))
        continue
    seen[src] = [src, cfg["repo"], cfg.get("branch", "master"), set(cfg.get("sparse", []))]
for src, repo, branch, sparse in seen.values():
    print("\t".join([src, repo, branch, ",".join(sorted(sparse))]))
PY
)"

while IFS=$'\t' read -r src repo branch sparse; do
  [ -n "$src" ] || continue
  dir="$ROOT/$src"
  if [ -d "$dir/.git" ]; then
    echo "have  $repo -> $src"
  else
    echo "clone $repo -> $src"
    git clone --depth 1 --filter=blob:none --sparse --branch "$branch" \
      "https://github.com/$repo.git" "$dir" --quiet
  fi
  if [ -n "$sparse" ]; then
    IFS=',' read -r -a patterns <<< "$sparse"
    git -C "$dir" sparse-checkout set --no-cone "${patterns[@]}"
  fi
done <<< "$SOURCES"

echo "done. Sources are in tools/cache/models/ (not committed)."
