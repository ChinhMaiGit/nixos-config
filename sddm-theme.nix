# Omarchy's SDDM login theme (basecamp/omarchy default/sddm/omarchy, MIT) with Main.qml from
# ./sddm (adds a session line and F2 switch). Installed as the SDDM theme "omarchy".
{ pkgs }:

let
  omarchy = pkgs.fetchFromGitHub {
    owner = "basecamp";
    repo = "omarchy";
    rev = "821ae589059ffdadc970315f866c94b55d268af7";
    hash = "sha256-pgiltTj1hlgRXq058HlibqHX3QDeIayYzRaRGltcFhU=";
  };
in
pkgs.runCommand "sddm-theme-omarchy" { } ''
  mkdir -p $out/share/sddm/themes
  cp -r ${omarchy}/default/sddm/omarchy $out/share/sddm/themes/omarchy
  chmod -R u+w $out/share/sddm/themes/omarchy
  cp ${./sddm/Main.qml} $out/share/sddm/themes/omarchy/Main.qml
''
