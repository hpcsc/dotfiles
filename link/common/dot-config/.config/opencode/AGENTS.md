# Tools for shell interactions

## Finding code structure

You run in an environment where `ast-grep is available`.
Whenever a search requires syntax-aware or structural matching, default to `ast-grep -p '<pattern>'` (and set `--lang` appropriately).
Avoid falling back to text-only tools like `rg` or `grep` unless I explicitly request a plain-text search.

## Others

- Finding files: use `fd`
- Finding text/strings: use `rg`
- Selecting from multiple results: pipe to `fzf`
- Interacting with JSON: use `jq`
- Interacting with YAML or XML: use `yq`
