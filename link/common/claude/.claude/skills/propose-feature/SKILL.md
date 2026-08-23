---
name: propose-feature
description: Discover, refine, and write a feature proposal end to end. Brainstorm options, size them with real data, converge with the user, then produce audience-specific deliverables (one-page brief, flow proposal, implementation notes, event model, interactive demo).
argument-hint: Problem statement or topic — or "resume .scratches/propose-feature/<slug>" to continue an existing proposal
---

# Feature Proposal

Guide a feature from an open question to a set of finished proposal documents. The process is
conversational and spans many turns, often many sessions. The user steers every convergence
point; you supply options, evidence, and drafts — never a unilateral decision.

Operating principles:

- **Ground every claim.** Current behaviour comes from reading the code, sizes come from
  real data. Never assert from memory what a system does.
- **Options before commitment.** Brainstorm wide, let the user pick. Rejected options usually
  survive as progressive complements (hints, later phases), not as discards.
- **One document per audience.** Business readers never see code paths; engineers never wade
  through business justification. Split rather than mix.
- **Small iteration cycles.** One edge case per cycle: discuss → decide → fold into every
  affected document. Do not batch edge cases.
- **Each user correction is a standing rule.** "Less wordy", "simplify the diagram",
  "that's demo-only" apply to everything that follows, not just the artifact corrected.

## Working folder

- Deliverables live in `./.scratches/propose-feature/<slug>/` in the repo.
- Raw analysis (queries, result dumps, sample content — may contain PII) stays in
  `./.scratches/propose-feature/<slug>/raw/`; deliverables reference only the distilled numbers, never the
  raw files.
- **Resume:** if the user points at an existing folder, read every doc in it first, then
  continue from the newest open thread.

## Phase 1 — Frame and explore

1. Restate the problem, the constraints, and any business rules the user mentions (capture
   their exact wording — stated rules get tested against data later).
2. Read the actual code paths involved. Map the current flow end to end before proposing
   anything. Note hard constraints the design must respect.
3. Report the current-state map back briefly; correct it with the user before building on it.

## Phase 2 — Brainstorm options

- Enumerate strategies as **A, B, C…** so later discussion can reference them by letter.
- For each: mechanism (2–3 sentences), what it wins, what it costs, its risk.
- Always include a hybrid: one primary strategy with the others as progressive complements.
- Discussion only — no proposal documents yet.

## Phase 3 — Size with data

- Offer a data breakdown before the user commits: how big is each branch of the problem,
  which option covers how much of it. Use whatever the project provides — a query skill,
  a warehouse, application logs — and follow its PII rules.
- **Test the user's stated business rules against the data.** A rule that sounds right may
  conflict with reality (e.g. a stated priority rule that the data shows picks the wrong
  record most of the time). Report conflicts neutrally with numbers; the user decides.
- Incidental bugs discovered during analysis get reported (and ticketed, if the project
  tracks work that way) separately — do not fold fixes into the proposal.

## Phase 4 — Converge and record decisions

- The user picks the direction. Reframe the losing options as complements where honest.
- Keep a numbered decision ledger **D1, D2, …** — one line of decision, one line of
  rationale. It lives in the implementation notes and is the single source of truth when
  documents disagree.
- Then iterate edge cases (alternate channels, partial failures, "what still leaks
  through"). Per cycle: discuss the case → the user decides → add a Dn entry → update
  every affected document in the same turn.

## Phase 5 — Write the deliverables

| Deliverable | Audience | Rules |
|---|---|---|
| One-page brief | Business stakeholders | Problem, flow, value, explicit asks. No code, no file paths, no jargon. Write via `/write` (STE). Hard one-page discipline. |
| Flow proposal | Product + engineering | Detailed flow with diagrams, edge-case sections, decision summary, rollout, measures, definition of done. Prose and diagrams only — no code paths. |
| Implementation notes | Engineers | Current-code constraints, the D-ledger with code/SQL/type snippets, schema and routes, changes by layer, test plan, technical acceptance criteria. |
| Event model | Engineers (event-sourced systems) | `emod` model, when the CLI is available; `validate` and `lint` must exit 0. Declare each view slice immediately before the slice that reads it. |
| Interactive demo | Everyone (only when asked) | Match the real product: read its theme, components, and navigation first and reproduce them. Fictitious data only. Label demo-only affordances explicitly (e.g. render two deployments as browser tabs, not an in-app switcher). Smoke-test headlessly (e.g. jsdom). |

Craft rules learned the hard way:

- Diagrams: simplify aggressively — drop anything the reader does not need for the decision
  at hand. Give each edge-case section its own small diagram, then one combined diagram
  placed after the last variant section.
- Every document reads as the first version ever written — no "previously", "updated",
  "this replaces". Change summaries go in chat.
- Do a final de-wording pass on each document; expect the user to ask for it anyway.
- Shareable pages (brief, demo) also publish as Artifacts.

## PII discipline

Warn before any query or fetch that surfaces personal data. Keep PII in `raw/` only;
deliverables carry counts and paraphrased snippets, never raw content. Offer to purge the
raw samples when the analysis is done.
