#!/bin/bash
# Alfred Script Filter: emit fuzzy-searchable keymaps from keymaps.tsv.
# Data format: app<TAB>keys<TAB>description  (lines starting with # are ignored).
cd "$(dirname "$0")" || exit 1

esc() {
	local s=$1
	s=${s//\\/\\\\}
	s=${s//\"/\\\"}
	printf '%s' "$s"
}

items=""
while IFS=$'\t' read -r app keys desc || [ -n "$app" ]; do
	[ -z "$app" ] && continue
	case "$app" in \#*) continue ;; esac
	[ -n "$items" ] && items+=","
	items+="{\"title\":\"$(esc "$keys")\",\"subtitle\":\"$(esc "$app") — $(esc "$desc")\",\"arg\":\"$(esc "$keys")\",\"match\":\"$(esc "$app") $(esc "$keys") $(esc "$desc")\",\"mods\":{\"cmd\":{\"subtitle\":\"Copy to clipboard\",\"arg\":\"$(esc "$keys")\"}}}"
done < keymaps.tsv

printf '{"items":[%s]}\n' "$items"
