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
          stb = pkgs.callPackage ./packages/stb.nix { };
          callPackage = lib.callPackageWith (pkgs // packages // { inherit src vrclientDeps stb; });
          packages = {
            frametop-src = src;
            ft-screens = callPackage ./packages/ft-screens.nix { };
            ft-pointer = callPackage ./packages/ft-pointer.nix { };
            ft-powerd = callPackage ./packages/ft-powerd.nix { };
            ft-pointer-driver = callPackage ./packages/ft-pointer-driver.nix { };
            ft-gaze = callPackage ./packages/ft-gaze.nix { };
            ft-eyegrab = callPackage ./packages/ft-eyegrab.nix { };
            ft-hands = callPackage ./packages/ft-hands.nix { };
            ft-camd = callPackage ./packages/ft-camd.nix { };
            ft-handpanel = callPackage ./packages/ft-handpanel.nix { };
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
          inherit (packages) ft-pointer-driver ft-gaze frametop-scripts;
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
          # The packaged tree runs gaze's and hand tracking's programs on the host
          # (FRAMETOP_HOST_BUILDS), and the gaze service idles (upstream's offline test, with
          # a fake ft-gaze).
          host-builds =
            pkgs.runCommand "frametop-host-builds-test"
              {
                nativeBuildInputs = [
                  (pkgs.python3.withPackages (ps: [
                    ps.pytest
                    ps.hypothesis
                  ]))
                ];
              }
              ''
                cp -r ${packages.frametop-scripts}/share/frametop/{gaze,hands} . && chmod -R u+w gaze hands
                export HOME=$TMPDIR

                (cd gaze
                  python3 -c 'import gazecal; assert gazecal.BUILDS == gazecal.Builds.HOST, gazecal.BUILDS'
                  python3 -m pytest -q -p no:cacheprovider test_gazecal_builds.py
                  python3 test/idle-test.py)

                grep -qF 'host_builds=''${FRAMETOP_HOST_BUILDS:-1}' hands/ft-cutouts
                python3 hands/tests/test_cutouts.py
                (cd hands/rec
                  python3 -c 'import session; assert session.BUILDS == session.Builds.HOST, session.BUILDS'
                  python3 tests/test_tracker_argv.py)
                touch $out
              '';
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
