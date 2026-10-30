#!/usr/bin/env bash
# Tests home/.local/bin/portal-color-scheme against a fake gdbus, so it needs no
# session bus or portal: each answer maps to the right word, and a portal that
# does not answer (or answers nonsense) fails.
#
# Usage: test-portal-color-scheme.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SCRIPT="$REPO/home/.local/bin/portal-color-scheme"

fail=0
ok() { echo "ok:   $*"; }
bad() { echo "FAIL: $*"; fail=1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
cat > "$work/bin/gdbus" <<'FAKE'
#!/usr/bin/env bash
case "${FAKE_GDBUS:-}" in
  error) echo "Error: org.freedesktop.DBus.Error.ServiceUnknown" >&2; exit 1 ;;
  *) echo "(<<uint32 $FAKE_GDBUS>>,)" ;;
esac
FAKE
chmod +x "$work/bin/gdbus"

# Keep the real gdbus/busctl out of reach: only the fake directory plus the basics.
run() { FAKE_GDBUS="$1" PATH="$work/bin:/usr/bin:/bin" bash "$SCRIPT" 2>/dev/null; }
[ -x "$work/bin/gdbus" ] && [ "$(PATH="$work/bin:$PATH" command -v gdbus)" = "$work/bin/gdbus" ] || bad "fake gdbus not first on PATH"

for pair in "1 dark" "2 light" "0 no-preference"; do
  set -- $pair
  got="$(run "$1" || true)"
  if [ "$got" = "$2" ]; then ok "answer $1 -> $2"; else bad "answer $1 gave '$got', expected $2"; fi
done
if run error >/dev/null; then bad "a silent portal must exit non-zero"; else ok "a silent portal exits non-zero"; fi
if run 7 >/dev/null; then bad "an unknown value must exit non-zero"; else ok "an unknown value exits non-zero"; fi

exit "$fail"
