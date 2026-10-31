#!/usr/bin/env bash
# Tests for the mark that the deliver-story driver puts on the tmux pane that orchestrates a
# plan, for the prompt that it launches a deliverable with, and for when a stacked deliverable
# is ready. tmux, workmux and clerk are stubs on PATH; the tmux stub keeps the pane option in a
# file, so no tmux server is needed, and the clerk stub prints the story from a file. Run with:
# tests/deliver-story-test.sh
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
  set-option)      if [ "$2" = -w ]; then echo "tmux $*" >> "$STUBS/log"; else printf '%s' "${@: -1}" > "$STUBS/option"; fi ;;
  rename-window)   printf '%s' "${@: -1}" > "$STUBS/name" ;;
  display-message) case "$*" in *window_name*) cat "$STUBS/name" 2>/dev/null ;; *) echo Work ;; esac ;;
esac
EOF
printf '#!/usr/bin/env bash\necho "[]"\n' > "$STUBS/workmux"
printf '#!/usr/bin/env bash\ncat "$STUBS/story.json" 2>/dev/null || echo "[]"\n' > "$STUBS/clerk"
chmod +x "$STUBS/tmux" "$STUBS/workmux" "$STUBS/clerk"
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

printf '\ndeliver-story driver — the name of the orchestrator window\n'

fresh() { rm -f "$STUBS/option" "$STUBS/log"; printf 'customer-portal' > "$STUBS/name"; }
R2=$(repo age-5-five)
printf 'story: S\nstory_slug: age-5-five\nticket: "AGE-5"\ndeliverables: []\n' > "$R2/tasks/age-5-five/plan.yaml"
fresh
TMUX_PANE=%7 drive "$R2" tasks/age-5-five/plan.yaml --mark
eq "a pane that orchestrates one plan names its window after the ticket" "age-5-orchestrator" "$(cat "$STUBS/name")"
fresh
TMUX_PANE=%7 drive "$R" tasks/age-1-one/plan.yaml --mark
eq "with no ticket, the window takes the story slug" "age-1-one-orchestrator" "$(cat "$STUBS/name")"
TMUX_PANE=%7 drive "$R" tasks/age-2-two/plan.yaml --mark
eq "a second plan gives the window back its automatic name" "tmux set-option -w -t %7 automatic-rename on" "$(cat "$STUBS/log")"
fresh
TMUX_PANE=%7 drive "$R2" tasks/age-5-five/plan.yaml --dry-run
eq "a dry run renames nothing" "customer-portal" "$(cat "$STUBS/name")"

fresh
git -C "$R2" worktree add -q -b wt "$R2/.worktrees/wt" 2>/dev/null
mkdir -p "$R2/.worktrees/wt/tasks/age-5-five"
cp "$R2/tasks/age-5-five/plan.yaml" "$R2/.worktrees/wt/tasks/age-5-five/plan.yaml"
TMUX_PANE=%7 drive "$R2/.worktrees/wt" tasks/age-5-five/plan.yaml --mark
eq "a window in a worktree keeps its name" "customer-portal" "$(cat "$STUBS/name")"
eq "and its pane still gets the mark" "$R2/.worktrees/wt/tasks/age-5-five/plan.yaml" "$(mark)"

printf '\ndeliver-story driver — the launch prompt\n'

R3=$(repo age-9-nine)
mkdir -p "$R3/tasks/age-9-nine/one"
printf '# One\n' > "$R3/tasks/age-9-nine/one/tasks.md"
cat > "$R3/tasks/age-9-nine/plan.yaml" <<'EOF'
story: S
story_slug: age-9-nine
deliverables:
  - id: one
    branch: age-9-one
    base: main
    wave: 1
    depends_on: []
    tasks: tasks/age-9-nine/one/tasks.md
    status: pending
EOF
launch() { (cd "$R3" && PATH="$STUBS:$PATH" bash "$DRIVER" tasks/age-9-nine/plan.yaml --dry-run "$@" 2>/dev/null) | grep -e '--prompt'; }
eq "the launch prompt names the orchestrator" 1 "$(launch --orchestrator customer-portal-cd | grep -c -F 'orchestrator:\ customer-portal-cd')"
eq "with no name given, the launch prompt ends after its own note" 1 "$(launch | grep -c -F 'for\ review\)')"

printf '\ndeliver-story driver — a stacked deliverable waits for a finished prerequisite\n'

R4=$(repo age-8-eight)
for d in first stacked; do
  mkdir -p "$R4/tasks/age-8-eight/$d"
  printf '# %s\n' "$d" > "$R4/tasks/age-8-eight/$d/tasks.md"
done
cat > "$R4/tasks/age-8-eight/plan.yaml" <<'EOF'
story: S
story_slug: age-8-eight
deliverables:
  - id: first
    branch: age-8-first
    base: main
    wave: 1
    depends_on: []
    tasks: tasks/age-8-eight/first/tasks.md
    status: running
  - id: stacked
    branch: age-8-stacked
    base: first
    wave: 2
    depends_on: [first]
    tasks: tasks/age-8-eight/stacked/tasks.md
    status: pending
EOF
git -C "$R4" checkout -q -b age-8-first
git -C "$R4" -c user.email=t@t -c user.name=T -c commit.gpgsign=false commit -q --allow-empty -m "task 1"
git -C "$R4" checkout -q main
first_is() {  # state archived
  printf '[{"deliverables":[{"id":"first","state":"%s","archived":%s,"handle":"age-8-first"}]}]' "$1" "$2" > "$STUBS/story.json"
}
pass() { (cd "$R4" && PATH="$STUBS:$PATH" bash "$DRIVER" tasks/age-8-eight/plan.yaml --dry-run "$@" 2>/dev/null); }

first_is in-progress false
eq "a prerequisite with a commit but an unfinished run holds its dependent" 1 "$(pass | grep -c '^deliver-story: waiting: stacked')"
first_is awaiting-merge false
eq "so does a prerequisite with every task done, while its audit can still rewrite it" 1 "$(pass | grep -c '^deliver-story: waiting: stacked')"
first_is awaiting-merge true
eq "a prerequisite whose run archived its task record lets its dependent launch" 1 "$(pass | grep -c '^deliver-story: launch: stacked')"
first_is merged false
eq "and so does a merged prerequisite" 1 "$(pass | grep -c '^deliver-story: launch: stacked')"

rm -rf "$STUBS"
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
