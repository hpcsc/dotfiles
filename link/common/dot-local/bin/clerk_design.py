"""The design of a change, read from its code: the types it adds or changes with their
fields and methods, its package functions, the exported names it adds, and every name it
declares. `clerk design` draws it, and the comparison with a planned design reads it.

The Go source is read by a small program under share/clerk/design-go, built on first use
into the cache. It reads syntax only, so it needs no build of the code it reads. A
language with no reader, and a machine with no Go, are reported as `not_checked` rather
than as a change with no design: an empty design and an unread one must not look alike.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from itertools import combinations
from pathlib import Path

from clerk_lib import gitout

HERE = Path(__file__).resolve().parent
READER_SRC = HERE.parent / "share" / "clerk" / "design-go"

# Methods that a type exports to satisfy an interface of the standard library, which no
# scan of the repository can find.
STD_INTERFACE_METHODS = {
    "String", "GoString", "Format", "Error", "Unwrap", "Is", "As",
    "MarshalJSON", "UnmarshalJSON", "MarshalText", "UnmarshalText", "MarshalBinary",
    "UnmarshalBinary", "MarshalYAML", "UnmarshalYAML", "Scan", "Value", "ServeHTTP",
    "Read", "Write", "Close", "Len", "Less", "Swap", "Seek", "ReadFrom", "WriteTo",
}


# --------------------------------------------------------------------------------
# The reader
# --------------------------------------------------------------------------------

def reader():
    """(path of the built reader, None) or (None, why it is not available)."""
    go = shutil.which("go")
    if not go:
        return None, "go is not installed"
    digest = hashlib.sha1()
    for name in ("go.mod", "main.go"):
        digest.update((READER_SRC / name).read_bytes())
    cache = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "clerk"
    exe = cache / f"design-go-{digest.hexdigest()[:12]}"
    if exe.is_file():
        return str(exe), None
    cache.mkdir(parents=True, exist_ok=True)
    tmp = cache / f"{exe.name}.{os.getpid()}"
    r = subprocess.run([go, "build", "-o", str(tmp), "."], cwd=READER_SRC, capture_output=True, text=True)
    if r.returncode != 0:
        return None, f"the design reader did not build: {r.stderr.strip()}"
    tmp.replace(exe)
    return str(exe), None


def read_packages(exe, root, dirs):
    if not dirs:
        return []
    r = subprocess.run([exe, "design", *dirs], cwd=root, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"the design reader failed: {r.stderr.strip()}")
    return parse_reply(r.stdout)


def parse_reply(text):
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"the design reader returned something that is not JSON: {e}")


# --------------------------------------------------------------------------------
# What changed, and the two sides of it
# --------------------------------------------------------------------------------

def is_go_source(path):
    return path.endswith(".go") and not path.endswith("_test.go")


def changed_dirs(cwd, base, head=None):
    """The package directories whose Go source differs between `base` and `head`, or the
    working tree when `head` is None. The working tree counts staged and untracked files
    too, because `clerk finish` reads the design before the commit exists."""
    if head is None:
        listed = (gitout("diff", "--name-only", base, cwd=cwd) or "").splitlines()
        listed += (gitout("ls-files", "--others", "--exclude-standard", cwd=cwd) or "").splitlines()
    else:
        listed = (gitout("diff", "--name-only", base, head, cwd=cwd) or "").splitlines()
    dirs = {str(Path(p).parent) for p in listed if is_go_source(p)}
    return sorted(dirs)


def dirs_at(cwd, ref, dirs):
    """The directories in `dirs` that exist at `ref`, or in the working tree."""
    if ref is None:
        return [d for d in dirs if (Path(cwd) / d).is_dir()]
    out = []
    for d in dirs:
        # `<ref>:.` is not a path git resolves; the root of the tree is `<ref>^{tree}`.
        spec = f"{ref}^{{tree}}" if d == "." else f"{ref}:{d}"
        if gitout("cat-file", "-t", spec, cwd=cwd) == "tree":
            out.append(d)
    return out


def read_side(exe, cwd, ref, dirs):
    """The packages in `dirs` as `ref` has them, or as the working tree has them."""
    present = dirs_at(cwd, ref, dirs)
    if ref is None:
        return read_packages(exe, cwd, present)
    if not present:
        return []
    with tempfile.TemporaryDirectory(prefix="clerk-design-") as tmp:
        archive = subprocess.run(["git", "archive", ref, "--", *present], cwd=cwd, capture_output=True)
        if archive.returncode != 0:
            raise RuntimeError(f"git archive {ref} failed: {archive.stderr.decode(errors='replace').strip()}")
        untar = subprocess.run(["tar", "-x", "-C", tmp], input=archive.stdout, capture_output=True)
        if untar.returncode != 0:
            raise RuntimeError(f"tar could not unpack {ref}: {untar.stderr.decode(errors='replace').strip()}")
        return read_packages(exe, tmp, present)


# --------------------------------------------------------------------------------
# The comparison
# --------------------------------------------------------------------------------

def exported(name):
    return bool(name) and name[0].isupper()


def signature(f):
    params = ", ".join(f"{p['name']} {p['type']}".strip() for p in f["params"])
    return f"{f['name']}({params}) {', '.join(f['results'])}".strip()


def short_type(t):
    t = t.replace("context.Context", "ctx")
    return t if len(t) <= 24 else t[:22] + "…"


def short_signature(f):
    """`name(params) results`, with the results unbracketed: Mermaid reads the text after
    the last bracket as the return type, so `(Refund, error)` would move a mark after it
    into the return type and leave the results in the method name."""
    params = ", ".join(p["name"] or short_type(p["type"]) for p in f["params"])
    results = ", ".join(short_type(r) for r in f["results"])
    return f"{f['name']}({params}) {results}".strip()


def compare(base_pkgs, head_pkgs):
    """The change from one extraction to the other, package by package."""
    base = {p["dir"]: p for p in base_pkgs}
    packages, exports, names = [], [], []
    for p in head_pkgs:
        bp = base.get(p["dir"]) or {"types": [], "funcs": []}
        is_main = p.get("name") == "main"
        btypes = {t["name"]: t for t in bp["types"]}
        bfuncs = {(f["receiver"], f["name"]): f for f in bp["funcs"]}
        by_receiver = {}
        for f in p["funcs"]:
            by_receiver.setdefault(f["receiver"], []).append(f)

        def note_names(f, where):
            old = bfuncs.get((f["receiver"], f["name"]))
            old_params = {q["name"] for q in (old or {}).get("params", [])}
            old_locals = set((old or {}).get("locals", []))
            for q in f["params"]:
                if q["name"] and q["name"] not in old_params:
                    names.append({"kind": "parameter", "name": q["name"], "package": p["dir"], "where": where})
            for v in f["locals"]:
                if v not in old_locals:
                    names.append({"kind": "variable", "name": v, "package": p["dir"], "where": where})

        types = []
        for t in p["types"]:
            old = btypes.get(t["name"])
            old_fields = {(x["name"], x["type"]) for x in (old or {}).get("fields", [])}
            new_fields = [x for x in t["fields"] if (x["name"], x["type"]) not in old_fields]
            methods = []
            for m in by_receiver.get(t["name"], []):
                prev = bfuncs.get((m["receiver"], m["name"]))
                if prev is None or signature(prev) != signature(m):
                    methods.append({"name": m["name"], "signature": short_signature(m),
                                    "status": "new" if prev is None else "changed",
                                    "exported": exported(m["name"])})
                if prev is None or prev["locals"] != m["locals"] or signature(prev) != signature(m):
                    note_names(m, f"{t['name']}.{m['name']}")
            if old and not new_fields and not methods:
                continue
            status = "changed" if old else "new"
            entry = {"name": t["name"], "kind": t["kind"], "file": t["file"], "status": status,
                     "exported": exported(t["name"]),
                     "fields": [{"name": x["name"], "type": x["type"], "tag": x["tag"]} for x in new_fields],
                     "fields_unchanged": len(t["fields"]) - len(new_fields),
                     "methods": methods}
            types.append(entry)
            if status == "new":
                names.append({"kind": "type", "name": t["name"], "package": p["dir"], "where": t["file"]})
                if exported(t["name"]) and not is_main:
                    exports.append({"name": t["name"], "kind": "type", "package": p["dir"],
                                    "package_name": p.get("name"), "owner": None, "tagged": False})
            for x in new_fields:
                if x["name"]:
                    names.append({"kind": "field", "name": x["name"], "package": p["dir"], "where": t["name"]})
                    if exported(x["name"]) and not is_main:
                        exports.append({"name": x["name"], "kind": "field", "package": p["dir"],
                                        "package_name": p.get("name"), "owner": t["name"],
                                        "tagged": bool(x["tag"])})
            for m in methods:
                if m["status"] == "new":
                    names.append({"kind": "method", "name": m["name"], "package": p["dir"], "where": t["name"]})
                    if m["exported"] and not is_main:
                        exports.append({"name": m["name"], "kind": "method", "package": p["dir"],
                                        "package_name": p.get("name"), "owner": t["name"], "tagged": False})

        functions = []
        for f in by_receiver.get("", []):
            prev = bfuncs.get(("", f["name"]))
            if prev is None or signature(prev) != signature(f):
                functions.append({"name": f["name"], "signature": short_signature(f), "file": f["file"],
                                  "status": "new" if prev is None else "changed",
                                  "exported": exported(f["name"]),
                                  "params": [q["name"] for q in f["params"] if q["name"]],
                                  "refs": [q["type"] for q in f["params"]] + f["results"]})
                if prev is None:
                    names.append({"kind": "function", "name": f["name"], "package": p["dir"], "where": f["file"]})
                    if exported(f["name"]) and not is_main:
                        exports.append({"name": f["name"], "kind": "function", "package": p["dir"],
                                        "package_name": p.get("name"), "owner": None, "tagged": False})
            if prev is None or prev["locals"] != f["locals"] or signature(prev) != signature(f):
                note_names(f, f["name"])

        removed = sorted(set(btypes) - {t["name"] for t in p["types"]})
        if types or functions or removed:
            packages.append({"dir": p["dir"], "name": p.get("name"), "types": types, "functions": functions,
                             "removed_types": removed, "declared": sorted(t["name"] for t in p["types"]),
                             "field_types": {t["name"]: [x["type"] for x in t["fields"]] for t in p["types"]}})
    for dir_ in sorted(set(base) - {p["dir"] for p in head_pkgs}):
        removed = sorted(t["name"] for t in base[dir_]["types"])
        if removed:
            packages.append({"dir": dir_, "name": base[dir_].get("name"), "types": [], "functions": [],
                             "removed_types": removed, "declared": [], "field_types": {}})
    return {"packages": packages, "exported": exports, "names": names,
            "params_together": params_together(packages)}


def params_together(packages):
    """Parameters that three or more package functions take in pairs, grouped: functions
    that keep taking the same values are a type that does not exist yet."""
    out = []
    for p in packages:
        pairs = {}
        for f in p["functions"]:
            ps = sorted(set(q for q, t in zip(f["params"], f["refs"]) if t != "context.Context"))
            for a, b in combinations(ps, 2):
                pairs.setdefault((a, b), set()).add(f["name"])
        groups = []
        for pair, fns in sorted(pairs.items()):
            if len(fns) < 3:
                continue
            for g in groups:
                if g[0] & set(pair):
                    g[0].update(pair)
                    g[1].update(fns)
                    break
            else:
                groups.append([set(pair), set(fns)])
        for params, fns in groups:
            out.append({"package": p["dir"], "params": sorted(params), "functions": sorted(fns)})
    return out


def find_uses(exe, root, design):
    """Who outside each package uses the exported names the change adds. Annotates each
    entry of design["exported"] with `used_by` (files) and `exempt` (why it is exported
    without a use, or None)."""
    by_pkg = {}
    for e in design["exported"]:
        by_pkg.setdefault(e["package"], []).append(e)
    for pkg_dir, entries in by_pkg.items():
        keys = sorted({("member:" if e["kind"] in ("field", "method") else "pkg:") + e["name"] for e in entries})
        r = subprocess.run([exe, "uses", root, pkg_dir, *keys], cwd=root, capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError(f"the design reader failed: {r.stderr.strip()}")
        data = parse_reply(r.stdout)
        interface_methods = set(data.get("interface_methods") or []) | STD_INTERFACE_METHODS
        for e in entries:
            key = ("member:" if e["kind"] in ("field", "method") else "pkg:") + e["name"]
            e["used_by"] = data["uses"].get(key, [])
            if e["kind"] == "field" and e["tagged"]:
                e["exempt"] = "a struct tag"
            elif e["kind"] == "method" and e["name"] in interface_methods:
                e["exempt"] = "an interface method"
            else:
                e["exempt"] = None
    return design


def built(cwd, base, head=None, with_uses=False, extra_dirs=()):
    """The design of the change from `base` to `head` (the working tree when None), or
    {"not_checked": why}."""
    dirs = sorted(set(changed_dirs(cwd, base, head)) | set(extra_dirs))
    if not dirs:
        return {"packages": [], "exported": [], "names": [], "params_together": [], "dirs": []}
    exe, why = reader()
    if not exe:
        return {"not_checked": why}
    design = compare(read_side(exe, cwd, base, dirs), read_side(exe, cwd, head, dirs))
    design["dirs"] = dirs
    if with_uses and head is None and design["exported"]:
        find_uses(exe, cwd, design)
    return design


# --------------------------------------------------------------------------------
# The view
# --------------------------------------------------------------------------------

FILLS = {"new": "fill:#E6F4EA,stroke:#2E7D32", "changed": "fill:#FFF8E1,stroke:#B28704",
         "functions": "fill:#F6F8F7,stroke:#A7B0AB"}
LEGEND = ("Green: new type. Yellow: changed type. Grey: package functions. "
          "`★` new member, `✎` changed signature, `+` exported, `-` unexported.")


def node_id(pkg_dir, name):
    return re.sub(r"\W", "_", f"{pkg_dir}__{name}")


def visibility(name):
    return "+" if exported(name) else "-"


def base_type(t):
    return re.sub(r"^[\[\]*.]+", "", t).split("[")[0]


def diagram(design, styles=None):
    """The Mermaid class diagram of the new and changed types and functions. `styles`
    maps a node id to a style that replaces the default one for its status."""
    lines, relations, fills = ["classDiagram", "  direction LR"], set(), []
    for p in design["packages"]:
        local = set(p["declared"])
        short = p["name"] or Path(p["dir"]).name
        for t in p["types"]:
            nid = node_id(p["dir"], t["name"])
            mark = " ★" if t["status"] == "changed" else ""
            lines.append(f'  class {nid}["{short}.{t["name"]}"] {{')
            if t["kind"] == "interface" or re.fullmatch(r"[\w.]+", t["kind"]) and t["kind"] != "struct":
                lines.append(f"    <<{t['kind']}>>")
            for x in t["fields"]:
                if t["kind"] == "interface" and x["name"]:
                    lines.append(f"    {visibility(x['name'])}{x['name']}(){mark}")
                    continue
                label = x["name"] or "(embedded)"
                lines.append(f"    {visibility(x['name'] or 'x')}{label} {short_type(x['type'])}{mark}")
            if t["fields_unchanged"] and t["status"] == "changed":
                lines.append(f"    …{t['fields_unchanged']} fields unchanged")
            for m in t["methods"]:
                tail = " ✎" if m["status"] == "changed" else mark
                lines.append(f"    {visibility(m['name'])}{m['signature']}{tail}")
            lines.append("  }")
            fills.append((nid, t["status"]))
            for ft in p["field_types"].get(t["name"], []):
                ref = base_type(ft)
                if ref in local and ref != t["name"]:
                    relations.add((nid, "*--", node_id(p["dir"], ref)))
        if p["functions"]:
            nid = node_id(p["dir"], "functions")
            lines.append(f'  class {nid}["{short} functions"] {{')
            for f in p["functions"]:
                tail = " ✎" if f["status"] == "changed" else ""
                lines.append(f"    {visibility(f['name'])}{f['signature']}{tail}")
            lines.append("  }")
            fills.append((nid, "functions"))
            for ref in f_refs(p["functions"]):
                if ref in local:
                    relations.add((nid, "..>", node_id(p["dir"], ref)))
    ids = {nid for nid, _ in fills} | set((styles or {}).keys())
    for a, arrow, b in sorted(relations):
        if a in ids and b in ids:
            lines.append(f"  {a} {arrow} {b}")
    for nid, status in fills:
        lines.append(f"  style {nid} {(styles or {}).get(nid) or FILLS[status]}")
    return "\n".join(lines)


def f_refs(functions):
    return sorted({base_type(t) for f in functions for t in f["refs"]})


def exported_table(design):
    rows = design["exported"]
    if not rows:
        return "The change adds no exported name.\n"
    checked = any("used_by" in e for e in rows)
    head = "| Name | Kind | Where |" + (" Used outside its package by |" if checked else "")
    out = [head, "| --- | --- | --- |" + (" --- |" if checked else "")]
    for e in rows:
        where = f"{e['package']}" + (f" `{e['owner']}`" if e["owner"] else "")
        row = f"| `{e['name']}` | {e['kind']} | {where} |"
        if checked:
            if e.get("used_by"):
                use = ", ".join(e["used_by"])
            elif e.get("exempt"):
                use = e["exempt"]
            else:
                use = "**nothing**"
            row += f" {use} |"
        out.append(row)
    return "\n".join(out) + "\n"


def params_table(design):
    rows = design["params_together"]
    if not rows:
        return None
    out = ["| Parameters | Functions that take two or more of them |", "| --- | --- |"]
    for g in rows:
        out.append(f"| {', '.join(f'`{x}`' for x in g['params'])} | "
                   f"{', '.join(f'`{x}`' for x in g['functions'])} |")
    return "\n".join(out) + "\n"


def render_built(design, title="Built design", styles=None, sections=()):
    """The design view as Markdown. `sections` are (heading, body) pairs added after the
    generated ones."""
    out = [f"# {title}", ""]
    if design.get("not_checked"):
        out += [f"The design was not read: {design['not_checked']}.", ""]
        return "\n".join(out)
    if not design["packages"]:
        out += ["The change adds or changes no Go type or function.", ""]
    else:
        out += ["## New exported names", "", exported_table(design)]
        out += ["## Types and functions", "", LEGEND, "", "```mermaid", diagram(design, styles), "```", ""]
        table = params_table(design)
        if table:
            out += ["## Parameters passed together", "",
                    "Functions that keep taking the same parameters are a type that does not exist yet.", "",
                    table]
    for heading, body in sections:
        out += [f"## {heading}", "", body.rstrip("\n"), ""]
    return "\n".join(out)
