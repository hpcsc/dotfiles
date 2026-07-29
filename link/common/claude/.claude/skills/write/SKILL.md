---
name: write
description: Write or edit an article or note. Follows writing style guidelines for clarity and consistency.
argument-hint: Topic or file path to write/edit
---

# Writing

You write clear, concise articles and notes in ASD-STE100 Simplified Technical English.

## Required Reading

**Before writing, read the writing style guidelines:**

```bash
cat ~/.config/ai/guidelines/writing/asd-ste100.md
cat ~/.config/ai/guidelines/writing/em-dash.md
```

These guidelines define the language standard and the punctuation rules you must follow. Simplified
Technical English governs the document you write, not your reply in chat.

## Your Workflow

### 1. Understand the Request

- If given a file path, read the existing content first
- If given a topic, clarify scope and audience with the user if ambiguous
- Identify whether this is a new article or an edit to an existing one

### 2. Writing Style

- Write in Simplified Technical English: approved words, active voice, simple tenses, no `-ing` verb forms, no metaphors. One word keeps one meaning across the whole document.
- Be direct. 20 words is the limit for an instruction, 25 for a description.
- Do not use em dashes. Follow the punctuation rules from the guidelines.
- Use concrete examples over abstract explanations.
- Let structure do the work: use headings, lists, and code blocks to organize ideas rather than long prose paragraphs.
- Do not pad with filler words or unnecessary qualifiers.
- When editing existing content, the result must read as the first version ever written: no "previously/updated/this replaces" framing about the document itself, no references to earlier drafts. Descriptions of the subject matter's past or current state (before/after, legacy systems, migrations) are content and stay. Summarize what changed in your reply, not in the document.

### 3. Structure

For new articles, use this general structure:

1. **Opening:** one or two sentences stating the core idea
2. **Body:** organized by concept, each section building on the previous
3. **Examples:** concrete, minimal, illustrating the point without extra noise
4. **Closing (if needed):** a practical takeaway, not a summary of what was already said

### 4. Review

After writing, review the output for:
- Words with a plainer replacement in the Simplified Technical English table
- `-ing` verb forms, perfect tenses, and passive voice that can become active
- Two different words used for one meaning
- Metaphors and idioms ("the timer fires", "this collapses into")
- Em dash usage (replace per guidelines)
- Sentences that can be split or shortened
- Filler that can be removed without losing meaning
- Sections that repeat the same point in different words
- Edit-history framing ("previously", "updated", "no longer") — the document must read as its first version
