#!/usr/bin/env bash
# install.sh - set up dwm + bars + themes + wallpaper manager on CachyOS/Arch.
#
# Run it without arguments for the menu:
#
#     ./install.sh
#
#     1) Install   fresh setup (or repair) - packages, dwm, bars, themes, session
#     2) Update    git pull + re-apply the setup (keeps your config.h)
#     3) Restart   restart dwm (windows stay open)
#     4) Quit
#
# It returns to the menu after Install and Update.
#
# Scripted use (old behaviour still works):
#   ./install.sh [path/to/wallpaper.jpg]   install directly
#   ./install.sh --install [wallpaper]     same
#   ./install.sh --update                  pull + re-apply
#   ./install.sh --restart                 restart dwm only
#
# Environment:
#   FORCE_CONFIG=1            replace an existing ~/dwm/config.h (it is backed up)
#   BAR_PRESET=minimal        first bar style (see: dwm-bar presets)
#   BAR_OPACITY=70            translucent bars, 10-100
#   ANIMATIONS=0              turn picom animations off
#   KITTY_OPACITY=0.9         terminal transparency, 1.0 = opaque
#   DWM_SKIP_PACKAGES=1       do not run pacman (used by Update)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DWM_SRC="$HOME/dwm"
BIN="$HOME/.local/bin"
CONF="$HOME/.config/dwm-theme"
WALL_DIR="$HOME/Pictures/wallpapers"
WALLPAPER="${1:-}"
KITTY_OPACITY="${KITTY_OPACITY:-0.85}"   # 1.0 = opaque; set before running to change

warn() { echo "!! $*" >&2; }
say() { printf '%s\n' "$*"; }

if [[ $EUID -eq 0 ]]; then
	echo "Run this as your normal user, not root (it uses sudo where needed)." >&2
	exit 1
fi

# ---------------------------------------------------------------- the work

install_packages() {
	[[ ${DWM_SKIP_PACKAGES:-0} == 1 ]] && { say "==> Skipping packages (DWM_SKIP_PACKAGES=1)"; return 0; }

	echo "==> Installing packages"
	sudo pacman -S --needed base-devel git libx11 libxft libxinerama libxext \
		xorg-server xorg-xinit xorg-xsetroot dmenu kitty firefox feh \
		brightnessctl wireplumber networkmanager network-manager-applet \
		blueman pavucontrol power-profiles-daemon libnotify \
		maim slop xclip thunar picom \
		|| { warn "core package installation failed"; return 1; }

	# Nice-to-haves: installed one at a time so a missing package cannot abort the rest
	echo "==> Installing optional packages (bars, fonts, icons, Thunar extras)"
	for pkg in polybar nsxiv ttf-jetbrains-mono-nerd papirus-icon-theme adwaita-icon-theme \
		thunar-archive-plugin thunar-volman file-roller gvfs tumbler ffmpegthumbnailer \
		noto-fonts xorg-xrdb python-pillow ffmpeg mpv rofi; do
		sudo pacman -S --needed --noconfirm "$pkg" || warn "could not install $pkg (skipping)"
	done

	if pacman -Qq dwm &>/dev/null; then
		warn "The packaged 'dwm' is installed. Remove it with: sudo pacman -R dwm"
	fi

	# the battery click opens this menu; on a desktop toolchain it may be absent
	if command -v powerprofilesctl >/dev/null 2>&1; then
		sudo systemctl enable --now power-profiles-daemon 2>/dev/null \
			|| warn "could not enable power-profiles-daemon (performance profiles may not work)"
	fi
}

install_dwm() {
	echo "==> Getting dwm source (version 6.5)"
	if [[ ! -d $DWM_SRC ]]; then
		git clone --branch 6.5 https://git.suckless.org/dwm "$DWM_SRC" \
			|| git clone https://git.suckless.org/dwm "$DWM_SRC" \
			|| { warn "could not clone dwm"; return 1; }
	fi

	# Never clobber an existing config.h (it may hold your own patches, e.g. systray or a power button).
	if [[ ! -f $DWM_SRC/config.h ]]; then
		cp "$REPO_DIR/config.h" "$DWM_SRC/config.h" \
			|| { warn "could not copy config.h"; return 1; }
	elif [[ ${FORCE_CONFIG:-0} == 1 ]]; then
		cp "$DWM_SRC/config.h" "$DWM_SRC/config.h.bak-dwm-$(date +%s)"
		cp "$REPO_DIR/config.h" "$DWM_SRC/config.h"
		echo "replaced $DWM_SRC/config.h with the repo's (old one saved as config.h.bak-dwm-*)"
	else
		echo "keeping your existing $DWM_SRC/config.h (FORCE_CONFIG=1 replaces it with the repo's)"
		grep -q 'bottompad' "$DWM_SRC/config.h" || warn "your config.h has no 'bottompad': the bottom bar will overlap windows"
		grep -q '#include "colors.h"' "$DWM_SRC/config.h" || warn "your config.h does not include colors.h: themes will not recolor dwm"
	fi
	[[ -f $DWM_SRC/colors.h ]] || cp "$REPO_DIR/colors.h" "$DWM_SRC/colors.h"
	"$REPO_DIR/patch-dwm.sh" "$DWM_SRC" \
		|| warn "some dwm patches were not applied: bars or status clicks may be missing"
}

install_scripts() {
	echo "==> Installing scripts to $BIN"
	mkdir -p "$BIN" || { warn "could not create $BIN"; return 1; }
	install -m755 "$REPO_DIR/dwmstatus.sh"    "$BIN/dwmstatus"     || return 1
	install -m755 "$REPO_DIR/dwm-keys"        "$BIN/dwm-keys"      || return 1
	install -m755 "$REPO_DIR/dwm-quit"        "$BIN/dwm-quit"      || return 1
	install -m755 "$REPO_DIR/dwm-theme"       "$BIN/dwm-theme"     || return 1
	install -m755 "$REPO_DIR/dwm-wall"        "$BIN/dwm-wall"      || return 1
	install -m755 "$REPO_DIR/dwm-live"        "$BIN/dwm-live"      || return 1
	install -m755 "$REPO_DIR/dwm-cpu"         "$BIN/dwm-cpu"       || return 1
	install -m755 "$REPO_DIR/dwm-bar"         "$BIN/dwm-bar"       || return 1
	install -m755 "$REPO_DIR/dwm-statusclick" "$BIN/dwm-statusclick" || return 1
	install -m755 "$REPO_DIR/dwm-perf"        "$BIN/dwm-perf"      || return 1
	install -m755 "$REPO_DIR/dwm-dock"        "$BIN/dwm-dock"      || return 1
	# ripple played when you switch to an empty workspace (a failed build only loses the effect)
	gcc -O2 -o "$BIN/dwm-flash" "$REPO_DIR/dwm-flash.c" -lX11 -lXext \
		|| warn "could not build dwm-flash: the empty-workspace animation will not play"
	command -v xwinwrap >/dev/null 2>&1 || warn "xwinwrap not found: live wallpapers need it (AUR: yay -S xwinwrap-git)"
	install -m755 "$REPO_DIR/dwm-palette"     "$BIN/dwm-palette"   || return 1
	install -m755 "$REPO_DIR/start-dwm"       "$BIN/start-dwm"     || return 1
	[[ -f $REPO_DIR/dwm-power-menu ]] && install -m755 "$REPO_DIR/dwm-power-menu" "$BIN/dwm-power-menu"
}

install_config() {
	echo "==> Installing themes and bar config"
	mkdir -p "$CONF/themes" "$HOME/.config/polybar" || return 1
	cp "$REPO_DIR"/themes/*.theme "$CONF/themes/" || return 1
	mkdir -p "$CONF/bar"
	cp "$REPO_DIR/polybar/config.ini.in" "$CONF/bar/polybar.ini.in" || return 1

	# bar layout/style (dwm-bar): writes bar.conf, barcfg.h for dwm, the polybar config,
	# picom.conf and the status icons. BAR_PRESET=classic|floating|minimal|dock|stacked|compact|plain
	# picks a first style; BAR_OPACITY and ANIMATIONS are remembered. Re-running keeps your saved style.
	echo "==> Bar style (floating top and bottom bars by default)"
	DWM_SRC="$DWM_SRC" "$BIN/dwm-bar" init || return 1
	DWM_SRC="$DWM_SRC" "$BIN/dwm-bar" gen  || return 1
}

install_wallpaper() {
	echo "==> Wallpapers ($WALL_DIR)"
	mkdir -p "$WALL_DIR"
	if [[ -n $WALLPAPER ]]; then
		cp "$WALLPAPER" "$WALL_DIR/" || warn "could not copy $WALLPAPER"
		"$BIN/dwm-wall" set "$WALL_DIR/$(basename "$WALLPAPER")" || true
	elif [[ -f $HOME/Pictures/wallpaper.jpg && -z $(ls -A "$WALL_DIR") ]]; then
		cp "$HOME/Pictures/wallpaper.jpg" "$WALL_DIR/"
		"$BIN/dwm-wall" set "$WALL_DIR/wallpaper.jpg" || true
	fi
}

install_theme() {
	echo "==> Applying theme and building dwm"
	local theme
	theme="${THEME:-$(cat "$CONF/current" 2>/dev/null || echo nord)}"
	DWM_SRC="$DWM_SRC" "$BIN/dwm-theme" set "$theme" --no-restart \
		|| { warn "dwm build failed, see $CONF/build.log"; return 1; }

	echo "==> Terminal theme (kitty)"
	local kc="$HOME/.config/kitty/kitty.conf"
	mkdir -p "$(dirname "$kc")"
	if [[ ! -f $kc ]]; then
		printf '%s\n' 'font_family JetBrainsMono Nerd Font' 'font_size 11.0' \
			'window_padding_width 6' 'include dwm-theme.conf' > "$kc"
	elif ! grep -q 'dwm-theme.conf' "$kc"; then
		printf '\n%s\n' 'include dwm-theme.conf' >> "$kc"
	fi
	if ! grep -q '^[[:space:]]*background_opacity' "$kc"; then
		printf '%s\n' "background_opacity $KITTY_OPACITY" >> "$kc"
	fi
	# picom.conf (translucent bars, rounded windows, animations) was written by dwm-bar
}

install_session() {
	echo "==> Installing session entry (for display managers)"
	sudo mkdir -p /usr/share/xsessions
	printf '%s\n' '[Desktop Entry]' 'Name=dwm' 'Comment=Dynamic window manager' \
		"Exec=$BIN/start-dwm" 'Type=Application' \
		| sudo tee /usr/share/xsessions/dwm.desktop >/dev/null \
		|| warn "could not write /usr/share/xsessions/dwm.desktop"

	echo "==> Writing ~/.xinitrc (for startx)"
	printf '%s\n' "exec $BIN/start-dwm" > "$HOME/.xinitrc"
	mkdir -p "$HOME/Pictures"
}

reload_status() {
	# restart the status loop so a new dwmstatus/dwm-statusclick pair is used right away.
	# dwmstatus is a shell script (process name "bash"), so match the command line.
	[[ -n ${DISPLAY:-} ]] || return 0
	if pgrep -f '(^|/)dwmstatus$' >/dev/null 2>&1; then
		pkill -f '(^|/)dwmstatus$' 2>/dev/null
		rm -f "${XDG_RUNTIME_DIR:-$HOME/.cache}/dwmstatus.pid"
		sleep 0.2
	fi
	setsid "$BIN/dwmstatus" >/dev/null 2>&1 &
}

install_all() {
	local wp="${1:-$WALLPAPER}"
	WALLPAPER=$wp
	install_packages || return 1
	install_dwm      || return 1
	install_scripts  || return 1
	install_config   || return 1
	install_wallpaper
	install_theme    || return 1
	install_session
	reload_status

	echo
	say "Done. Log out and choose the 'dwm' session, or run 'startx' from a TTY."
	say "Put wallpapers in $WALL_DIR, then use Super+Shift+W. Themes: Super+Shift+T."
	say "Click the WiFi, Bluetooth, volume and battery items in the top bar."
	say
	say "Tip: run this installer and choose Update every day or so to keep the dotfiles current."
}

update_all() {
	echo "==> Updating le-dwm-config"
	if git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		git -C "$REPO_DIR" pull --ff-only \
			|| { warn "git pull failed (local changes?). Nothing was installed."; return 1; }
	else
		warn "$REPO_DIR is not a git checkout; skipping git pull"
	fi
	DWM_SKIP_PACKAGES=1 install_all
}

restart_dwm() {
	if ! pgrep -x dwm >/dev/null 2>&1; then
		warn "dwm is not running; nothing to restart"
		return 1
	fi
	if [[ ${DWM_RESTARTABLE:-} == 1 ]] || pgrep -x start-dwm >/dev/null 2>&1; then
		echo "==> Restarting dwm (windows stay open)"
		pkill -TERM -x dwm && say "dwm restarted."
	else
		warn "dwm was not started by start-dwm; log out and back in to restart it"
		return 1
	fi
}

# ------------------------------------------------------------------- menu

menu_header() {
	echo
	echo "============================================================"
	echo "  le-dwm-config installer"
	echo "  Keep your dotfiles current: choose Update every day or so."
	echo "============================================================"
	echo "  1) Install    fresh setup / repair (packages, dwm, bars, themes)"
	echo "  2) Update     git pull + re-apply (keeps your config.h)"
	echo "  3) Restart    restart dwm, windows stay open"
	echo "  4) Quit"
	echo
}

menu_loop() {
	local choice
	while :; do
		menu_header
		read -r -p "Choose [1-4]: " choice || { echo; choice=4; }
		case ${choice,,} in
			1|install|i)
				install_all || warn "install did not finish cleanly (see above)"
				read -r -p "Press Enter to return to the menu..." _ || true
				;;
			2|update|u)
				update_all || warn "update did not finish cleanly (see above)"
				read -r -p "Press Enter to return to the menu..." _ || true
				;;
			3|restart|r)
				restart_dwm || true
				read -r -p "Press Enter to return to the menu..." _ || true
				;;
			4|quit|q)
				say "Bye. Come back soon for an update."
				return 0
				;;
			*)
				warn "please choose 1, 2, 3 or 4"
				;;
		esac
	done
}

usage() {
	sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'
}

# ------------------------------------------------------------------- main

case ${1:-} in
	"" )
		if [[ -t 0 && -t 1 ]]; then
			menu_loop
		else
			install_all
		fi
		;;
	--menu)    menu_loop ;;
	--install) shift; install_all "${1:-}" ;;
	--update)  update_all ;;
	--restart) restart_dwm ;;
	-h|--help) usage ;;
	*)
		# old behaviour: ./install.sh [wallpaper]
		install_all "$1"
		;;
esac
