#!/usr/bin/env bash
# Runs the clerk fixture tests at the same time, then prints each file's output whole, in
# order. Each file must keep its fixtures in its own temporary folders.

set -u

dir=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp -d) || exit 2
names=(clerk-test clerk-step-test clerk-run-test clerk-design-test)
pids=()
for name in "${names[@]}"; do
  bash "$dir/$name.sh" > "$out/$name.log" 2>&1 &
  pids+=($!)
done

failed=0
for i in "${!names[@]}"; do
  wait "${pids[$i]}" || failed=1
  printf '\n== %s\n' "${names[$i]}"
  cat "$out/${names[$i]}.log"
done
rm -rf "$out"
exit "$failed"
