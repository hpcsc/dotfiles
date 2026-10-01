---
name: learn-from-corrections
description: Turn the corrections a person made to a finished implement run into learnings, guideline entries or lint rules, so that the next run does not repeat them. Reads what changed after the run handed its branch over, finds who made each decision that was corrected, the planned design or the run, and suggests one entry for each lesson that applies beyond the branch. Use after you fix a branch that /implement or /deliver-story built, or when asked to learn from corrections, to find what the run keeps getting wrong, or to stop a mistake that comes back.
---

Learn from the corrections made to a finished run: $ARGUMENTS

A run learns from its own audit and writes the lesson at its `learn` step. A person's corrections come later, after the run handed the branch over, so no step of the run ever reads them. The same correction then comes back in the next run. This skill reads those corrections and turns each one that applies beyond the branch into an entry that the next run reads or that a program enforces.

## 1. Read what changed after the run

```
clerk design corrections [--run <slug>] [--head <ref>]
```

It returns the commit the run handed over (`finished_commit`), the commits and files after it, the design of that change, the planned design the run bound, and the design changes the run recorded with their reasons. Pass `--run` when you are not on the run's branch. Pass `--head` when the corrections are on another ref, for example the default branch after a merge.

- **No commits after `finished_commit`:** there is nothing to learn from. Say so and stop.
- **Commits from other people or other work:** after a merge, the default branch also holds unrelated commits. Read the subjects, and leave out each commit that does not touch the run's work.

Then read the corrections themselves, in one call: `git log -p <finished_commit>..<head_commit> -- <the run's files>`.

## 2. Sort each correction

For each correction, answer two questions.

**Who made the decision that you changed?**

| The decision came from | What it teaches | The step that learns |
| --- | --- | --- |
| The planned design (in `planned`) | The plan chose it wrong | the decompose step |
| A design change the run recorded (in `notes`) | The run left the plan, and chose wrong | the build step and the design check |
| A name or a type that neither the plan nor a note mentions | The run chose it alone, and chose wrong | the build step and the design check |

Also read the other direction: a design change that the person kept means that the planned design missed something. That is a lesson for the decompose step.

**Where does the lesson go?**

| The preference | The entry | What enforces it on the next run |
| --- | --- | --- |
| Only for this repository | `clerk learn add` | the decompose step and the design check |
| For all repositories | an entry in `~/.config/ai/guidelines/naming.md` or in a language guideline | `clerk guidelines`, the design check and the guidelines lens |
| A program can find it without judgment | a rule in `clerk-lint`, or in the refusals of `clerk finish` | `clerk finish`, on each task |

## 3. Keep only what applies again

Use the filter of the `learn` step: keep a candidate only if you can name, in one sentence, the mistake it prevents in a future run. A correction that only fixes this branch, such as a typo or a value, teaches nothing. Say so, and drop it.

Check each candidate against what exists. `clerk learn index` lists the learnings of the repository. Read the guideline that the entry would go in. Do not suggest a second entry for a lesson that one entry already holds; suggest a change to that entry instead.

## 4. Suggest, then ask

Show one row for each entry:

| # | Correction (commit) | Decision from | Lesson | Entry | Where |
| --- | --- | --- | --- | --- | --- |

Then ask the person which entries to write. A guideline and a lint rule change every repository, so they need the person's decision. Do not write an entry that the person did not approve.

## 5. Write the approved entries

- **A learning:** `clerk learn add --type <convention|recurring-finding|constraint|pattern> --title "<title>" --learning "<the fact, 1 to 2 sentences>" --apply-when "<the situation>" --feature "<the run>"`
- **A guideline entry:** edit the guideline file. Follow `~/.config/ai/guidelines/writing/asd-ste100.md`, and add a bad and a good example from the correction.
- **A lint rule:** describe the rule, the code it refuses and the code it accepts, and say where it goes. Write the rule only if the person asks for it.

Then report what you wrote and where, and what you dropped and why.

## What this skill does not do

- **Invent a lesson.** Every entry cites the commit of the correction that it comes from.
- **Change the run's branch.** It reads the corrections. It does not make more of them.
- **Decide for the person.** It suggests the entries. The person approves each one.
