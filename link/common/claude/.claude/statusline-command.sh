#!/usr/bin/env bash
# Claude Code status line – directory, model, effort, context usage, rate limit

input=$(cat)

# Every field in one jq pass. The status line re-renders continuously, so each
# extra process here is paid on every keystroke; splitting this back into a jq
# call per field (plus awk for the path) costs four processes instead of one.
#
# Fields are joined with US, not tab: tab is an IFS whitespace character, so
# bash would collapse the runs of it that an absent effort or rate_limit
# produces and shift every later field one slot left.
IFS=$'\x1f' read -r short_dir model effort used_pct pct_5h pct_7d <<<"$(
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
        (.model.display_name // ""),
        (.effort.level // ""),
        (.context_window.used_percentage | pct),
        (.rate_limits.five_hour.used_percentage | pct),
        (.rate_limits.seven_day.used_percentage | pct)
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
GAUGE_LOW=$'\033[1;32m'
GAUGE_MID=$'\033[1;33m'
GAUGE_HIGH=$'\033[1;31m'
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

limit_info=""
if [ -n "$limits" ]; then
  limit_info="${SEP}${limits}"
fi

printf '%s' "${DIR_COLOR}${short_dir}${RESET}${SEP}${MODEL_COLOR}${model}${RESET}${effort_info}${ctx_info}${limit_info}"
