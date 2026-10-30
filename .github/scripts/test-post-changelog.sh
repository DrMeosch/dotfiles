#!/usr/bin/env bash
# Checks post-changelog.sh against a stateful stub gh (issues and comments live in $tmp/state).
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/post-changelog.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0

# State: $tmp/issue holds the bot's issue number (absent until created), $tmp/comments the
# posted bodies, $tmp/log every call. An issue 3 by someone else always exists, as a trap.
cat > "$tmp/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
case "$1 $2" in
  "issue list")
    case "$*" in *"--author github-actions[bot]"*) ;; *) echo 3; exit 0 ;; esac
    [ -e "$STUB_DIR/issue" ] && cat "$STUB_DIR/issue" ;;
  "issue close") ;;
  "issue create") [ -n "${STUB_RACE:-}" ] && echo 6 >> "$STUB_DIR/issue"; echo 7 >> "$STUB_DIR/issue"; echo "https://github.com/o/r/issues/7" ;;
  "issue view")   echo "NODE" ;;
  "issue comment") printf '%s\n' "$5" >> "$STUB_DIR/comments" ;;
  "api --paginate") cat "$STUB_DIR/comments" 2>/dev/null || true ;;
esac
exit 0
STUB
chmod +x "$tmp/gh"

# run <body> [title]; state persists between calls, the log is reset
run() {
  : > "$tmp/log"
  PATH="$tmp:$PATH" STUB_LOG="$tmp/log" STUB_DIR="$tmp" PR_BODY="$1" PR_NUMBER="${PR:-5}" \
    PR_URL=https://github.com/o/r/pull/5 PR_TITLE="${2:-A title}" MERGE_SHA=0123456789abcdef \
    MERGED_AT=2026-10-30T12:00:00Z GH_REPO=o/r "$SCRIPT" >/dev/null 2>&1
}
check() { if [ "$2" = ok ]; then echo "ok:   $1"; else echo "FAIL: $1"; fail=1; fi; }
logged() { grep -q -- "$1" "$tmp/log" && echo ok || echo no; }
ncomments() { grep -c '^<!-- changelog-feed' "$tmp/comments" 2>/dev/null || true; }

run $'## Changelog\nFixed: the thing.'
check "creates the issue when missing" "$(logged 'issue create --title Changelog')"
check "pins the new issue" "$(logged 'pinIssue')"
check "comments on the new issue" "$(logged 'issue comment 7 ')"
check "comment has marker, date, PR and merge commit links" \
  "$(tr '\n' ' ' < "$tmp/comments" | grep -q 'pr=5 -->.*2026-10-30.*pull/5.*commit/0123456789abcdef.*Fixed: the thing' && echo ok || echo no)"

run $'## Changelog\nFixed: the thing.'
check "re-running the same PR posts nothing" "$([ "$(ncomments)" = 1 ] && echo ok || echo no)"

PR=6 run $'## Changelog\n- Added: x'
check "reuses the bot's issue, not someone else's" "$(logged 'issue comment 7 ')"
check "does not create a second issue" "$([ "$(logged 'issue create')" = no ] && echo ok || echo no)"
check "second PR is appended" "$([ "$(ncomments)" = 2 ] && echo ok || echo no)"

PR=8 run $'## Changelog\nAdded: ping @someone' "Thanks @other"
check "defuses @mentions" "$(! grep -q '@[a-z]' "$tmp/comments" && echo ok || echo no)"

for body in $'## Changelog\nnone' $'## Changelog\n- None.\r\n' $'## Changelog\nNone' "" $'## Summary\nx'; do
  before="$(ncomments)"; PR=9 run "$body"
  check "skips body: ${body//$'\n'/|}" "$([ ! -s "$tmp/log" ] && [ "$(ncomments)" = "$before" ] && echo ok || echo no)"
done

# A concurrent run created issue 6 first: keep it, close our 7, do not pin, post to 6.
rm -f "$tmp/issue" "$tmp/comments"
STUB_RACE=1 PR=10 run $'## Changelog\nAdded: y'
check "race: closes the newer duplicate" "$(logged 'issue close 7 ')"
check "race: does not close the oldest" "$([ "$(logged 'issue close 6 ')" = no ] && echo ok || echo no)"
check "race: does not pin the duplicate" "$([ "$(logged 'pinIssue')" = no ] && echo ok || echo no)"
check "race: posts to the oldest" "$(logged 'issue comment 6 ')"

exit "$fail"
