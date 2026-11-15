# Build environment for dwm and dwm-flash (a C compiler plus the X11 headers).
# Used by le-devrun on NixOS; install.sh copies this file to ~/.config/dwm-theme/nixenv/.
{
  description = "le-dwm-config: C toolchain and X11 headers for building dwm";

  # "nixpkgs" resolves through the flake registry, which NixOS points at the system's nixpkgs.
  inputs.nixpkgs.url = "nixpkgs";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # first attribute path that exists (nixpkgs renamed xorg.libX11 to libx11 and so on)
      pick = pkgs: names:
        pkgs.lib.foldr
          (n: rest:
            let v = pkgs.lib.attrByPath (pkgs.lib.splitString "." n) null pkgs;
            in if v != null then v else rest)
          (throw "none of these exist in nixpkgs: ${toString names}")
          names;
    in {
      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.gcc pkgs.gnumake pkgs.pkg-config ];
          buildInputs = [
            (pick pkgs [ "libx11" "xorg.libX11" ])
            (pick pkgs [ "libxft" "xorg.libXft" ])
            (pick pkgs [ "libxinerama" "xorg.libXinerama" ])
            (pick pkgs [ "libxext" "xorg.libXext" ])
            pkgs.freetype
            pkgs.fontconfig
          ];
          shellHook = ''
            export LE_DEVRUN_INNER=1
            # dwm's config.mk looks for freetype in /usr/include/freetype2, which NixOS does not have
            export NIX_CFLAGS_COMPILE="''${NIX_CFLAGS_COMPILE:-} -isystem ${pkgs.freetype.dev}/include/freetype2"
          '';
        };
      });
    };
}
