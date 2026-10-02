# Omarchy-style Hyprland desktop (Home Manager), a second login session next to KDE Plasma.
# Look, colours and keybindings follow basecamp/omarchy (MIT, (c) David Heinemeier Hansson)
# at commit 821ae58. Omarchy 4's own Quickshell bar and menus are replaced by the pre-4.0
# Omarchy stack: Waybar, Walker, Mako, Hyprlock, SwayOSD.
#
# Everything here starts from Hyprland itself (exec-once), not from systemd user services:
# those would also start inside Plasma, which shares graphical-session.target.
{ config, pkgs, lib, ... }:

let
  # Omarchy's Tokyo Night theme (themes/tokyo-night/colors.toml)
  c = {
    bg = "#1a1b26";
    bgDark = "#13141c";
    bgLight = "#24283b";
    selection = "#292e42";
    muted = "#414868";
    fg = "#a9b1d6";
    fgDim = "#565f89";
    fgBright = "#c0caf5";
    accent = "#7aa2f7";
    red = "#f7768e";
    yellow = "#e0af68";
    green = "#9ece6a";
    cyan = "#449dab";
    magenta = "#bb9af7";
  };
  font = "JetBrainsMono Nerd Font";

  wallpaper = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/basecamp/omarchy/821ae589059ffdadc970315f866c94b55d268af7/themes/tokyo-night/backgrounds/1-quattro.webp";
    hash = "sha256-yblsEG0nWBE5hqjdtiHzhn7fZeCaidrVGrufxfNEcUY=";
  };

  # The Edge launcher in ~/.local/bin keeps Edge's fontconfig cache separate (see home.nix).
  browser = "${config.home.homeDirectory}/.local/bin/microsoft-edge";
  app = cmd: "uwsm app -- ${cmd}";

  mako = "${pkgs.mako}/bin/mako";
  makoctl = "${pkgs.mako}/bin/makoctl";

  # SUPER + ESCAPE, like Omarchy's system menu
  powerMenu = pkgs.writeShellScript "power-menu" ''
    choice=$(printf '%s\n' Lock Suspend "Log out" Restart "Shut down" | walker --dmenu)
    case "$choice" in
      Lock) loginctl lock-session ;;
      Suspend) systemctl suspend ;;
      "Log out") uwsm stop ;;
      Restart) systemctl reboot ;;
      "Shut down") systemctl poweroff ;;
    esac
  '';

  # Font Awesome glyphs from the Nerd Font, written as JSON escapes
  icon = code: builtins.fromJSON ''"\u${code}"'';

  workspaceKeys = lib.concatMap (n:
    let key = "code:${toString (n + 9)}"; ws = toString n;
    in [
      "SUPER, ${key}, workspace, ${ws}"
      "SUPER SHIFT, ${key}, movetoworkspace, ${ws}"
      "SUPER SHIFT ALT, ${key}, movetoworkspacesilent, ${ws}"
    ]) (lib.range 1 10);
in
{
  home.packages = with pkgs; [
    walker elephant swaybg swayosd hypridle
    hyprshot hyprpicker wl-clipboard playerctl wiremix
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    # Hyprland itself comes from the NixOS module (programs.hyprland), started by UWSM.
    package = null;
    portalPackage = null;
    systemd.enable = false;
    # Classic config format; Home Manager's 26.05 default would be Lua.
    configType = "hyprlang";

    settings = {
      # Same layout as in Plasma: 75 Hz HDMI screen left, 165 Hz DP screen right.
      monitor = [
        "HDMI-A-1, 1920x1080@74.97, 0x0, 1"
        "DP-3, 1920x1080@165, 1920x0, 1"
        ", preferred, auto, 1"
      ];

      exec-once = [
        (app "swaybg -i ${wallpaper} -m fill")
        (app "waybar")
        (app "${mako}")
        (app "swayosd-server")
        (app "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent")   # not on PATH
        (app "hypridle")
        (app "elephant")
        (app "walker --gapplication-service")
      ];

      input = {
        kb_layout = "us";
        follow_mouse = 1;
        sensitivity = 0;
      };

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
        "col.inactive_border" = "rgba(595959aa)";
        resize_on_border = false;
        allow_tearing = false;
        layout = "dwindle";
      };

      decoration = {
        rounding = 0;
        shadow.enabled = false;
        blur.enabled = false;
      };

      animations.enabled = true;
      bezier = [
        "easeOutQuint, 0.23, 1, 0.32, 1"
        "easeInOutCubic, 0.65, 0.05, 0.36, 1"
        "linear, 0, 0, 1, 1"
        "almostLinear, 0.5, 0.5, 0.75, 1.0"
        "quick, 0.15, 0, 0.1, 1"
      ];
      animation = [
        "global, 1, 10, default"
        "border, 1, 5.39, easeOutQuint"
        "windows, 1, 3.79, easeOutQuint"
        "windowsIn, 1, 4.1, easeOutQuint, popin 87%"
        "windowsOut, 1, 1.49, linear, popin 87%"
        "fadeIn, 1, 1.73, almostLinear"
        "fadeOut, 1, 1.46, almostLinear"
        "fade, 1, 3.03, quick"
        "layers, 1, 3.81, easeOutQuint"
        "layersIn, 1, 4, easeOutQuint, fade"
      ];

      dwindle = {
        preserve_split = true;
        force_split = 2;
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        # Variable refresh rate only in full-screen apps (Plasma's "Automatic");
        # "Always" made the desktop flicker on this monitor.
        vrr = 2;
      };

      xwayland.force_zero_scaling = true;
      ecosystem.no_update_news = true;

      # Omarchy's keybindings (default/hypr/bindings), with Chinh's apps.
      bind = [
        "SUPER, RETURN, exec, ${app "alacritty"}"
        "SUPER SHIFT, RETURN, exec, ${app browser}"
        "SUPER SHIFT, B, exec, ${app browser}"
        "SUPER SHIFT, F, exec, ${app "dolphin"}"
        "SUPER SHIFT, N, exec, ${app "code"}"
        "SUPER, SPACE, exec, walker"
        "SUPER, ESCAPE, exec, ${powerMenu}"

        "SUPER, W, killactive,"
        "SUPER, Q, killactive,"
        "SUPER, J, layoutmsg, togglesplit"
        "SUPER, P, pseudo,"
        "SUPER, T, togglefloating,"
        "SUPER, F, fullscreen, 0"
        "SUPER ALT, F, fullscreen, 1"

        "SUPER, left, movefocus, l"
        "SUPER, right, movefocus, r"
        "SUPER, up, movefocus, u"
        "SUPER, down, movefocus, d"
        "SUPER SHIFT, left, swapwindow, l"
        "SUPER SHIFT, right, swapwindow, r"
        "SUPER SHIFT, up, swapwindow, u"
        "SUPER SHIFT, down, swapwindow, d"

        "SUPER, S, togglespecialworkspace, scratchpad"
        "SUPER ALT, S, movetoworkspacesilent, special:scratchpad"
        "SUPER, TAB, workspace, e+1"
        "SUPER SHIFT, TAB, workspace, e-1"
        "SUPER CTRL, TAB, workspace, previous"
        "SUPER, mouse_down, workspace, e+1"
        "SUPER, mouse_up, workspace, e-1"
        "SUPER SHIFT ALT, left, movecurrentworkspacetomonitor, l"
        "SUPER SHIFT ALT, right, movecurrentworkspacetomonitor, r"

        "ALT, TAB, cyclenext,"
        "ALT, TAB, bringactivetotop,"
        "ALT SHIFT, TAB, cyclenext, prev"
        "ALT SHIFT, TAB, bringactivetotop,"
        "CTRL ALT, TAB, focusmonitor, +1"

        # code:20 / code:21 are the minus and equals keys
        "SUPER, code:20, resizeactive, -100 0"
        "SUPER, code:21, resizeactive, 100 0"
        "SUPER SHIFT, code:20, resizeactive, 0 -100"
        "SUPER SHIFT, code:21, resizeactive, 0 100"

        "SUPER, comma, exec, ${makoctl} dismiss"
        "SUPER SHIFT, comma, exec, ${makoctl} dismiss --all"
        "SUPER CTRL, comma, exec, ${makoctl} mode -t do-not-disturb"
        "SUPER SHIFT, SPACE, exec, pkill -SIGUSR1 waybar"

        ", PRINT, exec, hyprshot -m region -o ${config.home.homeDirectory}/Pictures/Screenshots"
        "SUPER, PRINT, exec, pkill hyprpicker || hyprpicker -a"
      ] ++ workspaceKeys;

      bindm = [
        "SUPER, mouse:272, movewindow"
        "SUPER, mouse:273, resizewindow"
      ];

      # Volume keys with the on-screen display; repeat while held, work on the lock screen.
      bindel = [
        ", XF86AudioRaiseVolume, exec, swayosd-client --output-volume raise"
        ", XF86AudioLowerVolume, exec, swayosd-client --output-volume lower"
      ];
      bindl = [
        ", XF86AudioMute, exec, swayosd-client --output-volume mute-toggle"
        ", XF86AudioMicMute, exec, swayosd-client --input-volume mute-toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
      ];
    };
  };

  # Session environment for UWSM (applies only to the Hyprland session).
  # KDE apps (Dolphin, Kate, Gwenview) keep their Plasma look through the "kde" Qt theme.
  xdg.configFile."uwsm/env".text = ''
    export XCURSOR_THEME=breeze_cursors
    export XCURSOR_SIZE=24
    export HYPRCURSOR_SIZE=24
    export QT_QPA_PLATFORMTHEME=kde
    export ELECTRON_OZONE_PLATFORM_HINT=wayland
  '';

  # Lock before sleep only. No idle lock or screen-off, matching the Plasma power settings.
  xdg.configFile."hypr/hypridle.conf".text = ''
    general {
      lock_cmd = pidof hyprlock || hyprlock
      before_sleep_cmd = loginctl lock-session
      after_sleep_cmd = hyprctl dispatch dpms on
    }
  '';

  programs.hyprlock = {
    enable = true;
    settings = {
      general.hide_cursor = true;
      background = [{
        monitor = "";
        path = "${wallpaper}";
        blur_passes = 3;
      }];
      input-field = [{
        monitor = "";
        size = "600, 90";
        position = "0, 0";
        halign = "center";
        valign = "center";
        outline_thickness = 4;
        rounding = 0;
        inner_color = "rgba(1a1b26cc)";
        outer_color = "rgb(7aa2f7)";
        font_color = "rgb(c0caf5)";
        check_color = "rgb(9ece6a)";
        fail_color = "rgb(f7768e)";
        font_family = font;
        placeholder_text = "Enter password";
        fade_on_empty = false;
      }];
    };
  };

  programs.alacritty = {
    enable = true;
    settings = {
      env.TERM = "xterm-256color";
      font = {
        normal = { family = font; style = "Regular"; };
        bold = { family = font; style = "Bold"; };
        italic = { family = font; style = "Italic"; };
        size = 9;
      };
      window = {
        padding = { x = 14; y = 14; };
        decorations = "None";
      };
      colors = {
        primary = { background = c.bg; foreground = c.fg; };
        normal = {
          black = "#15161e"; red = c.red; green = c.green; yellow = c.yellow;
          blue = c.accent; magenta = c.magenta; cyan = "#7dcfff"; white = c.fg;
        };
        bright = {
          black = c.muted; red = c.red; green = c.green; yellow = c.yellow;
          blue = c.accent; magenta = c.magenta; cyan = "#7dcfff"; white = c.fgBright;
        };
        selection.background = c.selection;
      };
    };
  };

  programs.waybar = {
    enable = true;
    settings.main = {
      layer = "top";
      position = "top";
      height = 26;
      spacing = 0;
      modules-left = [ "hyprland/workspaces" ];
      modules-center = [ "clock" ];
      modules-right = [ "tray" "bluetooth" "network" "pulseaudio" "cpu" "custom/power" ];

      "hyprland/workspaces" = {
        on-click = "activate";
        format = "{name}";
        persistent-workspaces."*" = 5;
      };
      clock = {
        format = "{:%A %H:%M}";
        format-alt = "{:%d %B W%V %Y}";
        tooltip = false;
      };
      network = {
        format-wifi = icon "f1eb";
        format-ethernet = icon "f0e8";
        format-disconnected = icon "f127";
        tooltip-format-wifi = "{essid} ({frequency} GHz, {signalStrength}%)\n⇣{bandwidthDownBytes}  ⇡{bandwidthUpBytes}";
        interval = 3;
        on-click = app "alacritty -e nmtui";
      };
      pulseaudio = {
        format = "{icon}";
        format-muted = icon "f026";
        format-icons.default = [ (icon "f026") (icon "f027") (icon "f028") ];
        tooltip-format = "Volume {volume}%";
        on-click = app "alacritty -e wiremix";
        on-click-right = "swayosd-client --output-volume mute-toggle";
        scroll-step = 5;
      };
      bluetooth = {
        format = icon "f293";
        format-disabled = "";
        format-off = "";
        tooltip-format = "{num_connections} connected";
        on-click = app "systemsettings kcm_bluetooth";
      };
      cpu = {
        interval = 5;
        format = icon "f2db";
        tooltip = true;
        on-click = app "alacritty -e btop";
      };
      "custom/power" = {
        format = icon "f011";
        tooltip = false;
        on-click = "${powerMenu}";
      };
      tray.spacing = 12;
    };
    style = ''
      * {
        font-family: "${font}";
        font-size: 12px;
        min-height: 0;
        border: none;
      }
      window#waybar {
        background-color: ${c.bg};
        color: ${c.fg};
      }
      #workspaces button {
        padding: 0 6px;
        margin: 0 1.5px;
        color: ${c.fgDim};
        background: transparent;
        border-radius: 0;
      }
      #workspaces button.active { color: ${c.fgBright}; }
      #workspaces button.empty { opacity: 0.5; }
      #workspaces button:hover { background: ${c.selection}; }
      #clock { font-weight: bold; }
      #tray, #bluetooth, #network, #pulseaudio, #cpu, #custom-power {
        padding: 0 10px;
      }
      #custom-power { margin-right: 6px; }
      tooltip {
        background: ${c.bgDark};
        border: 2px solid ${c.accent};
      }
    '';
  };

  # Mako's package registers it as the D-Bus notification service, so installing it (or
  # Home Manager's services.mako) could let it start inside Plasma during login. Run it by
  # store path from Hyprland only, and write its config directly.
  xdg.configFile."mako/config".text = ''
    font=${font} 11
    background-color=${c.bg}
    text-color=${c.fg}
    border-color=${c.accent}
    border-size=2
    border-radius=0
    padding=10
    width=420
    default-timeout=5000
    anchor=top-right
    outer-margin=20

    [mode=do-not-disturb]
    invisible=1
  '';

  # Dark GTK apps in this session, like Omarchy.
  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
}
