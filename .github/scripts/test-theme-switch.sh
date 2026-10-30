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

# -- btop: only the color_theme line of btop.conf changes ----------------------
conf="$HOME/.config/btop/btop.conf"
rm -f "$conf"; "$atc" dark >/dev/null
[ ! -e "$conf" ] && ok "atc skips a missing btop.conf" || bad "atc created btop.conf"
mkdir -p "$HOME/.config/btop"
printf '#? Config\ncolor_theme = "DWM-Pink-Light"\nsave_config_on_exit = false\ntheme_background = False' >"$conf"
chmod 640 "$conf"
want_conf() { # $1 theme: the seed with only the color_theme value swapped
  printf '#? Config\ncolor_theme = "%s"\nsave_config_on_exit = false\ntheme_background = False' "$1"
}
for pair in dark:DWM-Pink-Dark light:DWM-Pink-Light dark:DWM-Pink-Dark; do
  "$atc" "${pair%%:*}" >/dev/null
  if cmp -s "$conf" <(want_conf "${pair#*:}") && [ "$(stat -c %a "$conf")" = 640 ]; then
    ok "atc ${pair%%:*} -> btop color_theme ${pair#*:}, other lines and mode untouched"
  else
    bad "atc ${pair%%:*} left btop.conf as: $(cat "$conf")"
  fi
done
printf 'save_config_on_exit = false\n' >"$conf"
"$atc" light >/dev/null
[ "$(cat "$conf")" = $'save_config_on_exit = false\ncolor_theme = "DWM-Pink-Light"' ] && ok "atc adds color_theme when btop.conf has none" || bad "btop.conf without color_theme became: $(cat "$conf")"
printf 'save_config_on_exit = false' >"$conf"
"$atc" dark >/dev/null
[ "$(cat "$conf")" = $'save_config_on_exit = false\ncolor_theme = "DWM-Pink-Dark"' ] && ok "atc keeps the last line intact when btop.conf has no color_theme and no trailing newline" || bad "btop.conf without color_theme or trailing newline became: $(cat "$conf")"
[ -z "$(ls "$HOME/.config/btop" | grep -v '^btop.conf$')" ] && ok "atc left no temp files in the btop directory" || bad "stray files in the btop directory"

# A running btop is told to reload with SIGUSR2. A stand-in binary (a copy of
# sleep, which reports a version above 1.3.1 and has no SIGUSR2 handler) dies from
# the signal, so its death shows atc sent it; an unrelated process must survive.
fake="$work/fake"; mkdir -p "$fake"
cp "$(command -v sleep)" "$fake/btop"
"$fake/btop" 30 & fake_pid=$!
{ # bash reports the signal death of the stand-in on stderr; keep that out of the log
  sleep 0.5
  "$atc" dark >/dev/null
  sleep 0.5
  if kill -0 "$fake_pid" 2>/dev/null; then bad "atc did not signal the running btop"; kill "$fake_pid"; else ok "atc signals a running btop to reload"; fi
  wait "$fake_pid" || true
} 2>/dev/null
sleep 30 & other=$!
"$atc" light >/dev/null
if kill -0 "$other" 2>/dev/null; then ok "atc leaves other processes alone"; else bad "atc killed an unrelated process"; fi
kill "$other" 2>/dev/null || true

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
