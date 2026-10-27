#!/usr/bin/env bash
# patch-dwm.sh - reserve space at the bottom of the screen for polybar.
#
# Stock dwm only reserves room for its own bar. This changes one line in
# dwm.c (updatebarpos) so windows stop `bottompad` pixels above the bottom
# edge. `bottompad` is defined in config.h.
#
# Usage: patch-dwm.sh [path/to/dwm-source]   (default: ~/dwm)
# Safe to run repeatedly; it refuses to guess if the line is not found.
set -euo pipefail

SRC="${1:-$HOME/dwm}"
F="$SRC/dwm.c"

[[ -f $F ]] || { echo "patch-dwm: $F not found" >&2; exit 1; }

if grep -q 'm->wh = m->mh - bottompad;' "$F"; then
	echo "patch-dwm: already applied"
	exit 0
fi

if ! grep -q $'^\tm->wh = m->mh;$' "$F"; then
	echo "patch-dwm: could not find 'm->wh = m->mh;' in updatebarpos()." >&2
	echo "           This dwm.c differs from 6.5; the bottom bar will overlap windows." >&2
	echo "           Change that line by hand to: m->wh = m->mh - bottompad;" >&2
	exit 1
fi

sed -i 's/^\tm->wh = m->mh;$/\tm->wh = m->mh - bottompad;/' "$F"
echo "patch-dwm: applied (bottompad reserved in updatebarpos)"
