#!/usr/bin/env bash
# Headless Claude coder (run by job.sh inside a worktree). Arg: absolute brief path.
brief=$1; common="$(git rev-parse --show-toplevel)/tasks/_common.md"
prompt="You are a coding agent working autonomously in this git worktree (a branch of the Knight Wings Godot iOS flight game, a video game).
Nobody will answer questions: decide yourself. Follow the brief below and the shared rules. Commit on the current branch with clear messages
as you finish meaningful pieces (git add specific files, never *.import). Do not push, do not merge, do not touch other worktrees.
When done, end with a <=15 line summary (what works, what is verified headless, known gaps).

$(cat "$brief")

---- shared rules ----
$(cat "$common" 2>/dev/null)"
exec claude -p "$prompt" --model sonnet --dangerously-skip-permissions --output-format json
