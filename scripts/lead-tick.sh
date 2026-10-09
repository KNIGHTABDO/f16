#!/usr/bin/env bash
# One lead/integrator pass (systemd timer). flock prevents overlap with a still-running tick.
ROOT=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel); cd "$ROOT"
exec 9>"$ROOT/.jobs/lead.lock"; flock -n 9 || exit 0
[ -f "$ROOT/.jobs/lead.paused" ] && exit 0
claude -p "$(cat docs/LEAD.md)" --model sonnet --dangerously-skip-permissions --output-format json >> .jobs/lead.json 2>> .jobs/lead.err
