#!/usr/bin/env bash
# Upgrade test for the Alacritty config layout.
#
# Older revisions linked the whole ~/.config/alacritty directory to the repo's
# home/.config/alacritty. gui.nix now links the files inside a real directory
# (so the upstream themes can sit next to ours). On a machine still on the old
# layout, home-manager used to write the new per-file links *through* the old
# directory symlink, into the repo checkout: alacritty.toml became a symlink to
# itself and the upstream theme links landed next to the tracked files.
#
# This test starts from the old layout in a throwaway $HOME, activates the real
# ubuntu configuration (the same generation `make` applies, only with a
# different home directory), and checks that the upgrade replaced the old
# symlink with a real directory and left the repo checkout untouched. Run it
# from anywhere with Nix on PATH; it never touches the real $HOME.
#
# Usage: test-alacritty-migration.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"

fail=0
ok() { echo "ok:   $*"; }
bad() { echo "FAIL: $*"; fail=1; }

work="$(mktemp -d)"
trap 'chmod -R u+w "$work" 2>/dev/null || true; rm -rf "$work"' EXIT
home="$work/home"
checkout="$home/.dotfiles"
mkdir -p "$home/.config" "$checkout"

# -- a checkout of the current tree (tracked and new files, as the flake sees them)
(cd "$REPO" && git ls-files -co --exclude-standard -z | xargs -0 cp --parents -t "$checkout")

# -- the old layout: the whole directory is one symlink into the checkout --------
ln -s "$checkout/home/.config/alacritty" "$home/.config/alacritty"

# A fingerprint of the checkout: every path with its type, link target and content hash.
snapshot() {
  (cd "$checkout" && find . -printf '%p %y %l\n' | LC_ALL=C sort &&
    find . -type f -exec sha256sum {} + | LC_ALL=C sort -k2)
}
snapshot >"$work/before"

# -- the activation package: the ubuntu configuration, rooted at the throwaway $HOME
# (home.homeDirectory is where every out-of-store link is resolved from, so it has to
# point at the throwaway home too, and activation insists on the configured user being
# the one running it; the GPU driver setup is a system service that has
# nothing to do with the links under test, so it is left out). Hand `path:` the
# checkout copy, so the build sees exactly the files above whether or not they are
# committed.
pkg="$(nix build --no-link --print-out-paths --no-write-lock-file --impure \
  --extra-experimental-features 'nix-command flakes' --expr "
    let
      flake = builtins.getFlake \"path:$checkout\";
      lib = flake.inputs.nixpkgs.lib;
      cfg = flake.homeConfigurations.ubuntu.extendModules {
        modules = [ {
          home.username = lib.mkForce \"$(id -un)\";
          home.homeDirectory = lib.mkForce \"$home\";
          targets.genericLinux.gpu.enable = lib.mkForce false;
        } ];
      };
    in cfg.activationPackage")"

activate() {
  # -b bak, like rebuild.sh: a file in the way is renamed rather than aborting the run.
  env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME \
    HOME="$home" HOME_MANAGER_BACKUP_EXT=bak "$pkg/activate"
}
echo "== first activation, from the old layout"
activate 2>&1 | tee "$work/first.log"
# The seeded current-theme.toml is state: a later activation must not overwrite it.
if [ -f "$home/.config/alacritty/current-theme.toml" ]; then
  cp "$home/.config/alacritty/current-theme.toml" "$work/seed"
  echo "# edited by atc" >"$home/.config/alacritty/current-theme.toml"
fi
echo "== second activation, must change nothing"
activate 2>&1 | tee "$work/second.log"

# -- the checks ---------------------------------------------------------------
conf="$home/.config/alacritty"
if [ -d "$conf" ] && [ ! -L "$conf" ]; then ok "$conf is a real directory"; else bad "$conf is not a real directory"; fi

want="$checkout/home/.config/alacritty/alacritty.toml"
link="$conf/alacritty.toml"
if [ -L "$link" ] && [ "$(readlink -f "$link")" = "$want" ] && [ -f "$want" ] && [ ! -L "$want" ]; then
  ok "alacritty.toml -> $want (a regular file)"
else
  bad "alacritty.toml resolves to '$(readlink -f "$link" 2>&1 || true)', expected the regular file $want"
fi

if grep -q 'Replacing the old ~/.config/alacritty symlink' "$work/first.log" &&
  ! grep -q 'Replacing the old' "$work/second.log"; then
  ok "the old symlink was replaced once, with a message"
else
  bad "expected the replacement message on the first activation only"
fi

theme="$conf/current-theme.toml"
if [ -f "$theme" ] && [ ! -L "$theme" ] && [ "$(cat "$theme")" = "# edited by atc" ]; then
  ok "current-theme.toml is a plain file and a later activation keeps its content"
else
  bad "current-theme.toml is missing, a link, or was overwritten"
fi
if cmp -s "$checkout/home/.config/alacritty/themes/rose-pine-moon.toml" "$work/seed"; then
  ok "current-theme.toml was seeded from rose-pine-moon"
else
  bad "current-theme.toml was not seeded from rose-pine-moon"
fi

for s in atc dwm-dark.sh dwm-light.sh; do
  l="$home/.local/bin/$s"
  if [ -L "$l" ] && [ "$(readlink -f "$l")" = "$checkout/home/.local/bin/$s" ] && [ -x "$l" ]; then
    ok "~/.local/bin/$s -> the executable in the checkout"
  else
    bad "~/.local/bin/$s does not resolve to the executable $checkout/home/.local/bin/$s"
  fi
done

own=0
for f in "$REPO"/home/.config/alacritty/themes/*.toml; do
  n="${f##*/}"
  t="$conf/themes/$n"
  if [ -L "$t" ] && [ "$(readlink -f "$t")" = "$checkout/home/.config/alacritty/themes/$n" ]; then own=$((own + 1)); else bad "own theme $n does not resolve to the checkout"; fi
done
[ "$own" -gt 0 ] && ok "$own own themes link into the checkout"

# Names the upstream collection has and ours does not (and one that is in both, where ours wins).
for n in dracula_plus.toml github_light_colorblind.toml; do
  t="$conf/themes/$n"
  case "$(readlink -f "$t" 2>/dev/null || true)" in
    /nix/store/*) ok "upstream theme $n is linked from the Nix store" ;;
    *) bad "upstream theme $n is missing or not from the Nix store" ;;
  esac
done

if snapshot | cmp -s - "$work/before"; then
  ok "the repo checkout is unchanged"
else
  bad "the repo checkout changed:"
  snapshot | diff "$work/before" - | head -20 || true
fi

exit "$fail"
