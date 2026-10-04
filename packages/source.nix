# Upstream Frametop with this repo's patches (patches/; see README.md). A patch that
# stops applying fails here.
{
  lib,
  applyPatches,
  frametop,
}:

applyPatches {
  # The packages' sourceRoot is "source/<dir>".
  name = "source";
  src = frametop;
  patches = lib.filesystem.listFilesRecursive ../patches;
}
