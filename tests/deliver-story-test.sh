#!/usr/bin/env bash
# Tests for the mark that the deliver-story driver puts on the tmux pane that orchestrates a
# plan. tmux and workmux are stubs on PATH; the tmux stub keeps the pane option in a file, so
# no tmux server is needed. Run with: tests/deliver-story-test.sh
set -uo pipefail

DRIVER="$(cd "$(dirname "$0")/.." && pwd)/link/common/claude/.claude/skills/deliver-story/deliver.sh"
PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }

STUBS=$(mktemp -d)
cat > "$STUBS/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  show-options)    cat "$STUBS/option" 2>/dev/null ;;
  set-option)      printf '%s' "${@: -1}" > "$STUBS/option" ;;
  display-message) echo Work ;;
esac
EOF
printf '#!/usr/bin/env bash\necho "[]"\n' > "$STUBS/workmux"
chmod +x "$STUBS/tmux" "$STUBS/workmux"
export STUBS

repo() {
  local d
  d=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$d" init -q -b main
  git -C "$d" -c user.email=t@t -c user.name=T -c commit.gpgsign=false commit -q --allow-empty -m seed
  mkdir -p "$d/tasks/$1"
  printf 'story: S\nstory_slug: %s\ndeliverables: []\n' "$1" > "$d/tasks/$1/plan.yaml"
  printf '%s' "$d"
}
drive() { (cd "$1" && shift && PATH="$STUBS:$PATH" bash "$DRIVER" "$@" >/dev/null 2>&1); }
mark() { cat "$STUBS/option" 2>/dev/null; }

printf '\ndeliver-story driver — the orchestrator mark\n'

R=$(repo age-1-one)
rm -f "$STUBS/option"
TMUX_PANE=%7 drive "$R" tasks/age-1-one/plan.yaml --mark
eq "--mark puts the absolute path of the plan on the pane" "$R/tasks/age-1-one/plan.yaml" "$(mark)"
TMUX_PANE=%7 drive "$R" tasks/age-1-one/plan.yaml --mark
eq "a second mark of the same plan changes nothing" "$R/tasks/age-1-one/plan.yaml" "$(mark)"
mkdir -p "$R/tasks/age-2-two"
printf 'story: S\nstory_slug: age-2-two\ndeliverables: []\n' > "$R/tasks/age-2-two/plan.yaml"
TMUX_PANE=%7 drive "$R" tasks/age-2-two/plan.yaml --mark
eq "the plan of another story joins the list, after a colon" \
   "$R/tasks/age-1-one/plan.yaml:$R/tasks/age-2-two/plan.yaml" "$(mark)"

rm -f "$STUBS/option"
(unset TMUX_PANE; drive "$R" tasks/age-1-one/plan.yaml --mark)
eq "outside tmux, --mark marks nothing" "" "$(mark)"
eq "and still succeeds" "0" "$(unset TMUX_PANE; drive "$R" tasks/age-1-one/plan.yaml --mark; echo $?)"

rm -f "$STUBS/option"
TMUX_PANE=%7 drive "$R" tasks/age-1-one/plan.yaml --dry-run
eq "a dry run marks nothing" "" "$(mark)"
TMUX_PANE=%7 drive "$R" tasks/age-1-one/plan.yaml
eq "a run marks the pane that runs it" "$R/tasks/age-1-one/plan.yaml" "$(mark)"

rm -rf "$STUBS"
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
