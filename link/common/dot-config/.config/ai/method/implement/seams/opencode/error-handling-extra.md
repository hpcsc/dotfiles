| `clerk worktree` fails | Fall back to `--in-place` on a feature branch, and say which you used — it changes where the user finds the code. |
| `clerk worktree` refuses the branch as checked out in the main tree | Something has that branch open already. Switch the main checkout away, or build there deliberately with `--in-place` — do not create a second tree for one feature. |
| A path resolves in the wrong tree | `cd "$WT"` runs at setup so all operations target the worktree; the main repo root comes from `clerk prepare`'s `repo_root`. A relative path resolved in the wrong checkout is how a file looks deleted while still sitting in the other one. |

---

## Implementation notes

This skill spawns subagents via the opencode `task` tool with complete, self-contained prompts: `decompose-to-tasks` for planning, `commit` for commits, `run-verifier` for the judgment residue after `clerk verify`, and — through `audit-implement` — the review lenses. Everything else is your own work, which is the point.
