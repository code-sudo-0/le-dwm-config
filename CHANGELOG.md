# Changelog

## Unreleased (releases are named by date and patch, e.g. 2026-10-28-patch1)

- dwm 6.x config with Nerd Font tag icons, kitty terminal, Thunar, screenshots, media keys.
- Top bar status (cat, online/offline, Bluetooth, volume, brightness, battery, clock) and a
  polybar bottom bar; both translucent through picom (default 75%).
- Theme switcher (`dwm-theme`, Super+Shift+T): Nord, Gruvbox, Catppuccin Mocha/Latte,
  Tokyo Night, Dracula for dwm, polybar, GTK/Thunar, kitty and dmenu.
- Wallpaper manager (`dwm-wall`, Super+Shift+W / Super+Ctrl+W).
- Quit confirmation (Super+Shift+Q) and a themed power menu for the top-bar power button.
- Window gaps (8px), icon-only power button (`patch-dwm.py`).
- picom: kitty transparency, translucent bars, open/close and tiling-move animations.
- Installer keeps an existing `~/dwm/config.h`; `release.sh` publishes releases.
- 11 more themes: Rose Pine (+ Dawn), Everforest, Solarized Dark, One Dark, Kanagawa, Ayu Mirage, GitHub Dark,
  Catppuccin Frappe/Macchiato, Gruvbox Light.
- Theme from wallpaper: `dwm-theme from-image` (images and videos), `dwm-wall auto on|off`; unchanged colors
  no longer trigger a dwm rebuild.
- `dwm-live`: live wallpaper manager (xwinwrap + mpv) with theme-from-video and login restore via `dwm-wall restore`.
- `dwm-live`: key Super+Ctrl+Shift+W and a middle-click on the bottom bar's wallpaper button open the live-wallpaper picker.
- Wallpaper picker (Super+Shift+W): centered rofi window with cached previews of pictures and live wallpapers; choosing applies it and recolors the theme.
- Bottom bar shows resources as used/total (CPU threads `1.6/8`, RAM and disk in GB) instead of percentages.
- Empty-workspace animation: a ripple (`dwm-flash`) plays when you switch to a workspace with no windows.
  Opt out with `touch ~/.config/dwm-theme/no-flash`.
- picom animations a little slower (open/move 0.28s, close 0.22s).
- `dwm-theme` rebuilds dwm when `dwm.c` or `config.h` are newer than the installed binary, even if the colors did not change.
