#!/usr/bin/env bash
# Checks scripts/detect-target.sh against fixture /proc/version and
# /etc/os-release files, so the WSL2-Arch case is covered without WSL2-Arch.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
DETECT="$REPO/scripts/detect-target.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
printf 'Linux version 6.8.0-generic (buildd@lcy02) #1 SMP\n' > "$TMP/proc-native"
printf 'Linux version 5.15.153.1-microsoft-standard-WSL2 (root@x) #1 SMP\n' > "$TMP/proc-wsl"
printf 'NAME="Arch Linux"\nID=arch\n' > "$TMP/os-arch"
printf 'NAME="Ubuntu"\nID=ubuntu\nID_LIKE=debian\n' > "$TMP/os-ubuntu"
printf 'NAME="Debian GNU/Linux"\nID=debian\n' > "$TMP/os-debian"

expect() { # expect <want> <proc file> <os-release file>
  local want="$1" got=""
  got="$(DETECT_PROC_VERSION="$TMP/$2" DETECT_OS_RELEASE="$TMP/$3" "$DETECT" 2>/dev/null)" || got="(error)"
  if [ "$got" = "$want" ]; then echo "ok:   $2 + $3 -> $want"; else echo "FAIL: $2 + $3 -> $got, want $want"; fail=1; fi
}

expect arch proc-native os-arch
expect ubuntu proc-native os-ubuntu
expect wsl-arch proc-wsl os-arch
expect wsl-ubuntu proc-wsl os-ubuntu
expect "(error)" proc-native os-debian
expect "(error)" proc-wsl os-debian

# TARGET override: known names pass through, anything else is an error.
for t in arch ubuntu wsl-arch wsl-ubuntu wsl; do
  if [ "$("$DETECT" "$t")" = "$t" ]; then echo "ok:   override $t"; else echo "FAIL: override $t"; fail=1; fi
done
if "$DETECT" bogus >/dev/null 2>&1; then echo "FAIL: override bogus accepted"; fail=1; else echo "ok:   override bogus rejected"; fi

exit "$fail"
