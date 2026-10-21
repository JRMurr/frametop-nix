# ft-screens, Frametop's wlroots compositor (screens/build.sh), ft-handtest, ft-handview (the
# hands drawn with Room View off), and ft-spotpanel (spotwatch's search panel).
# Linked against nixpkgs' openvr (the same v2.15.6 header screens/build.sh pins) instead of
# /opt/steamvr's libopenvr_api; libopenvr_api finds the runtime through
# ~/.config/openvr/openvrpaths.vrpath. GL comes from /run/opengl-driver (RUNPATH, via
# autoAddDriverRunpath), which Home Manager's targets.genericLinux.gpu provides.
{
  lib,
  stdenv,
  pkg-config,
  autoAddDriverRunpath,
  wlroots_0_20,
  wayland,
  wayland-protocols,
  libxkbcommon,
  libdrm,
  pixman,
  libGL,
  libgbm,
  openvr,
  vrclientDeps,
  # keyboard.cpp's key labels, ft-handview --snapshot's PNGs.
  stb,
  src,
}:

stdenv.mkDerivation {
  pname = "ft-screens";
  version = "0-unstable";
  inherit src;
  sourceRoot = "source/screens";

  nativeBuildInputs = [
    pkg-config
    autoAddDriverRunpath
  ];
  buildInputs = [
    wlroots_0_20
    wayland
    wayland-protocols
    libxkbcommon
    libdrm
    pixman
    libGL
    libgbm
    openvr
  ]
  ++ vrclientDeps.buildInputs;

  # The same commands as screens/build.sh, minus the downloads and the /opt/steamvr link.
  buildPhase = ''
    runHook preBuild
    mkdir -p build/include
    cp ${stb.truetype} build/include/stb_truetype.h
    cp ${stb.imageWrite} build/include/stb_image_write.h
    cc="$CC -std=c11 -O2 -Wall -Wno-unused-parameter \
      $(pkg-config --cflags wlroots-0.20 wayland-server xkbcommon libdrm pixman-1)"
    $cc -c -o build/compositor.o compositor.c
    $cc -c -o build/remote.o remote.c
    cxx="$CXX -std=c++17 -O2 -Wall -Wno-missing-field-initializers -Ibuild/include \
      $(pkg-config --cflags egl glesv2 gbm libdrm openvr)"
    $cxx -c -o build/vr.o vr.cpp
    $cxx -c -o build/keyboard.o keyboard.cpp
    $cxx -c -o build/overlaytex.o overlaytex.cpp
    for f in handcut handrender handinput palmmenu grabthat steampanels handtest handmesh handskin \
      handrobot handview; do
      $cxx -c -o build/$f.o $f.cpp
    done
    vrlibs="$(pkg-config --libs egl glesv2 gbm openvr) ${vrclientDeps.ldflags}"
    $CXX -o build/ft-screens build/compositor.o build/remote.o build/vr.o build/keyboard.o build/overlaytex.o build/handcut.o \
      build/handrender.o build/handinput.o build/palmmenu.o build/grabthat.o build/steampanels.o \
      $(pkg-config --libs wlroots-0.20 wayland-server xkbcommon pixman-1) $vrlibs
    $CXX -o build/ft-handtest build/handtest.o build/handcut.o build/handrender.o $vrlibs
    $CXX -o build/ft-handview build/handview.o build/handmesh.o build/handskin.o build/handrobot.o \
      build/handcut.o build/handrender.o $vrlibs
    $cxx -o build/ft-spotpanel ../spotwatch/ft-spotpanel.cpp $(pkg-config --libs gbm libdrm openvr) \
      ${vrclientDeps.ldflags} -lpthread
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin build/ft-screens build/ft-handtest build/ft-handview build/ft-spotpanel
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${vrclientDeps.check}
    vrclient_check $out/bin/ft-screens
    vrclient_check $out/bin/ft-handtest
    vrclient_check $out/bin/ft-handview
    vrclient_check $out/bin/ft-spotpanel
    runHook postInstallCheck
  '';

  meta = {
    description = "Frametop's compositor: each desktop screen as its own SteamVR panel";
    mainProgram = "ft-screens";
    platforms = lib.platforms.linux;
  };
}
