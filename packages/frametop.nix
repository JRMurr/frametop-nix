# Frametop's scripts, Python tools, and settings apps, plus the programs from the other
# packages, as one tree in share/frametop laid out like the repo. The scripts find each
# other by relative path, so they work unchanged. Only the defaults of four environment
# variables change (FRAMETOP_SCREENS_BIN, FRAMETOP_PYTHON, FRAMETOP_STARTPLASMA,
# FRAMETOP_HOST_BUILDS); nothing is exported, so the host's Plasma starts with a clean environment.
#
# withSettingsApps adds Frametop Display Settings and Frametop Input Settings (PySide6 and
# Kirigami). Without them (frametop-scripts), nothing depends on Qt.
{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  gnused,
  python3,
  glib,
  gobject-introspection,
  qt6,
  kdePackages,
  ft-screens,
  ft-pointer,
  ft-powerd,
  ft-gaze,
  ft-hands,
  ft-handpanel,
  zstd,
  src,
  withSettingsApps ? true,
  # The host's Plasma (Plasma isn't packaged here: the session nests the SteamOS one).
  startPlasma ? "/usr/bin/startplasma-wayland",
  # ft-camd's copy with its capabilities (store paths can't carry them), which the Home
  # Manager module installs with steamos-etc.
  camdPath ? "/etc/frametop/ft-camd",
}:

let
  # ft-floatd and Launch as Standalone use dbus-python and PyGObject (GLib, Gio). The
  # typelib path is set for this interpreter only, not exported to the desktop.
  scriptPython = python3.withPackages (ps: [
    ps.dbus-python
    ps.pygobject3
  ]);
  typelibPath = lib.makeSearchPath "lib/girepository-1.0" [
    glib.out
    gobject-introspection
  ];
  appPython = python3.withPackages (ps: [ ps.pyside6 ]);
  # Our own eye tracker's ft-eyes (gaze/tracker/requirements.txt).
  eyesPython = python3.withPackages (ps: [
    ps.numpy
    ps.opencv4
  ]);
  share = "share/frametop";
in
stdenvNoCC.mkDerivation {
  pname = if withSettingsApps then "frametop" else "frametop-scripts";
  version = "0-unstable";
  inherit src;

  nativeBuildInputs = [ makeWrapper ] ++ lib.optional withSettingsApps qt6.wrapQtAppsHook;
  # For patchShebangs (the host's bash and python3 would do too, but these are pinned).
  buildInputs = [
    bash
    scriptPython
  ]
  ++ lib.optionals withSettingsApps [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtwayland
    qt6.qtsvg
    kdePackages.kirigami
    kdePackages.qqc2-desktop-style
    kdePackages.breeze-icons
  ];

  dontConfigure = true;
  dontBuild = true;
  # wrapQtAppsHook would wrap everything executable in the tree; only the two apps get it.
  dontWrapQtApps = true;
  # ft-screens' copy is already fixed up; patchelf's --shrink-rpath would drop
  # /run/opengl-driver/lib, which isn't there at build time.
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    tree=$out/${share}
    mkdir -p $tree
    cp -r README.md LICENSE desktops.sh decoration display-settings docs float gaze hands input \
      input-settings layout remote scripts session setup steam $tree/
    mkdir -p $tree/pointer/helper $tree/screens/build $tree/power/build
    cp -r pointer/helper/actions $tree/pointer/helper/

    # The programs, where the scripts and their own lookups expect them. ft-screens is a
    # copy: it finds ft-layout from its own real path (/proc/self/exe).
    install -m755 ${ft-screens}/bin/ft-screens $tree/screens/build/ft-screens
    mkdir -p $tree/pointer/helper/build
    ln -s ${ft-pointer}/lib/ft-pointer/bin/ft-pointer $tree/pointer/helper/build/ft-pointer
    ln -s ${ft-powerd}/bin/ft-powerd $tree/power/build/ft-powerd
    mkdir -p $tree/gaze/build
    ln -s ${ft-gaze}/lib/ft-gaze/bin/ft-gaze ${ft-gaze}/lib/ft-gaze/bin/ft-gazepanel $tree/gaze/build/
    mkdir -p $tree/gaze/tracker/build/venv/bin
    ln -s ${eyesPython}/bin/python3 $tree/gaze/tracker/build/venv/bin/python
    # ft-hands finds its models from argv[0] (hands/build/../models), so a link does.
    mkdir -p $tree/hands/build $tree/hands/rec/build
    ln -s ${ft-hands}/bin/ft-hands $tree/hands/build/ft-hands
    ln -s ${camdPath} $tree/hands/build/ft-camd
    ln -s ${ft-handpanel}/bin/ft-handpanel $tree/hands/rec/build/ft-handpanel

    makeWrapper ${scriptPython}/bin/python3 $out/libexec/frametop/ft-python \
      --prefix GI_TYPELIB_PATH : ${typelibPath}

    # Point the scripts' defaults at this package.
    substituteInPlace $tree/session/frametop-session.sh \
      --replace-fail 'screens_bin=''${FRAMETOP_SCREENS_BIN:-}' \
                     "screens_bin=\''${FRAMETOP_SCREENS_BIN:-$tree/screens/build/ft-screens}" \
      --replace-fail '"''${FRAMETOP_PYTHON:-python3}"' "\"\''${FRAMETOP_PYTHON:-$out/libexec/frametop/ft-python}\"" \
      --replace-fail '"''${FRAMETOP_STARTPLASMA:-startplasma-wayland}"' "\"\''${FRAMETOP_STARTPLASMA:-${startPlasma}}\""
    for f in layout/ft-layout float/ft-floatd float/ft-float-apps; do
      substituteInPlace $tree/$f \
        --replace-fail '"''${FRAMETOP_PYTHON:-python3}"' "\"\''${FRAMETOP_PYTHON:-$out/libexec/frametop/ft-python}\""
    done
    # gaze/build's and hands/build's programs above are built for the host.
    for f in gaze/gazecal.py hands/rec/session.py; do
      substituteInPlace $tree/$f \
        --replace-fail '"FRAMETOP_HOST_BUILDS", "0"' '"FRAMETOP_HOST_BUILDS", "1"'
    done
    substituteInPlace $tree/hands/ft-cutouts \
      --replace-fail 'host_builds=''${FRAMETOP_HOST_BUILDS:-0}' 'host_builds=''${FRAMETOP_HOST_BUILDS:-1}'
    # desktops.sh install's "Native Desktop": SteamOS's entry for its own desktop, renamed and
    # without X-Steam-Special, so Steam singles out only Frametop's (native-desktop STOCK DEST).
    cat > $out/libexec/frametop/native-desktop <<'EOF'
    #!${bash}/bin/bash
    set -eu
    ${gnused}/bin/sed -e 's/^Name=.*/Name=Native Desktop/' -e '/^Name\[/d' -e '/^X-Steam-Special=/d' -e '/pick this out/d' \
      "$1" > "$2.new"
    ${coreutils}/bin/mv "$2.new" "$2"
    EOF
    chmod +x $out/libexec/frametop/native-desktop

    # The repo's relay unit uses /usr/bin/python3; the Home Manager unit uses this one.
    ln -s ${scriptPython}/bin/python3 $out/libexec/frametop/python3

    # Menu entries, filled in (Home Manager links them into ~/.local/share/applications).
    mkdir -p $out/${share}-entries
    sed "s|@SESSION@|$tree/session/frametop-session.sh|" session/deckard-nested-desktop.desktop \
      > $out/${share}-entries/deckard-nested-desktop.desktop
    for f in display-settings/ft-layout-reset display-settings/ft-screens-toggle \
      ${lib.optionalString withSettingsApps "display-settings/ft-display-settings input-settings/ft-input-settings hands/rec/ft-handrec"}; do
      sed "s|@REPO@|$tree|g" $f.desktop > $out/${share}-entries/$(basename $f).desktop
    done

    mkdir -p $out/bin
    ln -s ../${share}/layout/ft-layout $out/bin/ft-layout
    ln -s ../${share}/float/ft-float $out/bin/ft-float
    ln -s ../${share}/hands/ft-handsctl $out/bin/ft-handsctl
    ln -s ../${share}/hands/ft-cutouts $out/bin/ft-cutouts
    runHook postInstall
  '';

  postFixup = ''
    tree=$out/${share}
  ''
  # The settings apps' launchers run the app in the dev container. Here they run it directly
  # (same name, so the menu entries and anything calling them keep working).
  + lib.optionalString withSettingsApps ''
    for app in display-settings/ft-display-settings:ft_display_settings.py \
      input-settings/ft-input-settings:ft_input_settings.py hands/rec/ft-handrec:ft_handrec.py; do
      launcher=$tree/''${app%%:*} script=$(dirname $tree/''${app%%:*})/''${app##*:}
      rm $launcher
      makeQtWrapper ${appPython}/bin/python3 $launcher \
        --add-flags $script \
        --set-default QT_QPA_PLATFORM 'wayland;xcb' \
        --suffix PATH : ${lib.makeBinPath [ zstd ]}
      ln -s ../${share}/''${app%%:*} $out/bin/$(basename $launcher)
    done
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    cmp ${ft-screens}/bin/ft-screens $out/${share}/screens/build/ft-screens \
      || { echo "the tree's ft-screens differs from the package's" >&2; exit 1; }
    runHook postInstallCheck
  '';

  passthru = {
    inherit
      scriptPython
      appPython
      withSettingsApps
      camdPath
      ;
    tree = share;
  };

  meta = {
    description = "Frametop: a multi-screen Plasma desktop in VR on the Steam Frame";
    homepage = "https://github.com/DeeJanuz/frametop";
    platforms = lib.platforms.linux;
  };
}
