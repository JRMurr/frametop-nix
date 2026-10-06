# ft-eyegrab, our own eye tracker's frame grabber (gaze/tracker/build.sh). A root system
# service runs it (frametop-eyegrab.service).
{
  lib,
  stdenv,
  src,
}:

stdenv.mkDerivation {
  pname = "ft-eyegrab";
  version = "0-unstable";
  inherit src;
  sourceRoot = "source/gaze/tracker";

  buildPhase = ''
    runHook preBuild
    $CC -std=gnu11 -O2 -Wall -Wextra -pthread -o ft-eyegrab ft-eyegrab.c
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin ft-eyegrab
    runHook postInstall
  '';

  meta = {
    description = "Frametop's eye-camera frame grabber, for its own eye tracker";
    mainProgram = "ft-eyegrab";
    platforms = lib.platforms.linux;
  };
}
