# Omarchy's themes (and Chinh's own in ./themes) for the Hyprland session, with a live theme switcher.
#
# At build time every theme in basecamp/omarchy (themes/<name>/colors.toml, MIT) becomes a
# folder of colour files for Hyprland, Waybar, Mako, Alacritty and Hyprlock, like Omarchy's
# default/themed/*.tpl templates, plus the theme's wallpapers. The apps read them through
# ~/.local/state/theme/current, a symlink that the switcher repoints and then reloads the apps.
{ pkgs, config }:

let
  omarchy = pkgs.fetchFromGitHub {
    owner = "basecamp";
    repo = "omarchy";
    rev = "821ae589059ffdadc970315f866c94b55d268af7";
    hash = "sha256-pgiltTj1hlgRXq058HlibqHX3QDeIayYzRaRGltcFhU=";
  };

  stateDir = "${config.xdg.stateHome}/theme";
  defaultTheme = "tokyo-night";
  defaultFont = "JetBrainsMono Nerd Font";

  # Omarchy's themes plus Chinh's own (./themes/<name>/colors.toml + backgrounds/)
  themeSources = pkgs.runCommand "theme-sources" { } ''
    mkdir $out
    for d in ${omarchy}/themes/* ${./themes}/*; do ln -s "$d" $out/; done
  '';

  themes = pkgs.runCommand "omarchy-themes" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 ${./theme-generate.py} ${themeSources} $out
  '';

  # Points ~/.local/state/theme at a theme (and a wallpaper of it). Keeps the current
  # wallpaper when it belongs to the theme, so a rebuild doesn't change it.
  link = pkgs.writeShellScript "theme-link" ''
    set -eu
    state=${stateDir}
    name=''${1:-$(cat "$state/name" 2>/dev/null || echo ${defaultTheme})}
    [ -d ${themes}/themes/"$name" ] || name=${defaultTheme}
    mkdir -p "$state"
    printf '%s\n' "$name" > "$state/name"
    ln -sfn ${themes}/themes/"$name" "$state/current"
    bg=$(basename "$(readlink "$state/background" 2>/dev/null)" 2>/dev/null || true)
    if [ -z "$bg" ] || [ ! -e "$state/current/backgrounds/$bg" ]; then
      bg=$(ls "$state/current/backgrounds" | head -n1)
    fi
    ln -sfn "$(readlink -f "$state/current/backgrounds/$bg")" "$state/background"
    # Font (gear menu > Font): files the apps read next to the theme's colours
    font=$(cat "$state/font" 2>/dev/null || echo "${defaultFont}")
    printf '* { font-family: "%s"; }\n' "$font" > "$state/font.css"
    printf '[font]\nnormal = { family = "%s", style = "Regular" }\nbold = { family = "%s", style = "Bold" }\nitalic = { family = "%s", style = "Italic" }\n' \
      "$font" "$font" "$font" > "$state/font.toml"
    printf '$font = %s\n' "$font" > "$state/font.conf"
    sed "s/^font=.*/font=$font 11/" "$state/current/mako.ini" > "$state/mako.ini"
    # System-wide "monospace" default, like omarchy-font-set: code text in Edge, VS Code and
    # other apps. Its own file, so ~/.config/fontconfig/fonts.conf (KDE's rendering settings)
    # stays untouched.
    mkdir -p ${config.xdg.configHome}/fontconfig/conf.d
    cat > ${config.xdg.configHome}/fontconfig/conf.d/60-chosen-monospace.conf <<EOF
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
    <fontconfig>
      <match target="pattern">
        <test name="family" qual="any"><string>monospace</string></test>
        <edit name="family" mode="prepend_first" binding="strong"><string>$font</string></edit>
      </match>
    </fontconfig>
    EOF

    if [ "$(cat "$state/current/mode")" = light ]; then scheme=prefer-light; else scheme=prefer-dark; fi
    ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'$scheme'" 2>/dev/null || true
  '';

  hyprctl = "${pkgs.hyprland}/bin/hyprctl";
  # swaybg runs as a user service (hyprland.nix) and reads ~/.local/state/theme/background at
  # start; restarting it shows the new wallpaper. (pkill -x swaybg never matched: NixOS runs it
  # as ".swaybg-wrapped", so every switch had added another swaybg.)
  restartWallpaper = ''
    ${pkgs.systemd}/bin/systemctl --user restart swaybg.service
  '';

  # Switch theme and reload what shows it. Alacritty reloads its imported colours by itself.
  themeSet = pkgs.writeShellScript "theme-set" ''
    ${link} "$1"
    ${hyprctl} reload >/dev/null
    ${pkgs.procps}/bin/pkill -SIGUSR2 waybar || true
    ${pkgs.mako}/bin/makoctl reload || true
    ${restartWallpaper}
    ${pkgs.systemd}/bin/systemctl --user restart walker.service   # reads its colours at start
    ${pkgs.libnotify}/bin/notify-send -t 2000 "Theme: $(cat ${themes}/themes/"$(cat ${stateDir}/name)"/title)"
  '';

  # Set the font (from the gear menu) and reload what shows it, like Omarchy's omarchy-font-set.
  fontSet = pkgs.writeShellScript "font-set" ''
    printf '%s\n' "$1" > ${stateDir}/font
    ${link}
    ${pkgs.procps}/bin/pkill -SIGUSR2 waybar || true
    ${pkgs.mako}/bin/makoctl reload || true
    ${pkgs.systemd}/bin/systemctl --user restart walker.service
    ${pkgs.libnotify}/bin/notify-send -t 4000 "Font: $1" "Open apps (Edge, VS Code) show it in code text after a restart"
  '';

  # Set a wallpaper of the current theme by file name (from the background menu)
  backgroundSet = pkgs.writeShellScript "background-set" ''
    ln -sfn "$(readlink -f ${stateDir}/current/backgrounds/"$1")" ${stateDir}/background
    ${restartWallpaper}
  '';

  # Lists (and wallpaper thumbnails) for the image picker
  pickerData = pkgs.runCommand "omarchy-theme-pickers"
    { nativeBuildInputs = [ pkgs.python3 pkgs.imagemagick ]; } ''
    python3 ${./theme-generate.py} pickers ${themes} $out
  '';

  # Omarchy-style image carousel (picker.qml, Quickshell) for themes or the current theme's
  # wallpapers: SUPER + CTRL + SHIFT + SPACE and SUPER + CTRL + SPACE.
  picker = pkgs.writeShellScript "picker" ''
    state=${stateDir}
    colors=$state/current/colors.json
    jq=${pkgs.jq}/bin/jq
    case "$1" in
      themes)
        items=${pickerData}/pickers/themes.json
        selected=$(cat "$state/name")
        command=${themeSet} ;;
      backgrounds)
        items=${pickerData}/pickers/backgrounds-$(cat "$state/name").json
        selected=$(basename "$(readlink "$state/background")")
        command=${backgroundSet} ;;
      *) exit 1 ;;
    esac
    PICKER_ITEMS=$(cat "$items") \
    PICKER_SELECTED=$selected \
    PICKER_COMMAND=$command \
    PICKER_ACCENT=$($jq -r .accent "$colors") \
    PICKER_BACKGROUND=$($jq -r .background "$colors") \
    PICKER_FOREGROUND=$($jq -r .bright_foreground "$colors") \
      exec ${pkgs.quickshell}/bin/qs --no-duplicate -p ${./picker.qml}
  '';

in
{
  inherit themes stateDir link picker fontSet;
}
