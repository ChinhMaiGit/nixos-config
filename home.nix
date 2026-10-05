# User-level configuration for chinh (Home Manager).
# Most settings (KDE themes, app logins, Dolphin menus, game saves) come back from the
# backup archive; this file declares the programs and the few configs worth managing.
{ config, pkgs, lib, ... }:

let
  # Word, Excel and PowerPoint formats (old and new) for the Office Online opener
  officeTypes = [
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    "application/msword"
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    "application/vnd.ms-excel"
    "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    "application/vnd.ms-powerpoint"
  ];
in
{
  imports = [ ./hyprland.nix ./fastfetch.nix ./dev.nix ];

  home.username = "chinh";
  home.homeDirectory = "/home/chinh";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    # Browsers / communication / office
    # Edge keeps its cookie key in KDE Wallet by default; with the wallet off it hangs on
    # every page (2026-10-02). "basic" = Edge's own built-in key store.
    (microsoft-edge.override { commandLineArgs = "--password-store=basic"; })
    discord slack
    # Development
    vscode claude-code uv gh nodejs jdk python3
    # Documents, OCR, LaTeX
    pandoc ocrmypdf poppler-utils ghostscript
    (tesseract.override { enableLanguages = [ "eng" "deu" "vie" "frk" ]; })
    texlive.combined.scheme-full
    # Comics / e-books (Kindle pipeline)
    kcc unar
    # Gaming tools
    protonup-qt
    limo   # mod manager (Nexus Mods, LOOT); deploys mods into the game folders
    # Media and KDE apps
    haruna kdePackages.elisa kdePackages.gwenview kdePackages.kate kdePackages.kcalc
    kdePackages.kcharselect kdePackages.ark kdePackages.ksystemlog
    kdePackages.dolphin-plugins kdePackages.ffmpegthumbs kdePackages.kdegraphics-thumbnailers
    simple-scan papers
    # System / terminal tools
    btop htop cmatrix go-mtpfs
    # Cloud
    rclone
  ];

  # MangoHud: 60 FPS cap, overlay hidden (toggle Shift_R+F12), logging Shift_L+F2
  programs.mangohud = {
    enable = true;
    settings = {
      fps_limit = 60;
      no_display = true;
      fps = true; frametime = true; frame_timing = true;
      gpu_stats = true; gpu_temp = true; cpu_stats = true; cpu_temp = true;
      vram = true; ram = true;
      position = "top-left";
      toggle_hud = "Shift_R+F12";
      toggle_fps_limit = "Shift_L+F1";
      toggle_logging = "Shift_L+F2";
      log_duration = 60;
      output_folder = "/home/chinh/Documents/MangoHud-logs";
    };
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = "Chinh Mai";
      user.email = "chinhmai.work@gmail.com";
      init.defaultBranch = "main";
    };
  };

  # OneDrive mount (replaces the rclone systemd user service). rclone.conf with the
  # login token comes back from the backup (~/.config/rclone); keep it out of git.
  systemd.user.services.rclone-onedrive = {
    Unit = { Description = "RClone mount for OneDrive"; After = [ "network-online.target" ]; };
    Service = {
      # Clear a dead mount left by an unclean stop first ("-" = fine if nothing is mounted).
      ExecStartPre = [ "-/run/wrappers/bin/fusermount -uz %h/OneDrive" "${pkgs.coreutils}/bin/mkdir -p %h/OneDrive" ];
      # Caching (2026-10-05): with only "writes" cached, every folder listing, file check and
      # Dolphin thumbnail went to Microsoft's servers, and Dolphin froze while waiting (worst in
      # lib_ebooks: a PDF thumbnail means downloading the whole PDF). Now listings are kept for an
      # hour, OneDrive is asked for changes every minute (new files still appear quickly), and
      # opened files stay on disk for a week (up to 5 GB), so they open instantly afterwards.
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.rclone}/bin/rclone mount onedrive: %h/OneDrive"
        "--config=%h/.config/rclone/rclone.conf"
        "--vfs-cache-mode full"
        "--vfs-cache-max-size 5G"
        "--vfs-cache-max-age 168h"
        "--dir-cache-time 1h"
        "--poll-interval 1m"
      ];
      # Lazy unmount (-z): a plain unmount fails while a program still reads a file, and the
      # sleep hook stops this service even then (2026-10-02, Dolphin PDF previews).
      ExecStop = "/run/wrappers/bin/fusermount -uz %h/OneDrive";
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # KDE crash fix (2026-09-26): ignore the KaTeX webfonts that poisoned fontconfig
  xdg.configFile."fontconfig/conf.d/90-reject-katex.conf".text = ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
    <fontconfig>
      <selectfont><rejectfont><glob>*/katex/*</glob></rejectfont></selectfont>
    </fontconfig>
  '';
  # Safety net from the same incident: rebuild the font cache before plasmashell starts,
  # so a poisoned cache can't crash-loop the desktop ("-" = never block startup).
  xdg.configFile."systemd/user/plasma-plasmashell.service.d/fontcache.conf".text = ''
    [Service]
    ExecStartPre=-${pkgs.fontconfig.bin}/bin/fc-cache -f
  '';

  # KDE Wallet on (2026-10-02): it is the keyring Edge, VS Code, Slack and Discord store their
  # login keys in; turning it off made Edge hang. SDDM's login (PAM, pam_kwallet5) unlocks it
  # silently, as long as the wallet password equals the login password. The Secret Service API
  # lets apps that use the standard Linux keyring (libsecret) save logins too.
  # kwalletrc is rewritten by KDE, so set the keys on each activation instead of owning the file.
  home.activation.enableKWallet = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kwalletrc --group Wallet --key Enabled true
    run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kwalletrc --group org.freedesktop.secrets --key apiEnabled true
  '';

  # Baloo (KDE file search) must never index the rclone OneDrive mount: it downloads cloud
  # files just to index them, and a hung read there blocked sleep (2026-10-02). The existing
  # exclude entry wasn't enough on its own, so set it explicitly on each activation.
  home.activation.balooExcludeOneDrive = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file baloofilerc --group General --key "exclude folders" "${config.home.homeDirectory}/OneDrive/"
  '';

  # Word / Excel / PowerPoint files open in Office Online (2026-10-05, Chinh's choice). Office
  # Online only opens files that are in OneDrive, so: a file in ~/OneDrive opens directly (its
  # OneDrive ID is looked up through rclone); a file elsewhere is copied into
  # ~/OneDrive/Opened from PC/ first (the original stays as it is) and opens once uploaded.
  # The rclone mount is the personal OneDrive, so this is personal Office Online (no Power Query).
  xdg.desktopEntries.office-online = let
    officeOnline = pkgs.writeShellScript "office-online" ''
      set -u
      notify() { ${pkgs.libnotify}/bin/notify-send -t 4000 -i x-office-document "$@"; }
      rclone() { ${pkgs.rclone}/bin/rclone --config "$HOME/.config/rclone/rclone.conf" "$@"; }
      file=$(${pkgs.coreutils}/bin/realpath -- "$1")
      onedrive=$HOME/OneDrive
      case "$file" in
        "$onedrive"/*) rel=''${file#"$onedrive"/} ;;
        *)
          # Copy into OneDrive; a different file with the same name gets a number added.
          dir="$onedrive/Opened from PC"
          mkdir -p "$dir"
          name=$(basename -- "$file"); base=''${name%.*}; ext=''${name##*.}
          target="$dir/$name"; n=2
          while [ -e "$target" ] && ! cmp -s "$file" "$target"; do
            target="$dir/$base ($n).$ext"; n=$((n + 1))
          done
          [ -e "$target" ] || cp -- "$file" "$target"
          rel=''${target#"$onedrive"/}
          notify "Uploading to OneDrive…" "$(basename -- "$target") opens in Office Online when it's uploaded"
          ;;
      esac
      # Wait until OneDrive has the whole file (a fresh copy takes a few seconds to upload).
      size=$(stat -c %s -- "$onedrive/$rel")
      id=""
      for i in $(seq 1 60); do
        info=$(rclone lsjson --stat "onedrive:$rel" 2>/dev/null)
        id=$(echo "$info" | ${pkgs.jq}/bin/jq -r '.ID // empty')
        remote=$(echo "$info" | ${pkgs.jq}/bin/jq -r '.Size // -1')
        [ -n "$id" ] && [ "$remote" = "$size" ] && break
        id=""; sleep 2
      done
      if [ -z "$id" ]; then
        notify -u critical "Couldn't open in Office Online" "OneDrive didn't confirm the upload of $rel (offline?)"
        exit 1
      fi
      # rclone's ID is "<drive>#<item>"; the item ID opens the document in Office Online.
      drive=''${id%%#*}; item=''${id#*#}
      # Its own app window (no tabs or address bar), like the Word/Excel/PowerPoint Online
      # launchers, opening on the current workspace instead of as a tab in Edge's main window.
      exec ${config.home.profileDirectory}/bin/microsoft-edge --app="https://onedrive.live.com/edit.aspx?cid=$drive&resid=$item"
    '';
  in {
    name = "Office Online";
    comment = "Open in Word, Excel or PowerPoint Online (via OneDrive)";
    exec = "${officeOnline} %f";
    icon = "x-office-document";
    terminal = false;
    noDisplay = true;   # only for opening files, not listed in the launcher
    mimeType = officeTypes;
  };

  # Default apps (2026-10-05): PDF in Papers, images in Gwenview, video in Haruna, music in Elisa,
  # plus the link handlers that were already set. Home Manager now owns ~/.config/mimeapps.list;
  # to change a default, change it here (an app's "remember my choice" can't write the file).
  xdg.mimeApps = let
    for = app: types: lib.genAttrs types (_: app);
    office = "office-online.desktop";
    papers = "org.gnome.Papers.desktop";
    gwenview = "org.kde.gwenview.desktop";
    haruna = "org.kde.haruna.desktop";
    elisa = "org.kde.elisa.desktop";
  in {
    enable = true;
    defaultApplications =
      for papers [ "application/pdf" ]
      // for office officeTypes
      // for gwenview [
        "image/jpeg" "image/png" "image/gif" "image/webp" "image/bmp" "image/tiff"
        "image/svg+xml" "image/heic" "image/avif" "image/x-icon"
      ]
      // for haruna [
        "video/mp4" "video/x-matroska" "video/webm" "video/quicktime" "video/x-msvideo"
        "video/mpeg" "video/ogg" "video/x-flv" "video/3gpp"
      ]
      // for elisa [
        "audio/mpeg" "audio/flac" "audio/ogg" "audio/x-wav" "audio/wav" "audio/mp4"
        "audio/aac" "audio/opus" "audio/x-m4a" "audio/x-flac" "audio/x-vorbis+ogg"
      ]
      // {
        "x-scheme-handler/slack" = "slack.desktop";
        "x-scheme-handler/geo" = "google-maps-geo-handler.desktop";
        "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
      };
    associations.added = {
      "application/pdf" = papers;
      "x-scheme-handler/geo" = "google-maps-geo-handler.desktop";
      "x-scheme-handler/slack" = "slack.desktop";
    };
  };

  # App launcher entry: resume exactly the PCAgent Claude Code session (by its ID, not "the most
  # recent one") in a terminal, from Walker (SUPER + SPACE) or Plasma's menu.
  xdg.desktopEntries.pcagent = {
    name = "PC Agent";
    comment = "Resume the PC assistant session (Claude Code in ~/PCAgent)";
    exec = "alacritty --class pcagent --working-directory ${config.home.homeDirectory}/PCAgent -e ${config.home.homeDirectory}/.local/bin/claude --resume 08c2aab2-c850-4b4a-96fa-a4d55505b2c2";
    icon = "utilities-terminal";
    terminal = false;
    categories = [ "Utility" "System" ];
  };

  # Hide apps NixOS's Plasma module installs unconditionally (Skanpage comes with
  # hardware.sane, KWallet Manager is a required Plasma part); Chinh removed both on Kubuntu.
  xdg.dataFile = lib.genAttrs [
    "applications/org.kde.skanpage.desktop"
    "applications/org.kde.kwalletmanager.desktop"
  ] (_: { text = "[Desktop Entry]\nHidden=true\n"; });
}
