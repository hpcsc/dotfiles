#!/usr/bin/env bash
# Stamp each agent's `model:` into both trees from the registry, for the repo's own copies.
#
# `clerk models` is the implementation; this points it at the tracked trees rather than the
# symlinked ones under $HOME, so the generator works in CI and on a checkout that was never
# installed. One writer, two entry points: the command for a working machine, this for the
# repo.
#
# Usage: scripts/gen-agent-models.sh [--check]
#   --check  exit 1 if a tree disagrees with the registry, changing nothing

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLERK_MODELS="$ROOT/link/common/dot-local/bin/clerk-models"

[ -x "$CLERK_MODELS" ] || { echo "gen-agent-models: no clerk-models at $CLERK_MODELS" >&2; exit 2; }

PATHS=(
  --registry     "$ROOT/link/common/dot-config/.config/ai/method/agent-models.json"
  --claude-dir   "$ROOT/link/common/claude/.claude/agents"
  --opencode-dir "$ROOT/link/common/dot-config/.config/opencode/agents"
)

if [ "${1:-}" = "--check" ]; then
  exec "$CLERK_MODELS" "${PATHS[@]}" --check
fi
exec "$CLERK_MODELS" "${PATHS[@]}" apply
