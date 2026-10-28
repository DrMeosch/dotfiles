#!/usr/bin/env bash
# Prints the home-manager target for this machine. The one place that knows how
# to tell the four supported setups apart; bootstrap.sh, rebuild.sh and the
# Makefile all call it.
#
#   arch         native Arch Linux
#   ubuntu       native Ubuntu
#   wsl-arch     Arch Linux under WSL2
#   wsl-ubuntu   Ubuntu under WSL2
#
# The distro is ID from os-release, or else the first of arch/ubuntu in ID_LIKE,
# so derivatives (EndeavourOS, Manjaro, Pop!_OS, Linux Mint, ...) are detected.
#
# Usage: scripts/detect-target.sh [target]
#   With a target, validates it and prints it back (this is how TARGET=...
#   overrides detection). "wsl" is accepted as a legacy alias for wsl-ubuntu.
#   Exits 1 with a message on stderr for anything unsupported.
#
# DETECT_PROC_VERSION and DETECT_OS_RELEASE point at alternative files, for tests.
set -euo pipefail

TARGETS="arch ubuntu wsl-arch wsl-ubuntu"

if [ -n "${1:-}" ]; then
  for t in $TARGETS wsl; do
    if [ "$1" = "$t" ]; then
      echo "$1"
      exit 0
    fi
  done
  echo "Unknown target \"$1\". Supported: $TARGETS (legacy alias: wsl)." >&2
  exit 1
fi

if [ "$(uname -s)" != "Linux" ] && [ -z "${DETECT_OS_RELEASE:-}" ]; then
  echo "Unsupported OS \"$(uname -s)\": this setup is for Linux (arch, ubuntu, wsl-arch, wsl-ubuntu)." >&2
  exit 1
fi

OS_RELEASE="${DETECT_OS_RELEASE:-/etc/os-release}"
# Some minimal images only ship the file under /usr/lib.
if [ ! -r "$OS_RELEASE" ] && [ -z "${DETECT_OS_RELEASE:-}" ]; then
  OS_RELEASE=/usr/lib/os-release
fi
id="" id_like=""
if [ -r "$OS_RELEASE" ]; then
  # shellcheck source=/dev/null
  id="$(. "$OS_RELEASE" && echo "${ID:-}")"
  # shellcheck source=/dev/null
  id_like="$(. "$OS_RELEASE" && echo "${ID_LIKE:-}")"
fi

distro=""
for candidate in $id $id_like; do
  case "$candidate" in
    arch | ubuntu)
      distro="$candidate"
      break
      ;;
  esac
done

case "$distro" in
  arch | ubuntu) ;;
  *)
    echo "Unsupported distro \"${id:-unknown}\" (from $OS_RELEASE). Supported: $TARGETS (or derivatives via ID_LIKE)." >&2
    echo "Pass the target explicitly if you know better, e.g. TARGET=arch make." >&2
    exit 1
    ;;
esac

if grep -qiE '(microsoft|wsl)' "${DETECT_PROC_VERSION:-/proc/version}" 2>/dev/null; then
  echo "wsl-$distro"
else
  echo "$distro"
fi
