# frametop-nix

Nix packages and a Home Manager module for [Frametop](https://github.com/DeeJanuz/frametop) on the Steam Frame (SteamOS, aarch64-linux, standalone Home Manager, not NixOS).

Upstream builds Frametop in a Fedora `dev` container and sets it up with `install.sh`. This flake builds it with nixpkgs instead, and the Home Manager module sets up the same things `install.sh` does. This isn't part of upstream, it pins an upstream commit and carries a few [patches](#patches) on top.

There's a write up of a full frame setup using it in [this blog post](https://johns.codes/blog/nix-on-steam-frame).

## What works

You get the multi-screen desktop, the input relay, the 3D mouse, the power service, and both settings apps.

Gaze mode, hand tracking, and remote desktop aren't packaged yet. They still build or run in upstream's `dev` container, so their installers need that setup. Keep `REMOTE=0` in your config since remote desktop still enters the container. The Bluetooth fixes don't need the container, install them from an upstream checkout with `setup/bluetooth/install.sh` (it asks for `sudo`).

TODO: package gaze mode, hand tracking, and remote desktop. Gaze's frame grabber is a root service and `ft-camd` needs file capabilities (which store paths can't carry), so both would still need a `sudo` step.

## Usage

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
      # Keep this: frametop and your GPU drivers need to use the same Mesa (see below).
      # Your nixpkgs needs wlroots_0_20.
      inputs.nixpkgs.follows = "nixpkgs";
      # To use a different upstream commit:
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
          home.stateVersion = "26.05";

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

After the first switch, restart SteamVR once so it loads the 3D mouse driver and the input relay comes up before it. This closes everything open in VR.

### GPU drivers

ft-screens and the settings apps use Mesa from nixpkgs through `/run/opengl-driver`, which `targets.genericLinux.gpu` provides (on by default with `targets.genericLinux.enable`). That's also why the `follows` above matters: libgbm in frametop and the drivers in `/run/opengl-driver` need to be the same Mesa. If you drop the `follows`, point `targets.genericLinux.gpu.packages` at frametop-nix's Mesa instead.

You still need something to create `/run/opengl-driver` at boot. You have two options:

- **[steamos-etc](https://github.com/JRMurr/steamos-etc-nix) (recommended):** set `programs.steamos-etc.gpuDrivers = true` and run `steamos-etc` after switching. It survives reboots and SteamOS updates.
- **`non-nixos-gpu-setup`:** after the first `home-manager switch`, activation prints a command to run once:

  ```sh
  sudo /nix/store/...-non-nixos-gpu-setup/bin/non-nixos-gpu-setup
  ```

  Run it again when activation says the drivers need an update. WARNING: on SteamOS its tmpfiles rule is a symlink into the store, and tmpfiles runs before `/nix` is mounted, so the drivers can be missing after a reboot. That's the problem steamos-etc fixes.

### Moving from install.sh

Home Manager won't overwrite files the installers wrote, so remove those first, from your upstream checkout:

```sh
pointer/helper/run.sh uninstall
power/run.sh uninstall
pointer/driver/install.sh uninstall   # Home Manager registers the same path again
display-settings/install.sh uninstall
input-settings/install.sh uninstall
desktops.sh uninstall
rm ~/.config/systemd/user/frametop-input-relay.service && systemctl --user daemon-reload
```

`desktops.sh relay uninstall` also clears the relay's fd store. That works too, but then SteamVR needs a restart to see the new devices (which you're doing after the first switch anyway).

## What the module sets up

- **`frametop-input-relay`**: the same unit as upstream's `input/frametop-input-relay.service`, run with the package's Python. If SteamVR is already running when it's first installed, the relay waits for SteamVR's next start, since starting under a running SteamVR would take the mouse away from it.
- **`frametop-pointer`** and **`frametop-power`**: start and stop with SteamVR, same as with `install.sh`.
- **The ft_pointer driver**: linked at `~/.local/share/frametop/ft_pointer` (the same path `pointer/driver/install.sh` uses) and registered once with the host's `vrpathreg`. The path never changes between generations, so SteamVR's config isn't touched again.
- **Menu entries**: the launcher's Desktop entry (the `deckard-nested-desktop.desktop` override `desktops.sh install` writes), Frametop Display Settings, Frametop Input Settings, Reset Screen Layout, Hide/Show Screens, and their shortcuts. Activation rewrites each profile's entry (`ft-layout launchers`) since those point into the store.
- **`~/.config/frametop.conf`**: not managed, since the settings apps write to it. If it's missing it gets created from the example. Activation sets `POINTER` from `pointer.enable` and `SHARE_CONFIG` from `shareConfig` (both on by default) and leaves everything else alone.

The host programs it uses are options under `programs.frametop.host`: `steamvr` (`/opt/steamvr`), `startPlasma`, `vrpathreg`, and `kwriteconfig`.

Upstream's scripts still work from the tree, for example `$(dirname $(readlink -f $(which ft-layout)))/../desktops.sh status`. Just don't use `desktops.sh install`, `uninstall`, or `relay install`, Home Manager owns those files now.

## Packages

| Package | What it is |
| --- | --- |
| `ft-screens` | The compositor (`screens/build.sh`), and `ft-handtest` |
| `ft-pointer` | The 3D mouse's helper (`pointer/helper/build.sh`) |
| `ft-powerd` | The power service (`power/build.sh`) |
| `ft-pointer-driver` | The `ft_pointer` SteamVR driver, laid out how SteamVR expects (`share/frametop/ft_pointer`) |
| `frametop-apps` (`default`) | The scripts, Python tools, and both settings apps as one tree in `share/frametop`, with the three programs above inside it |
| `frametop-scripts` | The same tree without the settings apps, so no Qt |

### How the packages fit together

`share/frametop` mirrors the upstream repo. The scripts find each other by relative path (`$here/../layout/ft-layout`) and ft-screens finds `ft-layout` from its own path, so each program sits where upstream's build would put it (`screens/build/ft-screens`). The settings apps live in the same tree since they import `ft_layout` and call `desktops.sh` by relative path.

Upstream's scripts read three env vars (added by [patch 0001](#patches)): `FRAMETOP_SCREENS_BIN` (run ft-screens on the host, not in the container), `FRAMETOP_PYTHON`, and `FRAMETOP_STARTPLASMA`. The package defaults them to store paths but exports nothing, so the host Plasma the session starts gets a clean environment (no `LD_LIBRARY_PATH`, no Qt paths).

ft-screens (EGL, GLES, GBM) has `/run/opengl-driver/lib` first in its RUNPATH. The settings apps find the same drivers through nixpkgs' libglvnd, which looks there too.

The driver is the odd one out since it loads into the host's `vrserver`. `zig c++` builds it against glibc 2.39's symbol versions with libc++ linked in. It exports only `HmdDriverFactory`, needs only libc and libm, and has no RUNPATH. The package's install check enforces all of that, like upstream's `pointer/driver/build.sh`.

## Building and checking

```sh
nix flake check --all-systems                 # evaluates everything; builds the driver and frametop-scripts
nix build .#frametop-apps                     # on the Frame, or an aarch64 builder
nix build .#packages.x86_64-linux.ft-screens  # the same derivations on a PC
```

`nix flake check` builds the driver (with its install checks) and `frametop-scripts`, and runs `session/test_config_links.py`. It skips the settings apps so it doesn't have to build Qt.

To build against a local upstream checkout:

```sh
nix build .#frametop-apps --override-input frametop path:../frametop
```

CI (`.github/workflows/build.yml`) runs on PRs and pushes to main, natively on GitHub's arm runner (aarch64-linux, like the Frame). It evaluates the flake for both systems, runs the aarch64 checks, builds every package, and builds a Home Manager config with `programs.frametop` on (`checks/home.nix`, run it yourself with `nix build --impure -f checks/home.nix`). It also starts both settings apps with no display to check their QML loads. Determinate Nix and the Magic Nix Cache mean a run only rebuilds what changed.

`.github/workflows/update.yml` bumps `frametop` and `nixpkgs` weekly and opens a PR with the build run on it. It needs "Allow GitHub Actions to create and approve pull requests" turned on in the repo's Actions settings.

## Patches

`patches/` is the source of truth. They're edited as commits on a `nix-patches` branch in a local frametop checkout, rebased on upstream main, then exported here. `packages/source.nix` applies them in order, so a patch that stops applying fails every build.

| Patch | Why |
| --- | --- |
| 0001 env hooks | `FRAMETOP_SCREENS_BIN`, `FRAMETOP_PYTHON`, `FRAMETOP_STARTPLASMA`, so the package can point the scripts at store paths and run ft-screens on the host. Also a writable decoration copy, and `host_command` outside distrobox |
| 0002 SHARE_CONFIG | `session/config_links.py`: apps in the desktop keep your normal config (`programs.frametop.shareConfig`) |
| 0003 update-check | Checks that Nix-built programs link everything SteamVR's `vrclient.so` needs |

To change them, in a frametop checkout (`git am ../frametop-nix/patches/*` on upstream main recreates the branch):

```sh
git fetch https://github.com/DeeJanuz/frametop main
git switch nix-patches && git rebase FETCH_HEAD   # fix conflicts, edit, commit
rm ../frametop-nix/patches/*
git format-patch --no-signature --zero-commit -N FETCH_HEAD -o ../frametop-nix/patches
```

Then `git add patches` (flakes only see tracked files) and run `nix flake update frametop` here so the lock matches the base the patches were made on.
