#!/usr/bin/env bash
# install.sh - set up dwm + bars + themes + wallpaper manager on CachyOS/Arch
# Usage: ./install.sh [path/to/wallpaper.jpg]
# Safe to re-run; it also updates an existing install.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DWM_SRC="$HOME/dwm"
BIN="$HOME/.local/bin"
CONF="$HOME/.config/dwm-theme"
WALL_DIR="$HOME/Pictures/wallpapers"
WALLPAPER="${1:-}"
KITTY_OPACITY="${KITTY_OPACITY:-0.85}"   # 1.0 = opaque; set before running to change
BAR_OPACITY="${BAR_OPACITY:-75}"         # top/bottom bars, percent (100 = opaque)

warn() { echo "!! $*" >&2; }

if [[ $EUID -eq 0 ]]; then
	echo "Run this as your normal user, not root (it uses sudo where needed)." >&2
	exit 1
fi

echo "==> Installing packages"
sudo pacman -S --needed base-devel git libx11 libxft libxinerama \
	xorg-server xorg-xinit xorg-xsetroot dmenu kitty firefox feh \
	brightnessctl wireplumber networkmanager maim slop xclip thunar picom

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

echo "==> Installing scripts to $BIN"
mkdir -p "$BIN"
install -m755 "$REPO_DIR/dwmstatus.sh" "$BIN/dwmstatus"
install -m755 "$REPO_DIR/dwm-keys"     "$BIN/dwm-keys"
install -m755 "$REPO_DIR/dwm-quit"     "$BIN/dwm-quit"
install -m755 "$REPO_DIR/dwm-theme"    "$BIN/dwm-theme"
install -m755 "$REPO_DIR/dwm-wall"     "$BIN/dwm-wall"
install -m755 "$REPO_DIR/dwm-live"     "$BIN/dwm-live"
command -v xwinwrap >/dev/null 2>&1 || warn "xwinwrap not found: live wallpapers need it (AUR: yay -S xwinwrap-git)"
install -m755 "$REPO_DIR/dwm-palette"  "$BIN/dwm-palette"
install -m755 "$REPO_DIR/start-dwm"    "$BIN/start-dwm"
[[ -f $REPO_DIR/dwm-power-menu ]] && install -m755 "$REPO_DIR/dwm-power-menu" "$BIN/dwm-power-menu"

echo "==> Installing themes and bar config"
mkdir -p "$CONF/themes" "$HOME/.config/polybar"
cp "$REPO_DIR"/themes/*.theme "$CONF/themes/"
if [[ -f $HOME/.config/polybar/config.ini ]] && ! grep -q 'install.sh copies this' "$HOME/.config/polybar/config.ini"; then
	[[ -f $HOME/.config/polybar/config.ini.bak-dwm ]] || cp "$HOME/.config/polybar/config.ini" "$HOME/.config/polybar/config.ini.bak-dwm"
fi
sed "s|@HOME@|$HOME|g" "$REPO_DIR/polybar/config.ini.in" > "$HOME/.config/polybar/config.ini"

echo "==> Wallpapers ($WALL_DIR)"
mkdir -p "$WALL_DIR"
if [[ -n $WALLPAPER ]]; then
	cp "$WALLPAPER" "$WALL_DIR/"
	"$BIN/dwm-wall" set "$WALL_DIR/$(basename "$WALLPAPER")" || true
elif [[ -f $HOME/Pictures/wallpaper.jpg && -z $(ls -A "$WALL_DIR") ]]; then
	cp "$HOME/Pictures/wallpaper.jpg" "$WALL_DIR/"
	"$BIN/dwm-wall" set "$WALL_DIR/wallpaper.jpg" || true
fi

echo "==> Applying theme and building dwm"
THEME="${THEME:-$(cat "$CONF/current" 2>/dev/null || echo nord)}"
DWM_SRC="$DWM_SRC" "$BIN/dwm-theme" set "$THEME" --no-restart

echo "==> Terminal theme (kitty)"
KC="$HOME/.config/kitty/kitty.conf"
mkdir -p "$(dirname "$KC")"
if [[ ! -f $KC ]]; then
	printf '%s\n' 'font_family JetBrainsMono Nerd Font' 'font_size 11.0' \
		'window_padding_width 6' 'include dwm-theme.conf' > "$KC"
elif ! grep -q 'dwm-theme.conf' "$KC"; then
	printf '\n%s\n' 'include dwm-theme.conf' >> "$KC"
fi
if ! grep -q '^[[:space:]]*background_opacity' "$KC"; then
	printf '%s\n' "background_opacity $KITTY_OPACITY" >> "$KC"
fi

echo "==> Compositor (picom: needed for terminal transparency on X11)"
PC="$HOME/.config/picom/picom.conf"
mkdir -p "$(dirname "$PC")"
if [[ -f $PC ]] && ! grep -q 'generated by le-dwm-config' "$PC"; then
	[[ -f $PC.bak-dwm ]] || cp "$PC" "$PC.bak-dwm"
fi
# Animations (Hyprland-style open/close pop and smooth tiling moves) need picom 12 or newer;
# an older picom rejects the option and would not start at all, so check first.
# Turn them off with: ANIMATIONS=0 ./install.sh
ANIM_BLOCK=""
if [[ ${ANIMATIONS:-1} == 1 ]]; then
	PICOM_MAJOR=$(picom --version 2>/dev/null | grep -oE '[0-9]+' | head -n1 || true)
	if [[ ${PICOM_MAJOR:-0} -ge 12 ]]; then
		ANIM_BLOCK='# animations (picom 12+). Durations are in seconds; lower = snappier.
animations = (
  {
    triggers = [ "open", "show" ];
    preset = "appear";
    scale = 0.9;
    duration = 0.2;
  },
  {
    triggers = [ "close", "hide" ];
    preset = "disappear";
    scale = 0.9;
    duration = 0.15;
  },
  {
    triggers = [ "geometry" ];
    preset = "geometry-change";
    duration = 0.2;
  }
);'
	else
		warn "picom ${PICOM_MAJOR:-?} is too old for animations (needs 12+); skipping them"
	fi
fi
cat > "$PC" <<PICOM
# generated by le-dwm-config install.sh (edit freely; re-running the installer overwrites it)
backend = "glx";
vsync = true;
shadow = false;
fading = false;
# translucent bars (percent, 100 = opaque). dwm's top bar has class "dwm", polybar "Polybar".
opacity-rule = [
  "$BAR_OPACITY:class_g = 'dwm'",
  "$BAR_OPACITY:class_g = 'Polybar'"
];
$ANIM_BLOCK
PICOM

echo "==> Installing session entry (for display managers)"
sudo mkdir -p /usr/share/xsessions
printf '%s\n' '[Desktop Entry]' 'Name=dwm' 'Comment=Dynamic window manager' \
	"Exec=$BIN/start-dwm" 'Type=Application' \
	| sudo tee /usr/share/xsessions/dwm.desktop >/dev/null

echo "==> Writing ~/.xinitrc (for startx)"
printf '%s\n' "exec $BIN/start-dwm" > "$HOME/.xinitrc"

mkdir -p "$HOME/Pictures"
echo
echo "Done. Log out and choose the 'dwm' session, or run 'startx' from a TTY."
echo "Put wallpapers in $WALL_DIR, then use Super+Shift+W (pictures and live wallpapers). Themes: Super+Shift+T."
