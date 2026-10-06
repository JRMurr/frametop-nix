# ft-handpanel, the hand recorder's headset panel (hands/rec/build.sh). It finds its font
# with the host's fc-match, as ft-screens does.
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
  pname = "ft-handpanel";
  version = "0-unstable";
  inherit src;
  sourceRoot = "source/hands/rec";

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

  # The same command as hands/rec/build.sh, minus the downloads and the /opt/steamvr link.
  buildPhase = ''
    runHook preBuild
    mkdir -p build/include
    cp ${stb.truetype} build/include/stb_truetype.h
    cp ${stb.image} build/include/stb_image.h
    $CXX -std=c++17 -O2 -Wall -Wno-unused-parameter -Wno-missing-field-initializers -Ibuild/include \
      $(pkg-config --cflags openvr gbm libdrm) -o build/ft-handpanel panel/ft-handpanel.cpp \
      $(pkg-config --libs openvr gbm libdrm) -lpthread ${vrclientDeps.ldflags}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin build/ft-handpanel
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${vrclientDeps.check}
    vrclient_check $out/bin/ft-handpanel
    runHook postInstallCheck
  '';

  meta = {
    description = "Frametop Hand Recorder's headset panel";
    mainProgram = "ft-handpanel";
    platforms = lib.platforms.linux;
  };
}
