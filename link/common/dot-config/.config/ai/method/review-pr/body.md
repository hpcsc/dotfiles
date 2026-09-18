{{variant:frontmatter}}

Read a pull request and hand back a model of it: $ARGUMENTS

You are the reader here. The deliverable is understanding, in three artifacts and nothing else:

1. **The flow** — a diagram of the path through the system that the change lives in, with the parts it adds or moves marked.
2. **The outcomes** — a table with one row for each case a person can observe, before and after.
3. **The map** — one line for each question a reviewer asks, against the file that answers it, and the order to read those files in.

Stop there. This method finds no defects and posts nothing. `/code-review` critiques, the repository's own review runs in CI, and a person decides. A brief that also argues turns into a list of maybes the reader has to sort, which is the overload this exists to remove.

---

## Inputs

`$ARGUMENTS` is a pull request: a number, `#N`, `owner/repo#N` or a URL. With nothing, use the pull request of the current branch.

`--save` writes the same text to `.pr-notes/pr-<N>.md` and adds that path to `.git/info/exclude`. Without it, the brief lives in the chat only.

## 1. Fetch

```
gh pr view <n> --json number,title,url,author,baseRefName,headRefName,state,body,files
gh pr diff <n> > <scratch>/pr-<n>.diff
gh pr view <n> --json commits --jq '.commits[] | "\(.oid[0:9]) \(.messageHeadline)"'
```

Read the body and the commit bodies for the author's claim. Hold it as a claim. The diff decides what is true.

## 2. Read for the flow, not for the lines

Split the diff into production and test, and count both. The production files are the review surface; the tests say what the author believes.

Read whole files, not hunks, wherever a hunk changes a decision: a condition, a guard, a table, a branch. A hunk shows what moved, and never shows what the code decides.

Answer four questions in writing before drafting:

- What starts the flow? An event, a schedule, a request, a person.
- What are the steps from there to the outcome? Name each as the code names it.
- Where does this change alter a step, add a branch, or change an outcome?
- What does a person see that differs? The customer, the agent, the operator, the caller.

Where the answer is "nothing a person sees", the change is a refactor. Say that; it is a useful answer and it shortens the brief.

## 3. The three artifacts

**The flow.** Mermaid, ten to fifteen nodes. Name nodes as the system names them, so the reader can grep. Put conditions on the edges. Mark what the change adds with `NEW`. Render it before you print it:

```
mise exec -- mmdc -i <file>.mmd -o <file>.svg    # or: npx -y @mermaid-js/mermaid-cli -i ... -o ...
```

A terminal shows Mermaid as source, so print the picture's source and say it renders. When the reader wants it drawn, the `.svg` is already in the scratchpad.

**The outcomes.** One row for each case a person can observe, never one row per commit or per file. Include the cases the change leaves alone where a reader expects movement; a row that reads "unchanged" answers a question before it is asked. Put any irreversible outcome in a sentence of its own under the table.

**The map.** The question a reviewer asks, and the file that answers it. End with the reading order and the two sizes from step 2.

## 4. Print it

In this order, in chat: the heading line (number, title, author, base, state, CI), the three artifacts, then **what only the author can answer** — at most three questions, each about a decision the diff cannot explain.

Nothing else. No glossary, no commit narrative, no summary of the summary, no findings. If a claim of the author's is contradicted by the diff, that is one line under the table, in the reader's words.

Write the prose in Simplified Technical English, following `~/.config/ai/guidelines/writing/asd-ste100.md`. Read that file rather than working from memory.

## 5. Stay available

Answer follow-up questions from the diff and the files you read. Re-read only what a question reaches. Where a question needs a judgement about quality rather than a fact about the change, say so and point at `/code-review`.
