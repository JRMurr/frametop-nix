# Frametop's keyboard: Full Keyboard for Steam Frame by TaiKeid, vendored in keyboard/
# (keyboard/build.sh). frametop-keyboard.service runs it with --frametop.
# Linked against nixpkgs' openvr, as the other OpenVR programs here are, and Vulkan comes
# from /run/opengl-driver (autoAddDriverRunpath). Anthy (Japanese) and the Steam keyboard
# replacement's python3 are looked up at run time upstream; here they're store paths.
{
  lib,
  stdenv,
  cmake,
  ninja,
  pkg-config,
  python3,
  wayland-scanner,
  autoAddDriverRunpath,
  cairo,
  pango,
  libxkbcommon,
  json_c,
  wayland,
  SDL2,
  vulkan-loader,
  vulkan-headers,
  glib,
  pyzy,
  libhangul,
  anthy,
  openvr,
  vrclientDeps,
  src,
}:

stdenv.mkDerivation {
  pname = "ft-keyboard";
  version = "0.8.1-unstable";
  inherit src;
  sourceRoot = "source/keyboard";

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    python3
    wayland-scanner
    autoAddDriverRunpath
  ];
  buildInputs = [
    cairo
    pango
    libxkbcommon
    json_c
    wayland
    SDL2
    vulkan-loader
    vulkan-headers
    glib
    pyzy
    libhangul
    openvr
  ]
  ++ vrclientDeps.buildInputs;

  postPatch = ''
    substituteInPlace src/japanese.cpp \
      --replace-fail '"libanthy.so.0"' '"${anthy}/lib/libanthy.so.0"'
    substituteInPlace src/native_replacement.cpp \
      --replace-fail 'char python[] = "python3"' 'char python[] = "${python3}/bin/python3"'
  '';

  cmakeFlags = [
    "-DOPENVR_LIBRARY=${openvr}/lib/libopenvr_api.so"
    "-DOPENVR_RUNTIME_PATH=${openvr}/lib"
    # TODO: run its ctest suite here; several tests want a session bus or SteamVR.
    "-DBUILD_TESTING=OFF"
  ];

  # The flags have spaces, which cmakeFlags would split.
  preConfigure = ''
    cmakeFlagsArray+=("-DCMAKE_EXE_LINKER_FLAGS=${vrclientDeps.ldflags}")
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${vrclientDeps.check}
    vrclient_check $out/bin/framekeyboard
    test -e $out/lib/framekeyboard/framekeyboard-pinyin.so
    test -e $out/lib/framekeyboard/framekeyboard-hangul.so
    test -e ${anthy}/lib/libanthy.so.0
    runHook postInstallCheck
  '';

  meta = {
    description = "Full Keyboard for Steam Frame, as Frametop's keyboard";
    homepage = "https://github.com/TaiKeid/steam-frame-full-keyboard";
    license = lib.licenses.mit;
    mainProgram = "framekeyboard";
    platforms = lib.platforms.linux;
  };
}
