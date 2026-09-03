#!/usr/bin/env bash
# Static checks over every Python file in the repo.
#
# pyflakes rather than a full linter: it reports facts — an undefined name, an import
# nothing uses, a definition shadowed before it is read — rather than style opinions, so
# it needs no configuration and produces no findings to argue with. The class it catches
# is the one a green test suite misses, because the offending line never ran.
#
# Files are found rather than listed: any tracked file ending .py, or whose first line is
# a python shebang. A new command under link/common/dot-local/bin/ is covered the moment
# it is committed, without this script being told about it.
#
# Usage: scripts/lint-python.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

# A suffix test rather than a `case` pattern: an unbalanced `)` inside a case arm inside
# this command substitution is a parse error in bash 3.2.
files=$(git ls-files | while IFS= read -r f; do
  if [ "${f%.py}" != "$f" ]; then printf '%s\n' "$f"; continue; fi
  [ -f "$f" ] || continue
  head -1 "$f" 2>/dev/null | grep -q '^#!.*python' && printf '%s\n' "$f"
done)

if [ -z "$files" ]; then
  echo "lint-python: no Python files found" >&2
  exit 2
fi

# uv on a working machine, an installed pyflakes on a runner that has one. Both spell the
# same check; neither is required to be present as long as one is, and saying which is
# missing beats a bare "command not found" from whichever was tried last.
if command -v uv >/dev/null 2>&1; then
  runner=(uv run --quiet --with pyflakes python -m pyflakes)
elif python3 -c 'import pyflakes' >/dev/null 2>&1; then
  runner=(python3 -m pyflakes)
else
  echo "lint-python: needs uv, or pyflakes importable by python3 (pip install pyflakes)" >&2
  exit 2
fi

count=$(printf '%s\n' "$files" | wc -l | tr -d ' ')
printf '%s\n' "$files" | xargs "${runner[@]}"
rc=$?
[ "$rc" -eq 0 ] && printf 'pyflakes: %s files clean\n' "$count"
exit "$rc"
