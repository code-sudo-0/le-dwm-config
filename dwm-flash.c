/* dwm-flash.c - a soft ripple that plays in the middle of the screen when you
 * switch to an empty workspace. dwm starts it (see patch-dwm.py); it can also be
 * run by hand to preview the effect:
 *
 *     dwm-flash <x> <y> <w> <h> [#rrggbb] [milliseconds]
 *
 * x y w h = the area to center on (the monitor's usable area). The ring expands
 * and fades out; with picom running it is genuinely translucent, without a
 * compositor you just get a ring that grows and disappears.
 *
 * Build: gcc -O2 -o dwm-flash dwm-flash.c -lX11 -lXext
 * Opt out: touch ~/.config/dwm-theme/no-flash
 */
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <X11/extensions/shape.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static double
now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

/* only one ripple at a time: stop the previous one (its window dies with it) */
static void
single_instance(void)
{
	char path[256], comm[64], cpath[64];
	const char *rt = getenv("XDG_RUNTIME_DIR");
	FILE *f;
	long old = 0;

	if (rt && *rt)
		snprintf(path, sizeof path, "%s/dwm-flash.pid", rt);
	else
		snprintf(path, sizeof path, "/tmp/dwm-flash-%d.pid", (int)getuid());

	if ((f = fopen(path, "r"))) {
		if (fscanf(f, "%ld", &old) != 1)
			old = 0;
		fclose(f);
		if (old > 1 && old != (long)getpid()) {
			snprintf(cpath, sizeof cpath, "/proc/%ld/comm", old);
			if ((f = fopen(cpath, "r"))) {
				if (fgets(comm, sizeof comm, f) && strncmp(comm, "dwm-flash", 9) == 0)
					kill((pid_t)old, SIGTERM);
				fclose(f);
			}
		}
	}
	if ((f = fopen(path, "w"))) {
		fprintf(f, "%d\n", (int)getpid());
		fclose(f);
	}
}

int
main(int argc, char *argv[])
{
	Display *dpy;
	Window win;
	Colormap cmap;
	XColor xc;
	XSetWindowAttributes wa;
	XClassHint ch = { "dwm-flash", "dwm-flash" };
	GC gc;
	Atom opacity;
	const char *color = argc > 5 ? argv[5] : "#88c0d0";
	double dur = argc > 6 ? atof(argv[6]) : 600;
	int ax, ay, aw, ah, maxs, mins, mapped = 0, ev, er;
	const char *home = getenv("HOME");
	char flag[512];

	if (argc < 5)
		return 1;
	ax = atoi(argv[1]); ay = atoi(argv[2]); aw = atoi(argv[3]); ah = atoi(argv[4]);
	if (aw <= 0 || ah <= 0)
		return 1;
	if (dur < 150) dur = 150;
	if (dur > 3000) dur = 3000;

	if (home) {
		snprintf(flag, sizeof flag, "%s/.config/dwm-theme/no-flash", home);
		if (access(flag, F_OK) == 0)
			return 0;
	}

	if (!(dpy = XOpenDisplay(NULL)))
		return 0;
	if (!XShapeQueryExtension(dpy, &ev, &er))
		return 0;   /* no way to draw a ring: skip quietly */

	single_instance();

	maxs = (aw < ah ? aw : ah) / 3;
	if (maxs > 360) maxs = 360;
	if (maxs < 160) maxs = 160;
	mins = maxs * 40 / 100;

	cmap = DefaultColormap(dpy, DefaultScreen(dpy));
	if (!XParseColor(dpy, cmap, color, &xc) || !XAllocColor(dpy, cmap, &xc)) {
		xc.pixel = WhitePixel(dpy, DefaultScreen(dpy));
	}

	wa.override_redirect = True;
	wa.background_pixel = xc.pixel;
	wa.border_pixel = 0;
	wa.event_mask = 0;
	win = XCreateWindow(dpy, DefaultRootWindow(dpy), ax, ay, mins, mins, 0,
		CopyFromParent, InputOutput, CopyFromParent,
		CWOverrideRedirect | CWBackPixel | CWBorderPixel | CWEventMask, &wa);
	XSetClassHint(dpy, win, &ch);
	/* clicks fall straight through the ripple */
	XShapeCombineRectangles(dpy, win, ShapeInput, 0, 0, NULL, 0, ShapeSet, 0);
	opacity = XInternAtom(dpy, "_NET_WM_WINDOW_OPACITY", False);

	for (;;) {
		static double t0 = -1;
		double t, e, inv, a;
		int s, th, x, y;
		Pixmap pm;
		unsigned long op;

		if (t0 < 0)
			t0 = now_ms();
		t = (now_ms() - t0) / dur;
		if (t >= 1.0)
			break;

		inv = 1.0 - t;
		e = 1.0 - inv * inv * inv;                 /* ease-out */
		s = mins + (int)((maxs - mins) * e);
		th = 3 + (int)(s * 0.07 * inv);            /* ring thins as it grows */
		a = 0.85 * inv * inv;                      /* fades out */
		op = (unsigned long)(a * 0xffffffffUL);
		x = ax + (aw - s) / 2;
		y = ay + (ah - s) / 2;

		pm = XCreatePixmap(dpy, win, s, s, 1);
		gc = XCreateGC(dpy, pm, 0, NULL);
		XSetForeground(dpy, gc, 0);
		XFillRectangle(dpy, pm, gc, 0, 0, s, s);
		XSetForeground(dpy, gc, 1);
		XFillArc(dpy, pm, gc, 0, 0, s - 1, s - 1, 0, 360 * 64);
		XSetForeground(dpy, gc, 0);
		XFillArc(dpy, pm, gc, th, th, s - 1 - 2 * th, s - 1 - 2 * th, 0, 360 * 64);

		XMoveResizeWindow(dpy, win, x, y, s, s);
		XShapeCombineMask(dpy, win, ShapeBounding, 0, 0, pm, ShapeSet);
		XChangeProperty(dpy, win, opacity, XA_CARDINAL, 32, PropModeReplace,
			(unsigned char *)&op, 1);
		if (!mapped) {
			XMapRaised(dpy, win);
			mapped = 1;
		}
		XFreeGC(dpy, gc);
		XFreePixmap(dpy, pm);
		XFlush(dpy);
		usleep(12000);   /* ~60-80 frames per second */
	}

	XDestroyWindow(dpy, win);
	XSync(dpy, False);
	XCloseDisplay(dpy);
	return 0;
}
