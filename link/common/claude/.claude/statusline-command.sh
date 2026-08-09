#!/usr/bin/env bash
# Claude Code status line – directory, model, context usage

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

RESET=$'\033[0m'
DIM=$'\033[2m'
DIR_COLOR=$'\033[1;36m'
MODEL_COLOR=$'\033[1;35m'
CTX_LOW=$'\033[1;32m'
CTX_MID=$'\033[1;33m'
CTX_HIGH=$'\033[1;31m'
SEP="${DIM} · ${RESET}"

# Shorten the directory: keep last 2 components (mirrors starship truncation_length=2)
short_dir=$(echo "$cwd" | awk -F'/' '{
  n = NF
  if (n <= 2) print $0
  else print "-/" $(n-1) "/" $n
}')

# Coloured by how close the window is to auto-compaction, so a glance at the
# hue says whether there is room left without reading the number.
ctx_info=""
if [ -n "$used_pct" ]; then
  pct=$(printf '%.0f' "$used_pct")
  if [ "$pct" -ge 85 ]; then
    ctx_color="$CTX_HIGH"
  elif [ "$pct" -ge 60 ]; then
    ctx_color="$CTX_MID"
  else
    ctx_color="$CTX_LOW"
  fi
  ctx_info="${SEP}${DIM}ctx:${RESET}${ctx_color}${pct}%${RESET}"
fi

printf '%s' "${DIR_COLOR}${short_dir}${RESET}${SEP}${MODEL_COLOR}${model}${RESET}${ctx_info}"
