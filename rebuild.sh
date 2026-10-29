#!/usr/bin/env bash
# Apply the current config. Edit files in the repo, then run this (or `make`,
# which calls it once the machine has been bootstrapped).
#
# Usage: ./rebuild.sh [arch|ubuntu|wsl-arch|wsl-ubuntu]
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Detects arch / ubuntu / wsl-arch / wsl-ubuntu, or validates the one given.
TARGET="$("$DIR/scripts/detect-target.sh" "${1:-}")"
echo "==> Target: $TARGET"

# --no-write-lock-file: a machine only reads the committed flake.lock, never rewrites it.
exec home-manager switch --flake "$HOME/.dotfiles#$TARGET" -b bak --no-write-lock-file
