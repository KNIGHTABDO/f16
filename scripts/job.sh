#!/usr/bin/env bash
# Launch a long-running agent job as a systemd --user unit, so it survives Claude Code sessions ending.
#   scripts/job.sh gemini <name> <brief.md> [base]      -> Gemini (agy) in .claude/worktrees/gem-gem-<name>, branch gem/<name>
#   scripts/job.sh claude <name> <brief.md> <worktree>  -> headless Claude Sonnet working inside an existing worktree
#   scripts/job.sh status                               -> list jobs
set -euo pipefail
ROOT=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel); cd "$ROOT"; mkdir -p .jobs
kind=${1:?}; [ "$kind" = status ] && { systemctl --user list-units 'f16-*' --all --no-legend --plain | awk '{print $1, $3, $4}'; exit; }
name=${2:?}; brief=${3:?}
env=(--setenv=PATH="$PATH" --setenv=HOME="$HOME")
case $kind in
  gemini) systemd-run --user --collect --unit="f16-gem-$name" "${env[@]}" --working-directory="$ROOT" \
            -p StandardOutput=append:"$ROOT/.jobs/$name.out" -p StandardError=append:"$ROOT/.jobs/$name.out" \
            "$ROOT/scripts/gemini-task.sh" write "gem/$name" "$brief" "${4:-main}" ;;
  claude) wt=${4:?worktree}
          systemd-run --user --collect --unit="f16-cl-$name" "${env[@]}" --working-directory="$ROOT/$wt" \
            -p StandardOutput=append:"$ROOT/.jobs/$name.json" -p StandardError=append:"$ROOT/.jobs/$name.err" \
            "$ROOT/scripts/claude-task.sh" "$ROOT/$brief" ;;
esac
echo "$(date +%F\ %T) $kind $name $brief ${4:-}" >> .jobs/history.log
