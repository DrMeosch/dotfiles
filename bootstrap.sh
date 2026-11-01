#!/usr/bin/env bash
# Takes a fresh Linux machine (Arch or Ubuntu, native or under WSL2) from
# nothing to a built standalone home-manager config.
# Normally run through `make`, which picks this on a first run. After it
# finishes, `make` (or ./rebuild.sh) re-applies the config for every later change.
#
# Usage: ./bootstrap.sh [arch|ubuntu|wsl-arch|wsl-ubuntu]
#   Configures the account that runs it (not root); nothing to edit or pass.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Before anything is installed or linked: a root run would configure /root.
if [ "$(id -u)" -eq 0 ]; then
  echo "Running as root. Run this as the regular user whose home directory should be configured." >&2
  exit 1
fi

# Detects arch / ubuntu / wsl-arch / wsl-ubuntu, or validates the one given.
TARGET="$("$DIR/scripts/detect-target.sh" "${1:-}")"
echo "==> Target: $TARGET"

echo "==> Step 1: Nix"
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping"
else
  # Determinate Nix installer. It enables flakes and the nix command by default.
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

echo "==> Step 2: symlink this repo to ~/.dotfiles"
# common.nix points its mkOutOfStoreSymlink paths at ~/.dotfiles. The symlinks
# are created with a literal target, so this link must exist (and point here)
# or the resulting ~/.config symlinks would dangle until it did.
if [ -e ~/.dotfiles ] && [ ! -L ~/.dotfiles ]; then
  echo "    ~/.dotfiles exists and is not a symlink, so it cannot be pointed at $DIR."
  echo "    Move it out of the way (mv ~/.dotfiles ~/.dotfiles.old) and run again."
  exit 1
fi
ln -sfn "$DIR" ~/.dotfiles

echo "==> Step 3: first home-manager switch (#$TARGET)"
# The flake configures the account that runs this: it reads these variables
# (builtins.getEnv, hence --impure). USER is exported too because home-manager's
# activation compares it with the configured username, and cron and containers leave it unset.
export DOTFILES_USER="$(id -un)" DOTFILES_HOME="$HOME" USER="$(id -un)"
echo "    configuring \"$DOTFILES_USER\" ($DOTFILES_HOME)"
# home-manager isn't on PATH yet on a fresh machine, so run it straight from the
# flake's pinned input this once. After this, rebuild.sh uses the installed home-manager.
# --no-write-lock-file: a machine only reads the committed flake.lock, never rewrites it.
nix run --no-write-lock-file --inputs-from "$HOME/.dotfiles" home-manager#home-manager -- switch --flake "$HOME/.dotfiles#$TARGET" -b bak --no-write-lock-file --impure

echo "==> Done."
echo "    Start a new shell (or: exec zsh) to pick up the new environment."
echo "    For future changes: make   (or: make update, to pull first)"
