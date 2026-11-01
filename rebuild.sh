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

if [ "$(id -u)" -eq 0 ]; then
  echo "Running as root. Run this as the regular user whose home directory should be configured." >&2
  exit 1
fi

# The flake configures the account that runs this: it reads these variables
# (builtins.getEnv, hence --impure). USER is exported too because home-manager's
# activation compares it with the configured username, and cron and containers leave it unset.
export DOTFILES_USER="$(id -un)" DOTFILES_HOME="$HOME" USER="$(id -un)"

# --no-write-lock-file: a machine only reads the committed flake.lock, never rewrites it.
exec home-manager switch --flake "$HOME/.dotfiles#$TARGET" -b bak --no-write-lock-file --impure
