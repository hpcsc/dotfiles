#!/usr/bin/env zsh
# Tests for the fdeliver picker. clerk, fzf and deliverable-open are stubbed, so this checks
# that the row picked is the deliverable handed on, whole. What happens to it in each state
# is tested in tests/deliverable-open-test.sh. Run with: tests/fdeliver-test.zsh

FN="$(cd "$(dirname "$0")/.." && pwd)/link/common/zsh/.functions/fzf-functions/fdeliver"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); print "  ok   $1" }
bad() { FAIL=$((FAIL+1)); print "  FAIL $1\n     expected: $2\n     actual:   $3" }
eq()  { [[ "$2" == "$3" ]] && ok "$1" || bad "$1" "$2" "$3" }

STORY_JSON='[{"story_slug":"s","deliverables":[
 {"id":"live","wave":1,"state":"in-progress","done":1,"total":4,"tasks_file":"/t/c.md","worktree":"/wt/live","base_commit":"ccc3333333","blocked_by":[]},
 {"id":"fresh","wave":1,"state":"ready","done":0,"total":5,"tasks_file":"/t/d.md","worktree":null,"base_commit":"ddd4444444","blocked_by":[]}]}]'

clerk() { print -r -- "$STORY_JSON" }
PICK=""
fzf() { cat >/dev/null; print -r -- "$PICK" }   # drain the pipe, return the chosen row
deliverable-open() { print -r -- "deliverable-open $1 $(jq -r '"\(.id) \(.base_commit) \(.worktree)"' <<<"$2")" }

rows() { clerk story | jq -r '.[] | .story_slug as $s | .deliverables[] |
  [.state,"w\(.wave)","\(.done)/\(.total)",.id,$s,.tasks_file,tojson] | @tsv' }

run_with() { PICK=$(rows | awk -F'\t' -v i="$1" '$4 == i {print; exit}'); ( source $FN ) 2>&1 }

print "\nfdeliver"
eq "the picked deliverable goes to deliverable-open with its story" \
   "deliverable-open s fresh ddd4444444 null" "$(run_with fresh)"
eq "and with every field it needs, the worktree included" \
   "deliverable-open s live ccc3333333 /wt/live" "$(run_with live)"

PICK=""
eq "picking nothing does nothing" "" "$( ( source $FN ) 2>&1 )"

print "\n$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
