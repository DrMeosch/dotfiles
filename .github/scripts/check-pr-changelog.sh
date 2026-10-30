#!/usr/bin/env bash
# Fails unless the pull request body (env PR_BODY) has a non-empty "## Changelog"
# section; "none" is a valid entry. Pull requests by bots (env PR_AUTHOR) are exempt.
set -euo pipefail

author="${PR_AUTHOR:-}"
case "$author" in
  renovate\[bot\]|dependabot\[bot\]|github-actions\[bot\]|app/renovate|app/dependabot|app/github-actions)
    echo "ok: $author is exempt from the changelog rule"; exit 0 ;;
esac

section="$("$(dirname "${BASH_SOURCE[0]}")/changelog-section.sh")"

if [ -z "$section" ]; then
  echo "error: the PR body needs a non-empty '## Changelog' section." >&2
  echo "Add one or two user-facing lines (Added/Changed/Fixed/Removed/Security), or 'none' for internal-only changes." >&2
  exit 1
fi
echo "ok: changelog section found"
