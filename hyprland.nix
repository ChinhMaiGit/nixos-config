# Omarchy-style Hyprland desktop (Home Manager), a second login session next to KDE Plasma.
# Look, colours and keybindings follow basecamp/omarchy (MIT, (c) David Heinemeier Hansson)
# at commit 821ae58. Omarchy 4's own Quickshell bar and menus are replaced by the pre-4.0
# Omarchy stack: Waybar, Walker, Mako, Hyprlock, SwayOSD.
#
# Everything here starts from Hyprland itself (exec-once), not from systemd user services:
# those would also start inside Plasma, which shares graphical-session.target.
# Colours and wallpapers come from the current theme (theme.nix, switcher on SUPER+CTRL+SHIFT+SPACE).
{ config, pkgs, lib, osConfig, ... }:

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

  # ALT + PRINT, like Omarchy's omarchy-capture-screenrecording: if a recording runs, stop it;
  # otherwise pick what to record and start gpu-screen-recorder (GPU encoder, 60 fps) into
  # ~/Videos. The PID file marks a running recording (no process-name matching).
  screenRecord = pkgs.writeShellScript "screen-record" ''
    pidfile=$XDG_RUNTIME_DIR/screen-record.pid
    namefile=$XDG_RUNTIME_DIR/screen-record.file
    if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
      kill -INT "$(cat "$pidfile")"   # SIGINT lets it finish the file properly
      for _ in $(seq 50); do kill -0 "$(cat "$pidfile")" 2>/dev/null || break; sleep 0.1; done
      rm -f "$pidfile"
      notify-send -t 8000 "Screen recording saved" "$(cat "$namefile")"
      exit 0
    fi

    choice=$(printf '%s\n' "Region" "Region with sound" "Monitor" "Monitor with sound" \
      | ${launcher} --dmenu -p "Screen recording") || exit 0
    case "$choice" in
      Region*) target=$(${pkgs.slurp}/bin/slurp -f '%wx%h+%x+%y') || exit 0 ;;
      Monitor*) target=$(hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused).name') ;;
      *) exit 0 ;;
    esac
    audio=()
    case "$choice" in *sound) audio=(-a default_output -ac aac) ;; esac

    mkdir -p "$HOME/Videos"
    file=$HOME/Videos/screenrecording-$(date +%Y-%m-%d_%H-%M-%S).mp4
    echo "$file" > "$namefile"
    gpu-screen-recorder -w "$target" -k auto -f 60 -fm cfr -fallback-cpu-encoding yes \
      -o "$file" "''${audio[@]}" >/dev/null 2>&1 &
    echo $! > "$pidfile"
    notify-send -t 3000 "Screen recording started" "Alt + Print to stop"
  '';

  playerctlBin = "${pkgs.playerctl}/bin/playerctl";

  # Font Awesome glyphs from the Nerd Font, written as JSON escapes
  icon = code: builtins.fromJSON ''"\u${code}"'';

  # Wi-Fi menu in the launcher (top bar Wi-Fi icon, gear menu > Wi-Fi), replacing nmtui, whose
  # screen came out garbled in tiled windows (2026-10-03). Networks strongest first, one line per
  # name; a saved network is started through its own profile (keeps the 5 GHz access point pin),
  # a new one asks for its password. A saved network opens a submenu: connect / disconnect,
  # change password, connect automatically, forget, and KDE's page with all its settings.
  wifiMenu = pkgs.writeShellScript "wifi-menu" ''
    pick() { ${launcher} --dmenu -p "$1"; }
    notify() { notify-send -t 4000 -i network-wireless "$@"; }

    if [ "$(nmcli radio wifi)" != enabled ]; then
      choice=$(printf '%s\n' "${icon "f1eb"}  Turn Wi-Fi on" | pick Wi-Fi) || exit 0
      nmcli radio wifi on && notify "Wi-Fi on"
      exit 0
    fi

    # Saved profiles by network name (the name a profile has can differ from the network's)
    declare -A saved
    while IFS=: read -r uuid type; do
      [ "$type" = 802-11-wireless ] || continue
      saved["$(nmcli -g 802-11-wireless.ssid connection show "$uuid")"]=$uuid
    done < <(nmcli -t -f UUID,TYPE connection show)

    # nmcli writes ":" and "\" in network names as "\:" and "\\"
    unescape() { sed 's/\\:/:/g; s/\\\\/\\/g'; }
    # The connected network (its line may not be the strongest of its access points)
    current=$(nmcli -t -e yes -f IN-USE,SSID device wifi list --rescan no | sed -n 's/^\*://p' | head -1 | unescape)

    # "IN-USE:SIGNAL:BARS:SECURITY:SSID", strongest first; the name is last, so colons in it
    # stay in it
    ssids=() lines=()
    declare -A seen
    while IFS=: read -r inuse signal bars security ssid; do
      ssid=$(printf '%s' "$ssid" | unescape)
      [ -n "$ssid" ] && [ -z "''${seen[$ssid]:-}" ] || continue
      seen[$ssid]=1
      mark=""; [ "$ssid" = "$current" ] && mark="  ${icon "f00c"} connected"   # at the end: Walker trims leading spaces
      lock=""; [ -n "$security" ] && [ "$security" != "--" ] && lock="  ${icon "f023"}"
      ssids+=("$ssid|$security")
      lines+=("$bars  $ssid$lock$mark")
    done < <(nmcli -t -e yes -f IN-USE,SIGNAL,BARS,SECURITY,SSID device wifi list | sort -t: -k2,2nr)

    extras=("${icon "f021"}  Scan again" "${icon "f1eb"}  Turn Wi-Fi off" "${icon "f013"}  Advanced (nmtui)")
    i=$(printf '%s\n' "''${lines[@]}" "''${extras[@]}" | ${launcher} --dmenu -i -p Wi-Fi) || exit 0
    [ -n "$i" ] || exit 0

    if [ "$i" -ge "''${#lines[@]}" ]; then
      case "''${extras[$((i - ''${#lines[@]}))]}" in
        *"Scan again") nmcli device wifi rescan 2>/dev/null; sleep 3; exec "$0" ;;
        *"Turn Wi-Fi off") nmcli radio wifi off && notify "Wi-Fi off" ;;
        *Advanced*) uwsm app -- alacritty --class nmtui -e nmtui ;;
      esac
      exit 0
    fi

    ssid=''${ssids[$i]%|*}
    security=''${ssids[$i]##*|}

    uuid=''${saved[$ssid]:-}

    # Saved network: what to do with it
    if [ -n "$uuid" ]; then
      if [ "$ssid" = "$current" ]; then first="${icon "f127"}  Disconnect"; else first="${icon "f1eb"}  Connect"; fi
      if [ "$(nmcli -g connection.autoconnect connection show "$uuid")" = yes ]; then auto=on; else auto=off; fi
      choice=$(printf '%s\n' "$first" "${icon "f084"}  Change password" \
        "${icon "f021"}  Connect automatically: $auto" "${icon "f1f8"}  Forget network" \
        "${icon "f013"}  All settings…" | pick "$ssid") || exit 0
      case "$choice" in
        *Disconnect)
          nmcli connection down uuid "$uuid" >/dev/null && notify "Disconnected" "$ssid"
          exit 0 ;;
        *Connect) ;;   # below
        *"Change password")
          pw=$(${launcher} --password -p "New password for $ssid") || exit 0
          [ -n "$pw" ] || exit 0
          nmcli connection modify uuid "$uuid" wifi-sec.psk "$pw" || { notify -u critical "Couldn't change the password"; exit 1; }
          notify "Password changed" "$ssid"
          [ "$ssid" = "$current" ] || exit 0   # try it now if it's the network in use
          ;;
        *"Connect automatically"*)
          if [ $auto = on ]; then new=no; else new=yes; fi
          nmcli connection modify uuid "$uuid" connection.autoconnect $new \
            && notify "$ssid" "Connect automatically: $([ $new = yes ] && echo on || echo off)"
          exit 0 ;;
        *Forget*)
          # A pinned access point (the 5 GHz fix for the home network) goes with the profile
          note=""
          [ -n "$(nmcli -g 802-11-wireless.bssid connection show "$uuid")" ] && note=" (and its 5 GHz access point pin)"
          confirm=$(printf '%s\n' "Cancel" "Forget $ssid$note" | pick "Forget $ssid?") || exit 0
          case "$confirm" in
            Forget*) nmcli connection delete uuid "$uuid" >/dev/null && notify "Forgot $ssid" ;;
          esac
          exit 0 ;;
        *"All settings"*)
          # KDE's network settings page, opened at this network (IP, DNS, access point, ...)
          uwsm app -- kcmshell6 kcm_networkmanagement --args "Uuid=$uuid"
          exit 0 ;;
        *) exit 0 ;;
      esac
    fi

    notify "Connecting…" "$ssid"
    if [ -n "$uuid" ]; then
      out=$(nmcli connection up uuid "$uuid" 2>&1)
    elif [ -z "$security" ] || [ "$security" = "--" ]; then
      out=$(nmcli device wifi connect "$ssid" 2>&1)
    elif [[ "$security" == *802.1X* ]]; then
      notify "$ssid needs a company login" "Use Advanced (nmtui) to set it up"; exit 0
    else
      pw=$(${launcher} --password -p "Password for $ssid") || exit 0
      [ -n "$pw" ] || exit 0
      if ! out=$(nmcli device wifi connect "$ssid" password "$pw" 2>&1); then
        # Don't keep a profile with a wrong password, so the next try asks again
        nmcli connection delete id "$ssid" >/dev/null 2>&1
      fi
    fi
    if nmcli -t -f GENERAL.STATE device show "$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}')" | grep -q '(connected)' \
      && [ "$(nmcli -t -f IN-USE,SSID device wifi list --rescan no | sed -n 's/^\*://p' | head -1)" = "$ssid" ]; then
      notify "Connected" "$ssid"
    else
      notify -u critical "Couldn't connect to $ssid" "$(printf '%s' "$out" | tail -1)"
    fi
  '';

  # Quick notes (SUPER + N, "Notes" in the launcher): notes.qml, a Quickshell window that edits
  # ~/Notes/notes.md and saves by itself. Pressed again, it closes the window (which saves).
  # The notes came from Plasma's Sticky Notes widget (2026-10-03); they never go into git.
  notesToggle = pkgs.writeShellScript "notes-toggle" ''
    if ${pkgs.hyprland}/bin/hyprctl clients | grep -q '^\s*title: Quick Notes$'; then
      exec ${pkgs.hyprland}/bin/hyprctl dispatch closewindow 'title:^(Quick Notes)$' >/dev/null
    fi
    file=${config.home.homeDirectory}/Notes/notes.md
    mkdir -p "$(dirname "$file")"
    [ -e "$file" ] || install -m 600 /dev/null "$file"
    colors=${theme.stateDir}/current/colors.json
    jq=${pkgs.jq}/bin/jq
    NOTES_FILE=$file \
    NOTES_ACCENT=$($jq -r .accent "$colors") \
    NOTES_BACKGROUND=$($jq -r .background "$colors") \
    NOTES_FOREGROUND=$($jq -r .bright_foreground "$colors") \
    NOTES_MUTED=$($jq -r .muted "$colors") \
    NOTES_FONT=$(cat ${theme.stateDir}/font 2>/dev/null || echo "JetBrainsMono Nerd Font") \
      exec ${pkgs.quickshell}/bin/qs --no-duplicate -p ${./notes.qml}
  '';

  # Settings menu (gear in the top bar, SUPER + ALT + SPACE), like the setup part of Omarchy's
  # menu: Wi-Fi in the launcher (wifiMenu), terminal tools for Bluetooth / audio as in Omarchy,
  # drives via udisks (Hyprland doesn't auto-mount like Plasma), power profile, look, and KDE
  # System Settings for the rest while Plasma is installed.
  settingsMenu = pkgs.writeShellScript "settings-menu" ''
    pick() { ${launcher} --dmenu -p "$1"; }
    term() { uwsm app -- alacritty --class "$1" -e "''${@:2}"; }
    drives() {   # removable partitions as "DEVICE  LABEL  SIZE[  MOUNTPOINT]"; $1 = mounted | unmounted
      lsblk -J -p -o PATH,HOTPLUG,MOUNTPOINT,LABEL,SIZE,TYPE | ${pkgs.jq}/bin/jq -r --arg want "$1" '
        .. | objects | select(.type? == "part" and .hotplug == true)
        | select(($want == "mounted") == (.mountpoint != null))
        | [.path, (.label // "drive"), .size, (.mountpoint // empty)] | join("  ")'
    }

    choice=$(printf '%s\n' \
      "${icon "f1eb"}  Wi-Fi" "${icon "f293"}  Bluetooth" "${icon "f028"}  Audio" \
      "${icon "f287"}  Mount drive" "${icon "f052"}  Safely remove drive" \
      "${icon "f0e4"}  Power profile" "${icon "f1fc"}  Theme" "${icon "f03e"}  Background" \
      "${icon "f186"}  Night light" "${icon "f031"}  Font" "${icon "f0e7"}  Speed test" \
      "${icon "f11c"}  Keybindings" "${icon "f013"}  All settings (KDE)" \
      | pick Settings) || exit 0

    case "$choice" in
      *Wi-Fi) exec ${wifiMenu} ;;
      *Bluetooth) term bluetui ${pkgs.bluetui}/bin/bluetui ;;
      *Audio) term wiremix wiremix ;;
      *"Mount drive")
        d=$(drives unmounted)
        [ -n "$d" ] || { notify-send -t 3000 "No drive to mount"; exit 0; }
        dev=$(echo "$d" | pick "Mount") || exit 0
        out=$(udisksctl mount -b "''${dev%% *}" 2>&1)
        notify-send -t 4000 "Drive mounted" "$out"
        uwsm app -- dolphin "$(echo "$out" | sed -n 's/.* at //p')" ;;
      *"Safely remove drive")
        d=$(drives mounted)
        [ -n "$d" ] || { notify-send -t 3000 "No removable drive mounted"; exit 0; }
        dev=$(echo "$d" | pick "Remove") || exit 0
        dev=''${dev%% *}
        if out=$(udisksctl unmount -b "$dev" 2>&1); then
          disk=/dev/$(lsblk -no PKNAME "$dev")
          udisksctl power-off -b "$disk" >/dev/null 2>&1
          notify-send -t 4000 "Safe to remove" "$dev"
        else
          notify-send -t 6000 "Drive is busy" "Close the files or windows using it: $out"
        fi ;;
      *"Power profile")
        current=$(powerprofilesctl get)
        p=$(printf '%s\n' performance balanced power-saver | sed "s/^$current\$/$current  (current)/" \
          | pick "Power profile") || exit 0
        powerprofilesctl set "''${p%% *}" && notify-send -t 2000 "Power profile: ''${p%% *}" ;;
      *Theme) ${theme.picker} themes ;;
      *Background) ${theme.picker} backgrounds ;;
      *"Night light") ${nightlight} ;;
      *Font)   # installed Nerd Fonts (they carry the icons the top bar uses), like omarchy-font-list
        current=$(cat ${theme.stateDir}/font 2>/dev/null || echo "${font}")
        f=$(fc-list :spacing=100 -f '%{family[0]}\n' | grep -E 'Nerd Font$' | sort -u \
          | sed "s/^$current\$/$current  (current)/" | pick Font) || exit 0
        ${theme.fontSet} "''${f%  (current)}" ;;
      *"Speed test") uwsm app -- alacritty --class speedtest --hold -e ${pkgs.speedtest-go}/bin/speedtest-go ;;
      *Keybindings) ${keybindingsMenu} ;;
      *"All settings (KDE)") uwsm app -- systemsettings ;;
    esac
  '';

  # Notification centre (bell in the top bar, SUPER + SHIFT + ALT + COMMA, like Omarchy's
  # notification history): Mako's history in the launcher, newest first. Choosing one with
  # buttons offers them; Mako can only invoke actions on visible notifications, so it restores
  # history entries until the chosen one is visible, invokes, and dismisses the rest again.
  # Calendar popup for the clock (gsimplecal). It gets its own config folder: its settings, and
  # a GTK stylesheet with the top bar's theme colours and font (read at each opening, so a theme
  # or font switch applies next time) instead of the system GTK theme. Running it again closes it.
  calendarConfig = pkgs.runCommand "calendar-config" { } ''
    mkdir -p $out/gsimplecal $out/gtk-3.0
    cat > $out/gsimplecal/config <<'EOF'
    show_calendar = 1
    show_timezones = 0
    mark_today = 1
    show_week_numbers = 1
    close_on_unfocus = 1
    mainwindow_decorated = 0
    mainwindow_keep_above = 1
    mainwindow_skip_taskbar = 1
    mainwindow_resizable = 0
    mainwindow_position = none
    EOF
    cat > $out/gtk-3.0/gtk.css <<'EOF'
    @import url("file://${current}/waybar.css");
    @import url("file://${theme.stateDir}/font.css");

    * { font-size: 12px; }
    window, calendar {
      background-color: @background;
      color: @foreground;
      border: none;
      box-shadow: none;
    }
    calendar { padding: 6px 8px; }
    calendar.header { font-weight: bold; color: @bright_foreground; }
    calendar.highlight { color: @accent; }
    calendar:indeterminate { color: @muted; }
    calendar:selected { background-color: @accent; color: @background; border-radius: 0; }
    calendar.button { color: @dark_foreground; background: transparent; border: none; }
    calendar.button:hover { color: @accent; }
    EOF
  '';
  calendar = pkgs.writeShellScript "calendar" ''
    XDG_CONFIG_HOME=${calendarConfig} exec ${pkgs.gsimplecal}/bin/gsimplecal
  '';

  notificationCenter = pkgs.writeShellScript "notification-center" ''
    jq=${pkgs.jq}/bin/jq
    hist=$(${makoctl} history -j)
    count=$(echo "$hist" | $jq length)
    if [ "$count" = 0 ]; then notify-send -t 2000 "No notifications"; exit 0; fi
    choice=$(echo "$hist" | $jq -r 'to_entries[] | "\(.key + 1). \(.value.app_name) — \(.value.summary)\(if (.value.body // "") != "" then " · " + (.value.body | gsub("<[^>]*>"; "") | gsub("\\s+"; " ") | .[0:80]) else "" end)"' \
      | ${launcher} --dmenu -p Notifications) || exit 0
    pos=''${choice%%.*}
    [[ $pos =~ ^[0-9]+$ ]] || exit 0
    n=$(echo "$hist" | $jq ".[$((pos - 1))]")
    id=$(echo "$n" | $jq -r .id)
    [ "$(echo "$n" | $jq '.actions | length')" -gt 0 ] || exit 0
    label=$(echo "$n" | $jq -r '.actions | to_entries[] | .value' | ${launcher} --dmenu -p Action) || exit 0
    key=$(echo "$n" | $jq -r --arg l "$label" '.actions | to_entries[] | select(.value == $l) | .key' | head -n1)
    restored=()
    for _ in $(seq "$pos"); do
      ${makoctl} list -j | $jq -e --argjson id "$id" 'any(.[]; .id == $id)' >/dev/null && break
      ${makoctl} restore
      restored+=("$(${makoctl} list -j | $jq -r '.[0].id')")
    done
    ${makoctl} invoke -n "$id" "$key"
    for r in "''${restored[@]}"; do [ "$r" != "$id" ] && ${makoctl} dismiss -n "$r" 2>/dev/null; done
    true
  '';

  # Bell for Waybar: bell-slash while Do Not Disturb is on; history count in the tooltip.
  notificationStatus = pkgs.writeShellScript "notification-status" ''
    jq=${pkgs.jq}/bin/jq
    count=$(${makoctl} history -j 2>/dev/null | $jq length 2>/dev/null || echo 0)
    if ${makoctl} mode | grep -qx do-not-disturb; then
      printf '{"text":"${icon "f1f6"}","tooltip":"Do Not Disturb is on · %s in history","class":"dnd"}\n' "$count"
    else
      printf '{"text":"${icon "f0f3"}","tooltip":"Notifications · %s in history","class":"normal"}\n' "$count"
    fi
  '';
  toggleDnd = pkgs.writeShellScript "toggle-dnd" ''
    ${makoctl} mode -t do-not-disturb >/dev/null
    ${pkgs.procps}/bin/pkill -RTMIN+8 waybar || true   # refresh the bell now
  '';

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
        (app "${mako} -c ${theme.stateDir}/mako.ini")   # theme colours + chosen font
        (app "swayosd-server")
        (app "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent")   # not on PATH
        (app "hypridle")
        (app "hyprsunset")
      ];

      # PAM starts a wallet daemon per login and Plasma stops it at logout; do the same here,
      # or an old one stays behind after logging out of Hyprland.
      # No -x: NixOS wrappers rename it (".ksecretd-wrapp"), so match part of the name.
      exec-shutdown = [ "${pkgs.procps}/bin/pkill -u ${config.home.username} ksecretd" ];

      # Calendar from the top bar's clock: a small floating popup just below the bar, centred on
      # the screen in use (positions are per monitor).
      windowrule = [
        "float on, move ((monitor_w*0.5)-(window_w*0.5)) 36, match:class ^(gsimplecal)$"
        "float on, size 900 640, center on, match:title ^(Quick Notes)$"
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
        "SUPER ALT, SPACE, Settings menu, exec, ${settingsMenu}"
        "SUPER, ESCAPE, System menu (lock / sleep / log out / restart / shut down), exec, ${powerMenu}"
        "SUPER, RETURN, Terminal, exec, ${app "alacritty"}"
        "SUPER SHIFT, B, Browser, exec, ${app browser}"
        "SUPER SHIFT, F, File manager, exec, ${app "dolphin"}"
        "SUPER SHIFT, N, Editor, exec, ${app "code"}"

        "SUPER, Q, Close window, killactive,"   # not W: right next to Ctrl+W (close tab), easy to hit by mistake
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
        "SUPER CTRL, comma, Toggle silencing notifications, exec, ${toggleDnd}"
        "SUPER SHIFT ALT, comma, Open notification history, exec, ${notificationCenter}"
        "SUPER SHIFT, SPACE, Toggle top bar, exec, pkill -SIGUSR1 waybar"
        "SUPER CTRL, V, Clipboard manager, exec, ${launcher} -m clipboard"
        "SUPER CTRL, E, Emojis, exec, ${launcher} -m symbols"
        "SUPER, N, Quick notes, exec, ${notesToggle}"
        "SUPER CTRL, N, Toggle nightlight, exec, ${nightlight}"
        "SUPER CTRL SHIFT, SPACE, Theme menu, exec, ${theme.picker} themes"
        "SUPER CTRL, SPACE, Background switcher, exec, ${theme.picker} backgrounds"

        ", PRINT, Screenshot (select an area), exec, hyprshot -m region -o ${config.home.homeDirectory}/Pictures/Screenshots"
        "SHIFT, PRINT, Screenshot (whole screen in use), exec, hyprshot -m output -m active -o ${config.home.homeDirectory}/Pictures/Screenshots"
        "CTRL, PRINT, Screenshot (active window), exec, hyprshot -m window -m active -o ${config.home.homeDirectory}/Pictures/Screenshots"
        "SUPER, PRINT, Color picker, exec, pkill hyprpicker || hyprpicker -a"
        "ALT, PRINT, Screen recording (start / stop), exec, ${screenRecord}"
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
        "${config.xdg.configFile."elephant/elephant.toml".source}"
        "${config.xdg.configFile."elephant/files.toml".source}"
        # Elephant reads the app list at start and misses a rebuild swapping the app folder,
        # so a new or removed app restarts it too: user apps (home.packages, desktop entries)
        # and system apps (environment.systemPackages, NixOS modules such as Waydroid).
        "${config.home.path}"
        "${osConfig.system.path}"
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
    @import url("file://${theme.stateDir}/font.css");

    * { all: unset; }
    * { font-size: 18px; color: @text; }
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

  # Elephant's Arch/Fedora package providers are useless on NixOS (archlinuxpkgs downloaded a
  # 75 MB package list), and niri sessions don't apply here.
  xdg.configFile."elephant/elephant.toml".text = ''
    ignored_providers = [ "archlinuxpkgs", "dnfpackages", "nirisessions" ]
  '';

  # File search (Walker's "." prefix) indexes $HOME at every Elephant start. It walked all of
  # the rclone OneDrive mount (336,664 of 338,605 entries, 2026-10-03): slow, loads OneDrive, and
  # FUSE reads can block sleep. Exclude OneDrive from fd's walk.
  xdg.configFile."elephant/files.toml".text = ''
    fd_flags = [ "--ignore-vcs", "--type", "file", "--type", "directory", "--exclude", "OneDrive" ]
    ignored_dirs = [ "^${config.home.homeDirectory}/OneDrive" ]
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
      source = [ "${current}/hyprlock.conf" "${theme.stateDir}/font.conf" ];   # $theme_* colours, $font
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
        font_family = "$font";
        placeholder_text = "Enter password";
        fade_on_empty = false;
      }];
    };
  };

  programs.alacritty = {
    enable = true;
    settings = {
      general.import = [ "${current}/alacritty.toml" "${theme.stateDir}/font.toml" ];   # colours + font, reloaded live
      env.TERM = "xterm-256color";
      font.size = 9;   # family comes from font.toml (gear menu > Font)
      window = {
        padding = { x = 14; y = 14; };
        decorations = "None";
      };
    };
  };

  # "Notes" in the launcher (SUPER + SPACE), same as SUPER + N
  xdg.desktopEntries.quick-notes = {
    name = "Notes";
    comment = "Quick notes, saved automatically (~/Notes/notes.md)";
    exec = "${notesToggle}";
    icon = "accessories-text-editor";
    terminal = false;
    categories = [ "Utility" ];
  };

  programs.waybar = {
    enable = true;
    settings.main = {
      layer = "top";
      position = "top";
      # Floating "pills" (2026-10-05, ideas from the Serpantinum shell, written fresh): the bar
      # itself is transparent; each group of modules sits in its own rounded box.
      height = 34;
      spacing = 0;
      margin-top = 6;
      margin-left = 10;
      margin-right = 10;
      modules-left = [ "hyprland/workspaces" "group/media" ];
      modules-center = [ "clock" ];
      modules-right = [ "group/status" "group/system" ];

      # What's playing (any MPRIS player: Edge, Spotify, Fonos in Waydroid, ...), with buttons.
      # Hidden while nothing plays.
      "group/media" = {
        orientation = "horizontal";
        modules = [ "custom/media-title" "custom/media-prev" "custom/media-play" "custom/media-next" ];
      };
      # Own title item instead of Waybar's mpris module, which left an empty box behind for
      # Edge's stopped player. Same rule as the buttons: only while playing or paused.
      "custom/media-title" = {
        exec-if = "${playerctlBin} status 2>/dev/null | grep -qE 'Playing|Paused'";
        exec = "${playerctlBin} metadata --format '{{title}} – {{artist}}' 2>/dev/null";
        interval = 2;
        max-length = 34;
        tooltip = false;
        on-click = "${playerctlBin} play-pause";
      };
      "custom/media-prev" = {
        format = icon "f048";
        exec-if = "${playerctlBin} status 2>/dev/null | grep -qE 'Playing|Paused'";   # not for stopped players
        exec = "echo on";   # any output: an empty one would hide the button
        interval = 2;
        tooltip = false;
        on-click = "${playerctlBin} previous";
      };
      "custom/media-play" = {
        exec-if = "${playerctlBin} status 2>/dev/null | grep -qE 'Playing|Paused'";   # not for stopped players
        # pause icon while playing, play icon otherwise
        exec = "[ \"$(${playerctlBin} status)\" = Playing ] && echo '${icon "f04c"}' || echo '${icon "f04b"}'";
        interval = 1;
        tooltip = false;
        on-click = "${playerctlBin} play-pause";
      };
      "custom/media-next" = {
        format = icon "f051";
        exec-if = "${playerctlBin} status 2>/dev/null | grep -qE 'Playing|Paused'";   # not for stopped players
        exec = "echo on";   # any output: an empty one would hide the button
        interval = 2;
        tooltip = false;
        on-click = "${playerctlBin} next";
      };

      "group/status" = {
        orientation = "horizontal";
        modules = [ "tray" "bluetooth" "network" "pulseaudio" "cpu" ];
      };
      "group/system" = {
        orientation = "horizontal";
        modules = [ "custom/notifications" "custom/settings" "custom/power" ];
      };

      "hyprland/workspaces" = {
        on-click = "activate";
        format = "{name}";
        persistent-workspaces."*" = 5;
      };
      clock = {
        format = "{:%H:%M  ·  %a %d %b}";
        format-alt = "{:%A %d %B %Y  ·  W%V}";
        format-alt-click = "click-right";   # right click: full date
        on-click = "${calendar}";   # left click: calendar (again: close it)
        tooltip = false;
      };
      network = {
        format-wifi = icon "f1eb";
        format-ethernet = icon "f0e8";
        format-disconnected = icon "f127";
        tooltip-format-wifi = "{essid} ({frequency} GHz, {signalStrength}%)\n⇣{bandwidthDownBytes}  ⇡{bandwidthUpBytes}";
        interval = 3;
        on-click = "${pkgs.util-linux}/bin/setsid -f ${wifiMenu}";   # detached, like the gear menu
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
        on-click = app "alacritty --class bluetui -e ${pkgs.bluetui}/bin/bluetui";
      };
      cpu = {
        interval = 5;
        format = icon "f2db";
        tooltip = true;
        on-click = app "alacritty -e btop";
      };
      "custom/notifications" = {
        exec = "${notificationStatus}";
        return-type = "json";
        interval = 5;
        signal = 8;
        # Detached like the gear menu, so a Waybar reload can't end it.
        on-click = "${pkgs.util-linux}/bin/setsid -f ${notificationCenter}";
        on-click-right = "${toggleDnd}";
      };
      "custom/settings" = {
        format = icon "f013";
        tooltip-format = "Settings";
        # Detached: started as Waybar's child, the menu's own "reload Waybar" step (font,
        # theme) made Waybar end it halfway, so Walker and Mako were never reloaded.
        on-click = "${pkgs.util-linux}/bin/setsid -f ${settingsMenu}";
      };
      "custom/power" = {
        format = icon "f011";
        tooltip = false;
        on-click = "${pkgs.util-linux}/bin/setsid -f ${powerMenu}";
      };
      tray.spacing = 12;
    };
    style = ''
      @import url("file://${current}/waybar.css");
      @import url("file://${theme.stateDir}/font.css");

      * {
        font-size: 12px;
        min-height: 0;
        border: none;
      }
      window#waybar {
        background: transparent;
        color: @foreground;
      }

      /* the pills: one rounded box per group, in the theme's colours */
      #workspaces, #clock, #status, #system {
        background: alpha(@background, 0.92);
        border: 1px solid alpha(@foreground, 0.12);
        border-radius: 12px;
        padding: 0 6px;
        margin: 0 4px;
      }
      #clock {
        padding: 0 14px;
        font-weight: bold;
        color: @bright_foreground;
      }

      #workspaces button {
        padding: 0 7px;
        margin: 4px 1px;
        color: @dark_foreground;
        background: transparent;
        border-radius: 8px;
      }
      #workspaces button.active {
        color: @background;
        background: @accent;
      }
      #workspaces button.empty { opacity: 0.5; }
      #workspaces button:hover {
        background: @selection;
        color: @bright_foreground;
      }

      /* The media pill is drawn on its items, not on the group: an empty group (nothing
         playing) would otherwise leave an empty rounded box. */
      #custom-media-title, #custom-media-prev, #custom-media-play, #custom-media-next {
        background: alpha(@background, 0.92);
        border-top: 1px solid alpha(@foreground, 0.12);
        border-bottom: 1px solid alpha(@foreground, 0.12);
        padding: 0 6px;
        color: @accent;
      }
      #custom-media-title {
        color: @bright_foreground;
        padding: 0 8px 0 12px;
        margin-left: 4px;
        border-left: 1px solid alpha(@foreground, 0.12);
        border-radius: 12px 0 0 12px;
      }
      #custom-media-next {
        padding-right: 12px;
        border-right: 1px solid alpha(@foreground, 0.12);
        border-radius: 0 12px 12px 0;
      }

      #tray, #bluetooth, #network, #pulseaudio, #cpu,
      #custom-notifications, #custom-settings, #custom-power {
        padding: 0 9px;
      }
      #custom-power { color: @accent; }
      #custom-notifications.dnd { color: @dark_foreground; }

      tooltip {
        background: @dark_background;
        border: 2px solid @accent;
        border-radius: 10px;
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
