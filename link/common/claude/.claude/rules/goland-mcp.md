---
paths:
  - "**/*.go"
---

# GoLand MCP Tools

When `mcp__goland__*` tools are available as deferred tools, fetch their schemas and prefer them over built-in tools for Go code operations:

- **Symbol search**: `mcp__goland__search_symbol` over Grep for finding Go symbols (types, functions, variables)
- **Rename**: `mcp__goland__rename_refactoring` over manual Edit for renaming types, functions, or variables across files
- **Diagnostics**: `mcp__goland__get_file_problems` to verify changes compile after edits
- **Symbol info**: `mcp__goland__get_symbol_info` for go-to-definition and type information
- **Reformat**: `mcp__goland__reformat_file` after editing Go files
- **Build**: `mcp__goland__build_project` to validate multi-file changes compile (supports `filesToRebuild` for specific files, not subdirectories)
