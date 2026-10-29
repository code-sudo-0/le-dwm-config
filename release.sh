#!/usr/bin/env bash
# release.sh - commit, push, tag and publish a GitHub release of this repo.
#
# Usage: ./release.sh ["what changed"]
#
# Releases are named by date and patch number, not version numbers:
#   2026-10-28-patch1, 2026-10-28-patch2, ... (the number restarts each day)
# No notes -> GitHub writes them from the commits since the last release.
#
# One-time setup so it can create the release for you (no tokens to paste):
#   sudo pacman -S github-cli && gh auth login
# Without gh it still commits, pushes and tags, then tells you how to finish
# the release on github.com (Releases -> Draft a new release -> pick the tag).
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "release.sh: not inside a git repo" >&2; exit 1; }
branch=$(git symbolic-ref --short HEAD)
notes=${1:-}

git fetch --tags -q origin 2>/dev/null || true
today=$(date +%F)
n=1
while git rev-parse -q --verify "refs/tags/$today-patch$n" >/dev/null; do n=$((n + 1)); done
tag="$today-patch$n"

echo "==> Releasing $tag from branch $branch"
git add -A
if ! git diff --cached --quiet; then
	git commit -q -m "${notes:-Release $tag}"
	echo "    committed changes"
else
	echo "    nothing new to commit"
fi

git push origin "$branch"
git tag -a "$tag" -m "Release $tag"
git push origin "$tag"

asset="$(mktemp -d)/le-dwm-config-$tag.tar.gz"
git archive --format=tar.gz --prefix=le-dwm-config/ -o "$asset" "$tag"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
	args=(release create "$tag" "$asset" --title "le-dwm-config $today patch $n" --generate-notes)
	[[ -n $notes ]] && args+=(--notes "$notes")
	gh "${args[@]}"
	echo "==> Release published."
else
	echo "==> Pushed and tagged $tag, but gh is not set up, so no release was created."
	echo "    Either run: sudo pacman -S github-cli && gh auth login   (then re-run for the next release)"
	echo "    or on github.com: Releases -> Draft a new release -> choose tag $tag -> attach:"
	echo "    $asset"
fi
