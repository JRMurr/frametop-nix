# stb headers for the panels' text and pictures (screens/build.sh, gaze/build.sh, and
# hands/rec/build.sh pin this commit).
{ fetchurl }:

let
  rev = "2c980bb59875b0d32144a71867fbdebb2f77cd20";
  header =
    name: hash:
    fetchurl {
      url = "https://raw.githubusercontent.com/nothings/stb/${rev}/${name}";
      inherit hash;
    };
in
{
  truetype = header "stb_truetype.h" "sha256-7NMLBeDdT+o6E8JoEN2eGZLcN5BJSCw5PVoZ5rUJCqs=";
  image = header "stb_image.h" "sha256-WUwv411JSItDgtv67I+YNm3vyoGdkWrJW+zz519CALM=";
}
