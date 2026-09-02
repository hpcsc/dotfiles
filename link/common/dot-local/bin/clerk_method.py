"""The method's markup, resolved one way for both of its readers.

A method body and its step files carry four markers: `{{seam:name}}` pulls in the
per-harness fragment `seams/<harness>/name.md`, `{{include:path.md}}` pulls in a file
under the method root, `{{quote:path.md}}` pulls one in as a block quote, and `{{var}}`
is filled from the harness's `vars.tsv`. `gen-skills.sh` renders whole bodies into
SKILL.md files and `clerk step` renders one step file at a time, and until this module
each had its own resolver: the generator's awk knew every marker and the step's Python
knew two, so a step file that used the other two printed them raw to the model.
"""

import re
import sys
from pathlib import Path

MAX_DEPTH = 3

_SEAM = re.compile(r"^\{\{seam:([a-z-]+)\}\}$")
_INCLUDE = re.compile(r"^\{\{include:([a-z0-9/-]+\.md)\}\}$")
_QUOTE = re.compile(r"^\{\{quote:([a-z0-9/-]+\.md)\}\}$")
_ANY = re.compile(r"\{\{(seam|include|quote):")


class MethodError(Exception):
    pass


def read_vars(path):
    out = {}
    try:
        text = Path(path).read_text()
    except OSError:
        return out
    for line in text.splitlines():
        if re.match(r"^[a-z_]+\t", line):
            k, _, v = line.partition("\t")
            out[k] = v
    return out


class Renderer:
    """`strict` raises on a missing fragment or an unresolved marker, which is what a
    generator wants; otherwise the hole is marked in place, which is what a step printed
    to a model wants — a comment naming the missing seam beats a crash mid-run."""

    def __init__(self, root, seams, strict=True):
        """`root` is the method root that `{{include:}}` and `{{quote:}}` paths hang off;
        `seams` is the one harness's seam directory, with its `vars.tsv`."""
        self.method = Path(root)
        self.seams = Path(seams)
        self.vars = read_vars(self.seams / "vars.tsv")
        self.strict = strict

    def render_text(self, text, origin="<body>"):
        return "\n".join(self._lines(text.splitlines(), origin, 0))

    def render_file(self, path):
        return self.render_text(Path(path).read_text(), str(path))

    def _subst(self, line):
        for k, v in self.vars.items():
            line = line.replace("{{" + k + "}}", v)
        return line

    def _fragment(self, path, depth):
        p = Path(path)
        if not p.exists():
            if self.strict:
                raise MethodError(f"no such fragment {p}")
            return [f"<!-- no fragment {p} -->"]
        return self._lines(p.read_text().splitlines(), str(p), depth)

    def _lines(self, lines, origin, depth):
        out = []
        for line in lines:
            m = _SEAM.match(line)
            if m and depth < MAX_DEPTH:
                out += self._fragment(self.seams / f"{m.group(1)}.md", depth + 1)
                continue
            m = _INCLUDE.match(line)
            if m and depth < MAX_DEPTH:
                out += self._fragment(self.method / m.group(1), depth + 1)
                continue
            m = _QUOTE.match(line)
            if m:
                out += self._quote(self.method / m.group(1))
                continue
            if _ANY.search(line):
                if self.strict:
                    raise MethodError(f"unresolved marker in {origin}: {line}")
                out.append(f"<!-- unresolved marker: {line} -->")
                continue
            out.append(self._subst(line))
        return out

    def _quote(self, path):
        p = Path(path)
        if not p.exists():
            if self.strict:
                raise MethodError(f"no such fragment {p}")
            return [f"<!-- no fragment {p} -->"]
        return [("> " + self._subst(l)) if l else ">" for l in p.read_text().splitlines()]


def main(argv):
    """clerk_method.py <method-root> <seams-dir> <body-file>: the body rendered to
    stdout, exit 3 with the reason on stderr when a marker cannot be resolved."""
    if len(argv) != 3:
        print("usage: clerk_method.py <method-root> <seams-dir> <body-file>", file=sys.stderr)
        return 2
    root, seams, body = argv
    try:
        text = Renderer(root, seams).render_file(body)
    except MethodError as e:
        print(f"gen-skills: {e}", file=sys.stderr)
        return 3
    sys.stdout.write(text + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
