# Login screen: Omarchy's SDDM theme folder (basecamp/omarchy default/sddm/omarchy, MIT) with our
# own Main.qml from ./sddm (blurred wallpaper, big clock, password pill, session and keyboard
# pills, power menu; rewritten 2026-10-05) and the Cyan wallpaper. Installed as the SDDM theme "omarchy".
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
  cp ${./themes/cyan/backgrounds/1-wallpaper.jpg} $out/share/sddm/themes/omarchy/background.jpg
''
