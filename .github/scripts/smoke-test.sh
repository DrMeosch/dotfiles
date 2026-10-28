#!/usr/bin/env bash
# Checks that a bootstrapped machine really ended up with the dotfiles applied.
# Run it after ./bootstrap.sh, as the same user, from anywhere.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"

fail=0
ok() { echo "ok:   $*"; }
bad() { echo "FAIL: $*"; fail=1; }

# -- tools come from the home-manager profile ---------------------------------
for tool in zsh tmux nvim starship; do
  if path="$(command -v "$tool")"; then
    real="$(readlink -f "$path")"
    case "$real" in
      /nix/store/*) ok "$tool -> $real" ;;
      *) bad "$tool resolves to $real, not the Nix store" ;;
    esac
  else
    bad "$tool is not on PATH"
  fi
done
# Not part of the config today; checked only when something installs it.
if command -v rustup >/dev/null 2>&1; then
  rustup --version >/dev/null && ok "rustup works" || bad "rustup is broken"
fi

# -- linked files resolve into this repo --------------------------------------
check_link() {
  local link="$1" want="$2" real
  if [ ! -L "$link" ]; then bad "$link is not a symlink"; return; fi
  if ! real="$(readlink -f "$link")" || [ ! -e "$real" ]; then bad "$link dangles"; return; fi
  if [ "$real" = "$REPO/$want" ]; then ok "$link -> $real"; else bad "$link -> $real, expected $REPO/$want"; fi
}
check_link ~/.dotfiles .
check_link ~/.config/nvim home/.config/nvim
check_link ~/.tmux.conf home/.tmux.conf
check_link ~/.tmux/dark.conf home/.tmux/dark.conf
check_link ~/.tmux/light.conf home/.tmux/light.conf
[ -f ~/.tmux/current-theme.conf ] && ok "~/.tmux/current-theme.conf seeded" || bad "~/.tmux/current-theme.conf missing"

# -- zsh starts as an interactive shell with the config -----------------------
if out="$(zsh -i -c 'command -v starship' 2>&1)"; then ok "zsh -i starts ($out)"; else bad "zsh -i failed: $out"; fi

# -- tmux loads the config without errors -------------------------------------
# Config errors do not fail tmux's exit status; they land in its message log.
tmux kill-server 2>/dev/null || true
if msgs="$(tmux -f ~/.tmux.conf start-server \; show-messages 2>&1)"; then
  if grep -qiE 'error|unknown|invalid|not found|no such' <<<"$msgs"; then
    bad "tmux reported problems loading ~/.tmux.conf:"; echo "$msgs"
  else
    ok "tmux -f ~/.tmux.conf loads cleanly"
  fi
else
  bad "tmux failed to start: $msgs"
fi
tmux kill-server 2>/dev/null || true

# -- nvim starts and quits ----------------------------------------------------
if nvim --headless +qa; then ok "nvim --headless +qa exits 0"; else bad "nvim --headless +qa exited $?"; fi

exit "$fail"
