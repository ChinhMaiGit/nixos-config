# Omarchy-style Hyprland desktop (Home Manager), a second login session next to KDE Plasma.
# Look, colours and keybindings follow basecamp/omarchy (MIT, (c) David Heinemeier Hansson)
# at commit 821ae58. Omarchy 4's own Quickshell bar and menus are replaced by the pre-4.0
# Omarchy stack: Waybar, Walker, Mako, Hyprlock, SwayOSD.
#
# Everything here starts from Hyprland itself (exec-once), not from systemd user services:
# those would also start inside Plasma, which shares graphical-session.target.
# Colours and wallpapers come from the current theme (theme.nix, switcher on SUPER+CTRL+SHIFT+SPACE).
{ config, pkgs, lib, ... }:

let
  theme = import ./theme.nix { inherit pkgs config; };
  current = "${theme.stateDir}/current";

  font = "JetBrainsMono Nerd Font";

  # The Edge launcher in ~/.local/bin keeps Edge's fontconfig cache separate (see home.nix).
  browser = "${config.home.homeDirectory}/.local/bin/microsoft-edge";
  app = cmd: "uwsm app -- ${cmd}";

  # Omarchy 3's launcher size (bin/omarchy-launch-walker)
  launcher = "walker --width 644 --maxheight 300 --minheight 300";

  mako = "${pkgs.mako}/bin/mako";
  makoctl = "${pkgs.mako}/bin/makoctl";

  # SUPER + ESCAPE, like Omarchy's system menu
  powerMenu = pkgs.writeShellScript "power-menu" ''
    choice=$(printf '%s\n' Lock Sleep "Log out" Restart "Shut down" | ${launcher} --dmenu -p System)
    case "$choice" in
      Lock) loginctl lock-session ;;
      Sleep) systemctl suspend ;;
      "Log out") uwsm stop ;;
      Restart) systemctl reboot ;;
      "Shut down") systemctl poweroff ;;
    esac
  '';

  # SUPER + K, like Omarchy's omarchy-menu-keybindings: every described shortcut from the
  # running Hyprland, searchable in Walker; choosing one also runs it.
  keybindingsMenu = pkgs.writeShellScript "keybindings-menu" ''
    binds=$(hyprctl -j binds)
    mapfile -t lines < <(${pkgs.jq}/bin/jq -r '
      def bit($b): ((.modmask / $b) | floor) % 2 == 1;
      def keyname:
        if .keycode > 0 and (.key == "" or (.key | startswith("code:"))) then
          ({"10":"1","11":"2","12":"3","13":"4","14":"5","15":"6","16":"7","17":"8","18":"9","19":"0",
            "20":"MINUS","21":"EQUAL"}[.keycode | tostring] // "code:\(.keycode)")
        elif .key == "mouse:272" then "LEFT MOUSE BUTTON"
        elif .key == "mouse:273" then "RIGHT MOUSE BUTTON"
        elif .key == "mouse_down" then "SCROLL DOWN"
        elif .key == "mouse_up" then "SCROLL UP"
        else .key | ascii_upcase end;
      .[] | select(.has_description)
      | ([ (if bit(64) then "SUPER" else empty end), (if bit(4) then "CTRL" else empty end),
           (if bit(8) then "ALT" else empty end), (if bit(1) then "SHIFT" else empty end),
           keyname ] | join(" + ")) + "  →  " + .description
    ' <<<"$binds")
    mapfile -t actions < <(${pkgs.jq}/bin/jq -r '
      .[] | select(.has_description) | if .mouse then "" else "\(.dispatcher)\t\(.arg)" end
    ' <<<"$binds")

    choice=$(printf '%s\n' "''${lines[@]}" | ${launcher} --dmenu -p Keybindings) || exit 0
    for i in "''${!lines[@]}"; do
      if [[ "''${lines[$i]}" == "$choice" && -n "''${actions[$i]}" ]]; then
        IFS=$'\t' read -r dispatcher arg <<<"''${actions[$i]}"
        hyprctl dispatch "$dispatcher" "$arg" >/dev/null
        break
      fi
    done
  '';

  # SUPER + CTRL + N, like Omarchy's omarchy-toggle-nightlight: 4000 K on, no tint off.
  nightlight = pkgs.writeShellScript "nightlight-toggle" ''
    # Start hyprsunset if it isn't running yet (e.g. right after a rebuild).
    if ! pgrep -x hyprsunset >/dev/null; then
      setsid uwsm app -- hyprsunset >/dev/null 2>&1 &
      sleep 1
    fi
    temp=$(hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+' | head -n1)
    if [[ -n $temp ]] && (( temp < 6000 )); then
      hyprctl hyprsunset identity >/dev/null
      notify-send -t 2000 "Night light off"
    else
      hyprctl hyprsunset temperature 4000 >/dev/null
      notify-send -t 2000 "Night light on"
    fi
  '';

  # Choosing an emoji in SUPER + CTRL + E: Elephant's default only copies it (wl-copy), which
  # looks like nothing happened. Copy it and paste it into the window that had focus. Pasting
  # instead of typing it with wtype: Chromium apps with Wayland IME (Slack) garbled typed emoji.
  # Terminals paste with Ctrl + Shift + V, everything else with Ctrl + V.
  emojiInsert = pkgs.writeShellScript "emoji-insert" ''
    value=$(cat)
    printf '%s' "$value" | ${pkgs.wl-clipboard}/bin/wl-copy
    sleep 0.2   # let Walker close so the previous window has keyboard focus again
    class=$(${pkgs.hyprland}/bin/hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.class // ""')
    case "$class" in
      Alacritty|org.kde.konsole|kitty|foot|com.mitchellh.ghostty)
        ${pkgs.wtype}/bin/wtype -M ctrl -M shift v -m shift -m ctrl ;;
      *)
        ${pkgs.wtype}/bin/wtype -M ctrl v -m ctrl ;;
    esac
  '';

  # SUPER + L, like Omarchy's omarchy-hyprland-workspace-layout-toggle: switch the active
  # workspace between dwindle and Hyprland's scrolling layout. Saved per workspace in a file
  # that hyprland.conf sources, so it survives reloads (theme switches) and logins.
  layoutsFile = "${config.xdg.stateHome}/hypr/workspace-layouts.conf";
  layoutToggle = pkgs.writeShellScript "workspace-layout-toggle" ''
    ws=$(hyprctl activeworkspace -j | ${pkgs.jq}/bin/jq -r .id)
    [[ $ws =~ ^[0-9]+$ ]] || exit 0   # not for the scratchpad
    current=$(hyprctl activeworkspace -j | ${pkgs.jq}/bin/jq -r .tiledLayout)
    if [ "$current" = dwindle ]; then new=scrolling; else new=dwindle; fi
    sed -i "/^workspace = $ws,/d" ${layoutsFile}
    echo "workspace = $ws, layout:$new" >> ${layoutsFile}
    hyprctl keyword workspace "$ws, layout:$new" >/dev/null
    notify-send -t 2000 "Workspace $ws layout: $new"
  '';

  # Font Awesome glyphs from the Nerd Font, written as JSON escapes
  icon = code: builtins.fromJSON ''"\u${code}"'';

  workspaceKeys = lib.concatMap (n:
    let key = "code:${toString (n + 9)}"; ws = toString n;
    in [
      "SUPER, ${key}, Switch to workspace ${ws}, workspace, ${ws}"
      "SUPER SHIFT, ${key}, Move window to workspace ${ws}, movetoworkspace, ${ws}"
      "SUPER SHIFT ALT, ${key}, Move window silently to workspace ${ws}, movetoworkspacesilent, ${ws}"
    ]) (lib.range 1 10);
in
{
  home.packages = with pkgs; [
    walker elephant swaybg swayosd hypridle hyprsunset libnotify
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

      # Border colours of the current theme
      source = [ "${current}/hyprland.conf" layoutsFile ];

      exec-once = [
        # Hand the login password to the KDE Wallet daemon so it unlocks; Plasma does this
        # itself, but its autostart entry isn't run here (gh, Edge, VS Code need the wallet).
        "${pkgs.kdePackages.kwallet-pam}/libexec/pam_kwallet_init"
        (app "waybar")
        (app "${mako} -c ${current}/mako.ini")
        (app "swayosd-server")
        (app "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent")   # not on PATH
        (app "hypridle")
        (app "hyprsunset")
      ];

      # PAM starts a wallet daemon per login and Plasma stops it at logout; do the same here,
      # or an old one stays behind after logging out of Hyprland.
      # No -x: NixOS wrappers rename it (".ksecretd-wrapp"), so match part of the name.
      exec-shutdown = [ "${pkgs.procps}/bin/pkill -u ${config.home.username} ksecretd" ];

      input = {
        kb_layout = "us";
        follow_mouse = 1;
        sensitivity = 0;
      };

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
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

      # Walker opens without animation (Omarchy 3, default/hypr/apps/walker.conf)
      layerrule = [ "no_anim on, match:namespace walker" ];

      xwayland.force_zero_scaling = true;
      ecosystem.no_update_news = true;

      # Omarchy's keybindings (default/hypr/bindings), with Chinh's apps; one key per action
      # (Omarchy's second keys for close and browser removed). The "d" variants
      # (bindd, bindmd, ...) carry a description, which the SUPER + K list shows.
      bindd = [
        "SUPER, K, Show keybindings, exec, ${keybindingsMenu}"
        "SUPER, SPACE, App launcher, exec, ${launcher}"
        "SUPER, ESCAPE, System menu (lock / sleep / log out / restart / shut down), exec, ${powerMenu}"
        "SUPER, RETURN, Terminal, exec, ${app "alacritty"}"
        "SUPER SHIFT, B, Browser, exec, ${app browser}"
        "SUPER SHIFT, F, File manager, exec, ${app "dolphin"}"
        "SUPER SHIFT, N, Editor, exec, ${app "code"}"

        "SUPER, W, Close window, killactive,"
        "SUPER, J, Toggle window split, layoutmsg, togglesplit"
        "SUPER, L, Toggle workspace layout (dwindle / scrolling), exec, ${layoutToggle}"
        "SUPER, P, Pseudo window, pseudo,"
        "SUPER, T, Toggle window floating/tiling, togglefloating,"
        "SUPER, F, Full screen, fullscreen, 0"
        "SUPER ALT, F, Full width, fullscreen, 1"

        "SUPER, left, Focus on left window, movefocus, l"
        "SUPER, right, Focus on right window, movefocus, r"
        "SUPER, up, Focus on above window, movefocus, u"
        "SUPER, down, Focus on below window, movefocus, d"
        "SUPER SHIFT, left, Swap window to the left, swapwindow, l"
        "SUPER SHIFT, right, Swap window to the right, swapwindow, r"
        "SUPER SHIFT, up, Swap window up, swapwindow, u"
        "SUPER SHIFT, down, Swap window down, swapwindow, d"
      ] ++ workspaceKeys ++ [
        "SUPER, S, Toggle scratchpad, togglespecialworkspace, scratchpad"
        "SUPER ALT, S, Move window to scratchpad, movetoworkspacesilent, special:scratchpad"
        "SUPER, TAB, Next workspace, workspace, e+1"
        "SUPER SHIFT, TAB, Previous workspace, workspace, e-1"
        "SUPER CTRL, TAB, Former workspace, workspace, previous"
        "SUPER, mouse_down, Scroll active workspace forward, workspace, e+1"
        "SUPER, mouse_up, Scroll active workspace backward, workspace, e-1"
        "SUPER SHIFT ALT, left, Move workspace to left monitor, movecurrentworkspacetomonitor, l"
        "SUPER SHIFT ALT, right, Move workspace to right monitor, movecurrentworkspacetomonitor, r"

        "ALT, TAB, Focus on next window, cyclenext,"
        "ALT SHIFT, TAB, Focus on previous window, cyclenext, prev"
        "CTRL ALT, TAB, Focus on next monitor, focusmonitor, +1"

        # code:20 / code:21 are the minus and equals keys
        "SUPER, code:20, Expand window left, resizeactive, -100 0"
        "SUPER, code:21, Shrink window left, resizeactive, 100 0"
        "SUPER SHIFT, code:20, Shrink window up, resizeactive, 0 -100"
        "SUPER SHIFT, code:21, Expand window down, resizeactive, 0 100"

        "SUPER, comma, Dismiss last notification, exec, ${makoctl} dismiss"
        "SUPER SHIFT, comma, Dismiss all notifications, exec, ${makoctl} dismiss --all"
        "SUPER CTRL, comma, Toggle silencing notifications, exec, ${makoctl} mode -t do-not-disturb"
        "SUPER SHIFT, SPACE, Toggle top bar, exec, pkill -SIGUSR1 waybar"
        "SUPER CTRL, V, Clipboard manager, exec, ${launcher} -m clipboard"
        "SUPER CTRL, E, Emojis, exec, ${launcher} -m symbols"
        "SUPER CTRL, N, Toggle nightlight, exec, ${nightlight}"
        "SUPER CTRL SHIFT, SPACE, Theme menu, exec, ${theme.picker} themes"
        "SUPER CTRL, SPACE, Background switcher, exec, ${theme.picker} backgrounds"

        ", PRINT, Screenshot (select an area), exec, hyprshot -m region -o ${config.home.homeDirectory}/Pictures/Screenshots"
        "SUPER, PRINT, Color picker, exec, pkill hyprpicker || hyprpicker -a"
      ];

      # One key, two actions: Alt + Tab also raises the window it switches to. No description,
      # so the SUPER + K list shows each key once.
      bind = [
        "ALT, TAB, bringactivetotop,"
        "ALT SHIFT, TAB, bringactivetotop,"
      ];

      bindmd = [
        "SUPER, mouse:272, Move window, movewindow"
        "SUPER, mouse:273, Resize window, resizewindow"
      ];

      # Volume keys with the on-screen display; repeat while held, work on the lock screen.
      bindeld = [
        ", XF86AudioRaiseVolume, Volume up, exec, swayosd-client --output-volume raise"
        ", XF86AudioLowerVolume, Volume down, exec, swayosd-client --output-volume lower"
      ];
      bindld = [
        ", XF86AudioMute, Mute, exec, swayosd-client --output-volume mute-toggle"
        ", XF86AudioMicMute, Mute microphone, exec, swayosd-client --input-volume mute-toggle"
        ", XF86AudioPlay, Play / pause, exec, playerctl play-pause"
        ", XF86AudioNext, Next track, exec, playerctl next"
        ", XF86AudioPrev, Previous track, exec, playerctl previous"
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

  # Elephant (Walker's backend) as a service of the Hyprland session only (UWSM's target; not
  # graphical-session.target, which Plasma shares). It reads its config only at start, so the
  # config path is a restart trigger: a rebuild that changes it restarts Elephant.
  systemd.user.services.elephant = {
    Unit = {
      Description = "Elephant, data provider for the Walker launcher";
      PartOf = [ "wayland-session@hyprland.desktop.target" ];
      After = [ "wayland-session@hyprland.desktop.target" ];
      X-Restart-Triggers = [
        "${config.xdg.configFile."elephant/symbols.toml".source}"
        "${config.xdg.configFile."elephant/desktopapplications.toml".source}"
      ];
    };
    Service = {
      ExecStart = "${pkgs.elephant}/bin/elephant";
      Restart = "on-failure";
      # On restart stop only Elephant, never apps it launched from Walker.
      KillMode = "process";
    };
    Install.WantedBy = [ "wayland-session@hyprland.desktop.target" ];
  };

  # Wallpaper of the current theme. A service, so a theme or wallpaper switch restarts the one
  # instance instead of starting another.
  systemd.user.services.swaybg = {
    Unit = {
      Description = "Wallpaper (swaybg)";
      PartOf = [ "wayland-session@hyprland.desktop.target" ];
      After = [ "wayland-session@hyprland.desktop.target" ];
    };
    Service = {
      ExecStart = "${pkgs.swaybg}/bin/swaybg -i ${theme.stateDir}/background -m fill";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "wayland-session@hyprland.desktop.target" ];
  };

  # Walker's background service keeps a connection to Elephant and aborts when Elephant
  # restarts (2026-10-02, after a rebuild). PartOf elephant.service makes systemd restart it
  # together with Elephant; Restart covers any other crash.
  systemd.user.services.walker = {
    Unit = {
      Description = "Walker launcher (background service)";
      PartOf = [ "wayland-session@hyprland.desktop.target" "elephant.service" ];
      After = [ "wayland-session@hyprland.desktop.target" "elephant.service" ];
      Requires = [ "elephant.service" ];
      X-Restart-Triggers = [
        "${config.xdg.configFile."walker/config.toml".source}"
        "${config.xdg.configFile."walker/themes/omarchy-default/style.css".source}"
      ];
    };
    Service = {
      ExecStart = "${pkgs.walker}/bin/walker --gapplication-service";
      Environment = [ "GSK_RENDERER=cairo" ];   # as Omarchy starts it
      Restart = "on-failure";
      RestartSec = 1;
    };
    Install.WantedBy = [ "wayland-session@hyprland.desktop.target" ];
  };

  # Omarchy 3's Walker setup (config/walker/config.toml and theme omarchy-default, v3.8.4).
  # The theme's colours come from the current theme's walker.css.
  xdg.configFile."walker/config.toml".text = ''
    force_keyboard_focus = true
    selection_wrap = true
    theme = "omarchy-default"
    hide_action_hints = true

    [placeholders]
    "default" = { input = " Search...", list = "No Results" }

    [keybinds]
    quick_activate = []

    [columns]
    symbols = 1

    [providers]
    max_results = 256
    default = [ "desktopapplications", "websearch" ]

    [[providers.prefixes]]
    prefix = "/"
    provider = "providerlist"

    [[providers.prefixes]]
    prefix = "."
    provider = "files"

    [[providers.prefixes]]
    prefix = ":"
    provider = "symbols"

    [[providers.prefixes]]
    prefix = "="
    provider = "calc"

    [[providers.prefixes]]
    prefix = "@"
    provider = "websearch"

    [[providers.prefixes]]
    prefix = "$"
    provider = "clipboard"
  '';

  xdg.configFile."walker/themes/omarchy-default/layout.xml".source = ./walker/layout.xml;
  xdg.configFile."walker/themes/omarchy-default/style.css".text = ''
    @import url("file://${current}/walker.css");

    * { all: unset; }
    * { font-family: "${font}"; font-size: 18px; color: @text; }
    scrollbar { opacity: 0; }
    .normal-icons { -gtk-icon-size: 16px; }
    .large-icons { -gtk-icon-size: 32px; }
    .box-wrapper { background: alpha(@base, 0.95); padding: 20px; border: 2px solid @border; }
    .search-container { background: @base; padding: 10px; }
    .input placeholder { opacity: 0.5; }
    .input:focus, .input:active { box-shadow: none; outline: none; }
    child:selected .item-box * { color: @selected-text; }
    child:selected { background: alpha(@text, 0.07); }
    .item-box { padding-left: 14px; }
    .item-text-box { all: unset; padding: 14px 0; }
    .item-subtext { font-size: 0px; min-height: 0px; margin: 0px; padding: 0px; }
    .item-image { margin-right: 14px; -gtk-icon-transform: scale(0.9); }
    .current { font-style: italic; }
    .keybind-hints { background: @background; padding: 10px; margin-top: 10px; }
  '';

  # App search like Omarchy: by title only, no action entries, no history ordering.
  xdg.configFile."elephant/desktopapplications.toml".text = ''
    show_actions = false
    only_search_title = true
    history = false
  '';

  # Elephant reads one TOML file per provider; it runs "command" with the symbol on stdin.
  xdg.configFile."elephant/symbols.toml".text = ''
    command = "${emojiInsert}"
  '';

  # hyprsunset tints the screen by default; Omarchy's profile keeps it neutral until toggled.
  xdg.configFile."hypr/hyprsunset.conf".text = ''
    profile {
      time = 07:00
      identity = true
    }
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
      source = [ "${current}/hyprlock.conf" ];   # $theme_* colours
      general.hide_cursor = true;
      background = [{
        monitor = "";
        path = "${theme.stateDir}/background";
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
        inner_color = "$theme_inner";
        outer_color = "$theme_outer";
        font_color = "$theme_font";
        check_color = "$theme_check";
        fail_color = "$theme_fail";
        font_family = font;
        placeholder_text = "Enter password";
        fade_on_empty = false;
      }];
    };
  };

  programs.alacritty = {
    enable = true;
    settings = {
      general.import = [ "${current}/alacritty.toml" ];   # colours, reloaded live
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
      @import url("file://${current}/waybar.css");

      * {
        font-family: "${font}";
        font-size: 12px;
        min-height: 0;
        border: none;
      }
      window#waybar {
        background-color: @background;
        color: @foreground;
      }
      #workspaces button {
        padding: 0 6px;
        margin: 0 1.5px;
        color: @dark_foreground;
        background: transparent;
        border-radius: 0;
      }
      #workspaces button.active { color: @bright_foreground; }
      #workspaces button.empty { opacity: 0.5; }
      #workspaces button:hover { background: @selection; }
      #clock { font-weight: bold; }
      #tray, #bluetooth, #network, #pulseaudio, #cpu, #custom-power {
        padding: 0 10px;
      }
      #custom-power { margin-right: 6px; }
      tooltip {
        background: @dark_background;
        border: 2px solid @accent;
      }
    '';
  };

  # Mako's package registers it as the D-Bus notification service, so installing it (or
  # Home Manager's services.mako) could let it start inside Plasma during login. It runs by
  # store path from Hyprland only, with the current theme's mako.ini (see exec-once).

  # Point ~/.local/state/theme at the chosen theme again after each rebuild (the theme
  # folders move to a new store path), keeping the theme and wallpaper. Also sets the GTK
  # dark/light preference from the theme, as Omarchy does.
  home.activation.themeLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${theme.link}
    run mkdir -p ${builtins.dirOf layoutsFile}
    run touch ${layoutsFile}   # sourced by hyprland.conf, must exist
  '';
}
