### Read wide, not often

**Open in one message what you already know you need.** Independent calls run in parallel, and one message that reads four files costs the round trip that one file costs. A run's tool calls are its clock: every one re-reads the whole context before it can ask anything, so by the audit step a single call costs three hundred and sixty thousand tokens of re-reading.

**Never page one source across calls.** `head -400` on a command and then `sed -n '400,900p'` on the same command is two round trips for one answer. Reading a file whole and then re-`sed`-ing it for the parts you want is worse: the file is already in front of you. Where a source is too big to take whole, that is what its index is for — `clerk learn index` over the learnings, `clerk guidelines --file` and `--section` over the guidelines, `clerk status` over a breakdown. Ask for less, rather than for the same thing again in windows.

**Read a file with the tool that reads files.** `head`, `sed -n`, `cat` and `tail` each buy one window for one round trip, and then you reason about the window without the rest of the file. Use `rg` to find *where* something is, then open that file whole. Do not use it to read a file whose place you already know.
