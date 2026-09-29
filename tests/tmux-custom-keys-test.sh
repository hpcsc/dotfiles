#!/usr/bin/env bash
# Fixture-server tests for tmux-custom-keys. Each case starts a throwaway tmux server
# on a config of its own, points the script at it, and asserts on what it prints.
# Run with: tests/tmux-custom-keys-test.sh

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/link/common/dot-local/bin/tmux-custom-keys"
PASS=0
FAIL=0

ok()    { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }
skip()  { printf '  skip %s (%s)\n' "$1" "$2"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has()   { if grep -qE -- "$3" <<<"$2"; then ok "$1"; else bad "$1" "a line matching $3" "$2"; fi; }
lacks() { if grep -qE -- "$3" <<<"$2"; then bad "$1" "no line matching $3" "$2"; else ok "$1"; fi; }

# A throwaway server on the given config. A detached session keeps it alive until
# stop_server; TMUX is unset for these calls so that running the tests inside tmux is
# not "nesting". Clients of the fixture reach it through the SOCK path.
start_server() {
  DIR=$(mktemp -d)
  SOCK="$DIR/sock"
  printf '%s\n' "$1" > "$DIR/tmux.conf"
  env -u TMUX tmux -S "$SOCK" -f "$DIR/tmux.conf" new-session -d -s fixture -x 120 -y 40
}
stop_server() {
  env -u TMUX tmux -S "$SOCK" kill-server 2>/dev/null
  rm -rf "$DIR"
}
# The script itself is pointed at the fixture through TMUX, which is how a tmux client
# given no -S finds its server.
fixture() { TMUX="$SOCK,0,0" "$SCRIPT" "$@"; }

# Prints what the script outputs for a server on the given config: on_config <conf> [args]
on_config() {
  local conf=$1 out
  shift
  start_server "$conf"
  out=$(fixture "$@")
  stop_server
  printf '%s' "$out"
}

CONF='
bind -N "Open the thing" F run-shell true
bind c new-window -c "#{pane_current_path}"
bind -N "Split the other way" % split-window -h -c "#{pane_current_path}"
bind -n -N "Go left" M-h select-pane -L
bind -n -N "Previous session" "M-{" switch-client -p
bind -T copy-mode-vi v send -X begin-selection
bind -N "Leave a mark" T set -g @mark yes
bind -N "[tool] Open the dashboard" G run-shell true
bind -N "[tool] Pick a window" w
'

# --------------------------------------------------------------------------------
printf '\ncustom bindings\n'

OUT=$(on_config "$CONF")
has   "a binding the config adds shows with its note"          "$OUT" '^C-b F +Open the thing$'
has   "a default rebound to another command shows its command" "$OUT" '^C-b c +new-window -c "#\{pane_current_path\}"$'
lacks "a default left alone is not listed"                     "$OUT" '^C-b d '
has   "a key tmux writes escaped is matched to its note"       "$OUT" '^C-b % +Split the other way$'
has   "a key tmux writes quoted is matched to its note"        "$OUT" '^M-\{ +Previous session$'
has   "a no-prefix binding shows bare"                         "$OUT" '^M-h +Go left$'
eq    "no-prefix bindings come before prefix ones"             yes \
      "$(awk '/^M-/ { last = NR } /^C-b / && !first { first = NR } END { print (first > last) ? "yes" : "no" }' <<<"$OUT")"
has   "another table is named in the key column"               "$OUT" '^copy-mode-vi v +send-keys -X begin-selection$'
eq    "descriptions start in one column"                       0 "$(grep -cvE '^.{14}  [^ ]' <<<"$OUT")"
eq    "a config that adds nothing says so" \
      "no key bindings differ from tmux's defaults" "$(on_config '')"

# --------------------------------------------------------------------------------
printf '\nall bindings\n'

ALL=$(on_config "$CONF" --all)
has   "includes the defaults"              "$ALL" '^C-b d +Detach the current client$'
has   "still includes the custom ones"     "$ALL" '^C-b F +Open the thing$'
lacks "leaves mouse bindings out"          "$ALL" 'Mouse|Wheel'
eq    "prefix bindings precede other tables" yes \
      "$(awk '/^C-b / { last = NR } /^copy-mode/ && !first { first = NR } END { print (first > last) ? "yes" : "no" }' <<<"$ALL")"

# --------------------------------------------------------------------------------
printf '\ntools\n'

TOOLS=$(on_config "$CONF" --tools)
has   "a binding whose note starts with the tag shows without the tag" "$TOOLS" '^C-b G +Open the dashboard$'
lacks "a binding without the tag is left out"                         "$TOOLS" 'Open the thing|Detach'
has   "a default key whose note alone carries the tag still shows"    "$TOOLS" '^C-b w +Pick a window$'
has   "the custom list keeps the tag"                                 "$OUT"   '^C-b G +\[tool\] Open the dashboard$'
eq    "a config with no tagged binding says so" \
      "no key bindings carry the [tool] tag" "$(on_config '' --tools)"

# --------------------------------------------------------------------------------
printf '\nfzf rows\n'

ROWS=$(on_config "$CONF" --rows)
has "each row carries its command after a tab"  "$ROWS" $'Open the thing\trun-shell true$'
has "a row without a note shows its command"    "$ROWS" $'C-b c .*new-window -c "#\\{pane_current_path\\}".*\tnew-window -c'

# --------------------------------------------------------------------------------
printf '\npicker\n'

# fzf needs a terminal; BSD script(1) lends it one and forwards stdin as keystrokes.
# Each key waits a moment, so the list has loaded before the next key arrives.
# pick <ctrl-a presses> <query> [script args] leaves the fixture server up to inspect.
pick() {
  local presses=$1 query=$2
  shift 2
  start_server "$CONF"
  PANE=$(env -u TMUX tmux -S "$SOCK" list-panes -t fixture -F '#{pane_id}' | head -1)
  (sleep 1; for ((i = 0; i < presses; i++)); do printf '\001'; sleep 1; done
   printf '%s' "$query"; sleep 1; printf '\r') \
    | script -q /dev/null env TMUX="$SOCK,0,0" "$SCRIPT" --fzf "$@" "$PANE" >/dev/null 2>&1
  sleep 1
}
mark()      { env -u TMUX tmux -S "$SOCK" show -gv @mark 2>/dev/null; }
pane_mode() { env -u TMUX tmux -S "$SOCK" display -p -t "$PANE" '#{pane_mode}'; }

if [ "$(uname)" = Darwin ] && command -v fzf >/dev/null; then
  pick 0 'Leave a mark'
  eq "enter runs the chosen binding" yes "$(mark)"
  stop_server

  pick 1 'Leave a mark' --tools
  eq "ctrl-a moves from the tools list to the custom list" yes "$(mark)"
  stop_server

  pick 2 'Show a clock' --tools
  eq "a second ctrl-a moves on to every binding" clock-mode "$(pane_mode)"
  stop_server

  pick 3 'Leave a mark' --tools
  eq "a third ctrl-a comes back to the tools list" "" "$(mark)"
  stop_server
else
  skip "the picker" "needs macOS script(1) and fzf"
fi

# --------------------------------------------------------------------------------
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
