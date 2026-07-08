export const meta = {
  name: 'implement-flow',
  description:
    'Autonomous, gate-free, evidence-closed implementation. Decomposes a story, then runs each task through design -> implement -> refactor -> review -> verify, closing on executed evidence (raw receipts + reproduced findings) instead of human approval gates.',
  phases: [
    { title: 'Decompose', detail: 'break the story into dependency-ordered tasks' },
    { title: 'Implement', detail: 'per task: design tests, implement, refactor, review' },
    { title: 'Verify', detail: 'reproduce findings + audit acceptance criteria against re-executed evidence' },
    { title: 'Replan', detail: 'after a task closes, reassess and re-decompose the remaining plan if its premises changed' },
    { title: 'Finalize', detail: 'commit closed tasks, full-suite receipt, archive task file, optional branch integration, distil learnings' },
  ],
}

// ---------------------------------------------------------------------------
// Config — mirrors the implement / implement-auto Language Configuration table.
// ---------------------------------------------------------------------------

const DISCLOSURE =
  'Each guideline opens with an HTML comment `<!-- index: 1-N -->` on line 1 giving the Section Index range. ' +
  'Read line 1 only, then the index range, then `rg -n` the headings you need and read only those sections. Do NOT read the file end-to-end.'

const CALLER_PATTERNS = '~/.config/ai/guidelines/testing/caller-patterns.md'

const LANG = {
  Go: {
    implementer: 'go-implementer',
    refactorer: 'go-refactorer',
    reviewers: ['go-semantic-reviewer', 'go-guidelines-reviewer', 'go-concurrency-reviewer', 'go-performance-reviewer'],
    guidelines: [CALLER_PATTERNS, '~/.config/ai/guidelines/go/testing-patterns.md'],
  },
  'JavaScript/TypeScript': {
    implementer: 'js-implementer',
    refactorer: 'js-refactorer',
    reviewers: ['js-semantic-reviewer', 'js-guidelines-reviewer', 'js-concurrency-reviewer', 'js-performance-reviewer'],
    guidelines: [CALLER_PATTERNS, '~/.config/ai/guidelines/javascript/testing-patterns.md'],
  },
  Elixir: {
    implementer: 'elixir-implementer',
    refactorer: 'elixir-refactorer',
    reviewers: ['elixir-semantic-reviewer', 'elixir-guidelines-reviewer', 'elixir-concurrency-reviewer', 'elixir-performance-reviewer'],
    guidelines: [CALLER_PATTERNS, '~/.config/ai/guidelines/elixir/testing-patterns.md'],
  },
  Generic: {
    implementer: 'general-purpose',
    refactorer: 'refactorer',
    reviewers: ['semantic-reviewer', 'concurrency-reviewer', 'performance-reviewer'],
    guidelines: [CALLER_PATTERNS],
  },
}

// Decompose agents emit free-form language labels (e.g. "go", "golang", "ts").
// Normalise them to the canonical LANG keys so a Go task gets the Go-specific
// implementer/reviewers instead of silently falling through to Generic.
const LANG_ALIASES = {
  go: 'Go',
  golang: 'Go',
  js: 'JavaScript/TypeScript',
  ts: 'JavaScript/TypeScript',
  javascript: 'JavaScript/TypeScript',
  typescript: 'JavaScript/TypeScript',
  'javascript/typescript': 'JavaScript/TypeScript',
  elixir: 'Elixir',
  ex: 'Elixir',
}

const cfgFor = (language) => {
  if (language && LANG[language]) return LANG[language]
  const canonical = language && LANG_ALIASES[String(language).trim().toLowerCase()]
  return (canonical && LANG[canonical]) || LANG.Generic
}

const TEST_CMD = args?.testCommand ?? '(detect the project test command yourself: Makefile, package.json scripts, or framework convention)'
const MAX_RESOLVE = args?.maxResolve ?? 3
const MAX_REPLANS = args?.maxReplans ?? 2
const INTEGRATE = args?.integrate === true

// ---------------------------------------------------------------------------
// Reviewer triage — computed from the REAL changed files, not the decompose-time
// estimate. A docs/config-only change (README, JSON, YAML, ...) gets NO code
// reviewers; for code, concurrency/performance run only when the change signals
// their concern. Static so no classifier agent is spawned (that would be the very
// waste this avoids). Build/task files (Makefile, Taskfile, *.mk) count as
// docs/config too; other extension-less files (Dockerfile, Brewfile) count as
// code so we never skip review on something that might carry logic.
// ---------------------------------------------------------------------------

const NONCODE_EXT = new Set([
  'md', 'markdown', 'txt', 'rst', 'adoc', 'json', 'yaml', 'yml', 'toml', 'ini',
  'cfg', 'conf', 'csv', 'lock', 'mk', 'svg', 'png', 'jpg', 'jpeg', 'gif', 'webp',
])

const NONCODE_BASENAMES = new Set(['makefile', 'gnumakefile', 'taskfile'])

const isCodeFile = (p) => {
  const base = (p.split('/').pop() ?? p).toLowerCase()
  const stem = base.includes('.') ? base.slice(0, base.indexOf('.')) : base
  if (NONCODE_BASENAMES.has(base) || NONCODE_BASENAMES.has(stem)) return false
  if (!base.includes('.')) return true
  return !NONCODE_EXT.has(base.split('.').pop())
}

const kindOf = (r) =>
  r.includes('concurrency') ? 'concurrency'
    : r.includes('performance') ? 'performance'
      : r.includes('guidelines') ? 'guidelines'
        : 'semantic'

const CONCURRENCY_HINTS = /goroutine|channel|mutex|\block\b|atomic|async|await|thread|concurren|genserver|\bets\b|\brace\b|transaction|sync\.|semaphore|worker/i
const PERF_HINTS = /http|query|database|\bdb\b|readall|\bfile\b|stream|\bloop\b|cache|retry|poll|alloc|buffer|batch|pagination|\bindex\b/i

const selectReviewers = (cfg, task, changedFiles) => {
  const codeFiles = (changedFiles ?? []).filter(isCodeFile)
  if (codeFiles.length === 0) return { reviewers: [], reason: 'docs/config-only change — no code reviewers' }
  const hay = `${task.description} ${task.behavior} ${(changedFiles ?? []).join(' ')}`.toLowerCase()
  const reviewers = cfg.reviewers.filter((r) => {
    const k = kindOf(r)
    if (k === 'concurrency') return CONCURRENCY_HINTS.test(hay)
    if (k === 'performance') return PERF_HINTS.test(hay)
    return true
  })
  return { reviewers, reason: null }
}

// ---------------------------------------------------------------------------
// Schemas — the evidence contract. Every executable claim must arrive as a raw
// receipt (command + raw output tail + boolean), never as narrated prose.
// ---------------------------------------------------------------------------

const RECEIPT = {
  type: 'object',
  additionalProperties: false,
  required: ['command', 'raw_output_tail', 'passed'],
  properties: {
    command: { type: 'string', description: 'the exact command invoked, verbatim' },
    raw_output_tail: { type: 'string', description: 'the last lines of the actual command output — pass/fail counts, NOT a paraphrase' },
    passed: { type: 'boolean' },
  },
}

const TASK_LIST_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['tasks_file', 'tasks'],
  properties: {
    tasks_file: { type: 'string', description: 'repo-relative path of the saved task breakdown file (tasks/[story-name].md)' },
    tasks: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['n', 'title', 'description', 'language', 'behavior', 'acceptance_criteria', 'affected_files', 'patterns_to_follow', 'testable', 'depends_on'],
        properties: {
          n: { type: 'integer' },
          title: { type: 'string' },
          description: { type: 'string' },
          language: { type: 'string' },
          behavior: { type: 'string' },
          acceptance_criteria: { type: 'array', items: { type: 'string' } },
          affected_files: { type: 'array', items: { type: 'string' } },
          patterns_to_follow: { type: 'array', items: { type: 'string' } },
          testable: { type: 'boolean' },
          depends_on: { type: 'array', items: { type: 'integer' } },
        },
      },
    },
  },
}

const IMPL_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['files_changed', 'test_receipt', 'criteria_evidence'],
  properties: {
    files_changed: { type: 'array', items: { type: 'string' } },
    test_receipt: RECEIPT,
    criteria_evidence: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['criterion', 'kind', 'command', 'raw_output_tail', 'satisfied'],
        properties: {
          criterion: { type: 'string' },
          kind: { type: 'string', enum: ['test', 'demo'] },
          command: { type: 'string' },
          raw_output_tail: { type: 'string' },
          satisfied: { type: 'boolean' },
        },
      },
    },
  },
}

const REFACTOR_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['outcome', 'test_receipt'],
  properties: {
    outcome: { type: 'string', description: 'applied: <one-line> | none needed | reverted: <reason>' },
    test_receipt: RECEIPT,
  },
}

const REVIEW_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['verdict', 'findings'],
  properties: {
    verdict: { type: 'string', enum: ['pass', 'block'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['id', 'severity', 'file', 'claim'],
        properties: {
          id: { type: 'string' },
          severity: { type: 'string', enum: ['low', 'medium', 'high'] },
          file: { type: 'string' },
          line: { type: 'integer' },
          claim: { type: 'string' },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['finding_id', 'reproduced', 'classification', 'note'],
  properties: {
    finding_id: { type: 'string' },
    reproduced: { type: 'boolean' },
    repro: {
      type: ['object', 'null'],
      additionalProperties: false,
      required: ['command', 'raw_output_tail'],
      properties: { command: { type: 'string' }, raw_output_tail: { type: 'string' } },
    },
    classification: { type: 'string', enum: ['real', 'speculative'] },
    note: { type: 'string' },
  },
}

const AUDIT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['test_rerun', 'criteria', 'unmet'],
  properties: {
    test_rerun: RECEIPT,
    criteria: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['criterion', 'has_executed_evidence'],
        properties: { criterion: { type: 'string' }, has_executed_evidence: { type: 'boolean' } },
      },
    },
    unmet: { type: 'array', items: { type: 'string' }, description: 'criteria with no executed evidence, or whose evidence shows failure' },
  },
}

const COMMIT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['committed', 'hash', 'subject'],
  properties: { committed: { type: 'boolean' }, hash: { type: 'string' }, subject: { type: 'string' } },
}

const FINISH_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['tasks_file_moved_to', 'integrated', 'base_branch', 'note'],
  properties: {
    tasks_file_moved_to: { type: ['string', 'null'], description: 'new repo-relative path of the archived task breakdown; null if the move could not be done' },
    integrated: { type: 'boolean', description: 'true only when rebase + fast-forward + branch delete ALL completed' },
    base_branch: { type: ['string', 'null'], description: 'the default branch integrated into; null when integration was not attempted' },
    note: { type: 'string', description: 'what was done, and why anything was skipped or aborted' },
  },
}

const REFLECT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['learnings'],
  properties: {
    learnings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['title', 'kind', 'learning', 'apply_when', 'prevents'],
        properties: {
          title: { type: 'string' },
          kind: { type: 'string', enum: ['convention', 'recurring-finding', 'constraint', 'pattern'] },
          learning: { type: 'string', description: 'the durable fact, 1-2 sentences' },
          apply_when: { type: 'string', description: 'the future situation where this is relevant' },
          prevents: { type: 'string', description: 'the specific future mistake this learning prevents — the falsifiable filter; if you cannot name it, the learning is noise and must be dropped' },
        },
      },
    },
  },
}

const PLAN_IMPACT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['impact', 'reason'],
  properties: {
    impact: { type: 'string', enum: ['none', 'revise'] },
    reason: { type: 'string', description: 'the concrete mismatch between the remaining plan and the codebase reality the closed task revealed; required even when impact is "none" — then state why the plan still holds' },
  },
}

// ---------------------------------------------------------------------------
// Prompt builders
// ---------------------------------------------------------------------------

const taskHeader = (t) =>
  `Task ${t.n}: ${t.title}\nDescription: ${t.description}\nObservable behavior: ${t.behavior}\n` +
  `Acceptance criteria:\n${t.acceptance_criteria.map((c, i) => `  ${i + 1}. ${c}`).join('\n')}\n` +
  `Affected files: ${t.affected_files.join(', ') || '(discover them)'}\n` +
  `Patterns to follow: ${t.patterns_to_follow.join(', ') || '(match surrounding code)'}`

const decomposePrompt = (story) =>
  `Decompose the following user story into ordered, codebase-aware implementation tasks. For each task set \`language\` to the language it primarily involves, and \`depends_on\` to the task numbers it builds on (\`[]\` if none). Emit tasks in an order where every task's dependencies precede it.\n\n` +
  `Save the breakdown to \`tasks/[story-name].md\` as usual — including the \`- [ ] Task N: <title>\` checklist — and return its repo-relative path as \`tasks_file\`. The run checks entries off as tasks close, so the file doubles as restartable progress state.\n\n` +
  `If \`tasks/learnings.md\` exists, read it first: its entries are durable conventions, recurring review findings, and constraints distilled from earlier runs in this repo. Fold the relevant ones into each task's \`patterns_to_follow\` and do not re-propose work they already cover.\n\n` +
  `From ${CALLER_PATTERNS} read 'How to Identify the Caller' and the Quick Reference; from any language testing-patterns guideline read 'Unit of Behavior'. ${DISCLOSURE}\n\n` +
  `<user_story>\n${story}\n</user_story>`

const adoptTasksPrompt = (tasksFile) =>
  `Read the existing task breakdown at \`${tasksFile}\` and return its tasks in the required schema — ADOPT it, do not re-plan.\n\n` +
  `- Preserve the file's task order, titles, descriptions, and any stated acceptance criteria and dependencies. Do not invent, merge, split, or drop tasks.\n` +
  `- The file's checklist is the progress record: a task whose entry is already checked (\`- [x] Task N\`) was completed and committed by an earlier run — OMIT it from \`tasks\` so the run resumes from the first unchecked task.\n` +
  `- For any schema field the file does not state, infer conservatively from its content: \`language\` from the target stack, \`depends_on\` from stated ordering (\`[]\` if none), \`affected_files\` / \`patterns_to_follow\` from what it names (empty arrays if none), \`testable\` true unless the task is pure docs/config. \`n\` is each task's own number in the file (file order from 1 if unnumbered).\n` +
  `- Set \`tasks_file\` to \`${tasksFile}\`.\n` +
  `If \`tasks/learnings.md\` exists you may fold relevant durable learnings into \`patterns_to_follow\`, but otherwise leave the breakdown intact.`

const designPrompt = (t, cfg) =>
  `${taskHeader(t)}\n\nDesign the test scenarios for this task. Required reading: ${cfg.guidelines.join(', ')}. ${DISCLOSURE} ` +
  `From caller-patterns identify the caller pattern and read only that section plus the Quick Reference; use its assert-on / don't-assert-on tables to shape scenarios.`

const implementPrompt = (t, cfg, testPlan, feedback) =>
  `${taskHeader(t)}\n\nWrite failing tests first (per the approved plan), then implement until they pass. Test command: \`${TEST_CMD}\`.\n\n` +
  `Approved test plan:\n${testPlan}\n\n` +
  (feedback ? `REVISION REQUIRED — close these concrete gaps from the previous attempt:\n${feedback}\n\n` : '') +
  `EVIDENCE CONTRACT (this is non-negotiable):\n` +
  `- Actually RUN \`${TEST_CMD}\` and return its real output tail in \`test_receipt\` — verbatim command, raw output, pass/fail boolean. A narrated "tests pass" is rejected.\n` +
  `- For EACH acceptance criterion, attach \`criteria_evidence\`: a named test (kind:test) or, for behavior a unit test can't express, an executed demonstration (kind:demo) — with the exact command and its raw output tail. Mark \`satisfied\` only from what the output actually shows.\n` +
  `Leave all changes STAGED. Do NOT commit.`

const refactorPrompt = (t, cfg, impl) =>
  `${taskHeader(t)}\n\nFiles changed so far: ${impl.files_changed.join(', ')}.\n` +
  `Improve structure (duplication, naming, extraction) without changing behavior, following ${'~/.config/ai/guidelines/comments.md'} for comment usage. ` +
  `Keep tests green: after refactoring, RUN \`${TEST_CMD}\` and return the post-refactor \`test_receipt\` (verbatim). ` +
  `If refactoring breaks tests and you cannot fix it, revert and set outcome to "reverted: <reason>". If nothing is worth changing, set outcome "none needed" and still return a passing receipt. Leave changes STAGED.`

const reviewPrompt = (t) =>
  `Review the STAGED changes for this task. Use \`git diff --staged\` and \`git diff --staged --name-only\`.\n\n${taskHeader(t)}\n\n` +
  `When the diff adds or changes tests, do NOT judge them from the diff alone — read the WHOLE test file and weigh each new/changed test against the tests already there. A behaviorally-valid test still fails review if it is REDUNDANT: a new data point (enum value, field, config entry, allow-list token) exercising a behavior an existing test already covers belongs FOLDED into that test, not cloned as a parallel one; a change-detector already covered by a behavioral test should be dropped. This is test-quality scope — the semantic reviewer owns it (guideline: "Additional Data Point vs. New Behavior" / "Prefer Higher-Level Behavioral Tests Over Change Detectors"). Raise such a case as a finding to fold-or-drop.\n\n` +
  `Return a verdict and findings. For every finding give a stable \`id\`, severity, file, and a one-sentence \`claim\` precise enough that another agent could reproduce it. If your scope does not apply to this diff, return verdict "pass" with no findings.`

const reproPrompt = (t, f) =>
  `A reviewer claims a problem in the STAGED changes for task ${t.n}. Your job is to ESTABLISH EXECUTED EVIDENCE for or against it — do not take the claim on faith (the reviewer that raised it did not run anything).\n\n` +
  `Finding ${f.id} [${f.severity}] in ${f.file}: ${f.claim}\n\n` +
  `Try to reproduce it concretely: write and run a failing test, a \`-race\` run, a benchmark, or a direct execution that demonstrates the defect. ` +
  `If you reproduce it, set reproduced=true, classification="real", and put the exact command + raw output in \`repro\`. ` +
  `If you cannot reproduce it after a genuine attempt, set reproduced=false, classification="speculative", and explain what you tried in \`note\`. Default to "speculative" when uncertain — an unreproduced claim is an assertion, not evidence.`

const auditPrompt = (t, impl, refactor) =>
  `Independently audit task ${t.n} against its acceptance criteria. Do NOT trust the implementer's self-report — re-execute.\n\n${taskHeader(t)}\n\n` +
  `The implementer reported these receipts (verify, do not assume): impl test \`${impl.test_receipt.command}\` -> passed=${impl.test_receipt.passed}; refactor outcome "${refactor.outcome}".\n\n` +
  `1. RUN \`${TEST_CMD}\` yourself in the working tree and return the raw result as \`test_rerun\` (this is the executed-evidence check against a possibly-fabricated implementer receipt).\n` +
  `2. For each acceptance criterion, decide \`has_executed_evidence\` strictly: is there a test or demonstration whose ACTUAL output shows the criterion met? Narration does not count.\n` +
  `3. List in \`unmet\` every criterion with no executed evidence, plus "tests regressed" if your re-run failed.`

const commitPrompt = (t, ticket, tasksFilePath) =>
  `Commit task ${t.n}: ${t.title}. The changes are STAGED (stage anything missing with \`git add -A\`). Create exactly ONE commit.\n` +
  `First record progress: in \`${tasksFilePath}\`, flip this task's checklist entry from \`- [ ] Task ${t.n}:\` to \`- [x] Task ${t.n}:\` and stage the file so the progress update rides in this commit. If the file has no such entry or git refuses to stage it (e.g. ignored path), continue without it — never block the commit on the checklist.\n` +
  `Apply the repo's OWN commit conventions — read CLAUDE.md / any committing guideline and reuse a cached trailer (e.g. a Linear initiative trailer) if the repo uses one. ` +
  (ticket ? `Weave in this ticket context per those conventions: ${ticket}. ` : '') +
  `The subject MUST satisfy the repo commit rules regardless: imperative mood, <=50 chars, capitalized, no trailing period, NO mention of AI/Claude, NO Co-Authored-By trailer. ` +
  `Return the resulting commit hash and subject.`

const remainingDigest = (remaining) =>
  remaining.map((t) => `  - Task ${t.n}: ${t.title} — ${t.behavior}`).join('\n')

const completedDigest = (completed) =>
  completed.map((t) => `  - Task ${t.n}: ${t.title} (DONE, committed — frozen)`).join('\n')

const planImpactPrompt = (task, result, remaining) =>
  `Task ${task.n} ("${task.title}") just closed and was committed. Before continuing, assess whether implementing it changed the premises of the REMAINING plan.\n\n` +
  `What it actually changed (confirm with \`git show --stat HEAD\` and \`git show HEAD\`): ${(result.evidence?.impl?.files_changed ?? []).join(', ') || '(inspect the last commit)'}.\n\n` +
  `Remaining, not-yet-started tasks:\n${remainingDigest(remaining)}\n\n` +
  `Return \`impact: "revise"\` ONLY if the remaining plan must change to still deliver the story — a planned task is now unnecessary (already covered), missing (a new one is needed), mis-scoped, or its dependencies shifted because of how this task was actually built. ` +
  `Otherwise return \`impact: "none"\`. Default hard to "none": re-planning is expensive and justified only by a concrete mismatch you can name in \`reason\`. A task merely being large or hard is not a mismatch.`

const redecomposePrompt = (story, completed, remaining, reason, tasksFilePath) => {
  const nextN = (completed[completed.length - 1]?.n ?? 0) + 1
  return (
    `A run is in progress. The tasks below are DONE and committed (frozen) — implementing them revealed that the REMAINING plan needs revision.\n\n` +
    `Trigger: ${reason}\n\n` +
    `Completed tasks (do NOT re-emit, do NOT redo):\n${completedDigest(completed)}\n\n` +
    `Current remaining tasks you are revising:\n${remainingDigest(remaining)}\n\n` +
    `Re-decompose ONLY the not-yet-started work so the story still lands. Return \`tasks\` containing just the revised remaining tasks — numbered from ${nextN} upward, dependency-ordered, with \`depends_on\` allowed to reference completed task numbers. Same fields as a normal decomposition. Keep what is still correct, drop what is now unnecessary, add what is missing.\n\n` +
    `Also update the breakdown file at \`${tasksFilePath}\` in place: leave completed tasks and their checked \`- [x]\` checklist entries untouched, replace the not-yet-started task sections and their unchecked checklist entries with the revised tasks, and return the same path as \`tasks_file\`.\n\n` +
    `If \`tasks/learnings.md\` exists, read it and fold relevant durable learnings into \`patterns_to_follow\`. From ${CALLER_PATTERNS} read 'How to Identify the Caller' and the Quick Reference; from any language testing-patterns guideline read 'Unit of Behavior'. ${DISCLOSURE}\n\n` +
    `<user_story>\n${story}\n</user_story>`
  )
}

const finalSuitePrompt = () =>
  `Run the full test suite (\`${TEST_CMD}\`) in the main working tree and return the raw result as a receipt (verbatim command, raw output tail, pass/fail boolean). Do not summarize away the output.`

const finishPrompt = (tasksFilePath, integrate) =>
  `Every task in this run closed and was committed. Finish the run's bookkeeping in the main working tree:\n\n` +
  `1. Archive the task breakdown: \`mkdir -p tasks/completed\` then \`git mv ${tasksFilePath} tasks/completed/\` (if the file is untracked, plain \`mv\` and \`git add\` the new path). Commit the move as ONE commit whose subject satisfies the repo commit rules (imperative mood, <=50 chars, capitalized, no trailing period, NO mention of AI/Claude, NO Co-Authored-By). Set \`tasks_file_moved_to\` to the new repo-relative path, or null with the reason in \`note\` if the move could not be done.\n` +
  (integrate
    ? `2. Integrate the implementation branch into the default branch, LOCALLY ONLY — never push:\n` +
      `   a. \`git branch --show-current\` is the implementation branch. The default branch is \`git rev-parse --abbrev-ref origin/HEAD\` if set, else whichever of \`main\`/\`master\` exists locally. If you are already ON the default branch, set integrated=false and stop — nothing to integrate.\n` +
      `   b. \`git rebase <default>\`. On ANY conflict: \`git rebase --abort\`, set integrated=false, leave the branch exactly as it was, and explain in \`note\`.\n` +
      `   c. If the rebase actually replayed commits onto a moved base (not a no-op), re-run \`${TEST_CMD}\`; if it fails, STOP — leave the rebased branch checked out for human review, set integrated=false, and put the failing output tail in \`note\`.\n` +
      `   d. \`git switch <default>\`, \`git merge --ff-only <implementation branch>\`, \`git branch -d <implementation branch>\`. Set integrated=true and \`base_branch\` to the default branch.\n`
    : `2. Do NOT rebase, merge, switch, or delete any branch — the run ends on the implementation branch as-is. Set integrated=false and base_branch=null.\n`) +
  `Report what happened in \`note\`.`

const reflectDigest = (results) =>
  results
    .map((r) => {
      const repros = r.evidence?.repros ?? []
      const real = repros.filter((v) => v.reproduced && v.classification === 'real').map((v) => v.note)
      const spec = repros.filter((v) => v.classification === 'speculative').map((v) => v.note)
      return (
        `Task ${r.n} (${r.status}): ${r.title}\n` +
        `  reproduced findings: ${real.join('; ') || 'none'}\n` +
        `  speculative: ${spec.join('; ') || 'none'}\n` +
        `  unresolved: ${r.unresolved.join('; ') || 'none'}`
      )
    })
    .join('\n')

const reflectPrompt = (results) =>
  `Distil DURABLE learnings from this completed run so future runs in this repo start smarter — the self-improvement write-back. A learning is worth persisting only when it generalises beyond the one task that surfaced it.\n\n` +
  `Run digest:\n${reflectDigest(results)}\n\n` +
  `1. Inspect what actually changed: \`git log --oneline\` for this run's commits and \`git diff\` of their contents. The reproduced reviewer findings above are the richest signal — a finding class that recurred is a candidate convention.\n` +
  `2. Read \`tasks/learnings.md\` if it exists and dedup against it on substance, not wording — propose only genuinely new learnings.\n` +
  `3. FALSIFIABLE FILTER: keep a learning only when you can name the specific future mistake it prevents (the \`prevents\` field). If you cannot, it is task-specific noise — drop it. Prefer learnings evidenced across >=2 tasks or flagged by a reviewer as a repo-wide convention.\n` +
  `4. Append every surviving learning to \`tasks/learnings.md\` (create it if missing), each as:\n` +
  `   ## <title>\n   - Type: <kind>\n   - Learning: <the durable fact>\n   - Apply when: <future situation>\n` +
  `Leave \`tasks/learnings.md\` as an UNCOMMITTED working-tree change — this skill's gate is the human's post-run diff review, so persisted steering lands in the review surface, not behind an inline prompt. Return the learnings you wrote; empty list if none survive the filter.`

const buildFeedback = (unmet, realFindings) =>
  [
    ...unmet.map((c) => `- Unmet acceptance criterion (no executed evidence): ${c}`),
    ...realFindings.map((v) => `- Reproduced ${v.finding_id}: ${v.note} (repro: ${v.repro?.command ?? 'see note'})`),
  ].join('\n')

const trimEvidence = (e) =>
  e && {
    impl_test: e.impl?.test_receipt,
    refactor: e.refactor?.outcome,
    audit_rerun: e.audit?.test_rerun,
    findings: e.findings?.length ?? 0,
    reproduced_real: e.repros?.filter((v) => v.classification === 'real' && v.reproduced).length ?? 0,
    speculative: e.repros?.filter((v) => v.classification === 'speculative').length ?? 0,
  }

// ---------------------------------------------------------------------------
// One task, end to end. The VERIFY stage is the gate replacement: an
// independent agent re-executes and adversarially reproduces, so closure rests
// on executed ground truth rather than the implementer's word.
// ---------------------------------------------------------------------------

async function runTask(task) {
  const cfg = cfgFor(task.language)
  const tag = `task-${task.n}`

  let testPlan = 'N/A (testable: false) — verify via demonstration receipts instead of unit tests.'
  if (task.testable) {
    testPlan = await agent(designPrompt(task, cfg), { label: `${tag}:design`, phase: 'Implement', agentType: 'test-case-designer' })
  }

  let feedback = null
  let evidence = null
  let attemptsUsed = 0

  for (let attempt = 1; attempt <= MAX_RESOLVE; attempt++) {
    attemptsUsed = attempt
    // agent() returns null if a subagent dies on a terminal error after retries.
    // Guard the critical stages so one dead agent fails just this task, not the run.
    const impl = await agent(implementPrompt(task, cfg, testPlan, feedback), {
      label: `${tag}:impl#${attempt}`, phase: 'Implement', agentType: cfg.implementer, schema: IMPL_SCHEMA,
    })
    if (!impl) {
      feedback = 'implementer agent returned no result (terminal error after retries)'
      log(`${tag}: attempt ${attempt} aborted — implementer returned no result`)
      break
    }
    const refactor = (await agent(refactorPrompt(task, cfg, impl), {
      label: `${tag}:refactor#${attempt}`, phase: 'Implement', agentType: cfg.refactorer, schema: REFACTOR_SCHEMA,
    })) ?? { outcome: 'skipped (refactor agent returned no result)', test_receipt: impl.test_receipt }

    const { reviewers, reason } = selectReviewers(cfg, task, impl.files_changed)
    if (reason) log(`${tag}: skipping code reviewers — ${reason}`)
    const reviews = reviewers.length
      ? (await parallel(
          reviewers.map((r) => () => agent(reviewPrompt(task), { label: `${tag}:review:${r}`, phase: 'Implement', agentType: r, schema: REVIEW_SCHEMA })),
        )).filter(Boolean)
      : []
    const findings = reviews.flatMap((rv) => rv.findings ?? [])

    const repros = findings.length
      ? (await parallel(
          findings.map((f) => () => agent(reproPrompt(task, f), { label: `${tag}:repro:${f.id}`, phase: 'Verify', schema: VERDICT_SCHEMA })),
        )).filter(Boolean)
      : []
    const audit = await agent(auditPrompt(task, impl, refactor), { label: `${tag}:audit#${attempt}`, phase: 'Verify', schema: AUDIT_SCHEMA })
    if (!audit) {
      feedback = 'audit agent returned no result (terminal error after retries)'
      log(`${tag}: attempt ${attempt} aborted — audit returned no result`)
      break
    }

    const realFindings = repros.filter((v) => v.reproduced && v.classification === 'real')
    const speculative = repros.filter((v) => v.classification === 'speculative')
    const unmet = audit.unmet ?? []
    evidence = { impl, refactor, findings, repros, audit }

    const closed = audit.test_rerun?.passed && unmet.length === 0 && realFindings.length === 0
    if (closed) {
      return {
        n: task.n,
        title: task.title,
        status: 'closed',
        attempts: attempt,
        unresolved: speculative.map((s) => `speculative: ${s.finding_id} — ${s.note}`),
        evidence,
      }
    }

    feedback = buildFeedback(unmet, realFindings)
    log(`${tag}: attempt ${attempt} did not close — ${unmet.length} unmet criteria, ${realFindings.length} reproduced findings`)
  }

  return {
    n: task.n,
    title: task.title,
    status: 'open',
    attempts: attemptsUsed,
    unresolved: [feedback ?? 'evidence did not close'],
    evidence,
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

phase('Decompose')
const tasksFile = typeof args === 'object' ? args?.tasksFile : undefined
const ticket = typeof args === 'object' ? args?.ticket : undefined
const story = (typeof args === 'string' ? args : args?.story) || (tasksFile && `the existing task breakdown at ${tasksFile}`)
if (!story) throw new Error('implement-flow: pass args.story (a user story) and/or args.tasksFile (an existing tasks/*.md to adopt)')

// Adopt a prior breakdown verbatim when given a task file; otherwise decompose
// the story. `story` still anchors any later re-decompose, even in adopt mode.
const plan = tasksFile
  ? await agent(adoptTasksPrompt(tasksFile), { agentType: 'decompose-to-tasks', schema: TASK_LIST_SCHEMA })
  : await agent(decomposePrompt(story), { agentType: 'decompose-to-tasks', schema: TASK_LIST_SCHEMA })
let planFile = plan.tasks_file
log(tasksFile ? `adopted ${plan.tasks.length} unchecked task(s) from ${tasksFile}` : `decomposed into ${plan.tasks.length} tasks (${planFile})`)

// Tasks arrive dependency-ordered, but `remaining` is a MUTABLE queue, not a
// fixed list: after a task closes, an independent assessor can autonomously
// re-decompose the not-yet-started tail when the completed work changed the
// plan's premises (the gate-free analog of the siblings' plan-validity check).
// Re-decomposes are capped by MAX_REPLANS so a thrashing assessor can't loop
// forever — the cap is logged, not hidden. Parallelism still lives inside a task
// (reviewers + finding reproductions fan out concurrently).
const results = []
const completed = []
let remaining = [...plan.tasks]
let replans = 0

while (remaining.length) {
  const task = remaining.shift()
  const r = await runTask(task)

  if (r.status !== 'closed') {
    // A later task likely depends on this one; committing on top of unclosed
    // evidence would bury the gap. Stop and surface it instead.
    log(`task ${task.n} did not close after ${r.attempts} attempts — stopping the chain, left uncommitted for human review`)
    results.push(r)
    break
  }

  r.commit = await agent(commitPrompt(task, ticket, planFile), { label: `task-${task.n}:commit`, phase: 'Finalize', agentType: 'commit', schema: COMMIT_SCHEMA })
  results.push(r)
  completed.push(task)

  if (!remaining.length) continue

  const impact = await agent(planImpactPrompt(task, r, remaining), { label: `task-${task.n}:plan-impact`, phase: 'Replan', schema: PLAN_IMPACT_SCHEMA })
  if (impact.impact !== 'revise') continue

  if (replans >= MAX_REPLANS) {
    log(`task ${task.n} flagged a plan change ("${impact.reason}") but the re-decompose cap (${MAX_REPLANS}) is reached — keeping the current plan for human review`)
    continue
  }

  replans++
  log(`task ${task.n} triggered re-decompose (${replans}/${MAX_REPLANS}): ${impact.reason}`)
  const revised = await agent(redecomposePrompt(story, completed, remaining, impact.reason, planFile), { label: `replan#${replans}`, phase: 'Replan', agentType: 'decompose-to-tasks', schema: TASK_LIST_SCHEMA })
  remaining = revised.tasks ?? []
  planFile = revised.tasks_file ?? planFile
  log(`re-decomposed remaining work into ${remaining.length} task(s)`)
}

phase('Finalize')
const fullSuite = await agent(finalSuitePrompt(), { label: 'full-suite', phase: 'Finalize', schema: RECEIPT })

// Archive + optional integration run BEFORE reflect: reflect leaves
// tasks/learnings.md uncommitted by design, and a dirty tracked file would
// block the rebase. Integration additionally requires a passing full-suite
// receipt — never land unverified commits on the default branch.
const allClosed = results.length > 0 && remaining.length === 0 && results.every((r) => r.status === 'closed')
let finish = null
if (allClosed && planFile) {
  const integrate = INTEGRATE && fullSuite?.passed === true
  if (INTEGRATE && !integrate) log('integrate: skipped — full-suite receipt did not pass; branch left as-is')
  finish = await agent(finishPrompt(planFile, integrate), { label: 'finish', phase: 'Finalize', schema: FINISH_SCHEMA })
  if (finish) {
    log(finish.tasks_file_moved_to ? `task file archived at ${finish.tasks_file_moved_to}` : `task file NOT archived — ${finish.note}`)
    if (integrate) log(finish.integrated ? `integrated into ${finish.base_branch}, implementation branch deleted` : `integrate aborted — ${finish.note}`)
  }
} else if (INTEGRATE) {
  log('integrate: skipped — not all tasks closed; branch and task file left in place for human review')
}

// Self-improvement write-back. Learnings are left UNCOMMITTED on purpose: this
// skill has no inline gate, so its review surface is the human's post-run diff.
const reflection = results.some((r) => r.status === 'closed')
  ? await agent(reflectPrompt(results), { label: 'reflect', phase: 'Finalize', schema: REFLECT_SCHEMA })
  : { learnings: [] }
log(`reflect: ${reflection.learnings.length} durable learning(s) written to tasks/learnings.md`)

return {
  story,
  tasks_file: finish?.tasks_file_moved_to ?? planFile,
  closed: results.filter((r) => r.status === 'closed').length,
  open: results.filter((r) => r.status === 'open').length,
  replans,
  full_suite: fullSuite,
  integrated: finish?.integrated ?? false,
  finish_note: finish?.note ?? null,
  learnings: reflection.learnings,
  tasks: results.map((r) => ({
    n: r.n,
    title: r.title,
    status: r.status,
    attempts: r.attempts,
    commit: r.commit ?? null,
    unresolved: r.unresolved,
    evidence: trimEvidence(r.evidence),
  })),
}
