#!/usr/bin/env bash
# Checks the untracked theme switch: `atc` writes only state files under a
# throwaway $HOME (never the repo checkout), and Neovim picks its colorscheme
# from the state file (dark when the file is missing or unreadable).
#
# Needs nvim on PATH for the Neovim half; runs from anywhere.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"

fail=0
ok() { echo "ok:   $*"; }
bad() { echo "FAIL: $*"; fail=1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config"
# A tmux server of the real user must never see this: point tmux at an empty socket dir.
unset XDG_RUNTIME_DIR TMUX
export TMUX_TMPDIR="$work/tmux"
mkdir -p "$TMUX_TMPDIR"
mkdir -p "$HOME/.config/alacritty/themes" "$HOME/.tmux"
# Stand-ins for the two themes atc copies; only their content matters here.
echo "# dark" >"$HOME/.config/alacritty/themes/dracula_plus.toml"
echo "# light" >"$HOME/.config/alacritty/themes/github_light_colorblind.toml"
echo "# seed" >"$HOME/.config/alacritty/current-theme.toml"
touch "$HOME/.config/alacritty/alacritty.toml"

atc="$REPO/home/.local/bin/atc"
state="$HOME/.config/atc-theme"
tracked_before="$(cd "$REPO" && git status --porcelain && sha256sum home/.config/nvim/lua/plugins/colorscheme.lua)"

# No state file yet means dark, so the first plain switch goes to light.
for args in "" toggle; do
  rm -f "$state"
  "$atc" $args >/dev/null
  if [ "$(cat "$state")" = light ]; then ok "atc ${args:-(no argument)} without a state file -> light"; else bad "atc ${args:-(no argument)} without a state file left '$(cat "$state")', expected light"; fi
done

for theme in light dark toggle toggle; do
  want="$theme"
  [ "$theme" = toggle ] && { [ "$(cat "$state")" = dark ] && want=light || want=dark; }
  "$atc" "$theme" >/dev/null
  case "$want" in dark) file=dracula_plus ;; *) file=github_light_colorblind ;; esac
  if [ "$(cat "$state")" = "$want" ] &&
    cmp -s "$HOME/.config/alacritty/current-theme.toml" "$HOME/.config/alacritty/themes/$file.toml"; then
    ok "atc $theme -> $want (state file and current-theme.toml)"
  else
    bad "atc $theme did not leave state '$want' with $file as current-theme.toml"
  fi
done

if [ "$(cd "$REPO" && git status --porcelain && sha256sum home/.config/nvim/lua/plugins/colorscheme.lua)" = "$tracked_before" ]; then
  ok "atc left the repo checkout alone"
else
  bad "atc changed the repo checkout:"; (cd "$REPO" && git status --short)
fi

# -- Neovim picks the colorscheme from the state file ---------------------------
colorscheme() {
  nvim --headless -u NONE --cmd "set rtp^=$REPO/home/.config/nvim" \
    '+lua io.stdout:write(require("config.atc_theme").colorscheme())' +qa 2>&1
}
expect() {
  local label="$1" want="$2" got
  got="$(colorscheme)" || true
  if [ "$got" = "$want" ]; then ok "nvim: $label -> $want"; else bad "nvim: $label gave '$got', expected $want"; fi
}
echo dark >"$state";  expect "state file dark" dracula
echo light >"$state"; expect "state file light" github_light_colorblind
printf 'light\n\n' >"$state"; expect "state file light with trailing blank line" github_light_colorblind
echo nonsense >"$state"; expect "state file with an unknown value" dracula
: >"$state";          expect "empty state file" dracula
rm -f "$state";       expect "no state file" dracula
mkdir "$state";       expect "unreadable state file (a directory)" dracula
rmdir "$state"
mkdir -p "$work/nohome/.config"; echo light >"$work/nohome/.config/atc-theme"
got="$(XDG_CONFIG_HOME="" HOME="$work/nohome" colorscheme)"
[ "$got" = github_light_colorblind ] && ok "nvim: ~/.config/atc-theme is read when XDG_CONFIG_HOME is unset" || bad "nvim: fallback gave '$got'"

exit "$fail"
