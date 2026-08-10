| `EnterWorktree` unavailable or refused | Fall back to `--in-place`: feature branch in the main checkout. Say which you used — it changes where the user finds the code. |
| Worktree based on `origin/<default>` but the work needs unpushed local commits | Re-run with `--in-place`, or set `worktree.baseRef: head`. Do not cherry-pick around it. |
