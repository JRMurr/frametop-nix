# The copies the root parts need, as steamos-etc files: ft-eyegrab and ft-camd (with its
# capabilities) with their parts on, and neither with them off, so steamos-etc removes them.
#   nix eval --impure --expr "import ./checks/root-files.nix { }"   (true)
{
  system ? builtins.currentSystem,
  homeManager ? "github:nix-community/home-manager",
  steamosEtc ? "github:JRMurr/steamos-etc-nix",
}:
let
  frametop = builtins.getFlake ("git+file://" + toString ../. + "?shallow=1");
  home-manager = builtins.getFlake homeManager;
  steamos-etc = builtins.getFlake steamosEtc;
  files =
    parts:
    (home-manager.lib.homeManagerConfiguration {
      pkgs = frametop.inputs.nixpkgs.legacyPackages.${system};
      modules = [
        frametop.homeManagerModules.default
        steamos-etc.homeManagerModules.default
        {
          home.username = "steamos";
          home.homeDirectory = "/home/steamos";
          home.stateVersion = "25.11";
          programs.steamos-etc.enable = true;
          programs.frametop = {
            enable = true;
          }
          // parts;
        }
      ];
    }).config.programs.steamos-etc.files;
  on = files {
    gaze.enable = true;
    gaze.ownTracker.enable = true;
    hands.enable = true;
  };
  off = files { };
in
on."frametop/ft-eyegrab".mode == "0755"
&& on."frametop/ft-camd".mode == "0755"
&&
  on."frametop/ft-camd".capabilities == [
    "cap_sys_ptrace"
    "cap_perfmon"
    "cap_dac_read_search"
  ]
&& !(off ? "frametop/ft-eyegrab")
&& !(off ? "frametop/ft-camd")
