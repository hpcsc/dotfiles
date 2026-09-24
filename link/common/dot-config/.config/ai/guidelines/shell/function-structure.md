# Shell Function Structure

A shell script reads top to bottom as a pipeline of named stages, and each stage
takes its input as arguments and answers on stdout. This is the same shape as a
shell pipeline, without the literal pipe.

## 1. main() is the pipeline

Keep the top level of a script down to three things: the constants a stage needs,
small failure helpers, and `main()`. `main()` calls the stages in order, so the
reader sees the sequence of the script in one glance and can open a stage when a
step needs attention.

```sh
main() {
	parse_args "$@"
	require_tools

	tag=$(resolve_version)
	install_binary "$tag"
	print_done "$tag"
}

main "$@"
```

No top-level flow between the globals and `main "$@"`. Anything a script does
after `set -eu` and before `main()` is a stage that failed to get a name.

## 2. A stage takes arguments and answers on stdout

A value-producing stage receives what it needs as arguments and prints exactly one
answer on stdout. The caller reads the answer with command substitution, so the
call site reads like a value passing from one stage to the next.

```sh
tag=$(choose_version "$matches")
channel=$(choose_channel "$flag_channel")
```

The stage names its own inputs. Do not read shared state, consumers, or globals
the caller has no way to predict.

## 3. Progress goes to stderr inside a value stage

stdout is the answer channel in a captured stage, so anything the stage prints for
the user — a prompt, a hint, progress — must go to stderr with `>&2`. A prompt or
a listing that stays on stdout lands inside the returned value.

```sh
choose_version() {
	matches=$1
	printf 'Which version? [1]: ' >&2
	...
	printf '%s\n' "$tag"   # the answer
}
```

`die()` already writes to stderr and exits 1, so it is always safe inside a
captured stage.

## 4. Side-effect stages run as statements

A stage whose work is a side effect and whose output is not captured (download,
extract, install) is a plain call in `main()`. It can print to stdout because no
listener is capturing it. Add it to the pipeline only when its result is actually
consumed.

## 5. Errors exit, they do not pipe

Keep `set -eu` and fail hard. A stage reports failure by printing to stderr and
exiting 1 (`die`), and an external fetch gets an explicit guard:

```sh
releases_json=$(api_releases) || die 'could not fetch the releases'
```

A stage that fails this way stops the script at the exact stage that failed. That
is the point of the structure: the error lands on its own stage, not on a
consumer.

## 6. No literal pipes between stages

Do not chain stages with `|`. Two ways it breaks:

- **`set -e` cannot see a failing middle stage.** A pipeline's status is the last
  command's. `set -o pipefail` would fix it, but dash — the default `/bin/sh` on
  Linux — does not support pipefail. `stage_a | stage_b` under `set -eu` runs
  `stage_b` on `stage_a`'s garbage when `stage_a` fails, and the script continues
  instead of stopping.
- **A pipe owns the pipeline's stdin.** Interactive stages `read` their prompts
  from stdin. As a pipe component their stdin is the pipe, so the first `read`
  consumes the piped value instead of the user's answer.

Pipes to a plain tool inside a stage (for example `printf '%s\n' "$json" | jq ...`)
are fine. The limit is on making a stage a pipe component.

## 7. Two results use two named globals

A stage that answers with one value prints it. A stage that answers with two
closely related values — say a URL pair — sets two named globals instead, and its
comment names them:

```sh
# find_release stores the URLs in archive_url and checksums_url.
find_release() { ... }
```

Packing both values into one string and re-parsing it at the call site passes the
reader two puzzles. A named global needs no packing or re-parsing.

## Review

- Top-level flow between the globals and `main "$@"`
- A stage that reads a global instead of taking it as an argument
- A prompt, a listing, or progress on stdout inside a captured stage
- A stage that returns a value but is called only for its side effect
- A `|| die` guard missing from an external fetch
- A stage chained to another with `|`
- Two values packed into one answer string instead of two named globals