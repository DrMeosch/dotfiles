#!/usr/bin/env bash
# Drives the real `make update` against a throwaway origin and clone. nix and
# home-manager are stubs that log their calls, so `apply` takes the rebuild path.
# Run it as a regular user: rebuild.sh refuses root.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME" "$TMP/bin"
printf '#!/bin/sh\necho "$@" "DOTFILES_USER=$DOTFILES_USER DOTFILES_HOME=$DOTFILES_HOME USER=$USER" >> "%s/hm.log"\n' "$TMP" > "$TMP/bin/home-manager"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/nix"
chmod +x "$TMP/bin/home-manager" "$TMP/bin/nix"
# `id` reports uid 0 while FAKE_ROOT is set, to exercise the root guards without being root.
REAL_ID="$(command -v id)"
printf '#!/bin/sh\n[ -n "${FAKE_ROOT:-}" ] && [ "${1:-}" = "-u" ] && { echo 0; exit 0; }\nexec "%s" "$@"\n' "$REAL_ID" > "$TMP/bin/id"
chmod +x "$TMP/bin/id"
export PATH="$TMP/bin:$PATH"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

fail=0
ok() { echo "ok:   $*"; }
bad() { echo "FAIL: $*"; fail=1; }

# A repo shaped like this one: the files the scenarios pull and edit are tracked.
mkdir "$TMP/seed"
cp -r "$REPO/Makefile" "$REPO/bootstrap.sh" "$REPO/rebuild.sh" "$REPO/scripts" "$TMP/seed/"
echo '{"pinned": true}' > "$TMP/seed/flake.lock"
printf '# flake\n' > "$TMP/seed/flake.nix"
printf 'notes\n' > "$TMP/seed/notes.txt"
git -C "$TMP/seed" init -q -b master
git -C "$TMP/seed" add -A
git -C "$TMP/seed" commit -qm seed
git clone -q --bare "$TMP/seed" "$TMP/origin.git"

fresh() { # fresh <name>: clone of origin, linked as ~/.dotfiles
  rm -rf "$TMP/$1" "$HOME/.dotfiles"
  git clone -q "$TMP/origin.git" "$TMP/$1"
  ln -sfn "$TMP/$1" "$HOME/.dotfiles"
  : > "$TMP/hm.log"
}
upstream() { # upstream <sed script> <message>: push a change to origin's flake.nix
  rm -rf "$TMP/up"
  git clone -q "$TMP/origin.git" "$TMP/up"
  sed -i "$1" "$TMP/up/flake.nix"
  git -C "$TMP/up" commit -qam "$2"
  git -C "$TMP/up" push -q origin HEAD:master
}

# 1. a clean tree: update pulls and rebuilds for the account that runs it, leaving the tree clean
fresh c1
upstream '$a # more' "append"
if (cd "$TMP/c1" && make update TARGET=arch >"$TMP/c1.log" 2>&1); then ok "update succeeds on a clean tree"; else bad "update failed"; cat "$TMP/c1.log"; fi
grep -q '# more' "$TMP/c1/flake.nix" && ok "upstream change pulled" || bad "upstream change missing"
[ -z "$(git -C "$TMP/c1" status --porcelain --untracked-files=no)" ] && ok "tree is clean after update" || bad "tree is dirty after update"
grep -q 'switch' "$TMP/hm.log" && ok "rebuild ran after the pull" || bad "rebuild did not run"
grep -q -- '--no-write-lock-file' "$TMP/hm.log" && ok "rebuild leaves flake.lock alone" || bad "rebuild may write flake.lock"
grep -q -- '--impure' "$TMP/hm.log" && ok "rebuild is impure, so the flake sees the account" || bad "rebuild is not impure"
me="$(id -un)"
grep -q "DOTFILES_USER=$me DOTFILES_HOME=$HOME USER=$me" "$TMP/hm.log" && ok "rebuild is told the running account and its home" || bad "rebuild got the wrong account"

# 2. a tracked edit, in any file (flake.nix included), is refused and nothing is pulled
for f in notes.txt flake.nix; do
  fresh c2
  upstream "\$a # pulled-late-$f" "append"
  echo local >> "$TMP/c2/$f"
  if (cd "$TMP/c2" && make update TARGET=arch >"$TMP/c2.log" 2>&1); then bad "update accepted an edited $f"; else ok "edited $f refused"; fi
  grep -q "refusing to pull" "$TMP/c2.log" && ok "the refusal says why" || bad "no reason given for $f"
  [ ! -s "$TMP/hm.log" ] && ok "no rebuild after a refusal" || bad "rebuild ran after a refusal"
  grep -q "pulled-late-$f" "$TMP/c2/flake.nix" && bad "pulled despite refusing" || ok "nothing pulled"
done

# 3. diverged history stops and does not rebuild
fresh c3
echo local > "$TMP/c3/localfile"
git -C "$TMP/c3" add localfile
git -C "$TMP/c3" commit -qm local
upstream '$a # diverge' "diverge"
if (cd "$TMP/c3" && make update TARGET=arch >"$TMP/c3.log" 2>&1); then bad "update accepted diverged history"; else ok "diverged history refused"; fi
[ ! -s "$TMP/hm.log" ] && ok "no rebuild after a failed pull" || bad "rebuild ran after a failed pull"

# 4. a locally modified, tracked flake.lock (e.g. after a stray nix flake update) while upstream changes it:
#    kept as a copy, the committed one restored, the pull goes through
fresh c4
echo '{"edited": "locally"}' > "$TMP/c4/flake.lock"
rm -rf "$TMP/up"
git clone -q "$TMP/origin.git" "$TMP/up"
echo '{"pinned": "newer"}' > "$TMP/up/flake.lock"
git -C "$TMP/up" commit -qam "bump flake.lock"
git -C "$TMP/up" push -q origin HEAD:master
if (cd "$TMP/c4" && make update TARGET=arch >"$TMP/c4.log" 2>&1); then ok "update succeeds with a modified flake.lock"; else bad "update failed"; cat "$TMP/c4.log"; fi
grep -q 'keeping your copy as flake.lock.local-' "$TMP/c4.log" && ok "the copy is announced" || bad "copy not announced"
grep -q 'newer' "$TMP/c4/flake.lock" && ok "upstream flake.lock pulled" || bad "upstream flake.lock missing"
grep -q 'locally' "$TMP"/c4/flake.lock.local-* && ok "local flake.lock kept as a copy" || bad "local flake.lock copy missing"
[ -z "$(git -C "$TMP/c4" status --porcelain --untracked-files=no -- flake.lock)" ] && ok "flake.lock matches upstream" || bad "flake.lock modified"
grep -q 'switch' "$TMP/hm.log" && ok "rebuild ran after the pull" || bad "rebuild did not run"

# 5. the same for a flake.lock that was deleted
fresh c5
rm "$TMP/c5/flake.lock"
if (cd "$TMP/c5" && make update TARGET=arch >"$TMP/c5.log" 2>&1); then ok "update succeeds with a deleted flake.lock"; else bad "update failed"; cat "$TMP/c5.log"; fi
[ -s "$TMP/c5/flake.lock" ] && ok "committed flake.lock restored" || bad "flake.lock missing"

# 6. a cron-like environment has no USER: the rebuild still gets the right account
fresh c6
if (cd "$TMP/c6" && env -u USER make TARGET=arch >"$TMP/c6.log" 2>&1); then ok "make works without USER in the environment"; else bad "make failed without USER"; cat "$TMP/c6.log"; fi
grep -q "DOTFILES_USER=$me DOTFILES_HOME=$HOME USER=$me" "$TMP/hm.log" && ok "rebuild still got the running account" || bad "rebuild got the wrong account without USER"

# 7. root is refused by make and make update before git or the config is touched
fresh c7
upstream "\$a # pulled-late-root" "append"
head_before="$(git -C "$TMP/c7" rev-parse HEAD)"
for goal in update apply; do
  if (cd "$TMP/c7" && FAKE_ROOT=1 make $goal TARGET=arch >"$TMP/c7.log" 2>&1); then bad "make $goal accepted root"; else ok "make $goal refused as root"; fi
  grep -q 'Running as root' "$TMP/c7.log" && ok "make $goal says why" || bad "make $goal gave no reason"
  [ "$(git -C "$TMP/c7" rev-parse HEAD)" = "$head_before" ] && ok "make $goal pulled nothing as root" || bad "make $goal moved HEAD as root"
  [ ! -s "$TMP/hm.log" ] && ok "make $goal applied nothing as root" || bad "make $goal ran the rebuild as root"
done

exit "$fail"
