#!/usr/bin/env bash
# patch-dwm.sh - two small, checked edits to dwm.c.
#
#  1. bottom bar room (needed): stock dwm only reserves space for its own bar.
#     This changes one line in updatebarpos() so windows stop `bottompad` pixels
#     above the bottom edge. `bottompad` is defined in config.h.
#  2. plain window title (cosmetic): stock dwm paints the whole title area in the
#     accent color on the focused monitor. This draws it in the normal bar colors
#     so only the selected tag is highlighted, which looks cleaner.
#
# Usage: patch-dwm.sh [path/to/dwm-source]   (default: ~/dwm)
# Safe to run repeatedly. If a line is not found it says so instead of guessing;
# exit status is 1 only when the required patch (1) could not be applied.
set -uo pipefail

SRC="${1:-$HOME/dwm}"
F="$SRC/dwm.c"
[[ -f $F ]] || { echo "patch-dwm: $F not found" >&2; exit 1; }

rc=0

# --- 1. bottom bar room -------------------------------------------------
if grep -qF 'le-dwm-config: bar layout' "$F"; then
	echo "patch-dwm: bar room handled by the bar layout patch"
elif grep -qF 'm->wh = m->mh - bottompad;' "$F"; then
	echo "patch-dwm: bottom bar room already applied"
elif grep -q $'^\tm->wh = m->mh;$' "$F"; then
	sed -i 's/^\tm->wh = m->mh;$/\tm->wh = m->mh - bottompad;/' "$F"
	echo "patch-dwm: bottom bar room applied"
else
	echo "patch-dwm: could not find 'm->wh = m->mh;' in updatebarpos()." >&2
	echo "           This dwm.c differs from 6.5; the bottom bar will overlap windows." >&2
	echo "           Change that line by hand to: m->wh = m->mh - bottompad;" >&2
	rc=1
fi

# --- 2. plain window title ----------------------------------------------
OLD='drw_setscheme(drw, scheme[m == selmon ? SchemeSel : SchemeNorm]);'
NEW='drw_setscheme(drw, scheme[SchemeNorm]);'
if grep -qF "$OLD" "$F"; then
	sed -i 's/drw_setscheme(drw, scheme\[m == selmon ? SchemeSel : SchemeNorm\]);/drw_setscheme(drw, scheme[SchemeNorm]);/' "$F"
	echo "patch-dwm: plain window title applied"
elif grep -qF 'if (m->sel) {' "$F" && ! grep -qF "$OLD" "$F"; then
	echo "patch-dwm: window title line not found (or already changed); skipping the cosmetic patch" >&2
fi

# --- 3. gaps, power button look (python; all non-fatal) -------------------
if command -v python3 >/dev/null 2>&1; then
	python3 "$(dirname "$(readlink -f "$0")")/patch-dwm.py" "$SRC" \
		|| echo "patch-dwm: gaps/power-button patch reported a problem (see above)" >&2
else
	echo "patch-dwm: python3 not found; skipping gaps and power-button tweaks" >&2
fi

exit $rc
