#!/usr/bin/awk -f
#
# Deterministic user-story progress report over user-stories/ and tasks/.
#
# Inputs are classified by path, so the caller just passes files:
#
#   user-stories/**.md            story inventory: one "### US-NNN: Title" per story
#   user-stories/completed/**.md  story files finished in full
#   tasks/*.md                    task breakdowns in flight
#   tasks/<story>.json            the sidecar beside a breakdown, carrying each task's
#                                 done flag — the record of progress. Passed already
#                                 flattened as `-v progress=<file>`, one TSV row per
#                                 task, because awk is a poor place to parse JSON and
#                                 the caller has jq. A breakdown with no sidecar falls
#                                 back to any `- [ ] Task N` checklist it still carries
#   tasks/completed/*.md          archived breakdowns — an archived breakdown is
#                                 what marks its story delivered, since that is
#                                 where a fully-closed run moves its task file
#
# A breakdown joins to a story on its H1, "# US-NNN: Title", compared after
# normalisation. The H1 carries the story title verbatim; the *filename* does not
# (us-001-pin-files-to-dsl-version.md drops the "a" from "Pin files to a DSL
# version"), so the filename is never used to join.
#
# A breakdown whose H1 carries no story id covers several stories at once. It is
# attributed to the story file it references and reported at task granularity
# only, because which of that file's stories are done is not recorded anywhere
# machine-readable.
#
# Acceptance-criteria checkboxes inside story files are deliberately ignored:
# they stay unchecked even for delivered stories, so they track nothing.
#
# Modes: -v mode=summary (default) | stories | tasks
# Colour: -v color=1 greens the tick and dims the brackets. Left unset it emits
# plain text, so a redirected or piped run carries no escape codes. The caller
# decides, since awk cannot tell whether its stdout is a terminal.
#
# All three markers are three cells wide, so the titles they precede line up
# whatever mix of states a file is in.

BEGIN {
    # Progress rows: <breakdown path> \t <n> \t <0|1 done> \t <title>. Read first so the
    # per-file rules below know whether a breakdown has a sidecar and can leave a legacy
    # checklist alone when it does.
    if (progress != "") {
        while ((getline row < progress) > 0) {
            split(row, c, "\t")
            f = c[1]
            if (f == "") continue
            bd_side[f] = 1
            bd_total[f]++
            n = ++tk_n[f]
            tk_num[f, n] = c[2]
            tk_done[f, n] = (c[3] == "1")
            tk_title[f, n] = c[4]
            if (c[3] == "1") bd_done[f]++
        }
        close(progress)
    }

    if (color) {
        tick  = "\033[2m[\033[0m\033[38;5;46m✓\033[0m\033[2m]\033[0m"
        flight = "\033[2m[\033[0m~\033[2m]\033[0m"
        blank = "\033[2m[ ]\033[0m"
    } else {
        tick = "[✓]"; flight = "[~]"; blank = "[ ]"
    }
}

function base(p,   n, a) { n = split(p, a, "/"); return a[n] }

function label(p,   s) { s = p; sub(/^user-stories\//, "", s); return s }

function norm(s,   t) {
    t = tolower(s)
    gsub(/[^a-z0-9]+/, " ", t)
    gsub(/^ +| +$/, "", t)
    return t
}

function bar(done, total,   i, n, s) {
    if (total == 0) return "          "
    n = int((done * 10) / total)
    s = ""
    for (i = 0; i < 10; i++) s = s (i < n ? "#" : ".")
    return s
}

FNR == 1 {
    kind = ""
    if (FILENAME ~ /user-stories\//) {
        if (base(FILENAME) == "progress.md") kind = "skip"
        else if (FILENAME ~ /user-stories\/completed\//) kind = "story_done"
        else kind = "story"
    } else if (FILENAME ~ /tasks\//) {
        if (base(FILENAME) == "learnings.md") kind = "skip"
        else if (FILENAME ~ /tasks\/completed\//) kind = "bd_done"
        else kind = "bd"
    }
    h1_seen = 0
}

kind == "skip" { next }

kind == "story" || kind == "story_done" {
    if ($0 ~ /^#+[ \t]+US[A-Za-z0-9-]*[0-9]+:/) {
        head = $0
        sub(/^#+[ \t]+/, "", head)
        id = head
        sub(/:.*$/, "", id)
        title = head
        sub(/^[^:]*:[ \t]*/, "", title)

        if (kind == "story") {
            if (!(FILENAME in st_n)) sf_order[++sf_count] = FILENAME
            st_n[FILENAME]++
            st_id[FILENAME, st_n[FILENAME]] = id
            st_title[FILENAME, st_n[FILENAME]] = title
        } else {
            if (!(FILENAME in df_n)) df_order[++df_count] = FILENAME
            df_n[FILENAME]++
        }
    }
    next
}

kind == "bd" || kind == "bd_done" {
    if (!(FILENAME in bd_seen)) {
        bd_seen[FILENAME] = 1
        bd_order[++bd_count] = FILENAME
        bd_arch[FILENAME] = (kind == "bd_done")
    }

    if (!h1_seen && $0 ~ /^#[ \t]+/) {
        h1_seen = 1
        head = $0
        sub(/^#[ \t]+/, "", head)
        split(head, part, /[ \t]+/)
        cand = part[1]
        sub(/:$/, "", cand)
        if (cand ~ /^US[A-Za-z0-9-]*[0-9]+$/) {
            rest = head
            sub(/^[^ \t]+[ \t]*/, "", rest)
            bd_key[FILENAME] = norm(cand) SUBSEP norm(rest)
        }
    }

    # Only when the sidecar said nothing about this file. A breakdown written since
    # progress moved out of the markdown has no checklist to count, and one written
    # before it should not be counted twice.
    if (!(FILENAME in bd_side) && $0 ~ /^- \[[ x]\][ \t]+Task[ \t]/) {
        bd_total[FILENAME]++
        if ($0 ~ /^- \[x\]/) bd_done[FILENAME]++
    }

    if (!(FILENAME in bd_ref) && match($0, /user-stories\/[A-Za-z0-9._\/-]+\.md/)) {
        bd_ref[FILENAME] = substr($0, RSTART, RLENGTH)
    }
    next
}

END {
    # Index breakdowns by story key. An archived breakdown wins over an in-flight
    # one for the same story, so a re-opened breakdown cannot un-deliver a story.
    for (i = 1; i <= bd_count; i++) {
        f = bd_order[i]
        if (f in bd_key) {
            k = bd_key[f]
            if (!(k in by_key) || bd_arch[f]) by_key[k] = f
        } else if (f in bd_ref) {
            file_bd[bd_ref[f]] = file_bd[bd_ref[f]] (file_bd[bd_ref[f]] ? ", " : "") f
        } else {
            orphan[++orphan_count] = f
        }
    }

    for (i = 1; i <= sf_count; i++) {
        sf = sf_order[i]
        for (j = 1; j <= st_n[sf]; j++) {
            k = norm(st_id[sf, j]) SUBSEP norm(st_title[sf, j])
            state = "pending"
            note = ""
            if (k in by_key) {
                f = by_key[k]
                matched[f] = 1
                if (bd_arch[f]) {
                    state = "delivered"
                    delivered[sf]++
                } else {
                    state = "in flight"
                    inflight[sf]++
                    note = f " (" bd_done[f] + 0 "/" bd_total[f] + 0 " tasks)"
                }
            }
            st_state[sf, j] = state
            st_note[sf, j] = note
        }
        total_stories += st_n[sf]
        total_delivered += delivered[sf]
    }

    if (mode == "tasks") { report_tasks(); exit }
    if (mode == "stories") { report_stories(); exit }
    report_summary()
}

function report_summary(   i, j, sf, fb, n, a, extra) {
    printf "User story progress   (derived from user-stories/ and tasks/)\n\n"

    printf "%-42s %-19s %s\n", "STORY FILE", "DELIVERED", "IN FLIGHT"
    for (i = 1; i <= sf_count; i++) {
        sf = sf_order[i]
        extra = ""
        if (inflight[sf]) extra = inflight[sf] " story breakdown" (inflight[sf] > 1 ? "s" : "")
        if (sf in file_bd) {
            n = split(file_bd[sf], a, ", ")
            for (j = 1; j <= n; j++) {
                matched[a[j]] = 1
                extra = extra (extra ? "; " : "") a[j] " (" bd_done[a[j]] + 0 "/" bd_total[a[j]] + 0 " tasks)"
            }
        }
        printf "%-42s %3d/%-3d %s   %s\n", label(sf), delivered[sf] + 0, st_n[sf], \
               bar(delivered[sf] + 0, st_n[sf]), extra
    }

    printf "\n%-42s %3d/%-3d %s\n", "TOTAL", total_delivered + 0, total_stories, \
           bar(total_delivered + 0, total_stories)

    if (df_count) {
        printf "\nFinished in full (user-stories/completed/)\n"
        for (i = 1; i <= df_count; i++) {
            printf "  %-32s %3d stories\n", base(df_order[i]), df_n[df_order[i]]
        }
    }

    report_unmatched()
}

function report_stories(   i, j, sf, mark) {
    for (i = 1; i <= sf_count; i++) {
        sf = sf_order[i]
        printf "%s   %d/%d delivered\n", label(sf), delivered[sf] + 0, st_n[sf]
        for (j = 1; j <= st_n[sf]; j++) {
            if (st_state[sf, j] == "delivered") mark = tick
            else if (st_state[sf, j] == "in flight") mark = flight
            else mark = blank
            printf "  %s %s: %s%s\n", mark, st_id[sf, j], st_title[sf, j], \
                   st_note[sf, j] ? "   <- " st_note[sf, j] : ""
        }
        printf "\n"
    }
    printf "%s delivered (breakdown archived)   %s in flight   %s not started\n", tick, flight, blank
}

function report_tasks(   i, j, f, any, line, mark) {
    printf "Task breakdowns in flight (tasks/*.md)\n\n"
    for (i = 1; i <= bd_count; i++) {
        f = bd_order[i]
        if (bd_arch[f]) continue
        any = 1
        printf "%s   %d/%d tasks\n", f, bd_done[f] + 0, bd_total[f] + 0
        if (f in bd_ref) printf "  story file: %s\n", bd_ref[f]
        if (f in bd_side) {
            for (j = 1; j <= tk_n[f]; j++)
                printf "  %s Task %s: %s\n", (tk_done[f, j] ? tick : blank), tk_num[f, j], tk_title[f, j]
            continue
        }
        while ((getline line < f) > 0) {
            if (line ~ /^- \[[ x]\][ \t]+Task[ \t]/) {
                mark = (line ~ /^- \[x\]/) ? tick : blank
                sub(/^- \[[ x]\][ \t]*/, "", line)
                printf "  %s %s\n", mark, line
            }
        }
        close(f)
        printf "\n"
    }
    if (!any) printf "(none)\n"
}

function report_unmatched(   i, f, shown) {
    for (i = 1; i <= bd_count; i++) {
        f = bd_order[i]
        if (bd_arch[f] || (f in matched)) continue
        if (!shown) { printf "\nBreakdowns in tasks/ not joined to a listed story\n"; shown = 1 }
        printf "  %-52s %d/%d tasks\n", f, bd_done[f] + 0, bd_total[f] + 0
    }
}
