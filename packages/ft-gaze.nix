# ft-gaze and ft-gazepanel, gaze mode's SteamVR clients (gaze/build.sh): the eye tracking
# reader and the calibration panel. ft-gaze reads its action manifest from
# <exe dir>/../actions, so the binaries live in lib/ft-gaze/bin next to lib/ft-gaze/actions,
# as ft-pointer's do. The panel finds its font with the host's fc-match, as ft-screens does.
{
  lib,
  stdenv,
  pkg-config,
  autoAddDriverRunpath,
  libdrm,
  libgbm,
  openvr,
  vrclientDeps,
  stb,
  src,
}:

stdenv.mkDerivation {
  pname = "ft-gaze";
  version = "0-unstable";
  inherit src;
  sourceRoot = "source/gaze";

  nativeBuildInputs = [
    pkg-config
    autoAddDriverRunpath
  ];
  buildInputs = [
    libdrm
    libgbm
    openvr
  ]
  ++ vrclientDeps.buildInputs;

  # The same commands as gaze/build.sh, minus the downloads and the /opt/steamvr link.
  buildPhase = ''
    runHook preBuild
    mkdir -p build/include
    cp ${stb.truetype} build/include/stb_truetype.h
    cxx="$CXX -std=c++17 -O2 -Wall -Wno-unused-parameter -Wno-missing-field-initializers -Ibuild/include \
      $(pkg-config --cflags openvr)"
    $cxx -I../pointer/common -o build/ft-gaze ft-gaze.cpp \
      $(pkg-config --libs openvr) -lpthread ${vrclientDeps.ldflags}
    $cxx $(pkg-config --cflags gbm libdrm) -o build/ft-gazepanel panel/ft-gazepanel.cpp \
      $(pkg-config --libs openvr gbm libdrm) -lpthread ${vrclientDeps.ldflags}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/lib/ft-gaze/bin build/ft-gaze build/ft-gazepanel
    cp -r actions $out/lib/ft-gaze/actions
    mkdir -p $out/bin
    ln -s ../lib/ft-gaze/bin/ft-gaze $out/bin/ft-gaze
    ln -s ../lib/ft-gaze/bin/ft-gazepanel $out/bin/ft-gazepanel
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${vrclientDeps.check}
    vrclient_check $out/lib/ft-gaze/bin/ft-gaze
    vrclient_check $out/lib/ft-gaze/bin/ft-gazepanel
    runHook postInstallCheck
  '';

  meta = {
    description = "Frametop gaze mode's SteamVR clients: the eye tracking reader and calibration panel";
    mainProgram = "ft-gaze";
    platforms = lib.platforms.linux;
  };
}
