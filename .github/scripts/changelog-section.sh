#!/usr/bin/env bash
# Prints the entries of the "## Changelog" section of the pull request body in
# env PR_BODY: the text under the first such heading up to the next heading,
# minus comments, blank lines, bare bullets, type prefixes without text and CRs.
set -euo pipefail

printf '%s\n' "${PR_BODY:-}" | tr -d '\r' | awk '
  /^##[[:space:]]+Changelog[[:space:]]*$/ && !seen { seen = 1; on = 1; next }
  on && /^#/ { exit }
  on { print }
' | sed -e ':a' -e 's/<!--[^>]*-->//g' -e '/<!--/{N;ba' -e '}' \
  | grep -Eiv '^[[:space:]]*([-*][[:space:]]*)?((added|changed|fixed|removed|security|deprecated)[[:space:]]*:?[[:space:]]*)?$' || true
