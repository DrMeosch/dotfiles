#!/usr/bin/env bash
# Checks that a bootstrapped machine really ended up with the dotfiles applied.
# Run it after the first `make` (bootstrap.sh), as the same user, from anywhere.
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

# -- the Nerd Font is installed and fontconfig resolves it (desktop targets) ---
# gui.nix is not imported on WSL, so only check where the caller says it is expected.
if [ "${EXPECT_FONT:-}" = 1 ]; then
  FONT="GeistMono Nerd Font"
  # fc-list/fc-match print "Family,Alias" lists; compare whole names. Capture
  # first: a `| grep -q` would SIGPIPE its producer and fail under pipefail.
  families="$(fc-list : family 2>/dev/null | tr ',' '\n')"
  matched="$(fc-match -f '%{family}' "$FONT" 2>/dev/null | tr ',' '\n')"
  if grep -qxF "$FONT" <<<"$families"; then ok "fc-list has $FONT"; else bad "fc-list has no $FONT"; fi
  if grep -qxF "$FONT" <<<"$matched"; then ok "fc-match resolves $FONT"; else bad "fc-match '$FONT' resolved to '$matched'"; fi
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
# gui.nix is not imported on WSL, so the Alacritty files are only expected where the font is.
if [ "${EXPECT_FONT:-}" = 1 ]; then
  [ -d ~/.config/alacritty ] && [ ! -L ~/.config/alacritty ] && ok "~/.config/alacritty is a real directory" || bad "~/.config/alacritty is not a real directory"
  check_link ~/.config/alacritty/alacritty.toml home/.config/alacritty/alacritty.toml
  check_link ~/.config/alacritty/themes/rose-pine-moon.toml home/.config/alacritty/themes/rose-pine-moon.toml
  [ -f ~/.config/alacritty/current-theme.toml ] && ok "~/.config/alacritty/current-theme.toml seeded" || bad "~/.config/alacritty/current-theme.toml missing"
  check_link ~/.local/bin/atc home/.local/bin/atc
  check_link ~/.config/xdg-desktop-portal/portals.conf home/.config/xdg-desktop-portal/portals.conf
  check_link ~/.xprofile home/.xprofile
  check_link ~/.local/bin/x11-session-env home/.local/bin/x11-session-env
  check_link ~/.local/bin/portal-color-scheme home/.local/bin/portal-color-scheme
fi
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

# -- Markdown files open as markdown, only the wiki is vimwiki -----------------
# vimwiki would otherwise claim every .md file, and Markdown rendering would not apply.
nvim_filetype() { nvim --headless "$1" '+call writefile([&filetype], "/dev/stdout")' +qa 2>/dev/null; }
mdtmp="" wikifile="" wiki_created=0
cleanup() {
  rm -rf "$mdtmp" "$wikifile"
  [ "$wiki_created" = 0 ] || rmdir ~/vimwiki 2>/dev/null || true
}
trap cleanup EXIT
mdtmp="$(mktemp -d)"
[ -d ~/vimwiki ] || { mkdir ~/vimwiki; wiki_created=1; }
wikifile="$(mktemp ~/vimwiki/smoke-test.XXXXXX.md)"
touch "$mdtmp/README.md"
ft="$(nvim_filetype "$mdtmp/README.md")"
if [ "$ft" = markdown ]; then ok "a .md file outside ~/vimwiki is markdown"; else bad "a .md file outside ~/vimwiki is '$ft', expected markdown"; fi
ft="$(nvim_filetype "$wikifile")"
if [ "$ft" = vimwiki ]; then ok "a .md file in ~/vimwiki is vimwiki"; else bad "a .md file in ~/vimwiki is '$ft', expected vimwiki"; fi

exit "$fail"
