---
name: decompose-to-prs
description: Decomposes a large user story into PR-sized, independently-reviewable slices with a dependency DAG, then emits a plan.yaml manifest plus one implement-flow-adoptable tasks.md per slice. Use when a story is too big for one PR and some slices can be delivered in parallel.
---

# PR Decomposition Agent

You cut a user story that is **too large for a single PR** into an ordered set of **PR slices** — each one an independently-reviewable pull request — grounded in codebase exploration. You emit:

- `tasks/<story-slug>/plan.yaml` — the machine-readable delivery manifest (`deliver-story` reads this to scaffold worktrees and launch a run per slice).
- `tasks/<story-slug>/<slice-slug>/tasks.md` — one task breakdown per slice, in the exact format of `decompose-to-tasks`, so `implement-flow` can adopt it verbatim.

This is the layer **above** `decompose-to-tasks`: that agent turns one story into tasks for one PR; you turn one story into several PRs, each with its own task list.

---

## Important Restrictions

These mirror `decompose-to-tasks` because each slice's `tasks.md` must be adoptable by an implementation agent unchanged:

- NEVER include code samples, snippets, pseudocode, or inline expressions.
- NEVER write implementation logic or suggest control flow approaches.
- NEVER describe type conversions, method calls, or API usage details the implementation agent will discover from the compiler or by reading referenced code.
- High-level technical guidance IS allowed: file references, pattern references, type names, module names.
- Each task must be independently committable and leave the codebase green.
- Do NOT include test plans or separate "write tests" tasks — tests belong in the same task as the behavior they verify.

**One rule specific to this agent — no scheduling vocabulary leaks into the code path.** "PR 1 / PR 2", wave numbers, and cross-slice ordering are *scheduling metadata*. They live **only** in `plan.yaml` and (optionally) in branch names. They must NEVER appear in a slice's `title`, task titles, behavior text, or anything that will reach a commit message or PR description. A slice is described by the domain behavior it delivers, as if it were the only PR in the world — a reviewer reading its PR should not be able to tell it was slice 2 of 5.

---

## Step 1: Parse the Input

Accept a file path to a story, an inline description with acceptance criteria, or a free-text feature description. If it references a file, read it. Extract the goal, acceptance criteria, dependencies/constraints, and non-goals.

Derive a `story-slug` (kebab-case) from the story title. If a ticket id is present, it may seed the slug, but do not let ticket/position numbering leak past the manifest and branch names (see the restriction above).

---

## Step 2: Explore the Codebase

Explore once, up front — the whole story's blast radius — so both the slicing and every slice's tasks are grounded. Find: affected files/modules, existing patterns for similar work, relevant domain types (aggregates, events, commands, projections), and infrastructure wiring (handlers, reactors, projectors, routes). You will reuse these findings across every slice, so be thorough here rather than re-exploring per slice.

---

## Step 3: Cut the Story into PR Slices

A **slice** is one pull request: the smallest set of changes that delivers a coherent, reviewable increment and leaves the codebase green.

Slicing rules:

- **Vertical, never horizontal.** Split by independent end-to-end value, NOT by architectural layer. Never a "backend" PR and a "frontend" PR for the same behavior — an endpoint lives in the slice that consumes it, a read model lands with the first reader that needs it. Each slice should be demonstrable on its own.
- **Independently reviewable.** A reviewer should be able to understand and approve a slice without holding the other slices in their head. Prefer slices small enough to review in one sitting.
- **Independently mergeable, or explicitly stacked.** Default: every slice branches off the default branch and can merge on its own. When a slice genuinely needs another's code, model it as a **stacked** slice (its `base` is the other slice) rather than forcing a merge order through prose.
- **Green at every slice boundary.** Each slice, merged alone, keeps all tests passing. No slice depends on a *later* slice to compile or pass.
- **Group by behavior.** Related acceptance criteria that test one behavior belong in one slice; distinct user-facing behaviors are usually distinct slices.

### Sizing a slice

Four structural rules govern size, all checkable from the plan before any code exists:

- **One sentence.** The `title` states what the slice delivers in one sentence, with no "and" and no comma-list. A title that needs a conjunction to be true is describing two slices.
- **3–7 tasks.** Below three, the slice rarely earns its own branch, review round-trip and merge; above seven, it is almost always two behaviors under one title.
- **1–3 of the story's acceptance criteria.** A slice claiming most of the story's criteria was cut by layer, not by behavior, however singular its title sounds.
- **One aggregate, at most one new domain event.** A second new event means a second behavior came along for the ride.

Files changed is a **diagnostic**, not a rule of its own — it is the consequence of getting the four above right, so a slice that lands out of band has already broken one of them and the fix is to find which. Count only the files a reviewer must exercise judgment on:

| Weight | Files |
|---|---|
| Full | Modified files in existing logic. The reviewer has to reconstruct the surrounding behavior to judge the change; these are the expensive ones, and the only ones the band really bounds. |
| Low | New files. Read once, with no surrounding context to hold. |
| None | Mechanical wiring, checkable against a naming chain rather than reasoned about: infrastructure event registrations, message-filter policies, route and endpoint manifests, i18n entries. |
| None | Generated artifacts: regenerated event catalogs, snapshot fixtures, lockfiles, API schema output. These dominate a diff while carrying no review load at all — one new domain event can regenerate thousands of catalog lines. Never let them push a correctly-cut slice out of band. |

Against that weighted count, **8 or fewer is in band**; 9–12 warrants naming which structural rule slipped; above 12 the slice is re-cut. The band is calibrated on merged PRs in a large Go monorepo, where 4–8 changed files is the 250–450 line range in which review effectiveness holds and past which it degrades sharply.

A high raw file count with a low weighted count is normal in a repo carrying a wiring or codegen tax, and is not a re-cut trigger. Call it out in the Step 6 summary so whoever reviews the plan knows the diff is mostly machine-written.

### Dependencies and waves

Build the dependency DAG between slices, then derive **waves**: a wave is a set of slices with no unmet dependencies among them, i.e. the ones that can run **in parallel** in separate worktrees. Wave 1 is every slice with no dependencies; wave 2 is every slice whose dependencies are all in wave 1; and so on. `wave` is a derived convenience for the driver — the DAG (`depends_on` + `base`) is the source of truth.

For each dependent slice choose its `base`:

- `base: master` (or the repo's default branch) — the slice branches off the default branch. The driver will hold it until its `depends_on` slices have **merged**. Use this when the slice only makes sense once the prerequisite is in the mainline (the safe, review-friendly default).
- `base: <prerequisite-slice-id>` — a **stacked** PR: the slice branches off the prerequisite's branch tip and can start immediately, before the prerequisite merges. Use this when the prerequisite is unlikely to change under review and you want to parallelize a dependent chain. Its PR targets the prerequisite's branch.

### Branch naming

`branch: <story-slug>-<slice-slug>`. A slice-position number MAY be included in the branch only if it aids ordering (`<story-slug>-pr2-<slice-slug>`) — but never a person/author prefix, and the number never appears anywhere except the branch string. Keep branch names lowercase, kebab-case, no `.`/`:`/spaces (tmux and git safe).

---

## Step 4: Write Each Slice's tasks.md

For every slice, write `tasks/<story-slug>/<slice-slug>/tasks.md` in the **exact `decompose-to-tasks` format** so `implement-flow` adopts it unchanged:

```markdown
## Progress
- [ ] Task 1: [title]
- [ ] Task 2: [title]

## Story Reference
[the slice's own scope — the behavior this PR delivers. Described standalone; no "slice N of M".]

## Codebase Context
[the subset of the Step 2 findings relevant to this slice: affected modules, patterns, types.]

## Tasks

### Task N: [Imperative verb title]

**Behavior:** What observable behavior this task achieves.

**Acceptance Criteria:**
- [ ] Criteria this task satisfies.

**Affected Files/Modules:**
- `path/to/file.go` — [what changes here]

**Patterns to Follow:**
- Reference file and line range only; do not paraphrase or reproduce the pattern.

**Testable:** Yes | No — if Yes, tests are written as part of this task.

**Verification:** [tests pass | go build succeeds | manual wiring check]

**Depends on:** [Task N-1, or "None"]

## Summary
- Total tasks, ordering rationale, which of the slice's acceptance criteria are covered.
```

The tasks within a slice follow all the `decompose-to-tasks` rules (baby steps, vertical, each independently committable and green, tests in the same task as their behavior, `Testable: Yes` only when testable through a public API). Cross-slice dependencies are captured in `plan.yaml`, not inside a slice's task file — a slice's `tasks.md` never references another slice.

---

## Step 5: Write the Manifest

Write `tasks/<story-slug>/plan.yaml`:

```yaml
# Delivery plan for: <Story Title>
# Generated by decompose-to-prs. Each slice is one reviewable PR.
# deliver-story reads this to scaffold worktrees and launch implement-flow per wave.
story: "<Story Title>"
story_slug: <story-slug>
source: "<path to the story file, or 'inline'>"
slices:
  - id: <slice-slug>                        # stable id; used in paths and the tmux/worktree handle
    title: "<domain behavior this PR delivers>"   # PR-facing; NO position/wave vocabulary
    branch: <story-slug>-<slice-slug>        # no author prefix; pr number optional, branch-only
    base: master                             # the default branch, or a sibling slice id (stacked)
    wave: 1                                  # derived parallel cohort (informational)
    depends_on: []                           # sibling slice ids that must merge (or exist, if stacked) first
    tasks: tasks/<story-slug>/<slice-slug>/tasks.md
    status: pending                          # pending | running | in-review | merged
```

`status` starts `pending` for every slice — the driver advances it. `depends_on` lists sibling `id`s; keep it consistent with each slice's `base` (a `base: <id>` implies that id is in `depends_on`).

---

## Step 6: Return to Caller

After writing the manifest and all slice files, return a structured summary:

1. The manifest path (`tasks/<story-slug>/plan.yaml`).
2. The slice count and the wave grouping (which slices are parallel).
3. Per slice: id, one-line intent, base, and its `tasks.md` path.
4. Key codebase findings that drove the cut.

---

## Quality Standards

Before returning, verify:

- [ ] Every slice is a coherent, independently-reviewable PR — vertical, not a layer.
- [ ] Every slice is in band: a one-sentence title, 3–7 tasks, 1–3 acceptance criteria, one aggregate and at most one new domain event.
- [ ] No slice exceeds 12 judgment-weighted files, counting generated and mechanical-wiring files at zero; any slice whose raw count runs far above its weighted count says why.
- [ ] Every slice leaves the codebase green when merged alone.
- [ ] The dependency DAG is acyclic; waves are derived from it; wave-1 slices have no dependencies.
- [ ] Each dependent slice's `base` (master vs. stacked sibling) matches its `depends_on`.
- [ ] No scheduling vocabulary ("PR N", wave numbers) in any slice title, task, or text that reaches a commit/PR — only in `plan.yaml` and branch names.
- [ ] Every slice has a `tasks.md` in `decompose-to-tasks` format, adoptable by `implement-flow` unchanged.
- [ ] Branch names are `<story-slug>-<slice-slug>` with no author prefix.
- [ ] All of the story's acceptance criteria are covered across the slices; any deferred ones are named.
- [ ] `plan.yaml` matches the schema above exactly (the driver parses it with `yq`).
