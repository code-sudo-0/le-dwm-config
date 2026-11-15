# NixOS support for le-dwm-config. The dotfiles themselves are installed with ./install.sh;
# this flake only provides the NixOS module (programs, fonts, login sessions) and the dwm
# build shell. See nixos/le-dwm.nix and the NixOS section of the README.
{
  description = "le-dwm-config: dwm (X11) and niri (Wayland) desktop";

  outputs = { self }: {
    nixosModules.default = import ./nixos/le-dwm.nix;
    nixosModules.le-dwm = self.nixosModules.default;
  };
}
