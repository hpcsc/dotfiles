#!/usr/bin/env bash
# Claude Code status line – directory, model, effort and context usage on the
# left, rate limits and session cost flushed right

input=$(cat)

# Every field in one jq pass. The status line re-renders continuously, so each
# extra process here is paid on every keystroke; splitting this back into a jq
# call per field (plus awk for the path) costs four processes instead of one.
#
# Fields are joined with US, not tab: tab is an IFS whitespace character, so
# bash would collapse the runs of it that an absent effort or rate_limit
# produces and shift every later field one slot left.
IFS=$'\x1f' read -r short_dir cur_dir model effort used_pct pct_5h pct_7d cost <<<"$(
  jq -j '
    # Keep the last 2 path components (mirrors starship truncation_length=2).
    def shorten:
      (. // "") as $p
      | ($p | split("/")) as $parts
      | if ($parts | length) <= 2 then $p
        else "-/" + ($parts[-2:] | join("/")) end;

    # Round here rather than in bash: printf %.0f chokes on a null or a value
    # that is already a string, and an empty field is how bash tests presence.
    def pct: if type == "number" then (round | tostring) else "" end;

    [
        (.workspace.current_dir | shorten),
        (.workspace.current_dir // ""),
        (.model.display_name // ""),
        (.effort.level // ""),
        (.context_window.used_percentage | pct),
        (.rate_limits.five_hour.used_percentage | pct),
        (.rate_limits.seven_day.used_percentage | pct),
        (.cost.total_cost_usd | if type == "number" then tostring else "" end)
      ]
    | map(tostring | gsub("[\\n\\t]"; " "))
    | join("\u001f")
  ' <<<"$input"
)"

RESET=$'\033[0m'
DIM=$'\033[2m'
DIR_COLOR=$'\033[1;36m'
MODEL_COLOR=$'\033[1;35m'
EFFORT_COLOR=$'\033[1;34m'
# Its own constant despite matching GAUGE_LOW today: the two greens mean
# unrelated things, so repainting the gauge palette must not drag the cost with
# it.
COST_COLOR=$'\033[1;32m'
GAUGE_LOW=$'\033[1;32m'
GAUGE_MID=$'\033[1;33m'
GAUGE_HIGH=$'\033[1;31m'
# Its own hue because it is the only thing on this line that is neither the session nor
# the account: work in flight that outlives the turn you are looking at.
RUN_COLOR=$'\033[1;33m'
SEP="${DIM} · ${RESET}"

# Assigns rather than echoes: a $(...) result would fork a subshell per gauge.
gauge=""
set_gauge() {
  if [ "$1" -ge 85 ]; then
    gauge="$GAUGE_HIGH"
  elif [ "$1" -ge 60 ]; then
    gauge="$GAUGE_MID"
  else
    gauge="$GAUGE_LOW"
  fi
}

# A clerk run or audit round building in this directory. It is the one figure here that
# is not about the session: a round is launched into the background because it outlives a
# tool call, and without this the only sign it is still going is a file nobody remembers
# to tail.
#
# Zero processes, which is the constraint the rest of this file is written to. The runner
# writes a line to a fixed path — no git lookup to resolve a ledger — and presence is the
# signal: the file is removed when the run ends, and the next run to start clears whatever
# a killed one left behind. `read` and the glob are both builtins.
run_info=""
clerk_active="${XDG_CACHE_HOME:-$HOME/.cache}/clerk/active"
if [ -d "$clerk_active" ]; then
  for beat in "$clerk_active"/*; do
    [ -f "$beat" ] || continue
    IFS=$'\x1f' read -r b_dir b_slug b_label b_done b_cost b_at < "$beat" || continue
    # Either way round: the status line reports the session's cwd, which may be the
    # worktree the run builds in or the checkout it was launched from.
    case "$cur_dir" in
      "$b_dir"*) ;;
      *) case "$b_dir" in "$cur_dir"*) ;; *) continue ;; esac ;;
    esac
    run_info="${SEP}${RUN_COLOR}${b_slug}${RESET}${DIM}:${RESET}${b_label}"
    [ -n "$b_done" ] && [ "$b_done" != 0 ] && run_info="${run_info}${DIM} ${b_done}✓${RESET}"
    [ -n "$b_cost" ] && run_info="${run_info}${DIM} \$${b_cost}${RESET}"
    break
  done
fi

effort_info=""
if [ -n "$effort" ]; then
  effort_info="${SEP}${EFFORT_COLOR}${effort}${RESET}"
fi

# Coloured by how close the window is to auto-compaction, so a glance at the
# hue says whether there is room left without reading the number.
ctx_info=""
if [ -n "$used_pct" ]; then
  set_gauge "$used_pct"
  ctx_info="${SEP}${DIM}ctx:${RESET}${gauge}${used_pct}%${RESET}"
fi

# Both windows share one separator group: they are two readings of the same
# budget, and each is coloured independently so the hotter one stands out.
limits=""
if [ -n "$pct_5h" ]; then
  set_gauge "$pct_5h"
  limits="${DIM}5h:${RESET}${gauge}${pct_5h}%${RESET}"
fi
if [ -n "$pct_7d" ]; then
  set_gauge "$pct_7d"
  [ -n "$limits" ] && limits="${limits} "
  limits="${limits}${DIM}7d:${RESET}${gauge}${pct_7d}%${RESET}"
fi

# Formatted here rather than in jq, which has no fixed-precision conversion and
# would render a round figure as "0.4". printf is a builtin, so unlike the
# rounding done in jq this costs no process — but it does inherit the earlier
# caveat, hence the emptiness test: %.2f on a null would print "0.00" and
# invent a session that has spent nothing.
cost_text=""
if [ -n "$cost" ]; then
  printf -v cost_text '%.2f' "$cost"
fi

# The split is by what the figure describes, not by type. Left is this
# conversation — where it runs, what drives it, how full it is. Right is what
# the account is spending, which outlives the session and changes slowly, so it
# does not pull the eye. It also separates three adjacent percentages that
# otherwise can only be told apart by reading their labels.
left="${DIR_COLOR}${short_dir}${RESET}${SEP}${MODEL_COLOR}${model}${RESET}${effort_info}${ctx_info}${run_info}"

# The green is fixed, not a gauge: it never becomes yellow or red, however
# large the total grows. Every other figure on this line is a percentage of a
# ceiling that means something when reached, whereas a dollar total has none, so
# a threshold here would have to be invented — and one that fires on a long
# refactor as readily as on a runaway teaches the eye to discount the hue on the
# figures that do have a real limit. It reads as green beside a green gauge only
# by coincidence of palette.
right="$limits"
if [ -n "$cost_text" ]; then
  [ -n "$right" ] && right="${right}${SEP}"
  right="${right}${DIM}\$${RESET}${COST_COLOR}${cost_text}${RESET}"
fi

if [ -z "$right" ]; then
  printf '%s' "$left"
  exit 0
fi

# Flushed right like a zsh RPROMPT. Claude Code captures stdout instead of
# giving the script a tty, so tput cannot size the terminal and COLUMNS is the
# only way in; it is absent before v2.1.153, which the guard below inherits.
#
# The gap is measured on the text stripped of its escape sequences, since those
# occupy no columns. extglob makes an SGR sequence expressible as a glob, which
# keeps the strip a parameter expansion rather than another process, and the
# count is characters not bytes only because LC_CTYPE is UTF-8 — under LC_ALL=C
# each · would measure 2 and the right group would sit a few columns early.
shopt -s extglob
plain_left=${left//$'\033'\[*([0-9;])m/}
plain_right=${right//$'\033'\[*([0-9;])m/}

# COLUMNS is the terminal width, not the width of the row the status line is
# drawn into: the interface keeps a gutter of its own, and a line sized to the
# full terminal overflows it and loses its tail to the renderer's own ellipsis.
# The right group ends the line, so the tail is precisely what disappears.
GUTTER=4
pad=$(( ${COLUMNS:-0} - ${#plain_left} - ${#plain_right} - GUTTER ))

# Too narrow to flush right, so the groups run together instead: the line
# overflows either way, and one that wraps keeps figures truncation would drop.
if [ "$pad" -ge 1 ]; then
  printf '%s%*s%s' "$left" "$pad" "" "$right"
else
  printf '%s%s%s' "$left" "$SEP" "$right"
fi
