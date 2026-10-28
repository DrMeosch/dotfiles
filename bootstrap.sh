#!/usr/bin/env bash
# Takes a fresh Linux machine (Arch, Ubuntu, or Ubuntu on WSL2) from nothing to
# a built standalone home-manager config.
# Run this once. After it finishes, use ./rebuild.sh for every later change.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# -- detect the target --------------------------------------------------------
detect_target() {
  if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
    echo wsl
  elif [ -f /etc/arch-release ]; then
    echo arch
  elif command -v apt >/dev/null 2>&1; then
    echo ubuntu
  else
    echo ""
  fi
}

TARGET="${1:-$(detect_target)}"
if [ -z "$TARGET" ]; then
  echo "Could not auto-detect the target (arch/ubuntu/wsl)."
  echo "Re-run as: ./bootstrap.sh <arch|ubuntu|wsl>"
  exit 1
fi
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
ln -sfn "$DIR" ~/.dotfiles

echo "==> Step 3: personalize the configured username"
REAL_USER="$(id -un)"
FLAKE_USER="$(sed -nE 's/^[[:space:]]*user = "([^"]+)";.*/\1/p' "$DIR/flake.nix" | head -n1)"
if [ -z "$FLAKE_USER" ]; then
  echo "    Could not find the single \"user = \" line in flake.nix."
  echo "    Edit flake.nix yourself before continuing."
  exit 1
elif [ "$FLAKE_USER" != "$REAL_USER" ]; then
  echo "    flake.nix is configured for user \"$FLAKE_USER\", but you are \"$REAL_USER\"."
  read -r -p "    Rewrite flake.nix's \"user = \" line to \"$REAL_USER\"? [y/N] " REPLY
  if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    sed -i -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix"
    echo "    Updated. Review the change with: git -C \"$DIR\" diff flake.nix"
  else
    echo "    Skipped. Edit the single \"user = \" line in flake.nix yourself before continuing."
    exit 1
  fi
else
  echo "    flake.nix already matches \"$REAL_USER\", nothing to do."
fi

echo "==> Step 4: first home-manager switch (#$TARGET)"
# home-manager isn't on PATH yet on a fresh machine, so run it straight from the
# flake this once. After this, rebuild.sh uses the installed home-manager.
nix run github:nix-community/home-manager/release-26.05 -- switch --flake "$HOME/.dotfiles#$TARGET" -b bak

echo "==> Done."
echo "    Start a new shell (or: exec zsh) to pick up the new environment."
echo "    For future changes: ./rebuild.sh"
