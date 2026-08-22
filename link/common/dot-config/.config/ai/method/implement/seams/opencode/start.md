```
clerk step --start <kebab-slug> --request "<the request, verbatim>" --harness opencode
clerk step
```

`--harness opencode` is said once: the run records it, and every later `clerk step` renders its instructions for this harness — `cd` rather than EnterWorktree, the `task` tool rather than the Agent tool. Without it clerk cannot tell the harnesses apart from the shell it is called from.
