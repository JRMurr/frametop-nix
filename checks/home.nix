# A Home Manager configuration with all of programs.frametop on, for CI: building its
# activation package evaluates the module and builds everything it links, for this
# machine's system. The root parts go through steamos-etc.
#   nix build --impure -f checks/home.nix
# Impure: it reads this checkout as a flake, and takes home-manager's and steamos-etc's
# current main.
{
  system ? builtins.currentSystem,
  homeManager ? "github:nix-community/home-manager",
  steamosEtc ? "github:JRMurr/steamos-etc-nix",
}:
let
  frametop = builtins.getFlake ("git+file://" + toString ../. + "?shallow=1");
  home-manager = builtins.getFlake homeManager;
  steamos-etc = builtins.getFlake steamosEtc;
in
(home-manager.lib.homeManagerConfiguration {
  pkgs = frametop.inputs.nixpkgs.legacyPackages.${system};
  modules = [
    frametop.homeManagerModules.default
    steamos-etc.homeManagerModules.default
    {
      home.username = "steamos";
      home.homeDirectory = "/home/steamos";
      home.stateVersion = "25.11";
      targets.genericLinux.enable = true;
      programs.steamos-etc.enable = true;
      programs.frametop = {
        enable = true;
        gaze.enable = true;
        gaze.ownTracker.enable = true;
        hands.enable = true;
        hands.recorder.enable = true;
        bluetooth.enable = true;
      };
    }
  ];
}).activationPackage
