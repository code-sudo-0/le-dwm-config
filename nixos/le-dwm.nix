# NixOS module for le-dwm-config.
#
# It installs everything the dotfiles expect (programs, fonts, a login session for dwm, niri) so
# that ./install.sh can do the rest as your normal user. The config files themselves
# (~/.config/niri, ~/.config/polybar, ~/dwm ...) are still written by install.sh, so themes and
# the bar style can be changed at runtime with Super+Shift+T and friends, like on any other distro.
#
# Use it (pick one):
#
#   # flake-based system
#   inputs.le-dwm.url = "github:code-sudo-0/le-dwm-config";
#   ... modules = [ le-dwm.nixosModules.default { programs.le-dwm.enable = true; } ];
#
#   # classic /etc/nixos/configuration.nix
#   imports = [ /home/<you>/le-dwm-config/nixos/le-dwm.nix ];
#   programs.le-dwm.enable = true;
#
# then: sudo nixos-rebuild switch   and   ./install.sh   (it detects NixOS).
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.le-dwm;

  # first attribute path that exists (nixpkgs renamed xorg.xrdb to xrdb and so on)
  pick = names:
    lib.foldr
      (n: rest:
        let v = lib.attrByPath (lib.splitString "." n) null pkgs;
        in if v != null then v else rest)
      (throw "le-dwm: none of these exist in nixpkgs: ${toString names}")
      names;

  # optional: skipped when this nixpkgs does not have it
  maybe = name: lib.optional (lib.hasAttr name pkgs) pkgs.${name};

  common = [
    pkgs.git
    (pkgs.python3.withPackages (ps: [ ps.pillow ]))
    pkgs.kitty
    pkgs.firefox
    (pick [ "thunar" "xfce.thunar" ])
    pkgs.brightnessctl
    pkgs.wireplumber
    pkgs.networkmanagerapplet
    pkgs.blueman
    pkgs.power-profiles-daemon
    pkgs.pavucontrol
    pkgs.libnotify
    pkgs.file
    pkgs.pciutils
    pkgs.ffmpeg
    pkgs.imagemagick
    pkgs.mpv
    pkgs.rofi
    pkgs.papirus-icon-theme
    pkgs.adwaita-icon-theme
    pkgs.xdg-utils
  ];

  x11 = [
    pkgs.dmenu
    pkgs.picom
    pkgs.polybar
    pkgs.feh
    pkgs.maim
    pkgs.slop
    pkgs.xclip
    pkgs.nsxiv
    (pick [ "xrandr" "xorg.xrandr" ])
    (pick [ "xsetroot" "xorg.xsetroot" ])
    (pick [ "xrdb" "xorg.xrdb" ])
    (pick [ "xmessage" "xorg.xmessage" ])
  ] ++ maybe "xwinwrap";   # live wallpapers; not in every nixpkgs

  wayland = [
    pkgs.waybar
    pkgs.swaybg
    pkgs.mako
    pkgs.fuzzel
    pkgs.grim
    pkgs.slurp
    pkgs.wl-clipboard
    pkgs.swaylock
    pkgs.swayidle
    pkgs.xdg-desktop-portal-gtk
    # le-dock (GTK4 dock), menu previews and icons
    pkgs.gtk4
    pkgs.gtk4-layer-shell
    pkgs.gobject-introspection
    (pkgs.python3.withPackages (ps: [ ps.pygobject3 ps.pycairo ps.pillow ]))
    pkgs.papirus-icon-theme
  ];

  jetbrainsNerd =
    if pkgs ? nerd-fonts then pkgs.nerd-fonts.jetbrains-mono
    else pkgs.nerdfonts.override { fonts = [ "JetBrainsMono" ]; };
in
{
  options.programs.le-dwm = {
    enable = lib.mkEnableOption "the programs, fonts and login sessions le-dwm-config needs";

    dwm.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "dwm (X11): packages and a login session that runs ~/.local/bin/start-dwm.";
    };

    niri.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "niri (Wayland): niri, waybar, the dock and launcher tools.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = common;
      # dwm-wall, dwm-theme and the other scripts live in ~/.local/bin
      environment.localBinInPath = lib.mkDefault true;
      fonts.packages = [ jetbrainsNerd pkgs.noto-fonts ];

      # the click targets on the bars: network, bluetooth and the power profile menu.
      # Each one is mkDefault, so `services.x.enable = false;` in your own config wins.
      networking.networkmanager.enable = lib.mkDefault true;
      hardware.bluetooth.enable = lib.mkDefault true;
      services.blueman.enable = lib.mkDefault true;
      services.power-profiles-daemon.enable = lib.mkDefault true;
      services.upower.enable = lib.mkDefault true;

      # Sound: the bar and pavucontrol expect PipeWire (or PulseAudio). Enable one in your own
      # config if you have not, e.g.  services.pipewire = { enable = true; pulse.enable = true; };
    }

    (lib.mkIf cfg.dwm.enable {
      environment.systemPackages = x11;
      services.xserver.enable = true;
      # shows up as "le-dwm" on the login screen; start-dwm is installed by ./install.sh
      services.xserver.windowManager.session = [
        {
          name = "le-dwm";
          start = ''
            exec "$HOME/.local/bin/start-dwm"
          '';
        }
      ];
    })

    (lib.mkIf cfg.niri.enable {
      programs.niri.enable = true;
      environment.systemPackages = wayland;
    })
  ]);
}
