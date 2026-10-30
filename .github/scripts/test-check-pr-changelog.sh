#!/usr/bin/env bash
# Checks check-pr-changelog.sh against fixture PR bodies.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/check-pr-changelog.sh"
fail=0

# expect <pass|fail> <author> <body> <name>
expect() {
  local want="$1" author="$2" body="$3" name="$4" got=fail
  PR_AUTHOR="$author" PR_BODY="$body" "$SCRIPT" >/dev/null 2>&1 && got=pass
  if [ "$got" = "$want" ]; then echo "ok:   $name"; else echo "FAIL: $name (wanted $want)"; fail=1; fi
}

expect pass human $'## Changelog\n\nFixed: the thing.' "entry"
expect pass human $'## Summary\n\nx\n\n## Changelog\nnone\n\n## Notes\ny' "none, followed by another section"
expect pass human $'## Changelog\r\nnone\r\n' "CRLF body"
expect fail human "" "empty body"
expect fail human $'## Summary\n\nno changelog here' "no section"
expect fail human $'## Changelog\n\n## Notes\ntext' "empty section before another heading"
expect fail human $'## Changelog\n\n' "empty section at the end"
expect fail human $'## Changelog\n<!-- Write none for internal-only changes. -->\n' "template comment only"
expect fail human $'## Changelog\n<!-- multi\nline -->\n' "multi-line comment only"
expect pass human $'## Changelog\n<!-- note -->\nAdded: x' "comment plus entry"
expect fail human $'## Changelog\n- Added: \n' "type prefix without text"
expect fail human $'## Changelog\n-\nFixed:' "bare bullet and prefix"
expect pass human $'## Changelog\n- Added: a thing' "bulleted entry"
expect fail human "$(cat "$(dirname "$SCRIPT")/../pull_request_template.md")" "untouched PR template"
expect pass 'renovate[bot]' "" "renovate is exempt"
expect pass 'dependabot[bot]' "" "dependabot is exempt"
expect pass 'github-actions[bot]' "" "github-actions is exempt"
expect fail 'someone-else' "" "other authors are not exempt"

exit "$fail"
