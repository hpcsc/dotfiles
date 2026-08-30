#!/usr/bin/env python3
"""Generate audit-implement's Workflow script from its method body plus the shared
prompt fragments.

The prose in those fragments is the audit itself — the lens briefs, the finding
contract, the dedupe, verify and report rules — and the opencode skill states the same
procedure in markdown. Written twice, the two drifted: the same lens carried different
instructions on each side, and nothing failed to say so.

A Workflow script cannot read files at run time, so it cannot reference the fragments
the way opencode's SKILL.md includes them. It gets them spliced in instead, JSON-encoded
so no markdown character has to be escaped by hand.

Usage: scripts/gen-workflow.py [--check]
  --check  exit 1 if the generated file is out of date, changing nothing
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
METHOD = ROOT / "link/common/dot-config/.config/ai/method"

# method-dir  ->  output path. Empty since the audit's orchestration moved into
# `clerk audit run`, which both harnesses now launch; a method that wants a Workflow
# script again adds its entry here.
TARGETS = {}

BANNER = """// GENERATED from ~/.config/ai/method/{name}/ — edit body.js or a file under
// prompts/, then run `task gen:skills`. Edits made here are overwritten.
//
// The prompts/ fragments are shared with the opencode skill, which states the same
// procedure as markdown. Change the prose in one place and both harnesses follow."""

FILL = """// Substitute a fragment's {{name}} placeholders. An unfilled one becomes empty rather
// than staying literal — a prompt that ships `{{reading}}` to a model reads as a bug the
// model then has to guess around.
const fill = (s, vars) => s.replace(/\\{\\{(\\w+)\\}\\}/g, (_, k) => vars[k] ?? '')"""


def render(name):
    src = METHOD / name
    body = (src / "body.js").read_text(encoding="utf-8")
    frags = sorted((src / "prompts").glob("*.md"))
    if not frags:
        raise SystemExit(f"gen-workflow: no prompt fragments under {src / 'prompts'}")

    entries = []
    for f in frags:
        # The trailing newline is an artifact of the file, not of the prose: every
        # fragment ends where its own text ends, and the caller decides the spacing.
        entries.append(f"  {json.dumps(f.stem)}: {json.dumps(f.read_text(encoding='utf-8').rstrip(chr(10)))},")
    block = BANNER.format(name=name) + "\nconst PROMPTS = {\n" + "\n".join(entries) + "\n}\n\n" + FILL

    marker = "{{prompts}}"
    if body.count(marker) != 1:
        raise SystemExit(f"gen-workflow: {src / 'body.js'} must carry exactly one {marker}")
    out = body.replace(marker, block)

    # A fragment referenced by a name no file provides would fail only at run time, in a
    # background workflow, as an agent prompted with the word "undefined".
    names = {f.stem for f in frags}
    for ref in sorted(set(__import__("re").findall(r"PROMPTS\['([a-z0-9-]+)'\]", out))):
        if ref not in names:
            raise SystemExit(f"gen-workflow: body.js references PROMPTS['{ref}'], which has no fragment")
    return out


def main():
    check = "--check" in sys.argv[1:]
    failed = False
    for name, out_path in TARGETS.items():
        rendered = render(name)
        rel = out_path.relative_to(ROOT)
        if check:
            current = out_path.read_text(encoding="utf-8") if out_path.exists() else None
            if current != rendered:
                print(f"out of date: {rel}", file=sys.stderr)
                failed = True
            else:
                print(f"up to date:  {rel}")
        else:
            out_path.parent.mkdir(parents=True, exist_ok=True)
            out_path.write_text(rendered, encoding="utf-8")
            print(f"wrote {rel} ({rendered.count(chr(10)) + 1} lines)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
