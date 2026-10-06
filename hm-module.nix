# Home Manager module for Frametop on a Steam Frame (SteamOS, not NixOS). What
# install.sh sets up, from the flake's packages: the input relay, pointer, power, and gaze
# services, the ft_pointer SteamVR driver, the launcher's Desktop entry, and the settings
# apps' menu entries. See README.md.
self:
{
  config,
  options,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    literalExpression
    ;
  cfg = config.programs.frametop;
  system = pkgs.stdenv.hostPlatform.system;
  flakePackages =
    self.packages.${system} or (throw "programs.frametop: no Frametop packages for ${system}");

  pkg = cfg.package;
  tree = "${pkg}/${pkg.passthru.tree}";
  entries = "${pkg}/share/frametop-entries";
  platform = cfg.driverPackage.passthru.steamvrPlatform;
  steamvrBin = "${cfg.host.steamvr}/bin/${platform}";
  # The same path pointer/driver/install.sh uses, so SteamVR's registration matches.
  driverDir = "${config.xdg.dataHome}/frametop/ft_pointer";
  openvrPaths = "${config.xdg.configHome}/openvr/openvrpaths.vrpath";

  # What needs root: programs.steamos-etc installs it (github:JRMurr/steamos-etc-nix).
  ownTracker = cfg.gaze.ownTracker.enable;
  rootNeeded = ownTracker || cfg.hands.enable || cfg.bluetooth.enable;
  hasSteamosEtc = options ? programs.steamos-etc;
  steamosEtcOn = hasSteamosEtc && config.programs.steamos-etc.enable;
  # Copies of the programs that can't run from the store, as steamos-etc files (removed when
  # turned off): ft-eyegrab where gaze/ft-gazed and Input Settings look for it, and ft-camd
  # with file capabilities, which store paths can't carry.
  eyegrabFile = "frametop/ft-eyegrab";
  camdFile = lib.removePrefix "/etc/" pkg.passthru.camdPath;
  # pidfd_getfd on XRService, system-wide tracepoints, and their root-only format files
  # (hands/run.sh). ft-camd drops them once it has set up.
  camdCaps = [
    "cap_sys_ptrace"
    "cap_perfmon"
    "cap_dac_read_search"
  ];

  # SteamVR opens input devices only at startup, so the relay must not start for the first
  # time while SteamVR runs (it would take the mouse away from it). Home Manager starts new
  # services right away, so this skips that start. A restart (after a crash or an update) is
  # fine: systemd keeps the relay's virtual devices, so SteamVR keeps seeing them.
  relayCondition = pkgs.writeShellScript "frametop-input-relay-condition" ''
    systemctl --user is-active --quiet steamvr.service || exit 0
    n=$(systemctl --user show -p NFileDescriptorStore --value frametop-input-relay.service)
    [ "''${n:-0}" -gt 0 ] && exit 0
    echo "SteamVR is running: the input relay starts with it next time (restart SteamVR to start it now)"
    exit 1
  '';
in
{
  options.programs.frametop = {
    enable = mkEnableOption "Frametop, the multi-screen Plasma desktop in VR on the Steam Frame";

    package = mkOption {
      type = types.package;
      default = flakePackages.frametop-apps.override { startPlasma = cfg.host.startPlasma; };
      defaultText = literalExpression "frametop.packages.\${system}.frametop-apps.override { startPlasma = config.programs.frametop.host.startPlasma; }";
      description = ''
        Frametop's scripts, tools, and settings apps (with ft-screens, ft-pointer, and
        ft-powerd in their tree). `frametop-scripts` leaves out the settings apps.
      '';
    };

    driverPackage = mkOption {
      type = types.package;
      default = flakePackages.ft-pointer-driver;
      defaultText = literalExpression "frametop.packages.\${system}.ft-pointer-driver";
      description = "The ft_pointer SteamVR driver.";
    };

    launcher.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Make the VR launcher's Desktop entry start Frametop (an override of
        deckard-nested-desktop.desktop in ~/.local/share/applications, as
        `desktops.sh install` does). Off, the launcher opens the stock SteamOS desktop.
      '';
    };

    pointer.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        The universal 3D mouse: the ft_pointer SteamVR driver (registered with vrpathreg)
        and the frametop-pointer service, which starts and stops with SteamVR.
      '';
    };

    gaze.ownTracker = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Frametop's own eye tracker for gaze mode (gaze/tracker), more accurate than
          SteamVR's. Its frame grabber, ft-eyegrab, is a root system service, installed with
          programs.steamos-etc. Needs gaze.enable.
        '';
      };
      owner = mkOption {
        type = types.str;
        default = "1000:1000";
        description = "UID:GID that gets the eye-camera frames: the user running the gaze service.";
      };
      package = mkOption {
        type = types.package;
        default = flakePackages.ft-eyegrab;
        defaultText = literalExpression "frametop.packages.\${system}.ft-eyegrab";
        description = "ft-eyegrab, the eye-camera frame grabber.";
      };
    };

    hands = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Hand tracking (experimental): the frametop-camd and frametop-hands services, which
          don't start with SteamVR (ft-handsctl on, or ft-cutouts on for the cutouts without
          gestures), and frametop-camwatch. ft-camd needs file capabilities, so a copy with
          them is installed with programs.steamos-etc.
        '';
      };
      camdPackage = mkOption {
        type = types.package;
        default = flakePackages.ft-camd;
        defaultText = literalExpression "frametop.packages.\${system}.ft-camd";
        description = "ft-camd, the camera broker (static: it runs from a copy outside the store).";
      };
      recorder.enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Frametop Hand Recorder's menu entry: record your hands for Frametop's open hand
          dataset. Needs hands.enable and the settings apps (frametop-apps).
        '';
      };
    };

    bluetooth.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        The Bluetooth LE fixes (setup/bluetooth: LE mice and keyboards reconnect), a root
        system service installed with programs.steamos-etc.
      '';
    };

    gaze.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Gaze mode (experimental): the 3D mouse's pointer goes where you look. The
        frametop-gaze service (ft-gazed), which starts and stops with SteamVR, with SteamVR's
        eye tracker. Turn it on and calibrate on the Gaze page of Frametop Input Settings.
        Needs pointer.enable.
      '';
    };

    power.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        The frametop-power service (ft-powerd), which turns the displays off while the
        headset isn't used. It starts and stops with SteamVR.
      '';
    };

    shareConfig = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Apps in the Frametop desktop use the normal ~/.config and ~/.local/state (all but
        Plasma's own files), so they keep their config and logins. Written to
        SHARE_CONFIG in ~/.config/frametop.conf at each activation; takes effect at the next
        desktop start.
      '';
    };

    host = {
      steamvr = mkOption {
        type = types.str;
        default = "/opt/steamvr";
        description = "The host's SteamVR runtime (for vrpathreg).";
      };
      startPlasma = mkOption {
        type = types.str;
        default = "/usr/bin/startplasma-wayland";
        description = ''
          The host's startplasma-wayland, which the session runs nested in ft-screens.
        '';
      };
      vrpathreg = mkOption {
        type = types.str;
        default = "${steamvrBin}/vrpathreg";
        defaultText = literalExpression ''"''${host.steamvr}/bin/linuxarm64/vrpathreg"'';
        description = "The host's vrpathreg, which registers the ft_pointer driver with SteamVR.";
      };
      kwriteconfig = mkOption {
        type = types.str;
        default = "/usr/bin/kwriteconfig6";
        description = "The host's kwriteconfig6, for the Frametop desktop's global shortcuts.";
      };
    };
  };

  config = mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          (lib.hm.assertions.assertPlatform "programs.frametop" pkgs lib.platforms.linux)
          {
            assertion = rootNeeded -> steamosEtcOn;
            message = "programs.frametop: gaze.ownTracker, hands, and bluetooth need root, which programs.steamos-etc (github:JRMurr/steamos-etc-nix) installs: import its Home Manager module and set programs.steamos-etc.enable.";
          }
          {
            assertion = ownTracker -> cfg.gaze.enable;
            message = "programs.frametop.gaze.ownTracker.enable needs programs.frametop.gaze.enable.";
          }
          {
            assertion =
              cfg.hands.recorder.enable -> cfg.hands.enable && (pkg.passthru.withSettingsApps or false);
            message = "programs.frametop.hands.recorder.enable needs programs.frametop.hands.enable and the settings apps (frametop-apps).";
          }
          {
            assertion = cfg.gaze.enable -> cfg.pointer.enable;
            message = "programs.frametop.gaze.enable needs programs.frametop.pointer.enable: gaze mode moves the 3D mouse's pointer.";
          }
        ];

        # Wrappers only (ft-layout, ft-float, the settings apps): no Qt or KDE libraries in
        # ~/.nix-profile/bin.
        home.packages = [ pkg ];

        systemd.user.services.frametop-input-relay = {
          Unit = {
            Description = "Frametop input relay: stable virtual mouse and keyboard for SteamVR";
            Documentation = [ "file://${tree}/README.md" ];
            # SteamVR opens input devices only at startup, so the virtual devices must exist first.
            Before = [ "steamvr.service" ];
          };
          Service = {
            # READY=1 is sent only after the virtual devices exist.
            Type = "notify";
            NotifyAccess = "main";
            ExecCondition = "${relayCondition}";
            ExecStart = "${pkg}/libexec/frametop/python3 ${tree}/input/input-relay.py";
            Restart = "on-failure";
            RestartSec = 1;
            # systemd holds the virtual devices' file descriptors across relay restarts, so
            # SteamVR keeps the same devices. Clear with:
            # systemctl --user clean --what=fdstore frametop-input-relay
            FileDescriptorStoreMax = 4;
            FileDescriptorStorePreserve = "yes";
          };
          Install.WantedBy = [
            "default.target"
            "steamvr.service"
          ];
        };

        systemd.user.services.frametop-pointer = mkIf cfg.pointer.enable {
          Unit = {
            Description = "Frametop pointer helper: the universal 3D mouse (cursor, collision, ft_pointer driver)";
            Documentation = [ "file://${tree}/README.md" ];
            # Needs SteamVR's IPC; it starts and stops with SteamVR.
            After = [
              "steamvr.service"
              "frametop-input-relay.service"
            ];
            PartOf = [ "steamvr.service" ];
            Requisite = [ "steamvr.service" ];
          };
          Service = {
            ExecStart = "${tree}/pointer/helper/build/ft-pointer";
            Restart = "on-failure";
            RestartSec = 3;
          };
          Install.WantedBy = [ "steamvr.service" ];
        };

        systemd.user.services.frametop-gaze = mkIf cfg.gaze.enable {
          Unit = {
            Description = "Frametop gaze service: the eye tracking, corrected, for the pointer's gaze mode";
            Documentation = [ "file://${tree}/gaze/README.md" ];
            # ft-gaze is a SteamVR overlay client; it starts and stops with SteamVR.
            After = [
              "steamvr.service"
              "frametop-pointer.service"
            ];
            PartOf = [ "steamvr.service" ];
            Requisite = [ "steamvr.service" ];
          };
          Service = {
            ExecStart = "${pkg}/libexec/frametop/python3 ${tree}/gaze/ft-gazed";
            Restart = "on-failure";
            RestartSec = 3;
            TimeoutStopSec = 5;
          };
          Install.WantedBy = [ "steamvr.service" ];
        };

        # hands/frametop-camd.service and frametop-hands.service, installed but not started with
        # SteamVR, as hands/run.sh install leaves them: ft-handsctl on|off.
        systemd.user.services.frametop-camd = mkIf cfg.hands.enable {
          Unit = {
            Description = "Frametop camera broker: the headset cameras' frames, for hand tracking";
            Documentation = [ "file://${tree}/hands/README.md" ];
            After = [ "steamvr.service" ];
            PartOf = [ "steamvr.service" ];
          };
          Service = {
            ExecStart = "${tree}/hands/build/ft-camd --status 60";
            Restart = "always";
            RestartSec = 5;
            TimeoutStopSec = 5;
          };
        };

        systemd.user.services.frametop-hands = mkIf cfg.hands.enable {
          Unit = {
            Description = "Frametop hand tracking: hands for the screens' hand cutouts, pinches for the pointer";
            Documentation = [ "file://${tree}/hands/README.md" ];
            After = [
              "steamvr.service"
              "frametop-camd.service"
            ];
            Wants = [ "frametop-camd.service" ];
            PartOf = [ "steamvr.service" ];
          };
          Service = {
            ExecStartPre = "-${pkgs.procps}/bin/pkill -x ft-hands";
            ExecStart = "${tree}/hands/build/ft-hands --status 60";
            Restart = "always";
            RestartSec = 5;
            TimeoutStopSec = 5;
          };
        };

        systemd.user.services.frametop-camwatch = mkIf cfg.hands.enable {
          Unit = {
            Description = "Frametop camera watch: tells you when SteamVR leaves the headset's upper cameras off";
            Documentation = [ "file://${tree}/hands/README.md" ];
          };
          Service = {
            ExecStart = "${pkg}/libexec/frametop/python3 ${tree}/hands/ft-camwatch";
            Restart = "on-failure";
            RestartSec = 30;
            Nice = 10;
            CPUQuota = "5%";
            MemoryMax = "64M";
          };
          Install.WantedBy = [ "default.target" ];
        };

        systemd.user.services.frametop-power = mkIf cfg.power.enable {
          Unit = {
            Description = "Frametop power: turns the headset's displays off while nobody is using it";
            Documentation = [ "file://${tree}/docs/reference.md" ];
            # Needs SteamVR's IPC; it starts and stops with SteamVR.
            After = [ "steamvr.service" ];
            PartOf = [ "steamvr.service" ];
          };
          Service = {
            # SIGTERM makes ft-powerd turn the displays back on before it exits.
            ExecStart = "${tree}/power/build/ft-powerd";
            Restart = "on-failure";
            RestartSec = 3;
          };
          Install.WantedBy = [ "steamvr.service" ];
        };

        xdg.dataFile = lib.mkMerge [
          (mkIf cfg.launcher.enable {
            "applications/deckard-nested-desktop.desktop".source = "${entries}/deckard-nested-desktop.desktop";
          })
          (lib.listToAttrs (
            map
              (name: lib.nameValuePair "applications/${name}.desktop" { source = "${entries}/${name}.desktop"; })
              (
                [
                  "ft-layout-reset"
                  "ft-screens-toggle"
                ]
                ++ lib.optionals (pkg.passthru.withSettingsApps or false) [
                  "ft-display-settings"
                  "ft-input-settings"
                ]
                ++ lib.optional cfg.hands.recorder.enable "ft-handrec"
              )
          ))
          (mkIf cfg.pointer.enable {
            # A link to the store: the path SteamVR has registered stays the same across
            # generations. SteamVR loads drivers at startup, so a new driver takes a restart.
            "frametop/ft_pointer".source = "${cfg.driverPackage}/share/frametop/ft_pointer";
          })
        ];

        home.activation = {
          # ~/.config/frametop.conf stays the user's: the settings apps write it. Only a
          # missing one is created, from the example, as desktops.sh install does (and with the
          # 3D mouse on, as install.sh does).
          frametopConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            conf=${lib.escapeShellArg config.xdg.configHome}/frametop.conf
            if [ ! -e "$conf" ]; then
              run mkdir -p "$(dirname "$conf")"
              run install -m 644 ${tree}/session/frametop.conf.example "$conf"
              verboseEcho "frametop: created $conf"
            fi

            # Settings that follow this module's options; no settings app writes them.
            set_conf() {  # set_conf KEY 0|1
              grep -qE "^$1=$2([^0-9]|$)" "$conf" && return
              run sed -i "s/^$1=[0-9]*/$1=$2/" "$conf"
              grep -q "^$1=" "$conf" || run sh -c "echo $1=$2 >> '$conf'"
            }
            set_conf POINTER ${if cfg.pointer.enable then "1" else "0"}
            set_conf SHARE_CONFIG ${if cfg.shareConfig then "1" else "0"}

            # Lines still at an older example's default get the new one (install.sh runs it too).
            # It uses awk, which activation's PATH doesn't have.
            run env PATH=${lib.makeBinPath [ pkgs.gawk ]}:"$PATH" ${tree}/scripts/conf-migrate.sh \
              || warnEcho "frametop: conf-migrate.sh failed"
          '';

          # The ft_pointer driver's registration with SteamVR, once: the path doesn't change
          # between generations. (Turning pointer.enable off leaves it registered, pointing at
          # nothing, which SteamVR skips; `vrpathreg removedriver` removes it.)
          frametopDriver = mkIf cfg.pointer.enable (
            lib.hm.dag.entryAfter [ "linkGeneration" ] ''
              driver=${lib.escapeShellArg driverDir}
              if grep -qF "\"$driver\"" ${lib.escapeShellArg openvrPaths} 2>/dev/null; then
                verboseEcho "frametop: ft_pointer driver already registered"
              elif [ -x ${lib.escapeShellArg cfg.host.vrpathreg} ]; then
                run env LD_LIBRARY_PATH=${lib.escapeShellArg steamvrBin} ${lib.escapeShellArg cfg.host.vrpathreg} adddriver "$driver"
                echo "frametop: registered the ft_pointer driver; restart SteamVR to load it"
              else
                warnEcho "frametop: no ${cfg.host.vrpathreg}, so the ft_pointer driver isn't registered with SteamVR"
              fi
            ''
          );

          # Each profile's launcher entry (they point into the store, so they're rewritten for
          # each generation) and the Frametop desktop's global shortcuts, as
          # display-settings/install.sh does.
          frametopLaunchers = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            run ${tree}/layout/ft-layout launchers || warnEcho "frametop: ft-layout launchers failed"
            if [ -x ${lib.escapeShellArg cfg.host.kwriteconfig} ]; then
              shortcuts=${lib.escapeShellArg config.xdg.configHome}/frametop/kglobalshortcutsrc
              run mkdir -p "$(dirname "$shortcuts")"
              run ${cfg.host.kwriteconfig} --file "$shortcuts" --group services --group ft-layout-reset.desktop --key _launch 'Meta+Shift+R'
              run ${cfg.host.kwriteconfig} --file "$shortcuts" --group services --group ft-screens-toggle.desktop --key _launch 'Meta+Shift+H'
            fi
          '';
        };
      }

      # Root parts, through steamos-etc when it's imported.
      (lib.optionalAttrs hasSteamosEtc {
        programs.steamos-etc.files = lib.mkMerge [
          (mkIf ownTracker {
            ${eyegrabFile} = {
              source = "${cfg.gaze.ownTracker.package}/bin/ft-eyegrab";
              mode = "0755";
            };
          })
          (mkIf cfg.hands.enable {
            ${camdFile} = {
              source = "${cfg.hands.camdPackage}/bin/ft-camd";
              mode = "0755";
              capabilities = camdCaps;
            };
          })
        ];

        programs.steamos-etc.services = lib.mkMerge [
          (mkIf ownTracker {
            # gaze/tracker/frametop-eyegrab.service.
            frametop-eyegrab = {
              Unit = {
                Description = "Frametop eye-camera frames for our own eye tracker (read-only copies from SteamVR's eyetracking)";
                Documentation = [ "file://${tree}/gaze/README.md" ];
                # Ignored by systemd: a new build changes the unit, so steamos-etc restarts it
                # onto the new copy.
                X-Frametop-Build = "${cfg.gaze.ownTracker.package}";
              };
              Service = {
                # Idle until ft-eyes touches the want file (ft-eyegrab.c).
                ExecStart = "/etc/${eyegrabFile} --share /dev/shm/frametop-eyes-cams --owner ${cfg.gaze.ownTracker.owner} --want /dev/shm/frametop-eyes-want";
                Restart = "on-failure";
                RestartSec = 5;
                Nice = 5;
                # Root only for CAP_SYS_PTRACE (pidfd_getfd), CAP_DAC_READ_SEARCH (/proc/PID/fd),
                # and CAP_CHOWN (the shared file goes to the user).
                CapabilityBoundingSet = "CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_CHOWN";
                AmbientCapabilities = "";
                NoNewPrivileges = true;
                ProtectSystem = "strict";
                ProtectHome = true;
                ReadWritePaths = "/dev/shm";
                PrivateNetwork = true;
                RestrictAddressFamilies = "AF_UNIX";
                ProtectKernelModules = true;
                ProtectKernelTunables = true;
                ProtectControlGroups = true;
                ProtectClock = true;
                ProtectHostname = true;
                RestrictNamespaces = true;
                RestrictRealtime = true;
                LockPersonality = true;
                MemoryDenyWriteExecute = true;
                SystemCallArchitectures = "native";
              };
              Install.WantedBy = [ "multi-user.target" ];
            };
          })
          (mkIf cfg.bluetooth.enable {
            # setup/bluetooth/steamframe-bt-fixups.service. A separate unit rather than
            # ExecStartPost: the controller powers up only after bluetooth.service is active.
            steamframe-bt-fixups = {
              Unit = {
                Description = "SteamFrame Bluetooth LE workarounds (address resolution, privacy off)";
                After = [
                  "bluetooth.service"
                  "set-bluetooth-mac-address.service"
                ];
                PartOf = [ "bluetooth.service" ];
              };
              Service = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${tree}/setup/bluetooth/bt-fixups.sh";
                TimeoutStartSec = "5min";
              };
              Install.WantedBy = [ "bluetooth.service" ];
            };
          })
        ];
      })
    ]
  );
}
