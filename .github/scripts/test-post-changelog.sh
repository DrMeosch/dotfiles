#!/usr/bin/env bash
# Checks post-changelog.sh against a stub gh that records its calls.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/post-changelog.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0

cat > "$tmp/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
case "$1 $2" in
  "issue list")   printf '%s' "${STUB_EXISTING:-}" ;;
  "issue create") echo "https://github.com/o/r/issues/7" ;;
  "issue view")   echo "NODE" ;;
esac
STUB
chmod +x "$tmp/gh"

# run <existing-issue-number|""> <body>; leaves the stub's calls in $tmp/log
run() {
  : > "$tmp/log"
  PATH="$tmp:$PATH" STUB_LOG="$tmp/log" STUB_EXISTING="$1" PR_BODY="$2" PR_NUMBER=5 \
    PR_URL=https://github.com/o/r/pull/5 PR_TITLE="A title" MERGE_SHA=0123456789abcdef \
    MERGED_AT=2026-10-30T12:00:00Z GH_REPO=o/r "$SCRIPT" >/dev/null 2>&1
}
check() { if [ "$2" = ok ]; then echo "ok:   $1"; else echo "FAIL: $1"; fail=1; fi; }
logged() { grep -q -- "$1" "$tmp/log" && echo ok || echo no; }

run "" $'## Changelog\nFixed: the thing.'
check "creates the issue when missing" "$(logged 'issue create --title Changelog')"
check "pins the new issue" "$(logged 'pinIssue')"
check "comments on the new issue" "$(logged 'issue comment 7 ')"
check "comment has date, PR and merge commit links" \
  "$(tr '\n' ' ' < "$tmp/log" | grep -q '2026-10-30.*pull/5.*commit/0123456789abcdef.*Fixed: the thing' && echo ok || echo no)"

run 3 $'## Changelog\n- Added: x'
check "reuses the existing issue" "$(logged 'issue comment 3 ')"
check "does not create a second issue" "$([ "$(logged 'issue create')" = no ] && echo ok || echo no)"

for body in $'## Changelog\nnone' $'## Changelog\n- None\n' "" $'## Summary\nx'; do
  run 3 "$body"
  check "skips body: ${body//$'\n'/|}" "$([ ! -s "$tmp/log" ] && echo ok || echo no)"
done

exit "$fail"
