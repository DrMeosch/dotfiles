#!/usr/bin/env bash
# Appends the Changelog lines of a merged pull request as one comment on the
# running "Changelog" issue, creating (and pinning) that issue when missing.
# Skips pull requests whose section is empty or "none". Reads the pull request
# from env: PR_BODY PR_NUMBER PR_URL PR_TITLE MERGE_SHA MERGED_AT GH_REPO GH_TOKEN.
set -euo pipefail

TITLE="Changelog"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

section="$("$here/changelog-section.sh")"
if [ -z "$section" ] || [ "$(printf '%s' "$section" | tr -d '[:space:][:punct:]' | tr '[:upper:]' '[:lower:]')" = "none" ]; then
  echo "skip: PR #${PR_NUMBER} has no changelog entries"; exit 0
fi

commit_url="${GITHUB_SERVER_URL:-https://github.com}/${GH_REPO}/commit/${MERGE_SHA}"
marker="<!-- changelog-feed pr=${PR_NUMBER} -->"
# Defuse @mentions so that the feed does not ping anyone.
zwsp="$(printf '\342\200\213')"
section="${section//@/@$zwsp}"
title="${PR_TITLE//@/@$zwsp}"
comment="$(printf '%s\n**%s** - [#%s](%s) %s\n\nMerge commit: [`%s`](%s)\n\n%s\n' \
  "$marker" "${MERGED_AT%%T*}" "$PR_NUMBER" "$PR_URL" "$title" "${MERGE_SHA:0:7}" "$commit_url" "$section")"

# Only the issue created by the Actions bot counts: anyone can open one titled "Changelog".
number="$(gh issue list --state all --author 'github-actions[bot]' --limit 100 --json number,title \
  --jq "[.[] | select(.title == \"$TITLE\")] | min_by(.number) | .number // empty")"

if [ -z "$number" ]; then
  url="$(gh issue create --title "$TITLE" --body "Running list of the changes merged into this repository. One comment per merged pull request, added automatically.")"
  number="${url##*/}"
  echo "created issue #$number"
  node_id="$(gh issue view "$number" --json id --jq .id)"
  gh api graphql -f query='mutation($id: ID!) { pinIssue(input: {issueId: $id}) { issue { number } } }' \
    -f id="$node_id" >/dev/null || echo "warning: could not pin issue #$number" >&2
elif gh api --paginate "repos/${GH_REPO}/issues/${number}/comments" --jq '.[].body' | grep -qxF -- "$marker"; then
  echo "skip: PR #${PR_NUMBER} is already in issue #$number"; exit 0
fi

gh issue comment "$number" --body "$comment"
echo "ok: appended PR #$PR_NUMBER to issue #$number"
