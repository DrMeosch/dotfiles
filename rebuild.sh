#!/usr/bin/env bash
# Apply the current config. Edit files in the repo, then run this.
set -euo pipefail

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
  echo "Re-run as: ./rebuild.sh <arch|ubuntu|wsl>"
  exit 1
fi

exec home-manager switch --flake "$HOME/.dotfiles#$TARGET" -b bak
