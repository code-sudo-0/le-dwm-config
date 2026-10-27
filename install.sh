#!/usr/bin/env bash
# install.sh - set up dwm + status bar + session entry on CachyOS/Arch
# Usage: ./install.sh [path/to/wallpaper.jpg]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DWM_SRC="$HOME/dwm"
BIN="$HOME/.local/bin"
WALLPAPER="${1:-$HOME/Pictures/wallpaper.jpg}"

if [[ $EUID -eq 0 ]]; then
	echo "Run this as your normal user, not root (it uses sudo where needed)." >&2
	exit 1
fi

echo "==> Installing packages"
sudo pacman -S --needed base-devel git libx11 libxft libxinerama \
	xorg-server xorg-xinit xorg-xsetroot dmenu alacritty firefox feh \
	brightnessctl wireplumber networkmanager

if pacman -Qq dwm &>/dev/null; then
	echo "!! The packaged 'dwm' is installed and may shadow your build."
	echo "   Remove it with: sudo pacman -R dwm"
fi

echo "==> Building dwm from source (version 6.5)"
if [[ ! -d $DWM_SRC ]]; then
	git clone --branch 6.5 https://git.suckless.org/dwm "$DWM_SRC" \
		|| git clone https://git.suckless.org/dwm "$DWM_SRC"
fi
cp "$REPO_DIR/config.h" "$DWM_SRC/config.h"
( cd "$DWM_SRC" && sudo make clean install )

echo "==> Installing scripts to $BIN"
mkdir -p "$BIN"
install -m755 "$REPO_DIR/dwmstatus.sh" "$BIN/dwmstatus"
install -m755 "$REPO_DIR/dwm-keys" "$BIN/dwm-keys"

cat > "$BIN/start-dwm" <<SCRIPT
#!/bin/sh
[ -f "$WALLPAPER" ] && feh --bg-fill "$WALLPAPER" &
"$BIN/dwmstatus" &
exec /usr/local/bin/dwm
SCRIPT
chmod +x "$BIN/start-dwm"

echo "==> Installing session entry (for display managers)"
sudo mkdir -p /usr/share/xsessions
printf '%s\n' '[Desktop Entry]' 'Name=dwm' 'Comment=Dynamic window manager' \
	"Exec=$BIN/start-dwm" 'Type=Application' \
	| sudo tee /usr/share/xsessions/dwm.desktop >/dev/null

echo "==> Writing ~/.xinitrc (for startx)"
printf '%s\n' "exec $BIN/start-dwm" > "$HOME/.xinitrc"

echo
echo "Done. Log out and choose the 'dwm' session, or run 'startx' from a TTY."
[[ -f $WALLPAPER ]] || echo "Note: no wallpaper at $WALLPAPER - rerun with a path, e.g. ./install.sh ~/Pictures/wall.jpg"
