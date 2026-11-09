# ft-reset-timer, Reset Screen Layout's three-second countdown (layout/countdown/build.sh).
# It finds the host's Noto Sans in /usr/share/fonts at run time; nixpkgs' is only for the check.
{
  lib,
  stdenv,
  openvr,
  vrclientDeps,
  stb,
  noto-fonts,
  src,
}:

stdenv.mkDerivation {
  pname = "ft-reset-timer";
  version = "0-unstable";
  inherit src;
  sourceRoot = "source/layout/countdown";

  buildInputs = [ openvr ] ++ vrclientDeps.buildInputs;

  buildPhase = ''
    runHook preBuild
    mkdir -p build/include
    cp ${stb.truetype} build/include/stb_truetype.h
    cp ${stb.imageWrite} build/include/stb_image_write.h
    $CXX -std=c++17 -O2 -Wall -Wextra -Wno-missing-field-initializers -Ibuild/include \
      -I${openvr}/include/openvr -o ft-reset-timer ft-reset-timer.cpp -lopenvr_api -ldl \
      ${vrclientDeps.ldflags} -pthread
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin ft-reset-timer
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    # Offline timing and render checks (no OpenVR).
    $out/bin/ft-reset-timer --check --font ${noto-fonts}/share/fonts/noto/NotoSans.ttf
    ${vrclientDeps.check}
    vrclient_check $out/bin/ft-reset-timer
    runHook postInstallCheck
  '';

  meta = {
    description = "Reset Screen Layout's head-following 3-2-1 countdown";
    mainProgram = "ft-reset-timer";
    platforms = lib.platforms.linux;
  };
}
