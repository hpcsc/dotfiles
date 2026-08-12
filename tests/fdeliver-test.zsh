#!/usr/bin/env zsh
# Branch tests for the fdeliver picker. clerk, fzf and workmux are stubbed, so this
# exercises the decision the function makes for each deliverable state without creating a
# worktree or a tmux window. Run with: tests/fdeliver-test.zsh
#
# The decision worth pinning is the third one: a deliverable already under way must be
# opened rather than started, or a second worktree gets scaffolded for it and the first
# one's commits are stranded on a branch nobody is watching.

FN="$(cd "$(dirname "$0")/.." && pwd)/link/common/zsh/.functions/fzf-functions/fdeliver"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); print "  ok   $1" }
bad() { FAIL=$((FAIL+1)); print "  FAIL $1\n     expected: $2\n     actual:   $3" }
eq()  { [[ "$2" == "$3" ]] && ok "$1" || bad "$1" "$2" "$3" }

STORY_JSON='[{"story_slug":"s","deliverables":[
 {"id":"done-one","wave":1,"state":"merged","done":3,"total":3,"tasks_file":"/t/a.md","worktree":null,"base_commit":"aaa1111111","blocked_by":[]},
 {"id":"held","wave":2,"state":"blocked","done":0,"total":4,"tasks_file":"/t/b.md","worktree":null,"base_commit":"bbb2222222","blocked_by":["live"]},
 {"id":"live","wave":1,"state":"in-progress","done":1,"total":4,"tasks_file":"/t/c.md","worktree":"/wt/live","base_commit":"ccc3333333","blocked_by":[]},
 {"id":"fresh","wave":1,"state":"ready","done":0,"total":5,"tasks_file":"/t/d.md","worktree":null,"base_commit":"ddd4444444","blocked_by":[]},
 {"id":"empty","wave":1,"state":"scaffolded","done":0,"total":3,"tasks_file":"/t/e.md","worktree":"/wt/empty","base_commit":"eee5555555","blocked_by":[]}]}]'

clerk()   { print -r -- "$STORY_JSON" }
PICK=""
fzf()     { cat >/dev/null; print -r -- "$PICK" }   # drain the pipe, return the chosen row
workmux() { print -r -- "workmux $*" }

# PANES is what `tmux list-panes -a` would report; set per case to say whether a window is
# already showing the worktree.
PANES=""
tmux() {
  case "$1" in
    list-panes)      print -r -- "$PANES" ;;
    display-message) print -r -- "Work" ;;
    *)               print -r -- "tmux $*" ;;
  esac
}

rows() { clerk story | jq -r '.[] | .story_slug as $s | .deliverables[] |
  [.state,"w\(.wave)","\(.done)/\(.total)",.id,$s,.tasks_file,(.worktree//""),(.base_commit//""),(.blocked_by|join(","))] | @tsv' }

run_with() { PICK=$(rows | awk -F'\t' -v i="$1" '$4 == i {print; exit}'); ( source $FN ) 2>&1 }

print "\nfdeliver"
eq "a merged deliverable offers nothing to start" \
   "done-one is merged — nothing to start. Review or land it instead." "$(run_with done-one)"

eq "a blocked one names what it waits on" \
   "held is blocked by live — finish those first, or start one of them." "$(run_with held)"

# The window already showing that worktree. workmux identifies a target by NAME and keeps
# no worktree-to-target registry, so a window named anything else is invisible to it and
# `workmux open` would start a second session beside the running work.
PANES='Work:2|/wt/live
Work:3|/elsewhere'
TMUX=/tmp/fake out=$(run_with live)
eq "one already running is switched to, not reopened" \
   "live is already running in Work:2 — switching to it" "${out%%$'\n'*}"
eq "selecting the window that holds it"  "tmux select-window -t Work:2" "$(print -r -- "$out" | sed -n 2p)"
eq "and switching the client to its session" "tmux switch-client -t Work" "$(print -r -- "$out" | sed -n 3p)"

# A subdirectory of the worktree counts: a pane's cwd drifts as the run works.
PANES='Work:5|/wt/live/internal/api'
TMUX=/tmp/fake out=$(run_with live)
eq "a pane deeper in the tree still identifies the window" \
   "live is already running in Work:5 — switching to it" "${out%%$'\n'*}"

# A sibling path that merely starts with the same characters is not the same worktree.
PANES='Work:9|/wt/live-something-else'
TMUX=/tmp/fake out=$(run_with live)
eq "a path that only shares a prefix is not mistaken for it" \
   "live has a worktree at /wt/live but nothing running in it — opening it" "${out%%$'\n'*}"
eq "and that falls back to opening it as the config directs" \
   "workmux open live" "${out##*$'\n'}"

PANES=""
out=$(run_with live)
eq "with nothing running, it opens rather than switching" \
   "live has a worktree at /wt/live but nothing running in it — opening it" "${out%%$'\n'*}"

PANES=""
TMUX=/tmp/fake out=$(run_with fresh)
eq "a ready one launches implement against its absolute task file" \
   "starting fresh on ddd4444444 — /implement /t/d.md" "${out%%$'\n'*}"
eq "on the resolved base, leaving mode to the global config" \
   "workmux add s-fresh --name s-fresh --base ddd4444444 --prompt /implement /t/d.md --in-place" \
   "${out##*$'\n'}"


# A worktree a dead launch left behind: right branch, right base, nothing built. It needs
# the prompt that starts the run, which an open alone would never deliver.
PANES=""
TMUX=/tmp/fake out=$(run_with empty)
eq "an empty worktree is started in place, not left sitting" \
   "empty has an empty worktree at /wt/empty — starting the run in it" "${out%%$'\n'*}"
eq "opening it with the prompt that begins the work" \
   "workmux open empty --prompt /implement /t/e.md --in-place" "${out##*$'\n'}"

# One with commits behind it is opened bare: a fresh /implement would restart its story.
PANES=""
TMUX=/tmp/fake out=$(run_with live)
eq "a worktree with work in it is opened without a prompt" \
   "workmux open live" "${out##*$'\n'}"

PICK=""
eq "picking nothing does nothing" "" "$( ( source $FN ) 2>&1 )"

print "\n$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
