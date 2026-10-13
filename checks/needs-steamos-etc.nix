# Without steamos-etc, the parts that need root fail with an assertion that says so: this
# fails to evaluate, naming programs.steamos-etc.
#   nix eval --impure --expr "import ./checks/needs-steamos-etc.nix { }"
{
  system ? builtins.currentSystem,
  homeManager ? "github:nix-community/home-manager",
}:
let
  frametop = builtins.getFlake ("git+file://" + toString ../. + "?shallow=1");
  home-manager = builtins.getFlake homeManager;
in
(home-manager.lib.homeManagerConfiguration {
  pkgs = frametop.inputs.nixpkgs.legacyPackages.${system};
  modules = [
    frametop.homeManagerModules.default
    {
      home.username = "steamos";
      home.homeDirectory = "/home/steamos";
      home.stateVersion = "25.11";
      programs.frametop.enable = true;
      programs.frametop.hands.enable = true;
    }
  ];
}).activationPackage.drvPath
