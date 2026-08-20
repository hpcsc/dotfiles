#!/usr/bin/env bash
# Fetch everything a risk assessment needs, into a working directory.
# Usage: pr_fetch.sh <pr-number|#N|owner/repo#N|github-url|--branch> [outdir]
#
# --branch assesses the current local branch against the repo's default branch,
# for use before a PR exists. It writes the same file layout with a stub meta.json.
set -euo pipefail

REF="${1:?usage: pr_fetch.sh <pr-number|owner/repo#N|url|--branch> [outdir]}"
OUT="${2:-}"

if [ "$REF" = "--branch" ] || [ "$REF" = "-b" ]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || basename "$(git rev-parse --show-toplevel)")"
  BASE="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
  BASE="${BASE:-master}"
  HEAD_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  git fetch origin "$BASE" --quiet 2>/dev/null || true
  BASE_REF="origin/$BASE"
  git rev-parse --verify --quiet "$BASE_REF" >/dev/null || BASE_REF="$BASE"
  if ! MERGE_BASE="$(git merge-base "$BASE_REF" HEAD 2>/dev/null)"; then
    echo "no merge base between HEAD and $BASE_REF -- is the default branch named something else?" >&2
    exit 2
  fi
  if [ "$MERGE_BASE" = "$(git rev-parse HEAD)" ]; then
    echo "HEAD is at the merge base with $BASE_REF: nothing to assess" >&2
    exit 3
  fi
  OUT="${OUT:-${TMPDIR:-/tmp}/merge-risk/${REPO//\//-}-branch-${HEAD_BRANCH//\//-}}"
  mkdir -p "$OUT"

  git diff "$MERGE_BASE"...HEAD > "$OUT/diff.patch"
  git log --format='%H%x09%s' "$MERGE_BASE"..HEAD > "$OUT/commits.tsv"
  jq -n --arg t "local branch $HEAD_BRANCH" --arg b "$BASE" --arg h "$HEAD_BRANCH" \
        --arg sha "$(git rev-parse HEAD)" --arg mb "$MERGE_BASE" \
        --argjson files "$(git diff --name-only "$MERGE_BASE"...HEAD | jq -R . | jq -s 'map({path: .})')" \
    '{number: null, title: $t, body: "", baseRefName: $b, headRefName: $h, headRefOid: $sha,
      mergeBase: $mb, files: $files, changedFiles: ($files|length), local: true}' > "$OUT/meta.json"
  echo '[]' > "$OUT/review_comments.json"
  echo '[]' > "$OUT/issue_comments.json"

  printf 'repo=%s\nnumber=local\noutdir=%s\nbase=%s\nhead=%s\nmergeBase=%s\nfiles=%s\ncommits=%s\n' \
    "$REPO" "$OUT" "$BASE" "$HEAD_BRANCH" "$MERGE_BASE" \
    "$(git diff --name-only "$MERGE_BASE"...HEAD | wc -l | tr -d ' ')" \
    "$(wc -l < "$OUT/commits.tsv" | tr -d ' ')"
  exit 0
fi

REPO=""
NUM=""
case "$REF" in
  https://github.com/*)
    trimmed="${REF#https://github.com/}"
    REPO="$(printf '%s' "$trimmed" | cut -d/ -f1-2)"
    NUM="$(printf '%s' "$trimmed" | sed -E 's#.*/pull/([0-9]+).*#\1#')"
    ;;
  */*\#*)
    REPO="${REF%%#*}"
    NUM="${REF##*#}"
    ;;
  *)
    NUM="$(printf '%s' "$REF" | tr -cd '0-9')"
    ;;
esac

if [ -z "$NUM" ]; then
  echo "could not parse a PR number from: $REF" >&2
  exit 2
fi
[ -n "$REPO" ] || REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
OUT="${OUT:-${TMPDIR:-/tmp}/merge-risk/${REPO//\//-}-${NUM}}"
mkdir -p "$OUT"

gh pr view "$NUM" --repo "$REPO" --json \
  number,title,body,url,state,isDraft,mergeable,author,baseRefName,headRefName,headRefOid,additions,deletions,changedFiles,files,commits,labels,reviews,statusCheckRollup \
  > "$OUT/meta.json"

# combined base...head diff: correct line numbers for scanning
gh pr diff "$NUM" --repo "$REPO" > "$OUT/diff.patch"
# per-commit patches: only for reading the narrative, never for line numbers
gh pr diff "$NUM" --repo "$REPO" --patch > "$OUT/commits.patch" 2>/dev/null || true
gh api "repos/$REPO/pulls/$NUM/comments" --paginate > "$OUT/review_comments.json" 2>/dev/null || echo '[]' > "$OUT/review_comments.json"
gh api "repos/$REPO/issues/$NUM/comments" --paginate > "$OUT/issue_comments.json" 2>/dev/null || echo '[]' > "$OUT/issue_comments.json"
jq -r '.commits[]? | "\(.oid)\t\(.messageHeadline)"' "$OUT/meta.json" > "$OUT/commits.tsv" 2>/dev/null || true

printf 'repo=%s\nnumber=%s\noutdir=%s\n' "$REPO" "$NUM" "$OUT"
jq -r '"title=\(.title)\nauthor=\(.author.login)\nbase=\(.baseRefName)\nhead=\(.headRefName)\nheadSha=\(.headRefOid)\nstate=\(.state)\ndraft=\(.isDraft)\nmergeable=\(.mergeable)\nfiles=\(.changedFiles)\nadditions=\(.additions)\ndeletions=\(.deletions)\ncommits=\(.commits|length)\nlabels=\([.labels[]?.name]|join(","))"' "$OUT/meta.json"
jq -r '"existingReviewComments=\(length)"' "$OUT/review_comments.json"
jq -r '"failingChecks=\([.statusCheckRollup[]? | select(.conclusion=="FAILURE" or .state=="FAILURE") | .name // .context] | join(","))"' "$OUT/meta.json"
