# User-level configuration for chinh (Home Manager, draft, untested).
# Most settings (KDE themes, app logins, Dolphin menus, game saves) come back from the
# backup archive; this file declares the programs and the few configs worth managing.
{ config, pkgs, ... }:

{
  home.username = "chinh";
  home.homeDirectory = "/home/chinh";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    # Browsers / communication / office
    microsoft-edge discord slack
    # Development
    vscode claude-code uv gh nodejs jdk python3
    # Documents, OCR, LaTeX
    pandoc ocrmypdf poppler-utils ghostscript
    (tesseract.override { enableLanguages = [ "eng" "deu" "vie" "frk" ]; })
    texlive.combined.scheme-full
    # Comics / e-books (Kindle pipeline)
    kcc
    # Gaming tools
    protonup-qt
    # Media and KDE apps
    haruna kdePackages.elisa kdePackages.gwenview kdePackages.kate kdePackages.kcalc
    kdePackages.kcharselect kdePackages.ark kdePackages.ksystemlog kdePackages.kwalletmanager
    kdePackages.dolphin-plugins kdePackages.ffmpegthumbs kdePackages.kdegraphics-thumbnailers
    kdePackages.skanpage papers
    # System / terminal tools
    btop htop fastfetch cmatrix go-mtpfs
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
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/OneDrive";
      ExecStart = "${pkgs.rclone}/bin/rclone mount onedrive: %h/OneDrive --config=%h/.config/rclone/rclone.conf --vfs-cache-mode writes";
      ExecStop = "/run/wrappers/bin/fusermount -u %h/OneDrive";
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
}
