#!/usr/bin/env python3
"""patch-dwm.py - extra checked edits to dwm.c / config.h (called by patch-dwm.sh).

  1. gaps:   replaces tile() and monocle() with gap-aware versions and makes sure
             config.h defines `gappx` (8 px around and between tiled windows).
  2. power button: draws it in the normal bar colors (no accent-colored box).
  3. power icon:   shrinks the padded "  <icon>  " in config.h to just the icon.
  4. live key:     adds Super+Ctrl+Shift+W (dwm-live pick) to an existing config.h.
  5. empty-workspace animation: view() starts the dwm-flash ripple when the
             workspace you switch to has no windows.

Every edit looks for exact text first and says so if it is not found; nothing is
guessed. Files are backed up once as <file>.bak-le-dwm before the first change.
Safe to run repeatedly.

Usage: patch-dwm.py [path/to/dwm-source]   (default: ~/dwm)
"""
import os
import re
import shutil
import sys

SRC = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/dwm")
DWMC = os.path.join(SRC, "dwm.c")
CONFH = os.path.join(SRC, "config.h")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, text):
    bak = path + ".bak-le-dwm"
    if not os.path.exists(bak):
        shutil.copy2(path, bak)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


GAP_MARK = "/* le-dwm-config: gaps */"

NEW_TILE = GAP_MARK + r"""
void
tile(Monitor *m)
{
	unsigned int i, n, nm;
	int g = gappx, aw, mw, sw, sx = 0, my, ty, h;
	Client *c;

	for (n = 0, c = nexttiled(m->clients); c; c = nexttiled(c->next), n++);
	if (n == 0)
		return;

	nm = MIN(n, m->nmaster);
	aw = m->ww - 2 * g;                    /* width inside the outer gaps */
	if (nm && n > nm) {                    /* master column + stack column */
		mw = (int)((aw - g) * m->mfact);
		sw = aw - g - mw;
		sx = m->wx + g + mw + g;
	} else if (nm) {                       /* only master windows */
		mw = aw;
		sw = 0;
	} else {                               /* nmaster == 0: everything in the stack */
		mw = 0;
		sw = aw;
		sx = m->wx + g;
	}
	for (i = 0, my = ty = g, c = nexttiled(m->clients); c; c = nexttiled(c->next), i++)
		if (i < nm) {
			h = (m->wh - my - g - (int)(nm - i - 1) * g) / (int)(nm - i);
			resize(c, m->wx + g, m->wy + my, mw - 2 * c->bw, h - 2 * c->bw, 0);
			if (my + HEIGHT(c) + g < m->wh)
				my += HEIGHT(c) + g;
		} else {
			h = (m->wh - ty - g - (int)(n - i - 1) * g) / (int)(n - i);
			resize(c, sx, m->wy + ty, sw - 2 * c->bw, h - 2 * c->bw, 0);
			if (ty + HEIGHT(c) + g < m->wh)
				ty += HEIGHT(c) + g;
		}
}
"""

MONOCLE_OLD = "resize(c, m->wx, m->wy, m->ww - 2 * c->bw, m->wh - 2 * c->bw, 0);"
MONOCLE_NEW = ("resize(c, m->wx + gappx, m->wy + gappx, "
               "m->ww - 2 * c->bw - 2 * gappx, m->wh - 2 * c->bw - 2 * gappx, 0);")


def ensure_gappx():
    """Make sure config.h defines gappx. Returns True if it does."""
    cfg = read(CONFH)
    if re.search(r"\bgappx\b", cfg):
        return True
    line = ("static const int gappx              = 8;        "
            "/* gap around and between tiled windows */\n")
    for anchor in (r"^static const int bottompad.*\n", r"^static const unsigned int borderpx.*\n"):
        m = re.search(anchor, cfg, re.M)
        if m:
            write(CONFH, cfg[:m.end()] + line + cfg[m.end():])
            print("patch-dwm: added gappx = 8 to config.h")
            return True
    print("patch-dwm: could not place 'gappx' in config.h; add\n"
          "           static const int gappx = 8;\n"
          "           near the top of it, then run patch-dwm.sh again.", file=sys.stderr)
    return False


def patch_gaps():
    src = read(DWMC)
    if GAP_MARK in src and "m->wx + gappx" in src:
        ensure_gappx()   # dwm.c needs gappx even when config.h was restored from a backup
        print("patch-dwm: gaps already applied")
        return
    if "gappx" in src.replace(GAP_MARK, "") and GAP_MARK not in src:
        print("patch-dwm: dwm.c already mentions gappx (another gaps patch?); skipping gaps", file=sys.stderr)
        return
    if not ensure_gappx():
        return
    changed = False
    if GAP_MARK not in src:
        pat = re.compile(r"void\ntile\(Monitor \*m\)\n\{.*?\n\}\n", re.S)
        mt = pat.search(src)
        if mt and "m->nmaster" in mt.group(0):
            src = src[:mt.start()] + NEW_TILE + src[mt.end():]
            changed = True
        else:
            print("patch-dwm: could not find tile() in dwm.c; skipping gaps", file=sys.stderr)
            return
    if "m->wx + gappx" not in src:
        if src.count(MONOCLE_OLD) == 1:
            src = src.replace(MONOCLE_OLD, MONOCLE_NEW)
            changed = True
        else:
            print("patch-dwm: monocle() line not found; tiled gaps applied, monocle left as is",
                  file=sys.stderr)
    if changed:
        write(DWMC, src)
        print("patch-dwm: gaps applied")


def patch_power_button():
    src = read(DWMC)
    old = ("/* Clickable power button on the native dwm bar. */\n"
           "\tdrw_setscheme(drw, scheme[SchemeSel]);")
    new = old.replace("SchemeSel", "SchemeNorm")
    if old in src:
        write(DWMC, src.replace(old, new))
        print("patch-dwm: power button drawn without background")
    elif new in src:
        print("patch-dwm: power button background already removed")
    elif "powertext" in src:
        print("patch-dwm: power button drawing code differs from what I expect; left alone", file=sys.stderr)
    # no powertext at all: this dwm has no power button, nothing to do


def patch_power_text():
    if not os.path.exists(CONFH):
        return
    cfg = read(CONFH)
    pat = re.compile(r'(static const char powertext\[\]\s*=\s*)"[ \t]+(\S+)[ \t]+";')
    if pat.search(cfg):
        write(CONFH, pat.sub(lambda m: m.group(1) + '"' + m.group(2) + '";', cfg, count=1))
        print("patch-dwm: power icon padding removed in config.h")


def patch_live_key():
    cfg = read(CONFH)
    if "dwm-live" in cfg:
        return
    pat = re.compile(r'^\t\{ MODKEY\|ControlMask,\s+XK_w,\s+spawn,\s+SHCMD\("\$HOME/\.local/bin/dwm-wall random"\) \},\n', re.M)
    m = pat.search(cfg)
    if not m:
        print("patch-dwm: wallpaper keys not found in config.h; live-wallpaper key not added "
              "(add { MODKEY|ControlMask|ShiftMask, XK_w, spawn, SHCMD(\"$HOME/.local/bin/dwm-live pick\") }, yourself)",
              file=sys.stderr)
        return
    line = '\t{ MODKEY|ControlMask|ShiftMask, XK_w,      spawn,          SHCMD("$HOME/.local/bin/dwm-live pick") },\n'
    write(CONFH, cfg[:m.end()] + line + cfg[m.end():])
    print("patch-dwm: added Super+Ctrl+Shift+W (live wallpaper picker) to config.h")


FLASH_MARK = "/* le-dwm-config: empty-workspace flash */"

FLASH_BLOCK = (
    "\tarrange(selmon);\n"
    "\t" + FLASH_MARK + "\n"
    "\t{\n"
    "\t\tClient *fc;\n"
    "\t\tfor (fc = selmon->clients; fc && !ISVISIBLE(fc); fc = fc->next);\n"
    "\t\tif (!fc) {   /* nothing on this workspace: play the ripple (dwm-flash) */\n"
    "\t\t\tchar fx[16], fy[16], fw[16], fh[16];\n"
    "\t\t\tsnprintf(fx, sizeof fx, \"%d\", selmon->wx);\n"
    "\t\t\tsnprintf(fy, sizeof fy, \"%d\", selmon->wy);\n"
    "\t\t\tsnprintf(fw, sizeof fw, \"%d\", selmon->ww);\n"
    "\t\t\tsnprintf(fh, sizeof fh, \"%d\", selmon->wh);\n"
    "\t\t\tArg fa = { .v = (const char *[]){ \"/bin/sh\", \"-c\",\n"
    "\t\t\t\t\"exec \\\"$HOME/.local/bin/dwm-flash\\\" \\\"$@\\\" 2>/dev/null\", \"dwm-flash\",\n"
    "\t\t\t\tfx, fy, fw, fh, colors[SchemeSel][ColBorder], NULL } };\n"
    "\t\t\tspawn(&fa);\n"
    "\t\t}\n"
    "\t}\n"
)


def patch_flash():
    """Play a ripple when view() lands on a workspace with no windows."""
    src = read(DWMC)
    if FLASH_MARK in src:
        print("patch-dwm: empty-workspace animation already applied")
        return
    pat = re.compile(r"\nvoid\nview\(const Arg \*arg\)\n\{.*?\n\}\n", re.S)
    m = pat.search(src)
    if not m or m.group(0).count("\tarrange(selmon);\n") != 1 or "ColBorder" not in src:
        print("patch-dwm: view() in dwm.c differs from what I expect; empty-workspace "
              "animation not added", file=sys.stderr)
        return
    body = m.group(0).replace("\tarrange(selmon);\n", FLASH_BLOCK)
    write(DWMC, src[:m.start()] + body + src[m.end():])
    print("patch-dwm: empty-workspace animation added")


if not os.path.isfile(DWMC):
    print("patch-dwm.py: %s not found" % DWMC, file=sys.stderr)
    sys.exit(1)
if not os.path.isfile(CONFH):
    print("patch-dwm.py: %s not found" % CONFH, file=sys.stderr)
    sys.exit(1)

patch_gaps()
patch_power_button()
patch_power_text()
patch_live_key()
patch_flash()
