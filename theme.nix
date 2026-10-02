# Omarchy's themes for the Hyprland session, with a live theme switcher.
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

  themes = pkgs.runCommand "omarchy-themes" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 ${./theme-generate.py} ${omarchy}/themes $out
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
    if [ "$(cat "$state/current/mode")" = light ]; then scheme=prefer-light; else scheme=prefer-dark; fi
    ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'$scheme'" 2>/dev/null || true
  '';

  restartWallpaper = ''
    pkill -x swaybg || true
    hyprctl dispatch exec "uwsm app -- swaybg -i ${stateDir}/background -m fill" >/dev/null
  '';

  # Switch theme and reload what shows it. Alacritty reloads its imported colours by itself.
  themeSet = pkgs.writeShellScript "theme-set" ''
    ${link} "$1"
    hyprctl reload >/dev/null
    pkill -SIGUSR2 waybar || true
    ${pkgs.mako}/bin/makoctl reload || true
    ${restartWallpaper}
    notify-send -t 2000 "Theme: $(cat ${themes}/themes/"$(cat ${stateDir}/name)"/title)"
  '';

  # SUPER + CTRL + SHIFT + SPACE, like Omarchy's theme menu
  themeMenu = pkgs.writeShellScript "theme-menu" ''
    current=$(cat ${stateDir}/name 2>/dev/null)
    mapfile -t names < ${themes}/list
    titles=()
    for n in "''${names[@]}"; do
      t=$(cat ${themes}/themes/"$n"/title)
      [ "$n" = "$current" ] && t="$t  (current)"
      titles+=("$t")
    done
    choice=$(printf '%s\n' "''${titles[@]}" | walker --dmenu -p Theme) || exit 0
    for i in "''${!titles[@]}"; do
      [ "''${titles[$i]}" = "$choice" ] && exec ${themeSet} "''${names[$i]}"
    done
  '';

  # SUPER + CTRL + SPACE: next wallpaper of the current theme
  backgroundNext = pkgs.writeShellScript "background-next" ''
    state=${stateDir}
    mapfile -t bgs < <(ls "$state/current/backgrounds")
    cur=$(basename "$(readlink "$state/background")")
    next=''${bgs[0]}
    for i in "''${!bgs[@]}"; do
      if [ "''${bgs[$i]}" = "$cur" ]; then next=''${bgs[$(( (i + 1) % ''${#bgs[@]} ))]}; fi
    done
    ln -sfn "$(readlink -f "$state/current/backgrounds/$next")" "$state/background"
    ${restartWallpaper}
  '';
in
{
  inherit themes stateDir link themeSet themeMenu backgroundNext;
}
