# ft-hands, the hand tracker (hands/Makefile). It finds its models at
# <argv[0] dir>/../models/ncnn, so the tree runs it as hands/build/ft-hands next to
# hands/models.
#
# Upstream links a static ncnn built at the tag its models were converted for (20260526).
# nixpkgs' older, shared one gives the same outputs on all four models (float and int8);
# ft-hands turns its Vulkan off. The Makefile's targets need that static ncnn (and would
# clone it), so this runs the Makefile's commands itself.
{
  lib,
  stdenv,
  jsoncpp,
  ncnn,
  src,
}:

stdenv.mkDerivation {
  pname = "ft-hands";
  version = "0-unstable";
  inherit src;
  sourceRoot = "source/hands";

  buildInputs = [
    jsoncpp
    ncnn
  ];

  buildPhase = ''
    runHook preBuild
    cxx="$CXX -O2 -g -Wall -Wextra -Wno-unused-parameter -Wno-psabi -std=c++17 -fopenmp \
      -I${lib.getDev ncnn}/include/ncnn"
    track="track/calib.cpp track/nets.cpp track/tracker.cpp track/io.cpp track/record.cpp \
      track/pinch.cpp track/sides.cpp"
    mkdir -p build
    $cxx -o build/ft-hands track/main.cpp $track -lncnn -ljsoncpp -fopenmp -lpthread
    $cxx -o build/sides-test tests/sides_test.cpp $track -lncnn -ljsoncpp -fopenmp -lpthread
    runHook postBuild
  '';

  # make check
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    build/sides-test
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin build/ft-hands
    runHook postInstall
  '';

  meta = {
    description = "Frametop's hand tracker: hands for the screens' cutouts, pinches for the pointer";
    mainProgram = "ft-hands";
    platforms = lib.platforms.linux;
  };
}
