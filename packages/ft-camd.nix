# ft-camd, the headset cameras' broker (hands/Makefile). Linked statically, as upstream
# does: it needs file capabilities, which store paths can't carry, so it runs from a copy
# outside the store (frametop-install.service) that must not depend on the store.
{
  lib,
  stdenv,
  glibc,
  src,
}:

stdenv.mkDerivation {
  pname = "ft-camd";
  version = "0-unstable";
  inherit src;
  sourceRoot = "source/hands";

  buildInputs = [ glibc.static ];

  buildFlags = [ "build/ft-camd" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin build/ft-camd
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    if $READELF -d $out/bin/ft-camd | grep -q NEEDED; then
      echo "ft-camd isn't static: its copy outside the store would need store libraries" >&2
      exit 1
    fi
    runHook postInstallCheck
  '';

  meta = {
    description = "Frametop's camera broker: the headset cameras' frames, for hand tracking";
    mainProgram = "ft-camd";
    platforms = lib.platforms.linux;
  };
}
