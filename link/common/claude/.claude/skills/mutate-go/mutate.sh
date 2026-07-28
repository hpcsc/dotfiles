#!/usr/bin/env bash
# mutate-go — mutation-test one Go file with gremlins and report what survived.
#
# Runs gremlins on the file's package, narrowed to just that file (siblings are
# excluded from mutation, not from compilation), then prints the survivors with
# their source lines so each one can be judged directly.
#
# Statuses are grouped by the action they call for:
#   SURVIVED     the mutant ran and no test failed — an unasserted behaviour
#   UNREACHABLE  no test executes the line, so no mutant could even be tried
#   INCONCLUSIVE timed out / not viable — no verdict, never a finding
#
# Usage:
#   mutate.sh FILE.go [options]
#
#   --tags a,b              build tags the test suite needs (e.g. --tags unit)
#   --package               mutate every file in the package, not just FILE
#   --all-mutators          also enable gremlins' opt-in mutators (slower, wider)
#   --timeout-coefficient N pass through to gremlins; disables the auto-retry
#   --no-retry              don't re-run even if the results are timeout-dominated
#   --max-shown N           source excerpts per section (default 25)
#   --json PATH             keep the raw gremlins report here
#
# FILE may be either the source file or its _test.go counterpart; a test file is
# mapped to the code it covers.
#
# Gremlins derives each mutant's test timeout from how long the coverage run
# took, so a package whose tests finish in milliseconds reports everything as
# TIMED OUT — results that look catastrophic but mean nothing. When that shows
# up, this re-runs once with a much larger coefficient and says so.

set -uo pipefail

# Empirically enough to rescue a sub-second suite: the timeout is the coverage
# duration times this, and a mutant still has to compile before it can run.
retry_coefficient=150

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
  exit "${1:-0}"
}

file="" whole_pkg=0 all_mutators=0 coefficient="" retry=1 max_shown=25 json_out="" tags=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --tags) [[ $# -ge 2 ]] || die "--tags needs a value"; tags="$2"; shift ;;
    --package) whole_pkg=1 ;;
    --all-mutators) all_mutators=1 ;;
    --timeout-coefficient) [[ $# -ge 2 ]] || die "--timeout-coefficient needs a value"
                           coefficient="$2"; retry=0; shift ;;
    --no-retry) retry=0 ;;
    --max-shown) [[ $# -ge 2 ]] || die "--max-shown needs a value"; max_shown="$2"; shift ;;
    --json) [[ $# -ge 2 ]] || die "--json needs a path"; json_out="$2"; shift ;;
    -*) die "unknown option: $1" ;;
    *) [[ -z "$file" ]] || die "one file at a time (got '$file' and '$1')"; file="$1" ;;
  esac
  shift
done

[[ -n "$file" ]] || usage 1
[[ -f "$file" ]] || die "no such file: $file"
[[ "$file" == *.go ]] || die "not a Go file: $file"

# Asking "are these tests any good?" naturally points at the test file, so map it
# to the code it covers rather than refusing.
if [[ "$file" == *_test.go ]]; then
  under_test="${file%_test.go}.go"
  [[ -f "$under_test" ]] ||
    die "$file is a test file and $under_test does not exist — name the file to mutate"
  printf 'note: %s is a test file; mutating %s instead\n' "$file" "$under_test"
  file="$under_test"
fi
command -v gremlins >/dev/null ||
  die "gremlins not found on PATH (mise use -g github:go-gremlins/gremlins, or go install github.com/go-gremlins/gremlins/cmd/gremlins@latest)"
for tool in go jq awk; do
  command -v "$tool" >/dev/null || die "$tool not found on PATH"
done

base=$(basename "$file")
dir=$(cd "$(dirname "$file")" && pwd)

gomod=$(cd "$dir" && go env GOMOD 2>/dev/null)
[[ -n "$gomod" && "$gomod" != /dev/null ]] || die "not inside a Go module: $file"
root=$(dirname "$gomod")
rel="${dir#"$root"}"
rel="${rel#/}"
if [[ -n "$rel" ]]; then pkg="./$rel"; else pkg="."; fi

# A build-tagged suite is the trap this guards: `go test` on a package whose
# every test file is excluded prints "[no test files]" and exits 0, so gremlins
# gathers empty coverage, marks every mutant NOT COVERED and also exits 0. That
# looks like a finished run and means nothing. Catch it before spending minutes.
buildable_tests=$(cd "$dir" &&
  go list -tags "$tags" -f '{{len .TestGoFiles}} {{len .XTestGoFiles}}' . 2>/dev/null |
  awk '{print $1 + $2}')
if [[ "${buildable_tests:-0}" == 0 ]] && compgen -G "$dir/*_test.go" >/dev/null; then
  found=$(grep -hE '^//go:build' "$dir"/*_test.go 2>/dev/null |
    sed 's|^//go:build||' | tr '()|&!' ' ' | tr ' ' '\n' |
    grep -vE '^$|^(unix|linux|darwin|windows|js|wasm|amd64|arm64|cgo|race|go[0-9.]+)$' |
    sort -u | paste -sd, -)
  msg="$pkg has _test.go files but the build excludes all of them, so there is no
suite to mutate against."
  if [[ -n "$found" ]]; then
    msg="$msg The build tags in those files are: $found
Re-run with:  $0 $file --tags $found"
  else
    msg="$msg Check the files' build constraints and pass them with --tags."
  fi
  die "$msg"
fi

work=$(mktemp -d)
log="$work/gremlins.log"
report="$work/report.json"
trap 'rm -rf "$work"' EXIT

regex_escape() { printf '%s' "$1" | sed 's/[][^$.|?*+(){}\]/\\&/g'; }

# gremlins matches --exclude-files against the base name, so narrowing to one
# file means naming every sibling.
exclude=()
if ((whole_pkg == 0)); then
  for sibling in "$dir"/*.go; do
    name=$(basename "$sibling")
    [[ "$name" == "$base" || "$name" == *_test.go ]] && continue
    exclude+=(-E "^$(regex_escape "$name")\$")
  done
fi

mutators=()
if ((all_mutators == 1)); then
  mutators=(--invert-assignments --invert-bitwise --invert-bwassign
            --invert-logical --invert-loopctrl --remove-self-assignments)
fi

run_gremlins() { # $1 = coefficient or empty
  local args=(unleash -o "$report")
  [[ -n "$1" ]] && args+=(--timeout-coefficient "$1")
  [[ -n "$tags" ]] && args+=(--tags "$tags")
  args+=(${mutators[@]+"${mutators[@]}"} ${exclude[@]+"${exclude[@]}"} "$pkg")
  (cd "$root" && gremlins "${args[@]}") >"$log" 2>&1
}

# Selects the mutations this run is about: one file, or all of them.
jq_scope() {
  if ((whole_pkg == 1)); then
    printf '.files[]'
  else
    printf '.files[] | select(.file_name == $f)'
  fi
}

count() { # status
  jq -r --arg f "$base" --arg s "$1" \
    "[$(jq_scope) | .mutations[] | select(.status == \$s)] | length" "$report"
}

mutants_total() {
  jq -r --arg f "$base" "[$(jq_scope) | .mutations[]] | length" "$report"
}

list_status() { # status -> file<TAB>line<TAB>col<TAB>type, grouped by position
  jq -r --arg f "$base" --arg s "$1" \
    "$(jq_scope) | .file_name as \$fn | .mutations[] | select(.status == \$s)
     | [\$fn, (.line|tostring), (.column|tostring), .type] | @tsv" "$report" |
    sort -t"$(printf '\t')" -k1,1 -k2,2n -k3,3n
}

printf 'Mutation testing %s\n' "$file"
printf '  package %s   module %s   %s\n' "$pkg" \
  "$(cd "$root" && go list -m 2>/dev/null || echo '?')" "$(gremlins --version 2>/dev/null)"
if ((whole_pkg == 0)); then
  printf '  scope: this file only (%d sibling file(s) excluded from mutation)\n' \
    "$((${#exclude[@]} / 2))"
else
  printf '  scope: the whole package\n'
fi
((all_mutators == 1)) && printf '  mutators: gremlins defaults + all opt-in ones\n'
[[ -n "$tags" ]] && printf '  build tags: %s\n' "$tags"
printf '  running the test suite once per mutant, this takes a while...\n\n'

if ! run_gremlins "$coefficient"; then
  if grep -q 'failed to gather coverage' "$log"; then
    echo "error: the package's own tests do not pass, so there is no baseline to" >&2
    echo "mutate against. Fix the failing tests first — mutation results are only" >&2
    echo "meaningful when the suite is green. go test output:" >&2
    echo >&2
    grep -E '^(---|FAIL|ok|\s+[a-z_]+_test\.go:)' "$log" | head -20 >&2
    exit 1
  fi
  echo "gremlins failed:" >&2
  cat "$log" >&2
  exit 1
fi
no_mutants() {
  printf 'No mutants found in %s.\n\n' "$base"
  echo "Nothing in the analysed code matches the enabled mutators — no"
  echo "conditionals, arithmetic or increments. Either this file holds no"
  echo "decision logic worth mutating, or the logic lives elsewhere. Widen with"
  echo "--all-mutators if you expected bitwise, logical or loop-control mutants."
  exit 0
}

# With nothing to mutate, gremlins writes no report at all and still exits 0.
if [[ ! -s "$report" ]] || ! jq -e . "$report" >/dev/null 2>&1; then
  grep -q 'No results to report' "$log" && no_mutants
  echo "gremlins produced no readable report:" >&2
  cat "$log" >&2
  exit 1
fi

killed=$(count KILLED) lived=$(count LIVED)
uncovered=$(count "NOT COVERED") timedout=$(count "TIMED OUT")
unviable=$(count "NOT VIABLE") skipped=$(count SKIPPED)
total=$(mutants_total)
retried=0

# A timeout-dominated run says nothing about the tests, so try once more with a
# timeout that can accommodate a compile.
if ((retry == 1 && timedout > 0 && timedout * 4 >= killed + lived + timedout)); then
  printf 'most mutants timed out (%d of %d) — the suite is too fast for gremlins to\n' \
    "$timedout" "$((killed + lived + timedout))"
  printf 'time reliably; re-running with --timeout-coefficient %d\n\n' "$retry_coefficient"
  cp "$report" "$work/first.json"
  if run_gremlins "$retry_coefficient" && jq -e . "$report" >/dev/null 2>&1; then
    retried=1
    killed=$(count KILLED) lived=$(count LIVED)
    uncovered=$(count "NOT COVERED") timedout=$(count "TIMED OUT")
    unviable=$(count "NOT VIABLE") skipped=$(count SKIPPED)
    total=$(mutants_total)
  else
    cp "$work/first.json" "$report"
    printf 'the re-run failed; reporting the first run\n\n'
  fi
fi

((total == 0)) && no_mutants

decided=$((killed + lived))
printf '%d killed   %d survived   %d unreachable   %d inconclusive\n' \
  "$killed" "$lived" "$uncovered" "$((timedout + unviable + skipped))"

# Backstop for the empty-baseline trap the --tags check upstream cannot see: no
# mutant reached a test, so there is no result here to read either way.
if ((decided == 0 && uncovered > 0)); then
  printf '\nNo mutant reached a single test, so this run says nothing about the tests.\n'
  printf 'Either the suite does not exercise %s at all, or it did not build (build\n' "$base"
  printf 'tags, a skipped package). Confirm the tests actually run against this file\n'
  printf 'before reading anything below as a finding.\n\n'
fi
if ((decided > 0)); then
  awk -v k="$killed" -v d="$decided" -v t="$total" -v dec="$decided" 'BEGIN{
    printf "  efficacy %.0f%% of decided mutants   coverage %.0f%% of all %d mutants\n", 100*k/d, 100*dec/t, t
  }'
fi
((retried == 1)) && printf '  (after re-running with --timeout-coefficient %d)\n' "$retry_coefficient"
echo

gloss() {
  case "$1" in
    CONDITIONALS_BOUNDARY)   echo "boundary moved (> <-> >=, < <-> <=) — pin the edge value itself" ;;
    CONDITIONALS_NEGATION)   echo "condition negated (== <-> !=, > <-> <=) — assert both outcomes" ;;
    ARITHMETIC_BASE)         echo "operator swapped (+ <-> -, * <-> /) — assert the computed value" ;;
    INCREMENT_DECREMENT)     echo "++ <-> -- — assert the value after the step, not just that it changed" ;;
    INVERT_NEGATIVES)        echo "sign dropped (-x -> x) — cover a negative input" ;;
    INVERT_LOGICAL)          echo "&& <-> || — cover a case where only one side holds" ;;
    INVERT_ASSIGNMENTS)      echo "compound assignment inverted (+= <-> -=) — assert accumulated state" ;;
    INVERT_BITWISE)          echo "bitwise operator swapped (& <-> |) — assert the resulting bits" ;;
    INVERT_BWASSIGN)         echo "bitwise assignment swapped (&= <-> |=) — assert the resulting bits" ;;
    INVERT_LOOPCTRL)         echo "break <-> continue — assert what the loop produces, not that it ends" ;;
    REMOVE_SELF_ASSIGNMENTS) echo "self-assignment dropped — assert the updated value" ;;
  esac
}

show_source() { # path line col
  awk -v ln="$2" -v col="$3" '
    function spaces(k, s, j) { s = ""; for (j = 0; j < k; j++) s = s " "; return s }
    NR == ln {
      out = ""; pad = ""
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        width = (c == "\t") ? 4 : 1
        out = out ((c == "\t") ? spaces(4) : c)
        if (i < col) pad = pad spaces(width)
      }
      printf "      %5d | %s\n", ln, out
      printf "            | %s^\n", pad
      exit
    }
  ' "$1"
}

# Groups consecutive rows at the same position and prints one block each.
print_section() { # status, heading, with_source(0|1)
  local status="$1" heading="$2" with_source="$3"
  local rows; rows=$(list_status "$status")
  [[ -z "$rows" ]] && return 0

  local shown=0 groups=0 last="" types="" gfile="" gline="" gcol=""
  flush() {
    [[ -z "$last" ]] && return 0
    groups=$((groups + 1))
    if ((shown < max_shown)); then
      shown=$((shown + 1))
      printf '  %s:%s:%s  %s\n' "$gfile" "$gline" "$gcol" "$types"
      ((with_source >= 1)) && show_source "$dir/$gfile" "$gline" "$gcol"
      if ((with_source == 1)); then
        local t
        for t in $types_list; do
          local g; g=$(gloss "$t")
          [[ -n "$g" ]] && printf '            check: %s\n' "$g"
        done
      fi
      echo
    fi
  }

  printf '%s\n' "$heading"
  local f l c t key
  while IFS=$'\t' read -r f l c t; do
    key="$f:$l:$c"
    if [[ "$key" != "$last" ]]; then
      flush
      last="$key" gfile="$f" gline="$l" gcol="$c" types="$t" types_list="$t"
    else
      types="$types, $t"
      case " $types_list " in *" $t "*) ;; *) types_list="$types_list $t" ;; esac
    fi
  done <<<"$rows"
  flush

  if ((groups > shown)); then
    printf '  ... and %d more position(s) not shown (--max-shown %d)\n\n' \
      "$((groups - shown))" "$max_shown"
  fi
}

((lived > 0)) && print_section LIVED \
  "SURVIVED ($lived) — the tests did not notice these changes:" 1

# Go's cover tool instruments a case *body* (from the colon onward) and never the
# case condition, so a mutation position inside `case <expr>:` falls outside every
# coverage block. Gremlins then reports it NOT COVERED whether the case is
# exhaustively tested or never tested — the two are indistinguishable here.
count_case_expressions() {
  local f l c t n=0 src
  while IFS=$'\t' read -r f l c t; do
    [[ -z "${l:-}" ]] && continue
    src=$(awk -v ln="$l" 'NR == ln { print; exit }' "$dir/$f")
    [[ "$src" =~ ^[[:space:]]*case[[:space:]] ]] && n=$((n + 1))
  done < <(list_status "NOT COVERED" | cut -f1-3 | sort -u | awk -F'\t' '{print $1"\t"$2"\t"$3"\t"}')
  printf '%d' "$n"
}

if ((uncovered > 0)); then
  print_section "NOT COVERED" \
    "UNREACHABLE ($uncovered) — no test runs these lines, so nothing could be tested:" 2
  case_exprs=$(count_case_expressions)
  if ((case_exprs > 0)); then
    printf '  %d of these sit on a `case` condition. Go instruments only the case body,\n' "$case_exprs"
    printf '  never the condition, so gremlins cannot see coverage for those positions and\n'
    printf '  reports them unreachable whether they are exhaustively tested or never tested\n'
    printf '  at all. Do not treat them as gaps on this output alone — check the tests, or\n'
    printf '  the block hit-counts in `go test -coverprofile`, for each one.\n\n'
  fi
fi

if ((timedout + unviable + skipped > 0)); then
  printf 'INCONCLUSIVE — no verdict, do not read these as either pass or fail:\n'
  ((timedout > 0))  && printf '  %d timed out\n' "$timedout"
  ((unviable > 0))  && printf '  %d not viable (the mutant does not compile)\n' "$unviable"
  ((skipped > 0))   && printf '  %d skipped\n' "$skipped"
  if ((timedout > 0 && timedout * 4 >= killed + lived + timedout)); then
    printf '  Timeouts dominate, so the numbers above are not trustworthy. Gremlins\n'
    printf '  sizes each timeout from the coverage run, and this suite is too fast\n'
    printf '  for that to work. Re-run with a larger --timeout-coefficient.\n'
  fi
  echo
fi

if ((lived == 0 && uncovered == 0)); then
  printf 'Nothing survived and nothing was unreachable'
  ((timedout > 0)) && printf ' among the mutants that got a verdict'
  printf '.\n'
fi

if [[ -n "$json_out" ]]; then
  cp "$report" "$json_out" && printf 'Raw report: %s\n' "$json_out"
else
  tmpdir="${TMPDIR:-/tmp}"
  keep="${tmpdir%/}/mutate-go-$base-report.json"
  cp "$report" "$keep" && printf 'Raw report: %s\n' "$keep"
fi
