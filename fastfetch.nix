# fastfetch (system info in the terminal) and anifetch, which plays a looping animation next
# to it (github.com/Notenlish/anifetch). New terminals show anifetch until a key is pressed
# (that key is used up, it doesn't reach the prompt).
{ pkgs, anifetch, ... }:

let
  # Font Awesome glyphs from the Nerd Font, written as JSON escapes
  icon = code: builtins.fromJSON ''"\u${code}"'';
  anifetchPkg = anifetch.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  # Compact list with Nerd Font icons. Colours are the terminal's own (cyan keys, blue title),
  # so they follow the current theme. No local IP on purpose.
  programs.fastfetch = {
    enable = true;
    settings = {
      logo = { source = "nixos_small"; padding = { top = 1; right = 3; }; };
      display = {
        separator = "  ";
        color = { keys = "cyan"; title = "blue"; };
        key.width = 14;
      };
      modules = [
        { type = "title"; format = "{user-name}@{host-name}"; color = { user = "blue"; host = "cyan"; }; }
        { type = "separator"; string = "─"; }
        { type = "os"; key = "${icon "f313"}  OS"; format = "{pretty-name}"; }
        { type = "kernel"; key = "${icon "f17c"}  Kernel"; }
        { type = "wm"; key = "${icon "f2d2"}  WM"; }
        { type = "packages"; key = "${icon "f187"}  Packages"; }
        { type = "uptime"; key = "${icon "f017"}  Uptime"; }
        "break"
        { type = "cpu"; key = "${icon "f2db"}  CPU"; format = "{name} ({cores-logical})"; }
        { type = "gpu"; key = "${icon "f26c"}  GPU"; format = "{name}"; }
        { type = "memory"; key = "${icon "f1c0"}  Memory"; }
        { type = "disk"; key = "${icon "f0a0"}  Disk"; folders = "/"; }
        "break"
        { type = "colors"; symbol = "circle"; }
      ];
    };
  };

  home.packages = [ anifetchPkg ];

  # Run by ~/.bashrc in new interactive terminals only (not scripts, not `alacritty -e ...`
  # windows, which start no shell). Any key stops it and goes on to the prompt.
  xdg.configFile."anifetch/autostart.sh".text = ''
    if [[ $- == *i* ]] && [ -t 0 ] && [ -t 1 ] && [ -z "''${ANIFETCH_SHOWN:-}" ]; then
      export ANIFETCH_SHOWN=1   # once per terminal, not again in nested shells
      # The animation is as tall as the system info (14 lines, Chinh's wish, 2026-10-05) and then
      # about 65 columns wide; with the info beside it that needs ~125 columns (a full or
      # half-width window). Narrower windows show plain fastfetch.
      cols=$(tput cols)
      if [ "$cols" -ge 125 ]; then
        ${anifetchPkg}/bin/anifetch example.mp4 -W 64 -H 14
      else
        fastfetch
      fi
      unset cols
    fi
  '';
}
