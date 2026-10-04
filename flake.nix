{
  description = "Nix packages and a Home Manager module for Frametop, a multi-screen Plasma desktop in VR on the Steam Frame";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    frametop = {
      url = "github:DeeJanuz/frametop";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      frametop,
    }:
    let
      inherit (nixpkgs) lib;
      # The Frame is aarch64-linux; x86_64-linux builds and evaluates the same derivations
      # for CI and for checking changes on a PC.
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      mkPackages =
        pkgs:
        let
          src = pkgs.callPackage ./packages/source.nix { inherit frametop; };
          vrclientDeps = import ./packages/vrclient-deps.nix { inherit (pkgs) libGL libuuid; };
          callPackage = lib.callPackageWith (pkgs // packages // { inherit src vrclientDeps; });
          packages = {
            frametop-src = src;
            ft-screens = callPackage ./packages/ft-screens.nix { };
            ft-pointer = callPackage ./packages/ft-pointer.nix { };
            ft-powerd = callPackage ./packages/ft-powerd.nix { };
            ft-pointer-driver = callPackage ./packages/ft-pointer-driver.nix { };
            # Everything: scripts, Python tools, settings apps, and the programs above.
            frametop-apps = callPackage ./packages/frametop.nix { };
            # The same without the settings apps (no Qt).
            frametop-scripts = callPackage ./packages/frametop.nix { withSettingsApps = false; };
          };
        in
        packages;
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          packages = mkPackages pkgs;
        in
        packages
        // {
          frametop = packages.frametop-apps;
          default = packages.frametop-apps;
        }
      );

      homeManagerModules.default = import ./hm-module.nix self;
      homeManagerModules.frametop = self.homeManagerModules.default;

      checks = forAllSystems (
        pkgs:
        let
          packages = self.packages.${pkgs.stdenv.hostPlatform.system};
        in
        {
          inherit (packages) ft-pointer-driver frametop-scripts;
          config-links =
            pkgs.runCommand "frametop-config-links-test"
              {
                nativeBuildInputs = [
                  (pkgs.python3.withPackages (ps: [
                    ps.pytest
                    ps.hypothesis
                  ]))
                ];
              }
              ''
                cp -r ${packages.frametop-src}/session session && chmod -R u+w session && cd session
                python3 -m pytest -q -p no:cacheprovider test_config_links.py
                touch $out
              '';
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
