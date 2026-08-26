Read the diff AND the whole post-image of every changed file in your remit, before judging anything. You are weighing new code against the code already there, which a diff alone never shows.

Open a file with `Read`, whole, and do not open it again — it stays in your context. A file taken in eight `sed -n` slices costs eight model round-trips and yields what one `Read` yields; tool calls here are strictly sequential, so every extra one is time no parallelism gets back. Use `rg` to locate a file or symbol you cannot name, not to re-read one you already opened.

Do NOT run the full test suite — it already passes, that is why this work is finished. Run a scoped command only to demonstrate a specific finding.
