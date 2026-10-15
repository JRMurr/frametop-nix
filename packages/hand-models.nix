# The fine-tuned hand models ft-hands prefers (hands/models.sh fetch): hands/models.pin names a
# commit of the Hugging Face repo and every file's sha256, so they're fetched here, as
# hands/models/student. models.sh's own updates (HANDS_MODELS_UPDATE) can't write into the store;
# a newer pin comes with a newer upstream commit instead.
{
  lib,
  runCommand,
  fetchurl,
  frametop,
}:

let
  pinText = builtins.readFile "${frametop}/hands/models.pin";
  lines = map (lib.splitString " ") (
    lib.filter (l: l != "" && !lib.hasPrefix "#" l) (lib.splitString "\n" pinText)
  );
  value =
    key: lib.elemAt (lib.findFirst (l: lib.head l == key) (throw "models.pin: no ${key}") lines) 1;
  format = value "format";
  rev = value "rev";
  model = value "model";
  files = map (l: {
    name = lib.elemAt l 1;
    sha256 = lib.elemAt l 2;
  }) (lib.filter (l: lib.head l == "file") lines);
  hf = "https://huggingface.co/DeeJanuz/frametop-hands-models/resolve/${rev}";
  fetch =
    f:
    fetchurl {
      name = "frametop-hand-model-${f.name}";
      # LICENSE and README.md are the repo's, the rest the model folder's (models.sh).
      url =
        if
          lib.elem f.name [
            "LICENSE"
            "README.md"
          ]
        then
          "${hf}/${f.name}"
        else
          "${hf}/${model}/${f.name}";
      inherit (f) sha256;
    };
in
assert lib.assertMsg (format == "1") "hands/models.pin has format ${format}; ft-hands here reads 1";
runCommand "frametop-hand-models-${model}" { passthru = { inherit model rev; }; } ''
  mkdir $out
  ${lib.concatMapStrings (f: "ln -s ${fetch f} $out/${f.name}\n") files}
  cp ${frametop}/hands/models.pin $out/PIN
  echo "DeeJanuz/frametop-hands-models@${builtins.substring 0 7 rev} ${model}" > $out/VERSION
''
