#!/usr/bin/env bash
# Generate the per-tool SKILL.md files from the shared method body plus its seams.
#
# A procedure the agent must follow in full is concatenated, not referenced: splitting
# it into "now read these six files" adds six reads and invites partial compliance,
# which is the failure class this whole arrangement exists to remove. Guidelines are
# the opposite — consulted on demand, read partially by design — and stay referenced.
#
# The `model:` line is deliberately absent from every seam: agent-models.json owns it
# for both trees at once, and two writers for one field means whichever ran last wins.
# Run scripts/gen-agent-models.sh after this one — `task common:gen` does both in order.
#
# Usage: scripts/gen-skills.sh [--check]
#   --check  exit 1 if any generated file is out of date, changing nothing

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
METHOD="$ROOT/link/common/dot-config/.config/ai/method"

CHECK=false
[ "${1:-}" = "--check" ] && CHECK=true

# source-dir (under $METHOD)  tool  output-path
TARGETS="
implement claude   $ROOT/link/common/claude/.claude/skills/implement/SKILL.md
implement opencode $ROOT/link/common/dot-config/.config/opencode/skills/implement/SKILL.md
implement-auto claude   $ROOT/link/common/claude/.claude/skills/implement-auto/SKILL.md
implement-auto opencode $ROOT/link/common/dot-config/.config/opencode/skills/implement-auto/SKILL.md
agents/decompose-to-tasks claude   $ROOT/link/common/claude/.claude/agents/decompose-to-tasks.md
agents/decompose-to-tasks opencode $ROOT/link/common/dot-config/.config/opencode/agents/decompose-to-tasks.md
agents/commit claude   $ROOT/link/common/claude/.claude/agents/commit.md
agents/commit opencode $ROOT/link/common/dot-config/.config/opencode/agents/commit.md
agents/run-verifier claude   $ROOT/link/common/claude/.claude/agents/run-verifier.md
agents/run-verifier opencode $ROOT/link/common/dot-config/.config/opencode/agents/run-verifier.md
agents/decompose-to-deliverables claude   $ROOT/link/common/claude/.claude/agents/decompose-to-deliverables.md
agents/decompose-to-deliverables opencode $ROOT/link/common/dot-config/.config/opencode/agents/decompose-to-deliverables.md
"

fail=0

render() {
  local method=$1 tool=$2 body="$METHOD/$1/body.md" seams="$METHOD/$1/seams/$2"
  [ -f "$body" ]  || { printf 'gen-skills: missing body %s\n' "$body" >&2; return 1; }
  [ -d "$seams" ] || { printf 'gen-skills: missing seams %s\n' "$seams" >&2; return 1; }

  # Substitute every {{seam:name}} with seams/<tool>/<name>.md. An unresolved marker is
  # an error rather than a silent hole: a SKILL.md missing its worktree section reads
  # as complete and simply omits a step.
  awk -v seams="$seams" -v method="$METHOD" '
    /^\{\{seam:[a-z-]+\}\}$/ {
      name = $0
      sub(/^\{\{seam:/, "", name); sub(/\}\}$/, "", name)
      path = seams "/" name ".md"
      if ((getline line < path) < 0) {
        printf("gen-skills: no seam %s\n", path) > "/dev/stderr"
        exit 3
      }
      print line
      while ((getline line < path) > 0) print line
      close(path)
      next
    }
    # Fragments shared between skills, as opposed to per-tool variants. Included, not
    # referenced, for the same reason seams are: a procedure the agent must follow in
    # full should arrive in full.
    /^\{\{include:[a-z0-9\/-]+\.md\}\}$/ {
      name = $0
      sub(/^\{\{include:/, "", name); sub(/\}\}$/, "", name)
      path = method "/" name
      if ((getline line < path) < 0) {
        printf("gen-skills: no shared fragment %s\n", path) > "/dev/stderr"
        exit 3
      }
      print line
      while ((getline line < path) > 0) print line
      close(path)
      next
    }
    /\{\{(seam|include):/ { printf("gen-skills: malformed marker: %s\n", $0) > "/dev/stderr"; exit 3 }
    { print }
  ' "$body"
}

printf '%s\n' "$TARGETS" | while read -r method tool out; do
  [ -n "$method" ] || continue
  rendered=$(render "$method" "$tool") || { fail=1; continue; }

  if [ "$CHECK" = true ]; then
    # The `model:` line is stamped afterwards by gen-agent-models, from the registry that
    # owns it for both trees. Comparing it here would fail every generated agent for
    # carrying a field this script deliberately does not write.
    if [ ! -f "$out" ] || ! printf '%s\n' "$rendered" | diff -q - <(grep -v '^model: ' "$out") >/dev/null 2>&1; then
      printf 'out of date: %s\n' "${out#$ROOT/}" >&2
      exit 1
    fi
    printf 'up to date:  %s\n' "${out#$ROOT/}"
  else
    mkdir -p "$(dirname "$out")"
    printf '%s\n' "$rendered" > "$out"
    printf 'wrote %s (%s lines)\n' "${out#$ROOT/}" "$(printf '%s\n' "$rendered" | wc -l | tr -d ' ')"
  fi
done
