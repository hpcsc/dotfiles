# Tooling for shell interactions 

You run in an environment where `ast-grep` is available; whenever a search requires syntax-aware or structural matching, default to `ast-grep -p '<pattern>'` (and set `--lang` appropriately) and avoid falling back to text-only tools like `rg` or `grep` unless I explicitly request a plain-text search.

Is it about finding FILES? use 'fd' 
Is it about finding TEXT/strings? use 'rg' 
Is it about finding CODE STRUCTURE? use 'ast-grep'
Is it about SELECTING from multiple results? pipe to 'fzf' 
Is it about interacting with JSON? use 'jq' 
Is it about interacting with YAML or XML? use 'yq'

# Development workflow

Follow @~/.claude/kent-beck-workflow.md for general development workflow
