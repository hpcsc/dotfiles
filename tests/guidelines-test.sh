#!/usr/bin/env bash
# Checks the live guidelines and the live agents against each other.
#
# clerk-test.sh deliberately runs on fixtures: its assertions are about how a file is cut
# up, and pinning those to the real guidelines would make every edit to them a test
# failure. Nothing there can catch what matters here, which is the two sides drifting
# apart — an agent asking for a concept no guideline declares, a guideline declaring one
# nothing reads, a heading that quietly became unaddressable.
#
# Run with: tests/guidelines-test.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLERK="$ROOT/link/common/dot-local/bin/clerk"
GUIDELINES="${CLERK_GUIDELINES_DIR:-$HOME/.config/ai/guidelines}"
AGENTS="$ROOT/link/common/claude/.claude/agents"
PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

[ -d "$GUIDELINES" ] || { printf 'no guidelines at %s\n' "$GUIDELINES" >&2; exit 2; }

# A repo carrying every language marker, so an agent that detects its language rather
# than naming one resolves the way it would in a real project.
FIXTURE=$(cd "$(mktemp -d)" && pwd -P)
git -C "$FIXTURE" init -q -b main
printf 'module x\n' > "$FIXTURE/go.mod"
printf '{}\n' > "$FIXTURE/package.json"
printf 'defmodule X do end\n' > "$FIXTURE/mix.exs"

# --------------------------------------------------------------------------------
printf '\nagents — what they ask for is what the guidelines carry\n'

# Every agent's own command, run for real against the live guidelines. A concept renamed
# out from under an agent says so here, rather than at the point someone is relying on
# the answer.
for f in "$AGENTS"/*.md; do
  grep -q 'clerk guidelines' "$f" || continue
  agent=$(basename "$f" .md)
  cmd=$(awk '/^```bash$/{inb=1;buf="";next}
             /^```$/{if(inb && buf ~ /clerk guidelines/){print buf; exit} inb=0}
             inb{gsub(/\\$/,"");buf=buf $0 " "}' "$f")
  if [ -z "$cmd" ]; then
    # An orchestrator names the command without running it: its agents run their own.
    if grep -q 'Inner agents load their own guidelines' "$f"; then
      ok "$agent delegates to its inner agents"
    else
      bad "$agent names clerk guidelines but has no command" "no bash block found"
    fi
    continue
  fi
  out=$(cd "$FIXTURE" && eval "${cmd/clerk guidelines/\"$CLERK\" guidelines}" 2>&1)
  rc=$?
  if [ $rc -ne 0 ]; then
    bad "$agent's command succeeds" "exit $rc: $(printf '%s' "$out" | head -1)"
  elif printf '%s' "$out" | grep -q 'Not loaded'; then
    bad "$agent gets everything it asks for" \
        "$(printf '%s' "$out" | sed -n '/Not loaded/,$p' | grep '^- ' | head -2 | tr '\n' ' ')"
  else
    ok "$agent gets everything it asks for"
  fi
done

# --------------------------------------------------------------------------------
printf '\nguidelines — every heading addressable, every concept documented\n'

UNREAD=""
CHECKS=$(python3 - "$GUIDELINES" "$AGENTS" "$ROOT" <<'PY'
import pathlib, re, sys

root, agents, repo = (pathlib.Path(a) for a in sys.argv[1:4])
MARKER = re.compile(r"^<!--\s*concept:\s*([a-z0-9-]+)\s*-->")
out = []


def check(name, condition, detail=""):
    out.append(f"ok|{name}" if condition else f"fail|{name}|{detail}")


# The files the tool reads in parts. A concept declared outside this set is never looked
# at, so the two lists have to agree.
tool = (repo / "link/common/dot-local/bin/clerk-guidelines").read_text()
block = tool[tool.index("SLICED = {"):]
sliced = set(re.findall(r'"([a-z][a-z/-]+\.md)"', block[:block.index("}")]))

declared = {}
for rel in sorted(sliced):
    p = root / rel
    if not p.is_file():
        check(f"{rel} exists", False, "read in parts but not on disk")
        continue
    lines = p.read_text().splitlines()
    heads = [(l[3:].strip(), i) for i, l in enumerate(lines) if re.match(r"^## +", l)]
    unmarked, seen, dupes = [], {}, []
    for name, i in heads:
        hit = next((MARKER.match(l.strip()) for l in lines[i + 1:i + 4]
                    if MARKER.match(l.strip())), None)
        if not hit:
            unmarked.append(name)
            continue
        c = hit.group(1)
        if c in seen:
            dupes.append(c)
        seen[c] = name
        declared.setdefault(c, set()).add(rel)
    # A file where some headings are addressable and others silently are not is one where
    # a missing marker means two different things.
    check(f"{rel}: every heading declares a concept", not unmarked,
          f"unmarked: {', '.join(unmarked)}")
    check(f"{rel}: no concept declared twice", not dupes, f"repeated: {sorted(set(dupes))}")

# A marker in a guideline that is always delivered whole is never looked up.
stray = [str(p.relative_to(root)) for p in root.rglob("*.md")
         if str(p.relative_to(root)) not in sliced and p.name != "CONCEPTS.md"
         and any(MARKER.match(l.strip()) for l in p.read_text().splitlines())]
check("no concept is declared in a guideline delivered whole", not stray,
      f"unreachable markers in: {', '.join(stray)}")

doc = root / "CONCEPTS.md"
documented = set(re.findall(r"^\| `([a-z0-9-]+)` \|", doc.read_text(), re.M)) if doc.is_file() else set()
check("CONCEPTS.md documents every declared concept", not (set(declared) - documented),
      f"undocumented: {sorted(set(declared) - documented)}")
check("CONCEPTS.md documents nothing the guidelines do not declare",
      not (documented - set(declared)),
      f"documented but absent: {sorted(documented - set(declared))}")

asked = set()
for f in agents.glob("*.md"):
    text = f.read_text()
    asked |= set(re.findall(r"--concept ([a-z0-9-]+)", text))
    # Which caller a component has is chosen per task from a documented set, so an agent
    # offering `--caller` reads all five rather than the one that happens to be written
    # into an example.
    if "--caller" in text:
        asked |= {f"caller-{c}" for c in ("ui", "inbound", "outbound", "async", "exported")}

print("\n".join(out))
print("unread|" + " ".join(sorted(set(declared) - asked)))
PY
)

while IFS= read -r line; do
  case "$line" in
    'ok|'*)     ok "${line#ok|}" ;;
    'fail|'*)   rest="${line#fail|}"; bad "${rest%%|*}" "${rest#*|}" ;;
    'unread|'*) UNREAD="${line#unread|}" ;;
    *)          [ -n "$line" ] && printf '%s\n' "$line" ;;
  esac
done <<< "$CHECKS"

# --------------------------------------------------------------------------------
# Reported, not failed. A guideline may carry a recap nothing needs handing to it; the
# point of listing them is that the set stays a decision rather than an accumulation.
printf '\nconcepts no agent reads\n'
if [ -z "$UNREAD" ]; then
  printf '  none\n'
else
  for c in $UNREAD; do printf '  %s\n' "$c"; done
fi

rm -rf "$FIXTURE"
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
