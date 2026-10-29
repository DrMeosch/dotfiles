#!/usr/bin/env bash
# Drives the real `make update` against a throwaway origin and clone. nix and
# home-manager are stubs that log their calls, so `apply` takes the rebuild path.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME" "$TMP/bin"
printf '#!/bin/sh\necho "$@" >> "%s/hm.log"\n' "$TMP" > "$TMP/bin/home-manager"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/nix"
chmod +x "$TMP/bin/home-manager" "$TMP/bin/nix"
export PATH="$TMP/bin:$PATH"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

fail=0
ok() { echo "ok:   $*"; }
bad() { echo "FAIL: $*"; fail=1; }

# A repo shaped like this one: the user line sits right under a comment line.
mkdir "$TMP/seed"
cp -r "$REPO/Makefile" "$REPO/bootstrap.sh" "$REPO/rebuild.sh" "$REPO/scripts" "$TMP/seed/"
echo '{"pinned": true}' > "$TMP/seed/flake.lock"
cat > "$TMP/seed/flake.nix" <<'NIX'
{
  outputs = { ... }:
    let
      # The one username line to change.
      user = "ag";
    in { };
}
NIX
git -C "$TMP/seed" init -q -b master
git -C "$TMP/seed" add -A
git -C "$TMP/seed" commit -qm seed
git clone -q --bare "$TMP/seed" "$TMP/origin.git"

fresh() { # fresh <name>: clone of origin, linked as ~/.dotfiles, user line rewritten like a first run
  rm -rf "$TMP/$1" "$HOME/.dotfiles"
  git clone -q "$TMP/origin.git" "$TMP/$1"
  ln -sfn "$TMP/$1" "$HOME/.dotfiles"
  sed -i 's/user = "ag"/user = "me"/' "$TMP/$1/flake.nix"
  : > "$TMP/hm.log"
}
upstream() { # upstream <sed script> <message>: push a change to origin's flake.nix
  rm -rf "$TMP/up"
  git clone -q "$TMP/origin.git" "$TMP/up"
  sed -i "$1" "$TMP/up/flake.nix"
  git -C "$TMP/up" commit -qam "$2"
  git -C "$TMP/up" push -q origin HEAD:master
}

# 1. upstream edits the comment line right above the user line
fresh c1
upstream 's/The one username line to change./The one username line to change (edited)./' "touch comment"
if (cd "$TMP/c1" && make update TARGET=arch >"$TMP/c1.log" 2>&1); then ok "update succeeds next to an upstream edit"; else bad "update failed"; cat "$TMP/c1.log"; fi
grep -q '(edited)' "$TMP/c1/flake.nix" && ok "upstream change pulled" || bad "upstream change missing"
grep -q 'user = "me"' "$TMP/c1/flake.nix" && ok "user line kept" || bad "user line lost"
if grep -qE '^(<<<<<<<|=======|>>>>>>>)' "$TMP/c1/flake.nix"; then bad "conflict markers in flake.nix"; else ok "no conflict markers"; fi
[ -z "$(git -C "$TMP/c1" stash list)" ] && ok "no leftover stash" || bad "leftover stash"
grep -q 'switch' "$TMP/hm.log" && ok "rebuild ran after the pull" || bad "rebuild did not run"
grep -q -- '--no-write-lock-file' "$TMP/hm.log" && ok "rebuild leaves flake.lock alone" || bad "rebuild may write flake.lock"

# 2. an unrelated local edit is refused and nothing is pulled
fresh c2
upstream 's/"ag"/"ag"/;$a # more' "append"
echo local >> "$TMP/c2/Makefile"
if (cd "$TMP/c2" && make update TARGET=arch >"$TMP/c2.log" 2>&1); then bad "update accepted a dirty tree"; else ok "dirty tree refused"; fi
[ ! -s "$TMP/hm.log" ] && ok "no rebuild after a refusal" || bad "rebuild ran after a refusal"
grep -q 'more' "$TMP/c2/flake.nix" && bad "pulled despite refusing" || ok "nothing pulled"

# 3. diverged history stops, keeps the user line, and does not rebuild
fresh c3
echo local > "$TMP/c3/localfile"
git -C "$TMP/c3" add localfile
git -C "$TMP/c3" commit -qm local
upstream '$a # diverge' "diverge"
if (cd "$TMP/c3" && make update TARGET=arch >"$TMP/c3.log" 2>&1); then bad "update accepted diverged history"; else ok "diverged history refused"; fi
grep -q 'user = "me"' "$TMP/c3/flake.nix" && ok "user line kept after a failed pull" || bad "user line lost after a failed pull"
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

exit "$fail"
