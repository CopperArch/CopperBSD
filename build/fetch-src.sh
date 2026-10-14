#!/bin/sh
# fetch-src.sh — put the FreeBSD source at the exact pinned commit into $SRCDIR.
# Runs inside the FreeBSD builder. Reproducible: always the same commit.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/config.sh"

echo ">> CopperBSD: fetching FreeBSD $FREEBSD_BRANCH @ $FREEBSD_COMMIT into $SRCDIR"

# Prefer the vendored subset's remote if present, else official, else mirror.
pick_remote() {
    for r in "$FREEBSD_GIT_OFFICIAL" "$FREEBSD_GIT_MIRROR"; do
        if git ls-remote --heads "$r" "$FREEBSD_BRANCH" >/dev/null 2>&1; then
            echo "$r"; return 0
        fi
    done
    # last resort: mirror (documented fallback)
    echo "$FREEBSD_GIT_MIRROR"
}

if [ ! -d "$SRCDIR/.git" ]; then
    mkdir -p "$SRCDIR"
    git -C "$SRCDIR" init -q
fi

cd "$SRCDIR"
# Shallow-fetch just the pinned commit's tree (not the whole branch history --
# a full clone of freebsd-src is tens of GB; a single-commit shallow fetch is
# ~1-2GB). Falls back to the mirror if the official host rejects by-SHA fetch.
FETCHED=0
for REMOTE in "$FREEBSD_GIT_OFFICIAL" "$FREEBSD_GIT_MIRROR"; do
    git remote get-url origin >/dev/null 2>&1 && git remote remove origin
    git remote add origin "$REMOTE"
    if git fetch --depth 1 origin "$FREEBSD_COMMIT"; then
        FETCHED=1
        break
    fi
    echo ">> shallow fetch by commit failed from $REMOTE, trying next remote" >&2
done
[ "$FETCHED" = "1" ] || { echo "!! could not fetch pinned commit from any remote" >&2; exit 1; }
git checkout -q FETCH_HEAD

GOT=$(git rev-parse HEAD)
if [ "$GOT" != "$FREEBSD_COMMIT" ]; then
    echo "!! expected $FREEBSD_COMMIT but got $GOT" >&2
    exit 1
fi
echo ">> FreeBSD source ready at pinned commit $GOT"
