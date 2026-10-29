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
