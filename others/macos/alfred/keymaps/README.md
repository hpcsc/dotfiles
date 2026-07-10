# Keymaps — Alfred workflow

Fuzzy-search cross-app keymaps (tmux, nvim, yazi) from Alfred.

## Build & import

    task macos:alfred-keymaps

This lints `info.plist`, zips the sources into `Keymaps.alfredworkflow`, and
prints its path. Double-click the bundle to import it into Alfred, then trigger
with `km <query>` (searches app, key, or action; Enter/⌘ copies the keystroke).

## Files

- `keymaps.tsv` — the data: `app<TAB>keys<TAB>description`, one per line. Edit this to add keymaps.
- `keymaps.sh` — emits Alfred Script Filter JSON from the tsv (rarely changes).
- `info.plist` — the workflow definition: `km` keyword → Copy to Clipboard.

The built `Keymaps.alfredworkflow` is a generated artifact (gitignored).
