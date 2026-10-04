# frametop-nix

Nix packages and a Home Manager module for [Frametop](https://github.com/DeeJanuz/frametop). Not part of upstream: this repo pins an upstream commit and carries its own patches (see [Patches](#patches)).

The flake builds Frametop with nixpkgs instead of the Fedora `dev` container. A Home Manager module then sets up what `install.sh` sets up. This is for a Steam Frame (SteamOS, aarch64-linux, not NixOS) with Nix and standalone Home Manager.

It covers the multi-screen desktop, the input relay, the 3D mouse, the power service, and the two settings apps. Gaze mode, hand tracking, and remote desktop aren't supported with Nix: they build or run in the `dev` container, so their installers need the container setup. Keep `REMOTE=0`, since remote desktop still enters the container. The Bluetooth fixes don't need the container: install them from an upstream checkout with `setup/bluetooth/install.sh` (it asks for `sudo`).

TODO: package gaze mode, hand tracking, and remote desktop. Gaze's frame grabber is a root service, and `ft-camd` needs file capabilities, which store paths can't carry, so both would still need a `sudo` step.

## Packages

| Package | What it is |
| --- | --- |
| `ft-screens` | The compositor (`screens/build.sh`), and `ft-handtest` |
| `ft-pointer` | The 3D mouse's helper (`pointer/helper/build.sh`) |
| `ft-powerd` | The power service (`power/build.sh`) |
| `ft-pointer-driver` | The `ft_pointer` SteamVR driver, laid out as SteamVR expects (`share/frametop/ft_pointer`) |
| `frametop-apps` (`default`) | The scripts, Python tools, and both settings apps as one tree in `share/frametop`, with the three programs above inside it |
| `frametop-scripts` | The same tree without the settings apps, so no Qt |

`share/frametop` mirrors the repo. The scripts find each other by relative path (`$here/../layout/ft-layout`), and ft-screens finds `ft-layout` from its own path, so each program sits where the repo's build would put it (`screens/build/ft-screens`). The settings apps live in the same tree because they import `ft_layout` and call `desktops.sh` by relative path.

The repo's scripts read three environment variables: `FRAMETOP_SCREENS_BIN` (run ft-screens on the host, not in the container), `FRAMETOP_PYTHON`, and `FRAMETOP_STARTPLASMA`. The package sets their defaults to store paths. It exports nothing, so the host Plasma that the session starts gets a clean environment, with no `LD_LIBRARY_PATH` and no Qt paths.

ft-screens (EGL, GLES, GBM) has `/run/opengl-driver/lib` first in its RUNPATH. The settings apps reach the same drivers through nixpkgs' libglvnd, which looks there too.

The driver is the exception, because it loads into the host's `vrserver`. `zig c++` builds it against glibc 2.39's symbol versions with libc++ linked in. It exports only `HmdDriverFactory`, needs only libc and libm, and has no RUNPATH. The package's install check enforces all of this, like `pointer/driver/build.sh`.

## Using it from a standalone Home Manager config

```nix
# flake.nix of your Home Manager config
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    frametop = {
      url = "github:JRMurr/frametop-nix";
      # One nixpkgs for Frametop and the GPU drivers: libgbm and /run/opengl-driver's
      # backends must be the same Mesa. Your nixpkgs needs wlroots_0_20; drop this line to
      # use the nixpkgs pinned in frametop-nix's flake.lock (then point
      # targets.genericLinux.gpu.packages at its Mesa).
      inputs.nixpkgs.follows = "nixpkgs";
      # A different upstream commit:
      # inputs.frametop.url = "github:DeeJanuz/frametop/<rev>";
    };
  };

  outputs = { nixpkgs, home-manager, frametop, ... }: {
    homeConfigurations.steamos = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.aarch64-linux;
      modules = [
        frametop.homeManagerModules.default
        {
          home.username = "steamos";
          home.homeDirectory = "/home/steamos";
          home.stateVersion = "25.11";

          targets.genericLinux.enable = true;  # also turns on targets.genericLinux.gpu
          programs.frametop.enable = true;
          # programs.frametop.pointer.enable = false;  # no 3D mouse
          # programs.frametop.power.enable = false;    # no display power service
          # programs.frametop.launcher.enable = false; # the launcher keeps the stock desktop
          # programs.frametop.shareConfig = false;     # apps in the desktop get their own config
        }
      ];
    };
  };
}
```

`programs.frametop` sets up:

- **`frametop-input-relay`**: the same unit as `input/frametop-input-relay.service` run with the package's Python. If SteamVR is running when it's first installed, the relay waits for SteamVR's next start: starting under a running SteamVR would take the mouse away from it.
- **`frametop-pointer`** and **`frametop-power`**: they start and stop with SteamVR, as with `install.sh`.
- **The ft_pointer driver**: it's linked at `~/.local/share/frametop/ft_pointer`, the path `pointer/driver/install.sh` uses. Activation registers it once with the host's `vrpathreg`. The path stays the same across updates, so SteamVR's config isn't touched again.
- **Menu entries**: the launcher's Desktop entry (the `deckard-nested-desktop.desktop` override that `desktops.sh install` writes), Frametop Display Settings, Frametop Input Settings, Reset Screen Layout, Hide/Show Screens, and their shortcuts. Activation rewrites each profile's entry (`ft-layout launchers`), since those entries point into the store.
- **`~/.config/frametop.conf`**: it isn't managed, because the settings apps write to it. A missing one is created from the example. Activation sets `POINTER` from `pointer.enable` and `SHARE_CONFIG` from `shareConfig` (both on by default), and leaves the rest alone.

Host programs are options under `programs.frametop.host`: `steamvr` (`/opt/steamvr`), `startPlasma`, `vrpathreg`, and `kwriteconfig`. Don't add any `kdePackages` to `home.packages`. `~/.nix-profile/bin` comes first in PATH, so the session would start those programs instead of the host's.

The repo's scripts still work from the tree, for example `$(dirname $(readlink -f $(which ft-layout)))/../desktops.sh status`. Don't use `desktops.sh install`, `uninstall`, or `relay install`: Home Manager owns those files.

### GPU setup (once)

ft-screens and the settings apps use Mesa from nixpkgs, through `/run/opengl-driver`. Home Manager's `targets.genericLinux.gpu` provides that path (it's on by default with `targets.genericLinux.enable`). After the first `home-manager switch`, activation prints the command to run once:

```sh
sudo /nix/store/...-non-nixos-gpu-setup/bin/non-nixos-gpu-setup
```

It installs a systemd unit that links `/run/opengl-driver` to the current drivers at boot. Run it again when activation says the drivers need an update. It needs `sudo`.

### Moving from install.sh

Home Manager won't replace files the installers wrote. Remove those first, from the checkout:

```sh
pointer/helper/run.sh uninstall
power/run.sh uninstall
pointer/driver/install.sh uninstall   # Home Manager registers the same path again
display-settings/install.sh uninstall
input-settings/install.sh uninstall
desktops.sh uninstall
rm ~/.config/systemd/user/frametop-input-relay.service && systemctl --user daemon-reload
```

`desktops.sh relay uninstall` also clears the relay's fd store. That works too, but then SteamVR needs a restart to see the new devices. Either way, restart SteamVR once after the first switch, so it loads the driver and the relay comes up before it. Restarting SteamVR closes everything open in VR.

## Building and checking

```sh
nix flake check --all-systems                 # evaluates everything; builds the driver and frametop-scripts
nix build .#frametop-apps                     # on the Frame, or an aarch64 builder
nix build .#packages.x86_64-linux.ft-screens  # the same derivations on a PC
```

`nix flake check` builds the driver (with its install checks) and `frametop-scripts`, and runs `session/test_config_links.py`. It leaves out the settings apps, to skip building Qt.

CI (`.github/workflows/build.yml`) runs on pull requests and pushes to main, on GitHub's arm runner, natively on aarch64-linux like the Frame, with Determinate Nix and the Magic Nix Cache, so a run rebuilds only what changed. It evaluates the flake for both systems, runs the aarch64 checks, builds every package, and builds a Home Manager configuration with `programs.frametop` on (`checks/home.nix`; run it yourself with `nix build --impure -f checks/home.nix`). It also starts both settings apps with no display, to check that their QML loads.

`.github/workflows/update.yml` bumps `frametop` and `nixpkgs` weekly, opens a pull request, and runs the build on it. It needs "Allow GitHub Actions to create and approve pull requests" in the repo's Actions settings.

Against a local upstream checkout:

```sh
nix build .#frametop-apps --override-input frametop path:../frametop
```

## Patches

`patches/` is the source of truth. They're edited as commits on a `nix-patches` branch in a local frametop checkout, rebased on upstream main, then exported here. `packages/source.nix` applies them in order; a patch that no longer applies fails every build.

| Patch | Why |
| --- | --- |
| 0001 env hooks | `FRAMETOP_SCREENS_BIN`, `FRAMETOP_PYTHON`, `FRAMETOP_STARTPLASMA`, so the package can point the scripts at store paths and run ft-screens on the host. Also a writable decoration copy, and `host_command` outside distrobox |
| 0002 menu programs | Reset Screen Layout and Hide/Show Screens get their own programs; Steam merges entries sharing one |
| 0003 SHARE_CONFIG | `session/config_links.py`: apps in the desktop keep the user's config (`programs.frametop.shareConfig`) |
| 0004 update-check | Checks that Nix-built programs link everything SteamVR's `vrclient.so` needs |

To change them, in a frametop checkout (`git am ../frametop-nix/patches/*` on upstream main recreates the branch):

```sh
git fetch https://github.com/DeeJanuz/frametop main
git switch nix-patches && git rebase FETCH_HEAD   # fix conflicts, edit, commit
git format-patch --no-signature --zero-commit -N FETCH_HEAD -o ../frametop-nix/patches   # after rm ../frametop-nix/patches/*
```

Then `nix flake update frametop` here, so the lock matches the base the patches were made on.
