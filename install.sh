#!/usr/bin/env bash
# install.sh - set up dwm (X11) or niri (Wayland) with bars, themes and wallpapers
# on CachyOS/Arch. Safe to re-run; it also updates an existing install.
#
#     ./install.sh            opens the menu (Install dwm / Install Niri / updates)
#     ./install.sh <image>    install dwm with that wallpaper (old behaviour)
#
# Scripted flags:
#     --install [image]   --update        dwm
#     --install-dwm       --update-dwm    dwm
#     --install-niri      --update-niri   niri
#     --menu              --restart       dwm restart
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DWM_SRC="$HOME/dwm"
BIN="$HOME/.local/bin"
CONF="$HOME/.config/dwm-theme"
NIRI_CONF="$HOME/.config/niri"
WAYBAR_CONF="$HOME/.config/waybar"
WALL_DIR="$HOME/Pictures/wallpapers"
WALLPAPER="${1:-}"
KITTY_OPACITY="${KITTY_OPACITY:-0.85}"   # 1.0 = opaque; set before running to change

warn() { echo "!! $*" >&2; }
say() { printf '%s\n' "$*"; }

if [[ $EUID -eq 0 ]]; then
	echo "Run this as your normal user, not root (it uses sudo where needed)." >&2
	exit 1
fi

# NixOS has no pacman and no /usr: programs come from the system configuration
# (nixos/le-dwm.nix), and dwm is built inside a small nix dev shell (le-devrun).
NIXOS=0
if [[ -e /etc/NIXOS ]] || grep -qx 'ID=nixos' /etc/os-release 2>/dev/null; then NIXOS=1; fi

# which kind of system this is: nixos, arch (Arch, CachyOS, Manjaro, EndeavourOS...) or other
distro() {
	if (( NIXOS )); then echo nixos; return; fi
	local id="" like=""
	if [[ -r /etc/os-release ]]; then
		id=$(. /etc/os-release; echo "${ID:-}")
		like=$(. /etc/os-release; echo "${ID_LIKE:-}")
	fi
	if [[ $id == arch || " $like " == *" arch "* ]] || command -v pacman >/dev/null 2>&1; then
		echo arch
	else
		echo other
	fi
}

nix_check() {   # nix_check <dwm|niri>
	local need c missing=()
	case $1 in
		dwm)  need="git python3 kitty dmenu feh picom polybar xrandr xsetroot xrdb maim xclip pgrep nix" ;;
		*)    need="git python3 kitty niri waybar swaybg mako fuzzel grim slurp wl-copy brightnessctl" ;;
	esac
	echo "==> NixOS detected: programs come from your system configuration, not from this installer"
	for c in $need; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
	if (( ${#missing[@]} )); then
		warn "missing programs: ${missing[*]}"
		say "   Add the le-dwm module to your NixOS config, then run: sudo nixos-rebuild switch"
		say "     imports = [ $REPO_DIR/nixos/le-dwm.nix ];"
		say "     programs.le-dwm.enable = true;"
		[[ $1 == niri ]] && say "     programs.le-dwm.niri.enable = true;"
		say "   (flake users: see the NixOS section of the README). Continuing; things may be missing."
	else
		say "   all needed programs are present"
	fi
	return 0
}

# ------------------------------------------------------------------ dwm (X11)

# Refresh the package databases before installing anything. Without this a stale
# database points at package versions the mirror has already deleted (HTTP 404).
sync_packages() {
	(( NIXOS )) && return 0
	if [[ ${DWM_SKIP_PACKAGES:-0} == 1 ]]; then
		say "==> Skipping package sync (DWM_SKIP_PACKAGES=1)"
		return 0
	fi
	echo "==> Syncing package databases and upgrading (pacman -Syu)"
	if ! sudo pacman -Syu; then
		warn "pacman -Syu failed; package installs may still hit 404s. Fix your mirrors, then re-run."
		return 1
	fi
}

install_packages() {
	if (( NIXOS )); then nix_check dwm; return 0; fi
	if [[ ${DWM_SKIP_PACKAGES:-0} == 1 ]]; then
		say "==> Skipping packages (DWM_SKIP_PACKAGES=1)"
		return 0
	fi

	sync_packages || warn "continuing with the existing package databases"

	echo "==> Installing packages"
	sudo pacman -S --needed base-devel git libx11 libxft libxinerama libxext \
		xorg-server xorg-xinit xorg-xsetroot dmenu kitty firefox feh \
		brightnessctl wireplumber networkmanager maim slop xclip thunar picom

	# Nice-to-haves: installed one at a time so a missing package cannot abort the rest
	echo "==> Installing optional packages (bars, fonts, icons, Thunar extras)"
	for pkg in polybar nsxiv ttf-jetbrains-mono-nerd papirus-icon-theme adwaita-icon-theme \
		thunar-archive-plugin thunar-volman file-roller gvfs tumbler ffmpegthumbnailer \
		noto-fonts xorg-xrdb python-pillow ffmpeg mpv rofi \
		nm-connection-editor pavucontrol blueman bluez-utils power-profiles-daemon; do
		sudo pacman -S --needed --noconfirm "$pkg" || warn "could not install $pkg (skipping)"
	done

	if pacman -Qq dwm &>/dev/null; then
		warn "The packaged 'dwm' is installed. Remove it with: sudo pacman -R dwm"
	fi
}

install_dwm_source() {
	echo "==> Getting dwm source (version 6.5)"
	if [[ ! -d $DWM_SRC ]]; then
		git clone --branch 6.5 https://git.suckless.org/dwm "$DWM_SRC" \
			|| git clone https://git.suckless.org/dwm "$DWM_SRC"
	fi
	# Never clobber an existing config.h (it may hold your own patches, e.g. systray or a power button).
	if [[ ! -f $DWM_SRC/config.h ]]; then
		cp "$REPO_DIR/config.h" "$DWM_SRC/config.h"
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
		|| warn "bottom-bar patch not applied: the bottom bar will overlap windows"
}

install_dwm_scripts() {
	echo "==> Installing scripts to $BIN"
	mkdir -p "$BIN"
	install -m755 "$REPO_DIR/le-devrun"    "$BIN/le-devrun"
	if (( NIXOS )); then   # build shell for dwm (C compiler + X11 headers), see le-devrun
		mkdir -p "$CONF/nixenv"
		cmp -s "$REPO_DIR/nix/devshell/flake.nix" "$CONF/nixenv/flake.nix" \
			|| cp "$REPO_DIR/nix/devshell/flake.nix" "$CONF/nixenv/flake.nix"
	fi
	install -m755 "$REPO_DIR/dwmstatus.sh" "$BIN/dwmstatus"
	install -m755 "$REPO_DIR/dwm-keys"     "$BIN/dwm-keys"
	install -m755 "$REPO_DIR/dwm-quit"     "$BIN/dwm-quit"
	install -m755 "$REPO_DIR/dwm-theme"    "$BIN/dwm-theme"
	install -m755 "$REPO_DIR/dwm-wall"     "$BIN/dwm-wall"
	install -m755 "$REPO_DIR/dwm-live"     "$BIN/dwm-live"
	install -m755 "$REPO_DIR/dwm-cpu"      "$BIN/dwm-cpu"
	install -m755 "$REPO_DIR/dwm-uptime"   "$BIN/dwm-uptime"
	install -m755 "$REPO_DIR/dwm-bar"      "$BIN/dwm-bar"
	install -m755 "$REPO_DIR/dwm-dock"     "$BIN/dwm-dock"
	install -m755 "$REPO_DIR/dwm-status-click" "$BIN/dwm-status-click"
	install -m755 "$REPO_DIR/dwm-menu"     "$BIN/dwm-menu"
	install -m755 "$REPO_DIR/dwm-display"  "$BIN/dwm-display"
	install -m755 "$REPO_DIR/dwm-settings" "$BIN/dwm-settings"
	install -m755 "$REPO_DIR/dwm-doctor"   "$BIN/dwm-doctor"
	# ripple played when you switch to an empty workspace (a failed build only loses the effect)
	"$BIN/le-devrun" gcc -O2 -o "$BIN/dwm-flash" "$REPO_DIR/dwm-flash.c" -lX11 -lXext \
		|| warn "could not build dwm-flash: the empty-workspace animation will not play"
	command -v xwinwrap >/dev/null 2>&1 || warn "xwinwrap not found: live wallpapers need it (AUR: yay -S xwinwrap-git)"
	install -m755 "$REPO_DIR/dwm-palette"  "$BIN/dwm-palette"
	install -m755 "$REPO_DIR/start-dwm"    "$BIN/start-dwm"
	[[ -f $REPO_DIR/dwm-power-menu ]] && install -m755 "$REPO_DIR/dwm-power-menu" "$BIN/dwm-power-menu"
	return 0
}

install_dwm_config() {
	echo "==> Installing themes and bar config"
	mkdir -p "$CONF/themes" "$HOME/.config/polybar"
	cp "$REPO_DIR"/themes/*.theme "$CONF/themes/"
	mkdir -p "$CONF/bar"
	cp "$REPO_DIR/polybar/config.ini.in" "$CONF/bar/polybar.ini.in"
	# bar layout/style (dwm-bar): writes bar.conf, barcfg.h for dwm, the polybar config, picom.conf
	# and the status icons. BAR_PRESET=classic|floating|minimal|dock|stacked|compact|plain picks a first style;
	# BAR_OPACITY and ANIMATIONS are remembered. Re-running keeps your saved style.
	echo "==> Bar style (dwm-bar)"
	DWM_SRC="$DWM_SRC" "$BIN/dwm-bar" init
	DWM_SRC="$DWM_SRC" "$BIN/dwm-bar" gen
}

install_dwm_wallpaper() {
	echo "==> Wallpapers ($WALL_DIR)"
	mkdir -p "$WALL_DIR"
	local was_empty=0
	[[ -z $(ls -A "$WALL_DIR" 2>/dev/null) ]] && was_empty=1
	# the wallpaper shipped with the config stays available even if you add your own
	local bundled="$HOME/.local/share/le-dwm-config/wallpapers"
	mkdir -p "$bundled"
	if [[ -d $REPO_DIR/wallpapers ]]; then
		cp -n "$REPO_DIR"/wallpapers/* "$bundled"/ 2>/dev/null || true
		cp -n "$REPO_DIR"/wallpapers/* "$WALL_DIR"/ 2>/dev/null || true
	fi
	if [[ -n $WALLPAPER ]]; then
		cp "$WALLPAPER" "$WALL_DIR/"
		"$BIN/dwm-wall" set "$WALL_DIR/$(basename "$WALLPAPER")" || true
	elif [[ -f $HOME/Pictures/wallpaper.jpg && $was_empty == 1 ]]; then
		cp "$HOME/Pictures/wallpaper.jpg" "$WALL_DIR/"
		"$BIN/dwm-wall" set "$WALL_DIR/wallpaper.jpg" || true
	elif [[ -f $bundled/coastline.jpg && $was_empty == 1 ]]; then
		"$BIN/dwm-wall" set "$bundled/coastline.jpg" || true
	fi
}

install_dwm_theme() {
	echo "==> Applying theme and building dwm"
	local theme="${THEME:-$(cat "$CONF/current" 2>/dev/null || echo nord)}"
	DWM_SRC="$DWM_SRC" "$BIN/dwm-theme" set "$theme" --no-restart

	# dwm must exist and start before we point a login session at it: a missing dwm is a grey screen.
	echo "==> Checking the dwm build"
	local build_ok=1 version=""
	if "$BIN/le-devrun" make -C "$DWM_SRC" PREFIX="$HOME/.local" clean install >"$CONF/build.log" 2>&1; then
		# dwm -v prints its version but exits with status 1, so do not use a
		# pipeline here: with pipefail that always looked like a failed build.
		version="$("$BIN/dwm" -v 2>&1 || true)"
		[[ $version == dwm-* ]] && build_ok=0
	fi
	if (( build_ok != 0 )); then
		echo
		echo "!! dwm did NOT build, so I am not setting up the login session (you would get a grey screen)."
		echo "!! Last lines of $CONF/build.log:"
		tail -n 25 "$CONF/build.log" | sed 's/^/   /'
		echo
		echo "Send me those lines, or run:  bash $REPO_DIR/dwm-doctor"
		return 1
	fi
	echo "dwm built: $version"

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

	# picom.conf (translucent bars, rounded windows, animations) was written by dwm-bar above

	# battery menu: power-profiles-daemon must be running (CachyOS may already provide an equivalent)
	if (( ! NIXOS )) && command -v powerprofilesctl >/dev/null 2>&1 && ! powerprofilesctl get >/dev/null 2>&1; then
		sudo systemctl enable --now power-profiles-daemon 2>/dev/null \
			|| warn "could not start power-profiles-daemon (battery menu needs it)"
	fi
}

install_dwm_session() {
	if (( NIXOS )); then
		echo "==> Session entry: provided by the NixOS module (shows up as 'le-dwm' on the login screen)"
	else
		echo "==> Installing session entry (for display managers)"
		sudo mkdir -p /usr/share/xsessions
		printf '%s\n' '[Desktop Entry]' 'Name=dwm' 'Comment=Dynamic window manager' \
			"Exec=$BIN/start-dwm" 'Type=Application' \
			| sudo tee /usr/share/xsessions/dwm.desktop >/dev/null
	fi

	echo "==> Writing ~/.xinitrc (for startx)"
	printf '%s\n' "exec $BIN/start-dwm" > "$HOME/.xinitrc"

	mkdir -p "$HOME/Pictures"
}

install_dwm_all() {
	install_packages
	install_dwm_source
	install_dwm_scripts
	install_dwm_config
	install_dwm_wallpaper
	install_dwm_theme || return 1
	install_dwm_session

	echo
	if (( NIXOS )); then
		echo "Done. Log out and choose the 'le-dwm' session (needs programs.le-dwm.enable = true; in your NixOS config)."
	else
		echo "Done. Log out and choose the 'dwm' session, or run 'startx' from a TTY."
	fi
	echo "If the screen ever stays grey/black: Ctrl+Alt+F3, log in, run  bash $REPO_DIR/dwm-doctor  (log: ~/.local/state/dwm/session.log)."
	echo "Put wallpapers in $WALL_DIR, then use Super+Shift+W (pictures and live wallpapers). Themes: Super+Shift+T."
	echo "Settings (display, theme, bar, wallpaper, gaps, opacity): Super+Shift+D, or the gear on the bottom bar."
}

# --------------------------------------------------------------- niri (Wayland)

install_niri_packages() {
	if (( NIXOS )); then nix_check niri; return 0; fi
	if [[ ${DWM_SKIP_PACKAGES:-0} == 1 ]]; then
		say "==> Skipping packages (DWM_SKIP_PACKAGES=1)"
		return 0
	fi

	echo "==> Installing niri packages"
	sync_packages || warn "continuing with the existing package databases"
	local pkg failed=0
	for pkg in niri waybar swaybg mako fuzzel grim slurp wl-clipboard \
		brightnessctl xdg-desktop-portal-gtk; do
		if ! sudo pacman -S --needed --noconfirm "$pkg"; then
			warn "could not install $pkg"
			# niri is the session itself; the rest can be added later.
			[[ $pkg == niri ]] && failed=1
		fi
	done

	# nice-to-haves, installed one at a time
	for pkg in swaylock swayidle xdg-desktop-portal-gnome qt5-wayland qt6-wayland; do
		sudo pacman -S --needed --noconfirm "$pkg" || warn "could not install $pkg (skipping)"
	done
	return $failed
}

install_niri_scripts() {
	echo "==> Installing niri scripts to $BIN"
	mkdir -p "$BIN"
	install -m755 "$REPO_DIR/niri-theme" "$BIN/niri-theme"
	install -m755 "$REPO_DIR/niri-wall"  "$BIN/niri-wall"
	install -m755 "$REPO_DIR/niri-dock"  "$BIN/niri-dock"
	install -m755 "$REPO_DIR/niri-bars"  "$BIN/niri-bars"
	install -m755 "$REPO_DIR/niri-keys"  "$BIN/niri-keys"
}

# replace a managed file but keep one backup of the previous version
install_managed() {
	local src=$1 dst=$2
	[[ -r $src ]] || { warn "missing $src"; return 1; }
	if [[ -f $dst ]] && ! cmp -s "$src" "$dst"; then
		cp "$dst" "$dst.bak-niri" 2>/dev/null || true
	fi
	mkdir -p "$(dirname "$dst")"
	cp "$src" "$dst"
}

install_niri_config() {
	echo "==> Installing niri config, waybar bars and themes"
	mkdir -p "$NIRI_CONF" "$WAYBAR_CONF" "$HOME/.config/mako" "$HOME/Pictures/Screenshots"

	install_managed "$REPO_DIR/niri/config.kdl"                "$NIRI_CONF/config.kdl"
	install_managed "$REPO_DIR/niri/waybar/config-top.jsonc"   "$WAYBAR_CONF/config-top.jsonc"
	install_managed "$REPO_DIR/niri/waybar/style-top.css"      "$WAYBAR_CONF/style-top.css"
	install_managed "$REPO_DIR/niri/waybar/style-bottom.css"   "$WAYBAR_CONF/style-bottom.css"

	# themes are shared with dwm (niri-theme reads the same .theme files)
	mkdir -p "$CONF/themes"
	cp "$REPO_DIR"/themes/*.theme "$CONF/themes/" || warn "could not copy themes"

	# dock config: seed the app list and generate the bottom bar config
	"$BIN/niri-dock" generate || warn "could not generate the dock config"

	# generate colors.kdl, colors.css and the mako config from the saved theme
	"$BIN/niri-theme" init || warn "could not apply the niri theme"
}

install_niri() {
	install_niri_packages || return 1
	install_niri_scripts
	install_niri_config

	command -v waybar >/dev/null 2>&1 \
		|| warn "waybar is not installed: the bars will not start (sudo pacman -S waybar)"

	echo
	echo "Done. Log out and choose the 'niri' session on the login screen."
	(( NIXOS )) && echo "(On NixOS niri comes from programs.le-dwm.niri.enable = true; or programs.niri.enable = true;.)"
	echo "The top bar shows workspaces, window title and status; the dock is at the bottom."
	echo "Super+P opens the launcher/dock menu, Super+Shift+T themes, Super+Shift+W wallpapers."
	echo "Niri reloads ~/.config/niri/config.kdl automatically when you save it."
}

# ------------------------------------------------------------------- updates

pull_repo() {
	if git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		git -C "$REPO_DIR" pull --ff-only \
			|| { warn "git pull failed (local changes?). Nothing was installed."; return 1; }
	else
		warn "$REPO_DIR is not a git checkout; skipping git pull"
	fi
}

# Ask whether to update the whole system too (always yes when not on a terminal).
# SKIP_SYSTEM_UPDATE=1 turns the system part off.
want_system_update() {   # want_system_update "<what will run>"
	[[ ${SKIP_SYSTEM_UPDATE:-0} == 1 ]] && return 1
	[[ -t 0 && -t 1 ]] || return 0
	local a
	read -r -p "Also update the system packages ($1)? [Y/n] " a || return 1
	[[ ${a,,} != n* ]]
}

# NixOS: refresh the le-dwm input of the system flake, then switch to the new generation.
nixos_system_update() {
	local dir="${NIXOS_FLAKE:-/etc/nixos}"
	local nixcmd=(sudo nix --extra-experimental-features 'nix-command flakes')
	echo "==> NixOS: updating the system ($dir)"
	if [[ -f $dir/flake.nix ]]; then
		if grep -q 'le-dwm' "$dir/flake.nix"; then
			"${nixcmd[@]}" flake update le-dwm --flake "$dir" \
				|| { warn "could not update the le-dwm flake input (is the latest release pushed to GitHub?)"; return 1; }
		else
			warn "$dir/flake.nix has no le-dwm input; only rebuilding (see the NixOS section of the README)"
		fi
		sudo nixos-rebuild switch --flake "$dir" || { warn "nixos-rebuild failed (see above)"; return 1; }
	else
		sudo nix-channel --update 2>/dev/null || true
		sudo nixos-rebuild switch || { warn "nixos-rebuild failed (see above)"; return 1; }
	fi
}

# update_flow <dwm|niri>: pull the dotfiles, update the system the way this distro does it, re-apply
update_flow() {
	local kind=$1 apply
	[[ $kind == dwm ]] && apply=install_dwm_all || apply=install_niri
	echo "==> Updating le-dwm-config ($kind)"
	pull_repo || return 1
	case $(distro) in
		nixos)
			if want_system_update "nix flake update + nixos-rebuild switch"; then
				nixos_system_update || warn "system update did not finish; continuing with the dotfiles"
			fi
			$apply
			;;
		arch)
			# the install functions run pacman -Syu and install anything new
			if want_system_update "sudo pacman -Syu"; then
				$apply
			else
				DWM_SKIP_PACKAGES=1 $apply
			fi
			;;
		*)
			warn "unknown distro: only the dotfiles are updated, not the system packages"
			DWM_SKIP_PACKAGES=1 $apply
			;;
	esac
}

update_dwm()  { update_flow dwm; }
update_niri() { update_flow niri; }

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

# ---------------------------------------------------------------------- menu

menu_header() {
	echo
	echo "============================================================"
	echo "  le-dwm-config installer"
	echo "  dwm on X11 or niri on Wayland - same look and keys."
	echo "  Keep your dotfiles current: choose Update every day or so."
	(( NIXOS )) && echo "  NixOS detected: programs come from nixos/le-dwm.nix (see README)."
	echo "============================================================"
	echo "  1) Install dwm    packages, dwm, bars, themes, session"
	echo "  2) Install Niri   niri, waybar bars, dock, themes"
	echo "  3) Update dwm     git pull + system update + re-apply (keeps your config.h)"
	echo "  4) Update Niri    git pull + system update + re-apply the niri config"
	case $(distro) in
		nixos) echo "                    (system update here = nix flake update + nixos-rebuild switch)" ;;
		arch)  echo "                    (system update here = pacman -Syu)" ;;
	esac
	echo "  5) Restart dwm    restart dwm, windows stay open"
	echo "  6) Quit"
	echo
}

menu_loop() {
	local choice
	while :; do
		menu_header
		read -r -p "Choose [1-6]: " choice || { echo; choice=6; }
		case ${choice,,} in
			1|install|i|dwm)
				WALLPAPER=""
				install_dwm_all || warn "dwm install did not finish cleanly (see above)"
				read -r -p "Press Enter to return to the menu..." _ || true
				;;
			2|niri|install-niri)
				install_niri || warn "niri install did not finish cleanly (see above)"
				read -r -p "Press Enter to return to the menu..." _ || true
				;;
			3|update|u|update-dwm)
				update_dwm || warn "dwm update did not finish cleanly (see above)"
				read -r -p "Press Enter to return to the menu..." _ || true
				;;
			4|update-niri)
				update_niri || warn "niri update did not finish cleanly (see above)"
				read -r -p "Press Enter to return to the menu..." _ || true
				;;
			5|restart|r)
				restart_dwm || true
				read -r -p "Press Enter to return to the menu..." _ || true
				;;
			6|quit|q)
				say "Bye. Come back soon for an update."
				return 0
				;;
			*)
				warn "please choose 1, 2, 3, 4, 5 or 6"
				;;
		esac
	done
}

usage() {
	cat <<'EOF'
install.sh - set up dwm (X11) or niri (Wayland) on CachyOS/Arch.

Without arguments (on a terminal) this opens a menu:
  1) Install dwm     packages, dwm, bars, themes, session
  2) Install Niri    niri, waybar top bar, bottom dock, swaybg, mako, themes
  3) Update dwm      git pull, system update, re-apply (keeps your config.h)
  4) Update Niri     git pull, system update, re-apply the niri config
  5) Restart dwm
  6) Quit

Scripted use:
  ./install.sh [wallpaper]        install dwm directly
  ./install.sh --install [wp]     same
  ./install.sh --update           pull + re-apply dwm
  ./install.sh --restart          restart dwm
  ./install.sh --install-dwm      install/repair dwm
  ./install.sh --update-dwm       update dwm
  ./install.sh --install-niri     install/repair niri
  ./install.sh --update-niri      update niri

NixOS is detected automatically: packages are not installed by this script. Add the module in
nixos/le-dwm.nix to your system config (README, "NixOS"), then run this installer as usual.

Environment:
  FORCE_CONFIG=1              replace an existing ~/dwm/config.h (backed up)
  DWM_SKIP_PACKAGES=1         do not run pacman
  SKIP_SYSTEM_UPDATE=1        updates only the dotfiles, not the system (pacman -Syu / nixos-rebuild)
  NIXOS_FLAKE=/path           NixOS system flake directory (default /etc/nixos)
  THEME=<name>                theme for a fresh install
EOF
}

# ---------------------------------------------------------------------- main

case ${1:-} in
	"" )
		if [[ -t 0 && -t 1 ]]; then
			menu_loop
		else
			install_dwm_all
		fi
		;;
	--menu)         menu_loop ;;
	--install)      shift; WALLPAPER="${1:-}"; install_dwm_all ;;
	--install-dwm)  shift; WALLPAPER="${1:-}"; install_dwm_all ;;
	--update|--update-dwm) update_dwm ;;
	--restart)      restart_dwm ;;
	--install-niri|--niri) install_niri ;;
	--update-niri)  update_niri ;;
	-h|--help)      usage ;;
	*)
		# old behaviour: ./install.sh [wallpaper] installs dwm
		WALLPAPER="$1"
		install_dwm_all
		;;
esac
