# frametop-nix

Nix packages and a Home Manager module for [Frametop](https://github.com/DeeJanuz/frametop) on the Steam Frame (SteamOS, aarch64-linux, standalone Home Manager, not NixOS).

Upstream builds Frametop in a Fedora `dev` container and sets it up with `install.sh`. This flake builds it with nixpkgs instead, and the Home Manager module sets up the same things `install.sh` does. This isn't part of upstream, it pins an upstream commit and carries a few [patches](#patches) on top.

There's a write up of a full frame setup using it in [this blog post](https://johns.codes/blog/nix-on-steam-frame).

## What works

You get the multi-screen desktop, the input relay, the 3D mouse, the power service, and both settings apps. Opt in to gaze mode (with SteamVR's eye tracker or Frametop's own), hand tracking, the hand recorder, and the Bluetooth fixes. The ones that need root go through [steamos-etc](#parts-that-need-root).

Remote desktop isn't packaged yet, it still enters upstream's `dev` container. Keep `REMOTE=0` in your config.

TODO: package remote desktop, the gaze probe (a development tool), and hand tracking's recording tools (`make tools`).

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
          # programs.frametop.gaze.enable = true;      # gaze mode (experimental)
          # The rest need steamos-etc (see "Parts that need root"):
          # programs.frametop.gaze.ownTracker.enable = true;  # Frametop's own eye tracker
          # programs.frametop.hands.enable = true;            # hand tracking (experimental)
          # programs.frametop.hands.recorder.enable = true;   # Frametop Hand Recorder
          # programs.frametop.bluetooth.enable = true;        # Bluetooth LE fixes
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

### Parts that need root

Frametop's own eye tracker, hand tracking, and the Bluetooth fixes each need a root step that Home Manager can't do. If you import [steamos-etc](https://github.com/JRMurr/steamos-etc-nix)'s module and enable it, the module declares them there, and `steamos-etc` installs them after a switch. Without it, these options fail with an assertion that says so.

- **`frametop-install`**: a root oneshot that copies `ft-eyegrab` to `/etc/frametop/` (where Frametop looks for it) and `ft-camd` to `/var/lib/frametop/` with its file capabilities, which store paths can't carry. `ft-camd` is static, so its copy doesn't depend on the store. A new build changes the unit, so `steamos-etc` runs it again.
- **`frametop-eyegrab`**: the eye-camera frame grabber, upstream's unit and hardening. `gaze.ownTracker.owner` (`1000:1000`) is who gets the frames.
- **`steamframe-bt-fixups`**: upstream's Bluetooth unit, run from the store.

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
# Only what you installed:
gaze/run.sh uninstall
gaze/tracker/install.sh uninstall     # asks for sudo
hands/run.sh uninstall
hands/rec/install.sh uninstall
setup/bluetooth/install.sh uninstall  # asks for sudo
```

`desktops.sh relay uninstall` also clears the relay's fd store. That works too, but then SteamVR needs a restart to see the new devices (which you're doing after the first switch anyway).

## What the module sets up

- **`frametop-input-relay`**: the same unit as upstream's `input/frametop-input-relay.service`, run with the package's Python. If SteamVR is already running when it's first installed, the relay waits for SteamVR's next start, since starting under a running SteamVR would take the mouse away from it.
- **`frametop-pointer`** and **`frametop-power`**: start and stop with SteamVR, same as with `install.sh`.
- **`frametop-gaze`** (`gaze.enable`): starts and stops with SteamVR. Turn gaze mode on and calibrate on the Gaze page of Frametop Input Settings. With `gaze.ownTracker.enable`, `GAZE_TRACKER=auto` picks Frametop's own tracker.
- **`frametop-camd`**, **`frametop-hands`**, and **`frametop-camwatch`** (`hands.enable`): as `hands/run.sh install` leaves them. Hand tracking doesn't start with SteamVR: `ft-handsctl on|off`, or `ft-cutouts on|off` for the cutouts without gestures (both on your `PATH`).
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
| `ft-gaze` | Gaze mode's `ft-gaze` and calibration panel `ft-gazepanel` (`gaze/build.sh`) |
| `ft-eyegrab` | Frametop's own eye tracker's frame grabber (`gaze/tracker/build.sh`) |
| `ft-hands` | The hand tracker (`hands/Makefile`), with nixpkgs' ncnn |
| `ft-camd` | The camera broker, static (`hands/Makefile`) |
| `ft-handpanel` | The hand recorder's headset panel (`hands/rec/build.sh`) |
| `frametop-apps` (`default`) | The scripts, Python tools, the settings apps, and the hand recorder as one tree in `share/frametop`, with the programs above inside it |
| `frametop-scripts` | The same tree without the apps, so no Qt |

### How the packages fit together

`share/frametop` mirrors the upstream repo. The scripts find each other by relative path (`$here/../layout/ft-layout`) and ft-screens finds `ft-layout` from its own path, so each program sits where upstream's build would put it (`screens/build/ft-screens`). The settings apps live in the same tree since they import `ft_layout` and call `desktops.sh` by relative path.

Upstream's scripts read four env vars (added by [patches](#patches) 0001, 0005, and 0006): `FRAMETOP_SCREENS_BIN` (run ft-screens on the host, not in the container), `FRAMETOP_PYTHON`, `FRAMETOP_STARTPLASMA`, and `FRAMETOP_HOST_BUILDS` (run gaze's and hand tracking's programs on the host). The package defaults them to store paths but exports nothing, so the host Plasma the session starts gets a clean environment (no `LD_LIBRARY_PATH`, no Qt paths).

ft-screens (EGL, GLES, GBM) has `/run/opengl-driver/lib` first in its RUNPATH. The settings apps find the same drivers through nixpkgs' libglvnd, which looks there too.

The driver is the odd one out since it loads into the host's `vrserver`. `zig c++` builds it against glibc 2.39's symbol versions with libc++ linked in. It exports only `HmdDriverFactory`, needs only libc and libm, and has no RUNPATH. The package's install check enforces all of that, like upstream's `pointer/driver/build.sh`.

## Building and checking

```sh
nix flake check --all-systems                 # evaluates everything; builds the driver and frametop-scripts
nix build .#frametop-apps                     # on the Frame, or an aarch64 builder
nix build .#packages.x86_64-linux.ft-screens  # the same derivations on a PC
```

`nix flake check` builds the driver (with its install checks), `ft-gaze`, and `frametop-scripts`, runs `session/test_config_links.py`, and runs gaze's and hand tracking's tests on the packaged tree. It skips the settings apps so it doesn't have to build Qt.

To build against a local upstream checkout:

```sh
nix build .#frametop-apps --override-input frametop path:../frametop
```

CI (`.github/workflows/build.yml`) runs on PRs and pushes to main, natively on GitHub's arm runner (aarch64-linux, like the Frame). It evaluates the flake for both systems, runs the aarch64 checks, builds every package, and builds a Home Manager config with all of `programs.frametop` on (`checks/home.nix`, run it yourself with `nix build --impure -f checks/home.nix`). It checks that the root parts fail without steamos-etc (`checks/needs-steamos-etc.nix`), and starts the settings apps and the hand recorder with no display to check their QML loads. Determinate Nix and the Magic Nix Cache mean a run only rebuilds what changed.

`.github/workflows/update.yml` bumps `frametop` and `nixpkgs` weekly and opens a PR with the build run on it. It needs "Allow GitHub Actions to create and approve pull requests" turned on in the repo's Actions settings.

## Patches

`patches/` is the source of truth. They're edited as commits on a `nix-patches` branch in a local frametop checkout, rebased on upstream main, then exported here. `packages/source.nix` applies them in order, so a patch that stops applying fails every build.

| Patch | Why |
| --- | --- |
| 0001 env hooks | `FRAMETOP_SCREENS_BIN`, `FRAMETOP_PYTHON`, `FRAMETOP_STARTPLASMA`, so the package can point the scripts at store paths and run ft-screens on the host. Also a writable decoration copy, and `host_command` outside distrobox |
| 0002 SHARE_CONFIG | `session/config_links.py`: apps in the desktop keep your normal config (`programs.frametop.shareConfig`) |
| 0003 update-check | Checks that Nix-built programs link everything SteamVR's `vrclient.so` needs |
| 0004 gaze mmap layout | [Upstream PR #26](https://github.com/DeeJanuz/frametop/pull/26): reads SteamVR's eye tracking on newer SteamOS. Drop once merged |
| 0005 gaze host builds | `FRAMETOP_HOST_BUILDS`: the gaze service runs `ft-gaze`, `ft-gazepanel`, and `ft-eyes` on the host, not in the container |
| 0006 hands host builds | The same for `ft-hands`, in `ft-cutouts` and the hand recorder |

To change them, in a frametop checkout (`git am ../frametop-nix/patches/*` on upstream main recreates the branch):

```sh
git fetch https://github.com/DeeJanuz/frametop main
git switch nix-patches && git rebase FETCH_HEAD   # fix conflicts, edit, commit
rm ../frametop-nix/patches/*
git format-patch --no-signature --zero-commit -N FETCH_HEAD -o ../frametop-nix/patches
```

Then `git add patches` (flakes only see tracked files) and run `nix flake update frametop` here so the lock matches the base the patches were made on.
