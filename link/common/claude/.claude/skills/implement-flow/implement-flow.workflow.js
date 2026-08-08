export const meta = {
  name: 'implement-flow',
  description:
    'Autonomous, gate-free, evidence-closed implementation. Decomposes a story, then runs each task through design -> implement -> refactor -> review -> verify, closing on executed evidence (raw receipts + reproduced findings) instead of human approval gates.',
  phases: [
    { title: 'Decompose', detail: 'break the story into dependency-ordered tasks' },
    { title: 'Implement', detail: 'per task: design tests, implement, refactor, review' },
    { title: 'Verify', detail: 'reproduce runtime findings, honor quality findings directly, audit criteria against re-executed evidence' },
    { title: 'Replan', detail: 'after a task closes, reassess and re-decompose the remaining plan if its premises changed' },
    { title: 'Restructure', detail: 'one cross-cutting refactor over the finished branch, the structure no single task could see' },
    { title: 'Finalize', detail: 'commit closed tasks, full-suite receipt, run-verifier pass, archive task file, optional branch integration, distil learnings' },
  ],
}

// ---------------------------------------------------------------------------
// Config — mirrors the implement / implement-auto Language Configuration table.
// ---------------------------------------------------------------------------

const DISCLOSURE =
  'Each guideline opens with an HTML comment `<!-- index: 1-N -->` on line 1 giving the Section Index range. ' +
  'Read line 1 only, then the index range, then `rg -n` the headings you need and read only those sections. Do NOT read the file end-to-end.'

const CALLER_PATTERNS = '~/.config/ai/guidelines/testing/caller-patterns.md'

// Criteria are written once and then checked on every attempt, so a badly-shaped
// one costs the whole revision budget and leaves finished work uncommitted. Two
// shapes have done exactly that, both of which read perfectly natural when written:
// a criterion reaching for state that only exists after the commit, and one phrased
// as an absence that any deletion of the feature also satisfies.
// What makes a stage slow is round-trips, not tokens. Measured on one story: an
// 18-minute implementer spent it across ~150 model turns and 96 shell calls, 55% of
// them `rg`/`sed`/`head` reading code a few lines at a time, against a transcript
// that grew to 640KB — while the whole test suite runs in 7 seconds. Every extra
// turn also re-sends a bigger context, so narrow probing compounds. Reading wide and
// early costs input tokens once; probing costs a turn each time, forever.
const FRONT_LOAD_READING =
  'FRONT-LOAD YOUR READING. Each tool call is a full model round-trip against a context that keeps growing, so fifty narrow `rg`/`sed -n`/`head` probes cost far more than reading the same files whole. Open every file you already know you need in ONE message with parallel Read calls, and read each one whole rather than slicing it — the task names its files, so most of that list is known before you start. Search only for what the reading did not answer, and batch independent searches into one message too.'

const CRITERIA_RULE =
  'WRITING ACCEPTANCE CRITERIA — two shapes to avoid, both of which have cost real runs their entire revision budget:\n' +
  '1. A criterion must be checkable against the WORKING TREE while the task is still in progress. A task is committed only AFTER it closes, so a criterion reaching for commit state — "and the output is committed", "state the diff in the commit message", "git log shows ...", "git status is clean" — has no evidence available at any point in the loop and can never close. Phrase the same intent against the tree instead: "git diff moves exactly one line in each golden", "regenerating leaves the tracked files byte-identical", "the file exists and contains X". Where the repo asks for a receipt in the commit message, that belongs to the commit step, not to the criterion list.\n' +
  '2. A criterion must be falsifiable by the change it describes. "An X without the new entry behaves exactly as before", checked on input that omits the entry, is satisfied by deleting the feature outright, and invites a test that cannot fail. Phrase it against input that DOES exercise the change, so the with- and without- cases are asserted together: "a model declaring the entry and a sibling omitting it both format to their canonical bytes".'

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

// The harness can deliver `args` JSON-encoded rather than as a live object —
// either as a bare string, or as an object whose `story` holds the JSON-encoded
// original args (which silently collapses testCommand / tasksFile / integrate to
// undefined). Normalise both shapes back to the intended object so every field
// is honoured; a genuine object passes through untouched.
let ARGS = args
if (typeof ARGS === 'string') {
  try { const parsed = JSON.parse(ARGS); if (parsed && typeof parsed === 'object') ARGS = parsed } catch {}
}
if (
  ARGS && typeof ARGS === 'object' && typeof ARGS.story === 'string' &&
  ARGS.tasksFile === undefined && ARGS.testCommand === undefined && ARGS.integrate === undefined &&
  ARGS.story.trim().startsWith('{')
) {
  try {
    const parsed = JSON.parse(ARGS.story)
    if (parsed && typeof parsed === 'object' && (parsed.story || parsed.tasksFile)) ARGS = parsed
  } catch {}
}

const TEST_CMD = ARGS?.testCommand ?? '(detect the project test command yourself: Makefile, package.json scripts, or framework convention)'
// Per-language test commands, read by the orchestrator out of the repo's own
// tasks/test-commands.json and passed in whole (this script has no filesystem).
// A JS-only task re-running the Go suite on every implement, refactor and audit is
// pure latency, and a red suite in a language the task never touched stalls it for
// nothing. Whole-branch gates — the final suite, the cross-cutting refactor,
// integration — deliberately keep the full command: that is where cross-language
// breakage has to surface.
const TEST_CMDS = (typeof ARGS === 'object' && ARGS?.testCommands) || {}
const FULL_TEST_CMD = TEST_CMDS.default ?? TEST_CMD
const testCmdFor = (language) => {
  if (!language) return FULL_TEST_CMD
  const raw = String(language).trim()
  const canonical = LANG[raw] ? raw : LANG_ALIASES[raw.toLowerCase()]
  return TEST_CMDS[raw] ?? (canonical && TEST_CMDS[canonical]) ?? TEST_CMDS[raw.toLowerCase()] ?? FULL_TEST_CMD
}
const MAX_RESOLVE = ARGS?.maxResolve ?? 3
const MAX_REPLANS = ARGS?.maxReplans ?? 2
const INTEGRATE = ARGS?.integrate === true
// Cross-cutting structure is deferred out of the per-task loop into one pass over the
// finished branch: in-task refactoring that reaches beyond the task's own diff reads as
// scope creep to a reviewer and costs attempts arguing about it. Set false to skip.
const FINAL_REFACTOR = ARGS?.finalRefactor !== false
// Default keeps the legacy in-tree path, but that is NOT where a shared repo actually
// stores learnings — the orchestrator resolves this per project (an out-of-tree private
// store when the repo gitignores tasks/) and passes it as args.learningsPath.
const LEARNINGS_PATH = ARGS?.learningsPath ?? 'tasks/learnings.md'

// ---------------------------------------------------------------------------
// Infrastructure failures are not evidence.
//
// agent() yields null when a subagent dies on a terminal API error — a 529, a
// server error mid-response. Nothing was learned and there is no feedback to act
// on, which makes it categorically different from an agent that ran and returned
// a failing receipt. Spending an evidence attempt on it, or letting the null
// reach a property access, throws away work the outage had nothing to do with:
// a 529 on the first call has ended a run at second zero, and a null at the
// plan-impact stage would crash *after* task commits had already landed.
//
// So every critical call retries on its own budget, separate from MAX_RESOLVE.
// The retry varies the label because a resumed run replays cached results by
// (prompt, opts) and a cached null would otherwise replay as another null.
// ---------------------------------------------------------------------------

const INFRA_RETRIES = 2

const agentOrRetry = async (prompt, opts, what) => {
  for (let i = 0; i <= INFRA_RETRIES; i++) {
    const attemptOpts = i === 0 || !opts?.label ? opts : { ...opts, label: `${opts.label}~infra${i}` }
    const result = await agent(prompt, attemptOpts)
    if (result) return result
    if (i < INFRA_RETRIES) log(`${what}: no result (infrastructure error) — retrying ${i + 1}/${INFRA_RETRIES}`)
  }
  log(`${what}: no result after ${INFRA_RETRIES} infrastructure retries`)
  return null
}

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

// What "expensive" even means differs by language, and the old single pattern was
// written for a networked service: `http`, `query`, `database`. Pointed at a CLI and
// a canvas renderer it matched on `file`, `loop` and `index` — words that appear in
// prose about almost any task — and ran a specialist five times for nothing.
//
// These are matched against the TASK DESCRIPTION, not the diff: this script has no
// shell, so `impl.files_changed` gives it paths and never contents. That makes the
// gate a heuristic over how the work was described, which is why the vocabulary has
// to be words that only show up when the concern is real. A miss is logged below
// rather than passed over in silence.
//
// Do not mistake a quiet gate for coverage. Prose describes intent, and the one
// real cost defect this repo has seen — a per-character re-measure inside an
// ellipsis fit — sat in a task whose description mentioned no cost at all. Finding
// that needs a lens reading the diff, which is an audit over the finished branch,
// not a gate over the plan.
const PERF_HINTS = {
  Go: /http|\bgrpc\b|query|database|\bdb\b|\bsql\b|readall|\bio\.|retry|polling|pagination|unbounded|preallocat|goroutine leak/i,
  'JavaScript/TypeScript': /\bdom\b|layout|reflow|repaint|innerhtml|re-?render|listener|scroll|resize|animation|requestanimationframe|getboundingclientrect|thrash|debounce|throttle/i,
  Elixir: /ecto|\brepo\.|genserver|\bstream\b|preload|n\+1/i,
  Generic: /http|query|database|\bdb\b|readall|retry|polling|pagination|unbounded/i,
}
const perfHintsFor = (language) => PERF_HINTS[language] ?? PERF_HINTS[LANG[language] ? language : 'Generic'] ?? PERF_HINTS.Generic

const selectReviewers = (cfg, task, changedFiles) => {
  const codeFiles = (changedFiles ?? []).filter(isCodeFile)
  if (codeFiles.length === 0) return { reviewers: [], reason: 'docs/config-only change — no code reviewers' }
  const hay = `${task.description} ${task.behavior} ${(changedFiles ?? []).join(' ')}`.toLowerCase()
  const skipped = []
  const reviewers = cfg.reviewers.filter((r) => {
    const k = kindOf(r)
    if (k === 'concurrency') {
      if (CONCURRENCY_HINTS.test(hay)) return true
      skipped.push(`${r} (nothing in the task describes concurrent work)`)
      return false
    }
    if (k === 'performance') {
      if (perfHintsFor(task.language).test(hay)) return true
      skipped.push(`${r} (nothing in the task describes a cost this lens measures — a per-task gate reads the plan's prose, not the diff, so treat performance as covered by an audit over the finished branch rather than here)`)
      return false
    }
    return true
  })
  return { reviewers, reason: null, skipped }
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
    finding_dispositions: {
      type: 'array',
      description:
        'REQUIRED when the revision brief lists outstanding findings: exactly one entry per listed id. An id left out is treated as unaddressed and blocks the task from closing.',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['id', 'status', 'note'],
        properties: {
          id: { type: 'string' },
          status: { type: 'string', enum: ['fixed', 'rejected'] },
          note: {
            type: 'string',
            description:
              'fixed = the file and what concretely changed (what was removed/added), specific enough that a reviewer can check it; rejected = why the finding does not hold',
          },
        },
      },
    },
    criteria_evidence: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['criterion', 'kind', 'persisted_test', 'command', 'raw_output_tail', 'satisfied'],
        properties: {
          criterion: { type: 'string' },
          kind: { type: 'string', enum: ['test', 'demo'] },
          persisted_test: {
            type: 'string',
            description:
              'When kind is "test": "<repo-relative file path>::<test name>" naming the test that proves this criterion AS IT EXISTS IN THE FINAL TREE — the file must still be present and the test still runnable when you finish. A scratch/probe file you delete afterwards is NOT evidence. Empty string ONLY when kind is "demo".',
          },
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
        required: ['id', 'severity', 'nature', 'file', 'claim'],
        properties: {
          id: { type: 'string' },
          severity: {
            type: 'string',
            enum: ['low', 'medium', 'high'],
            description:
              'How bad the finding is, judged honestly — NOT whether it blocks. The block decision is made downstream from (nature, quality_kind, severity); never inflate severity to force a block. low = a genuine nit you would not hold a PR for; medium = you would ask for the change before merge; high = serious.',
          },
          nature: {
            type: 'string',
            enum: ['runtime', 'quality'],
            description:
              'runtime = a defect with observable runtime behavior an independent agent can reproduce by executing code (a failing test, -race, benchmark, direct run) — correctness, concurrency, performance. quality = a code-quality/convention violation with no runtime symptom (a comments.md comment-usage violation, a redundant / change-detector test, a naming or structure issue).',
          },
          quality_kind: {
            type: 'string',
            enum: ['comment-usage', 'redundant-test', 'broken-test', 'other'],
            description:
              'Required when nature="quality"; classify the violation. comment-usage = a ~/.config/ai/guidelines/comments.md violation. redundant-test = a cloned data-point / change-detector test that should fold into an existing test or be dropped. broken-test = a test that provides no value — a tautology, a vacuous passthrough / constant-pin (passes even if the code under test is a stub), a call-count-only assertion, or a test with no behavioral assertion; it must assert real behavior or be deleted. These three are non-negotiable: they block the task at ANY severity. "other" (naming, structure) blocks at medium or above. Classify honestly — the block decision keys off this, not off severity.',
          },
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
  required: ['test_rerun', 'criteria', 'unmet', 'false_fixed', 'unexpected_test_files'],
  properties: {
    test_rerun: RECEIPT,
    criteria: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['criterion', 'has_executed_evidence', 'evidence_persists'],
        properties: {
          criterion: { type: 'string' },
          has_executed_evidence: { type: 'boolean' },
          evidence_persists: {
            type: 'boolean',
            description:
              'For kind:test evidence — true only when you confirmed the cited file exists in the working tree AND re-ran the named test yourself and it selected and passed. False when the citation names a file or test that does not resolve (a deleted scratch/probe file: the evidence was destroyed). For kind:demo evidence with no persisted test, judge on the demonstration and set true.',
          },
          note: {
            type: 'string',
            description:
              'Optional. Use it to record a clause you judged on the working tree because the clause itself concerns state that does not exist during a task — commit message, git log, clean git status. Say which clause was deferred, so the human reviewing the branch can confirm it after the commit lands.',
          },
        },
      },
    },
    unmet: {
      type: 'array',
      items: { type: 'string' },
      description: 'criteria with no executed evidence, whose evidence shows failure, or whose cited test no longer resolves (evidence_persists false)',
    },
    false_fixed: {
      type: 'array',
      items: { type: 'string' },
      description:
        'Finding ids the implementer reported as "fixed" whose claimed change you could NOT find in the tree — the file it said it deleted is still present, the content it said it removed is still there, the path is still in `git ls-files --stage`. Empty array when nothing was claimed fixed or every claim checked out. Judge only what the claim asserts; do not re-litigate whether the finding was right.',
    },
    unexpected_test_files: {
      type: 'array',
      items: { type: 'string' },
      description:
        'Only for a task marked testable:false, whose evidence is the EXISTING suite passing unchanged. List any test file this task added, and any existing test file it added cases to. Empty array otherwise, and empty when a testable:false task left the test files alone.',
    },
  },
}

const COMMIT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['committed', 'hash', 'subject'],
  properties: { committed: { type: 'boolean' }, hash: { type: 'string' }, subject: { type: 'string' } },
}

const VERIFY_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['clean', 'findings'],
  properties: {
    clean: { type: 'boolean', description: 'true only when there are no block-severity findings' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['check', 'severity', 'detail'],
        properties: {
          check: { type: 'string', enum: ['staged-tail', 'vacuous-receipt', 'dead-code', 'commit-boundary'] },
          severity: { type: 'string', enum: ['block', 'warn'] },
          detail: { type: 'string', description: 'file/symbol/commit + the concrete problem and its fix' },
        },
      },
    },
    learnings_path: { type: ['string', 'null'], description: "the run's learnings file, surfaced for the human; null if none" },
  },
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
  `If \`${LEARNINGS_PATH}\` exists, read it first: its entries are durable conventions, recurring review findings, and constraints distilled from earlier runs in this repo. Fold the relevant ones into each task's \`patterns_to_follow\` and do not re-propose work they already cover.\n\n` +
  `${CRITERIA_RULE}\n\n` +
  `From ${CALLER_PATTERNS} read 'How to Identify the Caller' and the Quick Reference; from any language testing-patterns guideline read 'Unit of Behavior'. ${DISCLOSURE}\n\n` +
  `<user_story>\n${story}\n</user_story>`

const adoptTasksPrompt = (tasksFile) =>
  `Read the existing task breakdown at \`${tasksFile}\` and return its tasks in the required schema — ADOPT it, do not re-plan.\n\n` +
  `- Preserve the file's task order, titles, descriptions, and any stated acceptance criteria and dependencies. Do not invent, merge, split, or drop tasks.\n` +
  `- The file's checklist is the progress record: a task whose entry is already checked (\`- [x] Task N\`) was completed and committed by an earlier run — OMIT it from \`tasks\` so the run resumes from the first unchecked task.\n` +
  `- For any schema field the file does not state, infer conservatively from its content: \`language\` from the target stack, \`depends_on\` from stated ordering (\`[]\` if none), \`affected_files\` / \`patterns_to_follow\` from what it names (empty arrays if none), \`testable\` true unless the task is pure docs/config. \`n\` is each task's own number in the file (file order from 1 if unnumbered).\n` +
  `- Set \`tasks_file\` to \`${tasksFile}\`.\n` +
  `If \`${LEARNINGS_PATH}\` exists you may fold relevant durable learnings into \`patterns_to_follow\`, but otherwise leave the breakdown intact.`

const designPrompt = (t, cfg) =>
  `${taskHeader(t)}\n\nDesign the test scenarios for this task. Required reading: ${cfg.guidelines.join(', ')}. ${DISCLOSURE} ` +
  `From caller-patterns identify the caller pattern and read only that section plus the Quick Reference; use its assert-on / don't-assert-on tables to shape scenarios.`

const implementPrompt = (t, cfg, testPlan, feedback, outstanding = []) =>
  `${taskHeader(t)}\n\n` +
  (t.testable === false
    ? `This task is \`testable: false\`: it changes where code lives or how it is shaped WITHOUT changing what it does, so its evidence is the EXISTING suite passing unchanged. Do NOT add a test file and do NOT add cases to an existing one — a new test here asserts behaviour the current suite already covers, and a reviewer will raise it as a redundant test and block the task. If you believe some behaviour is genuinely uncovered, say so in your summary and leave it uncovered; it belongs to a task that owns that behaviour, not to this move. Run \`${testCmdFor(t.language)}\` and show the existing suite still passing.\n\n`
    : `Write failing tests first (per the approved plan), then implement until they pass. Test command: \`${testCmdFor(t.language)}\`.\n\n`) +
  `${FRONT_LOAD_READING} The task's affected-file list above is that starting set; read those files whole before your first edit, together with the one or two the patterns-to-follow name as precedent. While iterating, prefer the narrowest test selector that still covers what you changed — the full suite belongs to the receipt at the end, not to every loop.\n\n` +
  `Approved test plan:\n${testPlan}\n\n` +
  (feedback ? `REVISION REQUIRED — close these concrete gaps from the previous attempt:\n${feedback}\n\n` : '') +
  (outstanding.length
    ? `OUTSTANDING FINDINGS FROM EARLIER ATTEMPTS — return a \`finding_dispositions\` entry for EVERY id listed here.\n` +
      outstanding.map((c) => `- [${c.finding.id}] (${c.finding.file}) ${c.finding.claim}`).join('\n') +
      `\n\nEach entry is either status "fixed", whose note names the file and the concrete change a reviewer can go and check, or status "rejected", whose note says why the finding does not hold. ` +
      `Leaving an id out of \`finding_dispositions\` blocks this task from closing, and so does claiming "fixed" for something a reviewer then raises again — so do not claim a fix you have not made.\n\n`
    : '') +
  `COMMENT DISCIPLINE: keep comments minimal per ${'~/.config/ai/guidelines/comments.md'} — default to none; write one only when you can name the specific wrong conclusion a reader would draw without it. Never name code by its position in the plan ("reactor 1/2", "the decide leg", "the on switch", "PR N", "Task N", "design note X") and never narrate the task/fix/PR — those are plan artifacts a reader of the merged code cannot see. Describe code by its domain role.\n\n` +
  `EVIDENCE CONTRACT (this is non-negotiable):\n` +
  `- Actually RUN \`${testCmdFor(t.language)}\` and return its real output tail in \`test_receipt\` — verbatim command, raw output, pass/fail boolean. A narrated "tests pass" is rejected.\n` +
  `- For EACH acceptance criterion, attach \`criteria_evidence\`: a named test (kind:test) or, for behavior a unit test can't express, an executed demonstration (kind:demo) — with the exact command and its raw output tail. Mark \`satisfied\` only from what the output actually shows.\n` +
  `- EVIDENCE MUST PERSIST. A test that proves a criterion belongs IN the real test file, written there from the start — never in a scratch file you run once and delete. Before you finish, every \`persisted_test\` you cite must still exist and still run; the auditor re-runs them by name and a citation that no longer resolves is a vacuous receipt that blocks the task.\n` +
  `  A throwaway probe is legitimate ONLY when it answers a question for YOU (is this branch reachable, is this perf concern real) and NO criterion rests on it. Before deleting any test file, ask: "does an acceptance criterion lose its proof if this goes?" If yes, it was never a scratch file — fold it into the committed test file instead.\n` +
  `- A TEST THAT CANNOT FAIL IS NOT EVIDENCE. Before citing any test, apply the substitution test: if the code under test were reverted, stubbed, or had this branch deleted, would this test fail? If it would still pass, it proves nothing and will block the task as a \`broken-test\`.\n` +
  `  Criteria phrased as an ABSENCE — "without X", "behaves exactly as before", "produces no diagnostic", "is unchanged" — are where this goes wrong most, because asserting a zero value on input that omits the feature passes with the feature deleted. Prove those against input that DOES exercise the new handling: assert the with-X and without-X cases together (sibling elements, a table with both rows, a before/after of the same document), so deleting or misrouting the handling breaks the assertion. Where a criterion rests on such a claim, actually run the mutation once — break the handling, watch the test fail, restore it — and cite the test only after it has demonstrably failed for the right reason.\n` +
  `- Leave NO build artifacts in the tree. Build to a temp path or \`-o /dev/null\`; a compiler invoked without an output flag drops a binary in the repo root, where it reads as untracked source and can be swept into a commit.\n` +
  `Leave all changes STAGED. Do NOT commit.`

const refactorPrompt = (t, cfg, impl) =>
  `${taskHeader(t)}\n\nFiles changed so far: ${impl.files_changed.join(', ')}.\n` +
  `Tidy ONLY the lines this task just wrote. Read \`git diff --staged\` first and treat it as the boundary of your remit: rename the identifiers it introduces, collapse duplication it introduces, extract a helper used twice WITHIN the new code. Follow ${'~/.config/ai/guidelines/comments.md'} for comment usage.\n` +
  `OUT OF SCOPE, however tempting: extracting a type or module from code that was already there, decomposing or re-signaturing an existing function, renaming an existing function or file, moving code between modules, or restructuring anything the diff does not already touch. Cross-cutting structure is a separate pass over the finished branch and is not yours. If you can see such an improvement, name it in \`outcome\` and leave the code alone — a reviewer will otherwise raise it as scope creep and it will be reverted, costing the task an attempt for nothing.\n` +
  `If you move any existing function, you own the fallout: a test that locates code by scanning source text (\`readFileSync\` plus \`indexOf\`/\`substring\` bounds) can silently invert into scanning nothing and pass forever. Re-read any such test and prove it still fails for the reason it names.\n` +
  `Keep tests green: after refactoring, RUN \`${testCmdFor(t.language)}\` and return the post-refactor \`test_receipt\` (verbatim). ` +
  `If refactoring breaks tests and you cannot fix it, revert and set outcome to "reverted: <reason>". If nothing is worth changing, set outcome "none needed" and still return a passing receipt. Leave changes STAGED.`

const reviewPrompt = (t, changedFiles = []) =>
  `Review the STAGED changes for this task. Use \`git diff --staged\` for the diff.\n\n${taskHeader(t)}\n\n` +
  (changedFiles.length
    ? `The implementer changed these files — you do not need to discover them:\n${changedFiles.map((f) => `  ${f}`).join('\n')}\n\n`
    : '') +
  `${FRONT_LOAD_READING} For a review that means: the diff, plus the WHOLE post-image of each changed file, read together at the start. You are judging new code against the code already there, which the diff alone never shows.\n\n` +
  `Do NOT run the test suite. The implementer returned a receipt for it and an independent audit re-runs it after you, so repeating it adds nothing to your verdict and costs minutes of every review. Run a scoped command only to demonstrate a specific finding you are raising.\n\n` +
  `When the diff adds or changes tests, do NOT judge them from the diff alone — read the WHOLE test file and weigh each new/changed test against the tests already there. A behaviorally-valid test still fails review if it is REDUNDANT: a new data point (enum value, field, config entry, allow-list token) exercising a behavior an existing test already covers belongs FOLDED into that test, not cloned as a parallel one; a change-detector already covered by a behavioral test should be dropped. This is test-quality scope — the semantic reviewer owns it (guideline: "Additional Data Point vs. New Behavior" / "Prefer Higher-Level Behavioral Tests Over Change Detectors"). Raise such a case as a \`quality\` finding classified \`quality_kind: "redundant-test"\` to fold-or-drop; it is non-negotiable and blocks at any severity, so rate its severity honestly rather than inflating it to force the block.\n\n` +
  `Separately, a test that provides NO value is not a nit to defer: a tautology (expected value derived from the code under test at runtime), a vacuous passthrough or constant-pin (it still passes if the code under test is replaced by a stub returning a constant or forwarding a collaborator's value verbatim — the substitution test), a call-count-only assertion, or a test with no behavioral assertion at all. Raise it as a \`quality\` finding classified \`quality_kind: "broken-test"\`; it is non-negotiable and blocks at any severity. The fix is to make it assert real behavior or delete it.\n\n` +
  `Likewise weigh every new or changed comment against ${'~/.config/ai/guidelines/comments.md'}: a comment that only restates what the code already says, or names code by its plan position ("PR/Task N", "reactor 1/2", "the decide leg") rather than its domain role, is a comment-usage violation. Raise it as a \`quality\` finding classified \`quality_kind: "comment-usage"\` — also non-negotiable, also blocks at any severity.\n\n` +
  `Return a verdict and findings. For every finding give a stable \`id\`, an honest \`severity\`, \`file\`, a one-sentence \`claim\`, and its \`nature\`: "runtime" for a defect an independent agent could reproduce by executing code (correctness / concurrency / performance — make the \`claim\` precise enough to reproduce), or "quality" for a code-quality or convention violation with no runtime symptom. For every "quality" finding also set \`quality_kind\` (comment-usage / redundant-test / broken-test / other). Do NOT drop a quality finding just because it cannot be executed, and do NOT inflate severity to force a block — the block decision is made downstream from nature and quality_kind, where comment-usage, redundant-test and broken-test block at any severity and other quality findings block at medium or above. If your scope does not apply to this diff, return verdict "pass" with no findings.`

const reproPrompt = (t, f) =>
  `A reviewer claims a problem in the STAGED changes for task ${t.n}. Your job is to ESTABLISH EXECUTED EVIDENCE for or against it — do not take the claim on faith (the reviewer that raised it did not run anything).\n\n` +
  `Finding ${f.id} [${f.severity}] in ${f.file}: ${f.claim}\n\n` +
  `Try to reproduce it concretely: write and run a failing test, a \`-race\` run, a benchmark, or a direct execution that demonstrates the defect. ` +
  `If you reproduce it, set reproduced=true, classification="real", and put the exact command + raw output in \`repro\`. ` +
  `If you cannot reproduce it after a genuine attempt, set reproduced=false, classification="speculative", and explain what you tried in \`note\`. Default to "speculative" when uncertain — an unreproduced claim is an assertion, not evidence.`

const citedEvidenceDigest = (impl) => {
  const cited = (impl.criteria_evidence ?? []).filter((e) => e.kind === 'test' && e.persisted_test)
  if (!cited.length) return 'The implementer cited NO persisted tests — every criterion below therefore rests on a demo or on nothing; scrutinise accordingly.'
  return cited.map((e) => `  - "${e.criterion}" -> ${e.persisted_test}`).join('\n')
}

// A `fixed` disposition is a claim about the tree, so it is checkable there and then —
// waiting for a reviewer to raise the finding again costs a whole attempt and only works
// when the re-run happens to re-flag it, which reviewer non-determinism does not promise.
const claimedFixedStep = (impl) => {
  const claims = (impl.finding_dispositions ?? []).filter((d) => d.status === 'fixed')
  if (!claims.length) return `6. The implementer claimed no fixes this attempt, so \`false_fixed\` is an empty array.\n`
  return (
    `6. VERIFY EACH CLAIMED FIX LANDED. The implementer reported these findings "fixed":\n` +
    claims.map((d) => `   - [${d.id}] ${d.note}`).join('\n') +
    `\n   For each, check the claim against the tree: a file it says it deleted must be absent from disk AND from \`git ls-files --stage\`; content it says it removed must be gone from the file; a change it describes must be visible in \`git diff --staged\`. ` +
    `Note that this task's work is STAGED, not committed — plain \`git diff\` shows nothing here, so use \`git diff --staged\` and \`git status --short\`, and read the file itself rather than inferring from an empty diff. ` +
    `Put in \`false_fixed\` the id of every claim you cannot confirm. Judge only whether the described change is there; whether the finding deserved fixing is not yours to re-open.\n`
  )
}

const auditPrompt = (t, impl, refactor) =>
  `Independently audit task ${t.n} against its acceptance criteria. Do NOT trust the implementer's self-report — re-execute.\n\n${taskHeader(t)}\n\n` +
  `The implementer reported these receipts (verify, do not assume): impl test \`${impl.test_receipt.command}\` -> passed=${impl.test_receipt.passed}; refactor outcome "${refactor.outcome}".\n\n` +
  `It cited these persisted tests as the proof of its criteria:\n${citedEvidenceDigest(impl)}\n\n` +
  `1. RUN \`${testCmdFor(t.language)}\` yourself in the working tree and return the raw result as \`test_rerun\` (this is the executed-evidence check against a possibly-fabricated implementer receipt).\n` +
  `2. VERIFY EVERY CITATION RESOLVES. For each cited \`<file>::<test name>\` above: confirm the file exists in the working tree, then re-run that test BY NAME (e.g. \`go test -run 'TestX/sub' ./pkg/\`, \`pytest path::test\`, per this project's runner) and confirm it actually SELECTS a test and passes. A runner that matches nothing exits 0 while running zero tests — "no tests to run"/"0 passed"/"testing: warning: no tests to run" is a FAILED citation, not a pass. Set \`evidence_persists\` false for any citation naming a file or test that does not resolve: that means the implementer produced the evidence and then deleted it, which is a vacuous receipt.\n` +
  `3. For each acceptance criterion, decide \`has_executed_evidence\` strictly: is there a test or demonstration whose ACTUAL output shows the criterion met? Narration does not count.\n` +
  `   ONE EXEMPTION, applied narrowly. A criterion may carry a clause about state that does not exist yet during a task — the commit message, \`git log\`, a clean \`git status\` — because this task is committed only AFTER it closes. No evidence for such a clause can exist at any point in this loop, so judge the criterion on the part that IS checkable in the working tree, and record the deferred clause in that criterion's \`note\` rather than listing the criterion as unmet. This exemption covers ONLY clauses about commit or branch state; a criterion whose substance is simply unproven stays unmet.\n` +
  `4. List in \`unmet\` every criterion with no executed evidence OR with \`evidence_persists\` false (say which, and name the missing file/test), plus "tests regressed" if your re-run failed.\n` +
  `5. RESOLVE EVERY PATH AGAINST THIS TREE. Run \`git rev-parse --show-toplevel\` once and treat that as the root for every path you check. A repo checked out as a git worktree has sibling checkouts of the same repo on disk, and a relative path resolved in the wrong one reports a file "already deleted" that is still sitting in this tree — the exact shape of a fix that looks landed and is not.\n` +
  claimedFixedStep(impl) +
  (t.testable === false
    ? `7. THIS TASK IS \`testable: false\` — its evidence is the EXISTING suite passing unchanged, so it must not add tests. Report in \`unexpected_test_files\` any test file it created and any existing test file it added cases to (\`git diff --staged --stat\` against the project's test-file naming). Return an empty array if it added none.`
    : `7. This task is testable, so \`unexpected_test_files\` is an empty array.`)

const commitPrompt = (t, ticket, tasksFilePath) =>
  `Commit task ${t.n}: ${t.title}. The changes are already STAGED; if anything is missing, stage it by EXPLICIT path (\`git add -- <file>\` for each file this task changed) — never \`git add -A\`/\`git add .\`, which can sweep in unrelated or prior-task files and trips the individual-file-staging safety check. Create exactly ONE commit.\n` +
  `First record progress: in \`${tasksFilePath}\`, flip this task's checklist entry from \`- [ ] Task ${t.n}:\` to \`- [x] Task ${t.n}:\` and stage the file so the progress update rides in this commit. If the file has no such entry or git refuses to stage it (e.g. ignored path), continue without it — never block the commit on the checklist.\n` +
  `Apply the repo's OWN commit conventions — read CLAUDE.md / any committing guideline and reuse a cached trailer (e.g. a Linear initiative trailer) if the repo uses one. ` +
  (ticket ? `Weave in this ticket context per those conventions: ${ticket}. ` : '') +
  `The subject MUST satisfy the repo commit rules regardless: imperative mood, <=50 chars, capitalized, no trailing period, NO mention of AI/Claude, NO Co-Authored-By trailer. ` +
  `Return the resulting commit hash and subject.`

// The cross-cutting half of refactoring, which the per-task pass is forbidden to do.
// It runs once, over the finished branch, where restructuring IS the task and so
// cannot read as scope creep — the failure mode that stalled tasks when the same work
// was attempted inside them.
const finalRefactorPrompt = () =>
  `Every task on this branch is committed and its tests pass. Make ONE pass over the branch as a whole for the structure no single task could see.\n\n` +
  `Resolve the branch base yourself — \`git merge-base HEAD main\`, falling back to \`master\` — then read \`git diff <base>...HEAD\` and the whole post-image of each file it touches. You are looking for structure that emerged across tasks: the same shape built twice in different tasks, a function that grew past what its name claims, a helper that belongs beside its sibling, a module boundary the finished code argues for.\n\n` +
  `Behaviour must not change. This is the pass with the widest blast radius in the run and it lands after the tests are already green, so a mistake here is subtle rather than loud:\n` +
  `- A test that locates code by scanning source text (\`readFileSync\` plus \`indexOf\`/\`substring\` bounds, a regex over a file) can silently invert into scanning nothing and pass forever once you move a function. Find every such test in the changed area, and for each one PROVE it still fails for the reason its name gives: inject the violation it claims to catch, watch it fail, revert the injection. Report what you proved in \`outcome\`.\n` +
  `- An assertion that pins the ABSENCE of something passes when the feature is deleted. If you move code such a test guards, check it still has a positive assertion tying it to the feature.\n\n` +
  `Follow ${'~/.config/ai/guidelines/comments.md'} for comment usage. After restructuring RUN \`${FULL_TEST_CMD}\` and return the verbatim post-refactor \`test_receipt\`.\n` +
  `If anything breaks and you cannot fix it, revert everything and set outcome "reverted: <reason>". If the branch needs no cross-cutting change, set outcome "none needed" and still return a passing receipt — that is a perfectly good result, and inventing work here is worse than doing none. Leave changes STAGED and do NOT commit.`

const finalRefactorCommitPrompt = (ticket) =>
  `Commit the cross-cutting refactor that is already STAGED. If anything is missing, stage it by EXPLICIT path (\`git add -- <file>\`) — never \`git add -A\`/\`git add .\`. Create exactly ONE commit.\n` +
  `Apply the repo's OWN commit conventions — read CLAUDE.md / any committing guideline and reuse a cached trailer if the repo uses one. ` +
  (ticket ? `Weave in this ticket context per those conventions: ${ticket}. ` : '') +
  `The subject MUST satisfy the repo commit rules regardless: imperative mood, <=50 chars, capitalized, no trailing period, NO mention of AI/Claude, NO Co-Authored-By trailer. It describes the restructure, not the features that preceded it. ` +
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
    `If \`${LEARNINGS_PATH}\` exists, read it and fold relevant durable learnings into \`patterns_to_follow\`.\n\n` +
    `${CRITERIA_RULE}\n\n` +
    `From ${CALLER_PATTERNS} read 'How to Identify the Caller' and the Quick Reference; from any language testing-patterns guideline read 'Unit of Behavior'. ${DISCLOSURE}\n\n` +
    `<user_story>\n${story}\n</user_story>`
  )
}

const verifyBrief = (allClosed) =>
  `Verify this just-finished implementation run. Work in the tree that holds its commits ` +
  `(resolve with \`git rev-parse --show-toplevel\` — do NOT assume the main checkout), scoped to the run's commits ` +
  `(\`git merge-base HEAD <default-branch>\`..HEAD). Run all your checks and return the structured verdict. ` +
  `This run reports all tasks ${allClosed ? 'CLOSED' : 'NOT all closed'} — treat an uncalled new public symbol as ` +
  `\`block\` only when all tasks closed; otherwise \`warn\` (a later task may wire it).`

const finalSuitePrompt = () =>
  `Run the full test suite (\`${FULL_TEST_CMD}\`) in the worktree that holds this run's commits — resolve it with \`git rev-parse --show-toplevel\` from the tree where the tasks were committed; do NOT assume the main checkout, which may be on another branch. ` +
  `Return the raw result as a receipt (verbatim command, raw output tail, pass/fail boolean). Do not summarize away the output. ` +
  `A receipt whose output shows zero tests/packages executed (e.g. a change-scoped runner printing "No Go files changed, skip running tests") proves nothing — treat it as NOT passing: set \`passed\` to false and include that line verbatim in \`raw_output_tail\`.`

const finishPrompt = (tasksFilePath, integrate) =>
  `Every task in this run closed and was committed. Finish the run's bookkeeping in the main working tree:\n\n` +
  `1. Archive the task breakdown: \`mkdir -p tasks/completed\` then \`git mv ${tasksFilePath} tasks/completed/\` (if the file is untracked, plain \`mv\` and \`git add\` the new path). Commit the move as ONE commit whose subject satisfies the repo commit rules (imperative mood, <=50 chars, capitalized, no trailing period, NO mention of AI/Claude, NO Co-Authored-By). Set \`tasks_file_moved_to\` to the new repo-relative path, or null with the reason in \`note\` if the move could not be done.\n` +
  (integrate
    ? `2. Integrate the implementation branch into the default branch, LOCALLY ONLY — never push:\n` +
      `   a. \`git branch --show-current\` is the implementation branch. The default branch is \`git rev-parse --abbrev-ref origin/HEAD\` if set, else whichever of \`main\`/\`master\` exists locally. If you are already ON the default branch, set integrated=false and stop — nothing to integrate.\n` +
      `   b. \`git rebase <default>\`. On ANY conflict: \`git rebase --abort\`, set integrated=false, leave the branch exactly as it was, and explain in \`note\`.\n` +
      `   c. If the rebase actually replayed commits onto a moved base (not a no-op), re-run \`${FULL_TEST_CMD}\`; if it fails, STOP — leave the rebased branch checked out for human review, set integrated=false, and put the failing output tail in \`note\`.\n` +
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
  `2. Read \`${LEARNINGS_PATH}\` if it exists and dedup against it on substance, not wording — propose only genuinely new learnings.\n` +
  `3. FALSIFIABLE FILTER: keep a learning only when you can name the specific future mistake it prevents (the \`prevents\` field). If you cannot, it is task-specific noise — drop it. Prefer learnings evidenced across >=2 tasks or flagged by a reviewer as a repo-wide convention.\n` +
  `4. Append every surviving learning to \`${LEARNINGS_PATH}\` (create it if missing), each as:\n` +
  `   ## <title>\n   - Type: <kind>\n   - Learning: <the durable fact>\n   - Apply when: <future situation>\n` +
  `Write to \`${LEARNINGS_PATH}\` (create if missing) and do NOT commit it: when it is the in-tree \`tasks/learnings.md\` it lands in the post-run diff for your review; when the orchestrator resolved it to the out-of-tree per-project store it is private steering for the next run. Return the learnings you wrote; empty list if none survive the filter.`

const buildFeedback = (unmet, realFindings, qualityFindings = [], undisposed = [], falseFixed = []) =>
  [
    ...unmet.map((c) => `- Unmet acceptance criterion (no executed evidence): ${c}`),
    ...realFindings.map((v) => `- Reproduced ${v.finding_id}: ${v.note} (repro: ${v.repro?.command ?? 'see note'})`),
    ...qualityFindings.map((f) => `- Code-quality finding to fix directly [${f.id}] (${f.file}): ${f.claim}`),
    ...undisposed.map((c) => `- Finding [${c.finding.id}] raised earlier is still undisposed — fix it or reject it with a reason`),
    ...falseFixed.map(
      (c) => `- Finding [${c.finding.id}] was reported "fixed" ("${c.note}") but a reviewer raised it again — the claimed fix did not land`,
    ),
  ].join('\n')

const trimEvidence = (e) =>
  e && {
    impl_test: e.impl?.test_receipt,
    refactor: e.refactor?.outcome,
    audit_rerun: e.audit?.test_rerun,
    findings: e.findings?.length ?? 0,
    reproduced_real: e.repros?.filter((v) => v.classification === 'real' && v.reproduced).length ?? 0,
    speculative: e.repros?.filter((v) => v.classification === 'speculative').length ?? 0,
    quality_blocking: e.qualityFindings?.length ?? 0,
    quality_advisory: e.advisoryQuality?.length ?? 0,
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
    // Interpolated into the implementer's prompt, so a null would reach it as the
    // literal "null" and read as a test plan saying nothing.
    testPlan = (await agentOrRetry(designPrompt(task, cfg), { label: `${tag}:design`, phase: 'Implement', agentType: 'test-case-designer' }, `${tag} test-design`))
      ?? 'No test plan was produced (the design agent died on an API error). Derive the cases from the acceptance criteria yourself.'
  }

  let feedback = null
  let evidence = null
  let attemptsUsed = 0
  // An open task leaves its work in the tree uncommitted, and this script has no
  // shell to run `git status` with. Carrying the last implementer's file list out
  // is the one record available in-script of what is sitting loose — without it an
  // open task reports only that evidence did not close, and a finished-but-
  // uncommitted change is invisible to anything except the run-verifier.
  let lastFilesChanged = []
  // Findings survive the attempt that raised them. Reviewer output is not a
  // function of the diff — the same untouched code can be flagged, skipped, then
  // flagged again — so a finding that is merely not re-raised must not read as
  // resolved. Every id stays here until the implementer says fixed or rejected.
  const carried = new Map()
  // An attempt that failed on nothing but quality findings needs a cheaper next
  // pass than a full re-run: no behaviour is in question, so there is no fresh
  // code worth restructuring and no reason to re-ask a lens that raised nothing.
  // These two carry that decision from the end of one attempt into the next.
  let narrowTo = null
  let skipRefactor = false

  for (let attempt = 1; attempt <= MAX_RESOLVE; attempt++) {
    attemptsUsed = attempt
    const outstanding = [...carried.values()].filter((c) => c.status === 'open')
    // A dead agent must not cost an evidence attempt: agentOrRetry exhausts its own
    // infrastructure budget first, and only a still-null result opens the task.
    const impl = await agentOrRetry(implementPrompt(task, cfg, testPlan, feedback, outstanding), {
      label: `${tag}:impl#${attempt}`, phase: 'Implement', agentType: cfg.implementer, schema: IMPL_SCHEMA,
    }, `${tag} implement (attempt ${attempt})`)
    if (!impl) {
      feedback = `implementer returned no result after ${INFRA_RETRIES} infrastructure retries — an API outage, not a failed change. Any work already written to the tree is uncommitted.`
      log(`${tag}: attempt ${attempt} aborted — implementer returned no result`)
      break
    }
    lastFilesChanged = impl.files_changed ?? lastFilesChanged
    const refactor = skipRefactor
      ? { outcome: 'skipped (previous attempt failed on quality findings only — no new behaviour to restructure)', test_receipt: impl.test_receipt }
      : (await agent(refactorPrompt(task, cfg, impl), {
          label: `${tag}:refactor#${attempt}`, phase: 'Implement', agentType: cfg.refactorer, schema: REFACTOR_SCHEMA,
        })) ?? { outcome: 'skipped (refactor agent returned no result)', test_receipt: impl.test_receipt }
    if (skipRefactor) log(`${tag}: attempt ${attempt} skipping refactor — fixing quality findings only`)

    const { reviewers: panel, reason, skipped } = selectReviewers(cfg, task, impl.files_changed)
    if (reason) log(`${tag}: skipping code reviewers — ${reason}`)
    for (const s of skipped ?? []) log(`${tag}: not running ${s}`)
    // Re-ask only the lenses that raised what is still outstanding. A lens that
    // passed on this diff has nothing to re-decide, and the whole panel costs the
    // slowest reviewer for every nit. Anything touching behaviour is not a quality
    // finding, so it never narrows — narrowTo is only ever set on a quality-only fail.
    // Falling back to the whole panel when the narrowed set comes out empty is not
    // caution for its own sake: triage is recomputed from each attempt's changed files,
    // so an objecting lens can drop out of the panel between attempts — and narrowing
    // to nothing would let the fix close with nobody having looked at it.
    const narrowed = narrowTo ? panel.filter((r) => narrowTo.has(r)) : null
    const reviewers = narrowed?.length ? narrowed : panel
    if (narrowTo) {
      log(narrowed?.length
        ? `${tag}: attempt ${attempt} re-reviewing with ${reviewers.join(', ')} — the lens(es) that raised the outstanding findings`
        : `${tag}: attempt ${attempt} wanted to narrow but no objecting lens is in this attempt's panel — running the full panel`)
    }

    // The auditor re-runs the suite and checks criteria against the tree; the
    // reviewers are read-only. Nothing it needs depends on their verdicts, so it
    // starts here and is awaited once they are in — its whole duration used to sit
    // on the critical path of every attempt for no reason. It stays AHEAD of
    // reproduction, which does write scratch tests the audit's suite run would see.
    const auditPending = agentOrRetry(auditPrompt(task, impl, refactor), { label: `${tag}:audit#${attempt}`, phase: 'Verify', schema: AUDIT_SCHEMA }, `${tag} audit (attempt ${attempt})`)

    const reviews = reviewers.length
      ? (await parallel(
          reviewers.map((r) => () => agent(reviewPrompt(task, impl.files_changed ?? []), { label: `${tag}:review:${r}`, phase: 'Implement', agentType: r, schema: REVIEW_SCHEMA })
            .then((rv) => (rv ? { ...rv, reviewer: r } : null))),
        )).filter(Boolean)
      : []
    const audit = await auditPending
    if (!audit) {
      feedback = `audit returned no result after ${INFRA_RETRIES} infrastructure retries — an API outage, not a failed change. Any work already written to the tree is uncommitted.`
      log(`${tag}: attempt ${attempt} aborted — audit returned no result`)
      break
    }
    for (const d of impl.finding_dispositions ?? []) {
      const c = carried.get(d.id)
      if (c) Object.assign(c, { status: d.status, note: d.note, disposedAt: attempt })
    }

    const findings = reviews.flatMap((rv) => (rv.findings ?? []).map((f) => ({ ...f, reviewer: rv.reviewer })))
    for (const f of findings) {
      const c = carried.get(f.id)
      if (!c) carried.set(f.id, { finding: f, reviewer: f.reviewer, status: 'open', raisedAt: attempt })
      else if (c.status === 'fixed') Object.assign(c, { status: 'open', reraisedAt: attempt })
    }
    // A quality/convention finding has no runtime symptom to reproduce, so the
    // reproduce gate would always downgrade it to "speculative" and drop it. Send only
    // runtime findings through reproduction; decide quality findings here on the
    // reviewer's classification. Anything not explicitly "quality" defaults to the
    // conservative reproduce path.
    //
    // Blocking is a policy decision kept HERE, decoupled from the reviewer's severity —
    // severity stays an honest "how bad" signal so it is never inflated to force a block.
    // comment-usage violations and broken or redundant tests are non-negotiable and
    // block at any severity. Other quality findings (a naming nit, a minor structure quibble)
    // block only at medium or above; a genuine `low` rides out on the closed task's
    // `unresolved` list so it reaches the human reviewing the branch instead of burning
    // the revision budget and stopping the chain behind it.
    const NON_NEGOTIABLE_QUALITY = new Set(['comment-usage', 'redundant-test', 'broken-test'])
    const qualityBlocks = (f) => NON_NEGOTIABLE_QUALITY.has(f.quality_kind) || f.severity !== 'low'
    const allQuality = findings.filter((f) => f.nature === 'quality')
    const qualityFindings = allQuality.filter(qualityBlocks)
    const advisoryQuality = allQuality.filter((f) => !qualityBlocks(f))
    const runtimeFindings = findings.filter((f) => f.nature !== 'quality')

    const repros = runtimeFindings.length
      ? (await parallel(
          runtimeFindings.map((f) => () => agent(reproPrompt(task, f), { label: `${tag}:repro:${f.id}`, phase: 'Verify', schema: VERDICT_SCHEMA })),
        )).filter(Boolean)
      : []

    const realFindings = repros.filter((v) => v.reproduced && v.classification === 'real')
    const speculative = repros.filter((v) => v.classification === 'speculative')
    // A criterion whose cited test no longer resolves is evidence the implementer
    // produced and then deleted — the exact shape of a scratch/probe file written to
    // satisfy a receipt and removed before finishing. Fold it into `unmet` here rather
    // than trusting the auditor to have carried it across from `criteria`, so the
    // destroyed-evidence case blocks closure structurally.
    const destroyed = (audit.criteria ?? [])
      .filter((c) => c.evidence_persists === false)
      .map((c) => `${c.criterion} — cited test no longer resolves in the tree (evidence was produced then deleted; write it into the real test file)`)
    // A task whose evidence is "the existing suite passes unchanged" has no business
    // adding tests: anything it writes is untested-by-construction surface the reviewers
    // then argue over, which is how a pure move turns into a stalled revision loop.
    const strayTests =
      task.testable === false && (audit.unexpected_test_files ?? []).length
        ? [
            `this task is testable:false — its evidence is the existing suite passing unchanged, but it added test cases in ${audit.unexpected_test_files.join(', ')}; remove them`,
          ]
        : []
    const unmet = [...new Set([...(audit.unmet ?? []), ...destroyed, ...strayTests])]
    if (destroyed.length) log(`${tag}: ${destroyed.length} criterion(s) cite a test that no longer resolves`)
    if (strayTests.length) log(`${tag}: testable:false task added tests in ${audit.unexpected_test_files.join(', ')}`)

    // Blocking-ness is only knowable once reproduction has run, so stamp it here:
    // a high-severity quality finding, or a runtime one an independent agent
    // actually reproduced. Advisory findings are still carried and still reported —
    // they just never stall the task.
    const blockingIDs = new Set([...qualityFindings.map((f) => f.id), ...realFindings.map((v) => v.finding_id)])
    for (const id of blockingIDs) {
      const c = carried.get(id)
      if (c) c.blocking = true
    }
    // An earlier BLOCKING finding the implementer neither fixed nor rejected, and
    // one it claimed to have fixed that a reviewer then raised again: the first is
    // work silently skipped, the second a false report of work done. Neither can be
    // allowed to pass as resolved just because a later review happened not to
    // mention it — reviewer output is not a function of the diff.
    //
    // The reviewer-reraise route catches a false claim only one attempt late, and only
    // when a non-deterministic re-review happens to re-flag it. The auditor checks the
    // same claims against the tree in the attempt they were made, so a claim whose
    // change is simply not there blocks immediately.
    const auditFalseFixed = new Set(audit.false_fixed ?? [])
    if (auditFalseFixed.size) log(`${tag}: audit could not find the claimed fix for ${[...auditFalseFixed].join(', ')}`)
    const falseFixed = [...carried.values()].filter(
      (c) => (c.reraisedAt === attempt && c.blocking) || auditFalseFixed.has(c.finding.id),
    )
    const undisposed = [...carried.values()].filter(
      (c) => c.blocking && c.status === 'open' && c.raisedAt < attempt && c.reraisedAt !== attempt,
    )
    const carriedOut = [...carried.values()]
      .filter((c) => c.status !== 'fixed')
      .map((c) =>
        c.status === 'rejected'
          ? `rejected by implementer: [${c.finding.id}] (${c.finding.file}) ${c.finding.claim} — ${c.note}`
          : `advisory ${c.finding.severity} ${c.finding.nature}: [${c.finding.id}] (${c.finding.file}) ${c.finding.claim}`,
      )
    evidence = { impl, refactor, findings, repros, audit, qualityFindings, advisoryQuality }

    const closed =
      audit.test_rerun?.passed &&
      unmet.length === 0 &&
      realFindings.length === 0 &&
      qualityFindings.length === 0 &&
      undisposed.length === 0 &&
      falseFixed.length === 0
    if (closed) {
      return {
        n: task.n,
        title: task.title,
        status: 'closed',
        attempts: attempt,
        unresolved: [...speculative.map((s) => `speculative: ${s.finding_id} — ${s.note}`), ...carriedOut],
        // Carried so the caller can name the staged files if the commit agent dies
        // between closing this task and committing it.
        files_changed: lastFilesChanged,
        evidence,
      }
    }

    feedback = buildFeedback(unmet, realFindings, qualityFindings, undisposed, falseFixed)
    // Nothing about behaviour is in question: the suite passed, every criterion has
    // evidence, and no runtime claim reproduced. What is left is naming, comments and
    // test shape, so the next attempt edits those and re-asks only the lenses that
    // objected. A falsely-reported fix drops this back to the full panel — that is a
    // claim about the tree, and the point of re-reviewing is that we do not trust it.
    const qualityOnly =
      audit.test_rerun?.passed &&
      unmet.length === 0 &&
      realFindings.length === 0 &&
      falseFixed.length === 0 &&
      qualityFindings.length > 0
    const objecting = new Set(
      [...carried.values()].filter((c) => c.blocking && c.status === 'open' && c.reviewer).map((c) => c.reviewer),
    )
    narrowTo = qualityOnly && objecting.size ? objecting : null
    skipRefactor = qualityOnly
    log(
      `${tag}: attempt ${attempt} did not close — ${unmet.length} unmet criteria, ${realFindings.length} reproduced findings, ` +
        `${qualityFindings.length} blocking quality (${advisoryQuality.length} advisory), ${undisposed.length} undisposed, ${falseFixed.length} falsely reported fixed` +
        (qualityOnly ? ' — quality-only, next attempt runs narrowed' : ''),
    )
  }

  return {
    n: task.n,
    title: task.title,
    status: 'open',
    attempts: attemptsUsed,
    unresolved: [
      feedback ?? 'evidence did not close',
      ...(lastFilesChanged.length
        ? [`uncommitted in the working tree: ${lastFilesChanged.join(', ')} — review or discard these before relaunching, and note that anything else committing in this tree could absorb them`]
        : []),
    ],
    uncommitted: lastFilesChanged,
    evidence,
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

phase('Decompose')
const tasksFile = typeof ARGS === 'object' ? ARGS?.tasksFile : undefined
const ticket = typeof ARGS === 'object' ? ARGS?.ticket : undefined
const story = (typeof ARGS === 'string' ? ARGS : ARGS?.story) || (tasksFile && `the existing task breakdown at ${tasksFile}`)
if (!story) throw new Error('implement-flow: pass args.story (a user story) and/or args.tasksFile (an existing tasks/*.md to adopt)')

// A caller holding the breakdown already can hand it over as args.plan and skip the
// adopt agent. Adopting is deterministic work — read a checklist, drop the ticked
// entries — but running it as a model call put the most fragile step in the system at
// the front of the most-used path: resuming a partly-done story began by asking an
// agent to parse markdown, so one 529 there ended the run before any work started.
// The caller has a filesystem; this script does not. Let whoever can just read the
// file do it.
//
// tasks must contain only the work still OUTSTANDING — the same contract adopt mode
// honours by skipping `- [x]` entries. tasks_file still points at the breakdown, so
// closing a task keeps checking its box off there.
const suppliedPlan = typeof ARGS === 'object' ? ARGS?.plan : undefined

// args.plan arrives as caller data, so it never passed through a schema the way agent
// output does. Normalise it here: fill the fields the prompts interpolate, and reject
// what cannot be defaulted, rather than failing later inside a prompt builder.
const normalisePlan = (p) => {
  if (!p || typeof p !== 'object' || !Array.isArray(p.tasks)) {
    throw new Error('implement-flow: args.plan must be an object with a `tasks` array, and `tasks_file` when the breakdown lives on disk')
  }
  const tasks = p.tasks.map((t, i) => {
    if (!t || typeof t.title !== 'string' || !t.title.trim()) {
      throw new Error(`implement-flow: args.plan.tasks[${i}] needs a non-empty title`)
    }
    return {
      n: Number.isInteger(t.n) ? t.n : i + 1,
      title: t.title,
      description: t.description ?? t.title,
      language: t.language ?? 'unknown',
      behavior: t.behavior ?? t.description ?? t.title,
      acceptance_criteria: Array.isArray(t.acceptance_criteria) ? t.acceptance_criteria : [],
      affected_files: Array.isArray(t.affected_files) ? t.affected_files : [],
      patterns_to_follow: Array.isArray(t.patterns_to_follow) ? t.patterns_to_follow : [],
      // Absent means testable: only an explicit false opts a task out of test design.
      testable: t.testable !== false,
      depends_on: Array.isArray(t.depends_on) ? t.depends_on : [],
    }
  })
  if (!tasks.length) throw new Error('implement-flow: args.plan.tasks is empty — nothing left to do')
  return { tasks_file: typeof p.tasks_file === 'string' ? p.tasks_file : (tasksFile ?? null), tasks }
}

// Take the caller's plan when given one; otherwise adopt a prior breakdown verbatim
// when given a task file; otherwise decompose the story. `story` still anchors any
// later re-decompose in all three cases.
const plan = suppliedPlan
  ? normalisePlan(suppliedPlan)
  : tasksFile
    ? await agentOrRetry(adoptTasksPrompt(tasksFile), { label: 'adopt', agentType: 'decompose-to-tasks', schema: TASK_LIST_SCHEMA }, 'adopt')
    : await agentOrRetry(decomposePrompt(story), { label: 'decompose', agentType: 'decompose-to-tasks', schema: TASK_LIST_SCHEMA }, 'decompose')
if (!plan) {
  throw new Error(
    `implement-flow: ${tasksFile ? 'adopting the breakdown' : 'decomposing the story'} produced no plan after ${INFRA_RETRIES} retries — ` +
      'the agent died on a terminal API error rather than returning a bad plan. Nothing was changed; relaunch when the API recovers' +
      (tasksFile
        ? ' (adopt mode skips tasks already checked off, so no work is repeated). To skip this agent entirely, pass the outstanding tasks as args.plan.'
        : '.'),
  )
}
let planFile = plan.tasks_file
log(
  suppliedPlan
    ? `took ${plan.tasks.length} outstanding task(s) from args.plan — no adopt agent spawned${planFile ? ` (checklist: ${planFile})` : ''}`
    : tasksFile
      ? `adopted ${plan.tasks.length} unchecked task(s) from ${tasksFile}`
      : `decomposed into ${plan.tasks.length} tasks (${planFile})`,
)

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

  // Retry this one hardest: the task has already CLOSED on evidence, so a dead commit
  // agent is the one failure that strands proven work as a staged tail — the very
  // shape the run-verifier reports as a block.
  r.commit = await agentOrRetry(commitPrompt(task, ticket, planFile), { label: `task-${task.n}:commit`, phase: 'Finalize', agentType: 'commit', schema: COMMIT_SCHEMA }, `task ${task.n} commit`)
  if (!r.commit) {
    r.unresolved = [...(r.unresolved ?? []), 'closed on evidence but the commit agent returned no result — the work is STAGED and uncommitted; commit it by hand before relaunching']
    r.uncommitted = r.uncommitted?.length ? r.uncommitted : (r.files_changed ?? [])
    log(`task ${task.n} closed but was NOT committed — stopping the chain so the staged work is not buried under the next task`)
    results.push(r)
    break
  }
  results.push(r)
  completed.push(task)

  if (!remaining.length) continue

  const impact = await agentOrRetry(planImpactPrompt(task, r, remaining), { label: `task-${task.n}:plan-impact`, phase: 'Replan', schema: PLAN_IMPACT_SCHEMA }, `task ${task.n} plan-impact`)
  // No assessment is not a verdict to revise. Keep the plan and carry on: the
  // committed task stands either way, and the human reviews the branch.
  if (!impact) {
    log(`task ${task.n}: plan-impact returned no result — keeping the current plan`)
    continue
  }
  if (impact.impact !== 'revise') continue

  if (replans >= MAX_REPLANS) {
    log(`task ${task.n} flagged a plan change ("${impact.reason}") but the re-decompose cap (${MAX_REPLANS}) is reached — keeping the current plan for human review`)
    continue
  }

  replans++
  log(`task ${task.n} triggered re-decompose (${replans}/${MAX_REPLANS}): ${impact.reason}`)
  const revised = await agentOrRetry(redecomposePrompt(story, completed, remaining, impact.reason, planFile), { label: `replan#${replans}`, phase: 'Replan', agentType: 'decompose-to-tasks', schema: TASK_LIST_SCHEMA }, `replan#${replans}`)
  if (!revised) {
    log(`replan#${replans} returned no result — keeping the current plan of ${remaining.length} task(s)`)
    continue
  }
  remaining = revised.tasks ?? []
  planFile = revised.tasks_file ?? planFile
  log(`re-decomposed remaining work into ${remaining.length} task(s)`)
}

// Cross-cutting structure, once, over the finished branch. Gated on every task having
// closed: restructuring a branch with work still loose in the tree would mix the two
// and leave the human unable to tell them apart. Skipped for a single task too — one
// task's own diff is what the in-task tidy already covers, and there is no second task
// for structure to emerge between.
let finalRefactor = null
if (FINAL_REFACTOR && completed.length > 1 && remaining.length === 0 && results.every((r) => r.status === 'closed')) {
  phase('Restructure')
  // The language most of the branch is written in — the pass reads across tasks, so
  // the majority language is a better fit than whichever task happened to be last.
  const tally = new Map()
  for (const t of completed) tally.set(t.language, (tally.get(t.language) ?? 0) + 1)
  const mainLanguage = [...tally.entries()].sort((a, b) => b[1] - a[1])[0][0]
  finalRefactor = await agent(finalRefactorPrompt(), { label: 'final-refactor', phase: 'Restructure', agentType: cfgFor(mainLanguage).refactorer, schema: REFACTOR_SCHEMA })
  const changed = finalRefactor && !/^(none needed|reverted)/i.test(finalRefactor.outcome ?? '')
  if (changed && finalRefactor.test_receipt?.passed) {
    const rc = await agentOrRetry(finalRefactorCommitPrompt(ticket), { label: 'final-refactor:commit', phase: 'Restructure', agentType: 'commit', schema: COMMIT_SCHEMA }, 'final-refactor commit')
    finalRefactor.commit = rc
    log(`restructure: ${rc?.committed ? `committed ${rc.hash} ${rc.subject}` : 'left staged — commit agent returned no result'}`)
  } else if (changed) {
    log(`restructure: left UNCOMMITTED — its own test receipt did not pass (${finalRefactor.outcome})`)
  } else {
    log(`restructure: ${finalRefactor?.outcome ?? 'no result'}`)
  }
}

phase('Finalize')
// The run's headline receipt, and integration gates on it — a transient null here
// would report a completed run as unverified and silently skip landing it.
const fullSuite = await agentOrRetry(finalSuitePrompt(), { label: 'full-suite', phase: 'Finalize', schema: RECEIPT }, 'full-suite')
const allClosed = results.length > 0 && remaining.length === 0 && results.every((r) => r.status === 'closed')

// Independent post-run verification via the run-verifier agent — the same checks the
// /verify-run command runs: staged-but-uncommitted tails, new public symbols with no
// live caller (dead code), a vacuous/skipped full-suite, collapsed commit boundaries.
// A block-severity finding fails verification and, below, blocks landing the branch.
const verify = await agent(verifyBrief(allClosed), { label: 'verify', phase: 'Finalize', agentType: 'run-verifier', schema: VERIFY_SCHEMA })
if (verify && !verify.clean) log(`verify: ${verify.findings.filter((f) => f.severity === 'block').length} blocking finding(s) — ${verify.findings.map((f) => f.check).join(', ') || 'none'}`)

// Archive + optional integration run BEFORE reflect: reflect writes the learnings
// file and, when it is the in-tree tasks/learnings.md, leaves it uncommitted — a
// dirty tracked file would block the rebase. Integration additionally requires a
// passing full-suite receipt AND a clean verification — never land unverified commits.
let finish = null
if (allClosed && planFile) {
  const integrate = INTEGRATE && fullSuite?.passed === true && verify?.clean === true
  if (INTEGRATE && !integrate) log('integrate: skipped — full-suite or verification did not pass; branch left as-is')
  finish = await agent(finishPrompt(planFile, integrate), { label: 'finish', phase: 'Finalize', schema: FINISH_SCHEMA })
  if (finish) {
    log(finish.tasks_file_moved_to ? `task file archived at ${finish.tasks_file_moved_to}` : `task file NOT archived — ${finish.note}`)
    if (integrate) log(finish.integrated ? `integrated into ${finish.base_branch}, implementation branch deleted` : `integrate aborted — ${finish.note}`)
  }
} else if (INTEGRATE) {
  log('integrate: skipped — not all tasks closed; branch and task file left in place for human review')
}

// Self-improvement write-back. An in-tree learnings file is left UNCOMMITTED on
// purpose (review surface = the post-run diff); an out-of-tree one is the private
// per-project store. Either way the next run reads it back.
const reflection = results.some((r) => r.status === 'closed')
  ? await agent(reflectPrompt(results), { label: 'reflect', phase: 'Finalize', schema: REFLECT_SCHEMA })
  : { learnings: [] }
// agent() yields null when the subagent dies on a terminal API error, and reflect
// runs last: without this the whole finalize phase is thrown away by a transient 529.
const learnings = reflection?.learnings ?? []
log(reflection
  ? `reflect: ${learnings.length} durable learning(s) written to ${LEARNINGS_PATH}`
  : 'reflect: agent returned nothing — no learnings written this run')

return {
  story,
  tasks_file: finish?.tasks_file_moved_to ?? planFile,
  closed: results.filter((r) => r.status === 'closed').length,
  open: results.filter((r) => r.status === 'open').length,
  replans,
  full_suite: fullSuite,
  verification: verify ?? { clean: false, findings: [], learnings_path: null },
  integrated: finish?.integrated ?? false,
  // finish only runs on a fully-closed run, so on a partial one its note is null and
  // nothing at the top level said that finished work was left loose in the tree. State
  // it here, where the caller reads the summary, rather than only inside a task entry.
  finish_note:
    finish?.note ??
    (() => {
      const stranded = results.filter((r) => r.status === 'open' && r.uncommitted?.length)
      if (!stranded.length) return null
      return (
        `Run did not complete. Uncommitted work remains in the working tree from ${stranded.length} open task(s): ` +
        stranded.map((r) => `task ${r.n} (${r.uncommitted.join(', ')})`).join('; ') +
        '. Commit, stash or discard it before relaunching — a concurrent commit in this tree would absorb it.'
      )
    })(),
  learnings,
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
