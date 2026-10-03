# User-level configuration for chinh (Home Manager).
# Most settings (KDE themes, app logins, Dolphin menus, game saves) come back from the
# backup archive; this file declares the programs and the few configs worth managing.
{ config, pkgs, lib, ... }:

{
  imports = [ ./hyprland.nix ./fastfetch.nix ];

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
      ExecStart = "${pkgs.rclone}/bin/rclone mount onedrive: %h/OneDrive --config=%h/.config/rclone/rclone.conf --vfs-cache-mode writes";
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
