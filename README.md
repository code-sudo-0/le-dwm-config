# le-dwm-config

My dwm setup for CachyOS (Arch): Super as the modifier, Nord-style colors, a
status bar with a running cat, a keybind cheat sheet, and PipeWire/brightness keys.

## Files

| File | Purpose |
| --- | --- |
| `config.h` | dwm 6.5 config |
| `dwmstatus.sh` | status bar (cat, CPU, RAM, Wi-Fi, brightness, volume, battery, clock) |
| `dwm-keys` | keybind cheat sheet shown in dmenu |
| `install.sh` | one-step setup |

## Install

```
git clone https://github.com/code-sudo-0/le-dwm-config.git
cd le-dwm-config
./install.sh ~/Pictures/wallpaper.jpg
```

Then log out and pick the **dwm** session, or run `startx` from a TTY.

If the packaged `dwm` is installed it can shadow the build: `sudo pacman -R dwm`.

## Keys (Super = modifier)

`Super+Shift+/` opens the full cheat sheet. The basics:

- `Super+Enter` terminal, `Super+P` launcher, `Super+W` Firefox, `Super+E` Thunar
- `Super+J/K` focus, `Super+H/L` resize master, `Super+Shift+C` close
- `Super+1-9` tags, `Super+Shift+1-9` move window to tag
- `Super+T/F/M` tiled/floating/monocle
- `Super+Shift+S` region screenshot to clipboard, `Print` full screenshot to `~/Pictures`
- `Super+Shift+Q` quit dwm

## Changing the config

Edit `~/dwm/config.h`, then `cd ~/dwm && sudo make clean install` and restart dwm.
Copy the file back here to keep the repo current.

## Notes

- dwm is X11 only. Foot is Wayland-only, so the terminal is alacritty.
- Tearing was not an issue on an Intel UHD (i3-N305) laptop. If you see it,
  run `picom --backend glx --vsync &` from `start-dwm`.
