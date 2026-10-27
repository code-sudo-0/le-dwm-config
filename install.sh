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

warn() { echo "!! $*" >&2; }

if [[ $EUID -eq 0 ]]; then
	echo "Run this as your normal user, not root (it uses sudo where needed)." >&2
	exit 1
fi

echo "==> Installing packages"
sudo pacman -S --needed base-devel git libx11 libxft libxinerama \
	xorg-server xorg-xinit xorg-xsetroot dmenu alacritty firefox feh \
	brightnessctl wireplumber networkmanager maim slop xclip thunar

# Nice-to-haves: installed one at a time so a missing package cannot abort the rest
echo "==> Installing optional packages (bars, fonts, icons, Thunar extras)"
for pkg in polybar nsxiv ttf-jetbrains-mono-nerd papirus-icon-theme adwaita-icon-theme \
	thunar-archive-plugin thunar-volman file-roller gvfs tumbler ffmpegthumbnailer \
	noto-fonts xorg-xrdb; do
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
cp "$REPO_DIR/config.h" "$DWM_SRC/config.h"
[[ -f $DWM_SRC/colors.h ]] || cp "$REPO_DIR/colors.h" "$DWM_SRC/colors.h"
"$REPO_DIR/patch-dwm.sh" "$DWM_SRC" \
	|| warn "bottom-bar patch not applied: the bottom bar will overlap windows"

echo "==> Installing scripts to $BIN"
mkdir -p "$BIN"
install -m755 "$REPO_DIR/dwmstatus.sh" "$BIN/dwmstatus"
install -m755 "$REPO_DIR/dwm-keys"     "$BIN/dwm-keys"
install -m755 "$REPO_DIR/dwm-theme"    "$BIN/dwm-theme"
install -m755 "$REPO_DIR/dwm-wall"     "$BIN/dwm-wall"
install -m755 "$REPO_DIR/start-dwm"    "$BIN/start-dwm"

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

echo "==> Terminal theme (alacritty)"
AL="$HOME/.config/alacritty/alacritty.toml"
mkdir -p "$(dirname "$AL")"
if [[ ! -f $AL ]]; then
	printf '%s\n' '[general]' 'import = ["~/.config/alacritty/dwm-theme.toml"]' '' \
		'[font]' 'size = 10' '[font.normal]' 'family = "JetBrainsMono Nerd Font"' > "$AL"
elif grep -q 'dwm-theme.toml' "$AL"; then
	:
elif grep -q '^\[general\]' "$AL"; then
	warn "add this line under [general] in $AL to theme your terminal:"
	warn '    import = ["~/.config/alacritty/dwm-theme.toml"]'
else
	printf '\n%s\n%s\n' '[general]' 'import = ["~/.config/alacritty/dwm-theme.toml"]' >> "$AL"
fi

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
echo "Put wallpapers in $WALL_DIR, then use Super+Shift+W. Themes: Super+Shift+T."
