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
  local link="$1" want="$REPO${2:+/$2}" real
  if [ ! -L "$link" ]; then bad "$link is not a symlink"; return; fi
  if ! real="$(readlink -f "$link")" || [ ! -e "$real" ]; then bad "$link dangles"; return; fi
  if [ "$real" = "$want" ]; then ok "$link -> $real"; else bad "$link -> $real, expected $want"; fi
}
check_link ~/.dotfiles ""
check_link ~/.config/nvim home/.config/nvim
check_link ~/.tmux.conf home/.tmux.conf
check_link ~/.tmux/dark.conf home/.tmux/dark.conf
check_link ~/.tmux/light.conf home/.tmux/light.conf
[ -f ~/.tmux/current-theme.conf ] && ok "~/.tmux/current-theme.conf seeded" || bad "~/.tmux/current-theme.conf missing"

# -- zsh starts as an interactive shell with the config -----------------------
# (no tty here, so zsh warns on stderr that it cannot open a terminal)
if out="$(zsh -i -c 'command -v starship' 2>/dev/null)" && [ -n "$out" ]; then ok "zsh -i starts and finds starship"; else bad "zsh -i failed"; fi

# -- tmux loads the config without errors ------------------------------------
# Errors in the -f config are only printed, they do not change the exit status.
# So load it again with source-file, which does fail (and prints) on any error.
tmux kill-server 2>/dev/null || true
rc=0
msgs="$(tmux -f ~/.tmux.conf start-server \; source-file ~/.tmux.conf \; kill-server 2>&1)" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -qiE 'unknown|invalid|ambiguous|error' <<<"$msgs"; then
  ok "tmux -f ~/.tmux.conf loads cleanly"
else
  bad "tmux had problems loading ~/.tmux.conf (exit $rc):"; echo "$msgs"
fi
tmux kill-server 2>/dev/null || true

# -- nvim starts and quits ----------------------------------------------------
if nvim --headless +qa; then ok "nvim --headless +qa exits 0"; else bad "nvim --headless +qa exited $?"; fi

exit "$fail"
