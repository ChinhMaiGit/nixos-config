# System-level configuration (draft, untested). Mirrors the Kubuntu 26.04 setup of 2026-10-01.
{ config, pkgs, ... }:

{
  # ---------- Boot ----------
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 3;          # keep 3 generations in the menu
  boot.loader.systemd-boot.memtest86.enable = true;         # was memtest86+ on Kubuntu
  boot.loader.efi.canTouchEfiVariables = true;
  # 6.18 LTS (NixOS default; RX 9070 XT supported since 6.14). On 7.2 the MT7922 Wi-Fi needed
  # 2-5 tries for every 5 GHz handshake (the router dropped it, and NetworkManager then asked for
  # the "wrong" password); on 6.18 it connects first try, after boot and after sleep
  # (2026-10-02; Kubuntu's 7.0 was fine too). Retry linuxPackages_latest on a later 7.x.
  boot.kernelPackages = pkgs.linuxPackages;

  # ---------- Nix ----------
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  # Weekly cleanup: keep the 3 newest system versions (matching the 3 boot menu entries),
  # then delete everything in /nix/store no longer used. nix.gc can only delete by age,
  # so this is a small service instead. Persistent = catch up if the PC was off.
  systemd.services.nix-cleanup = {
    description = "Delete old NixOS versions (keep 3) and unused store paths";
    serviceConfig.Type = "oneshot";
    path = [ config.nix.package ];
    script = ''
      nix-env --profile /nix/var/nix/profiles/system --delete-generations +3
      nix-collect-garbage
    '';
    startAt = "weekly";
  };
  systemd.timers.nix-cleanup.timerConfig.Persistent = true;
  nixpkgs.config.allowUnfree = true;                        # Steam, Edge, VS Code, Discord, Slack, Claude Code
  programs.nix-ld.enable = true;                            # prebuilt binaries (uv/pip wheels, VS Code extensions)

  # ---------- Machine ----------
  networking.hostName = "ChinhMaiPC";
  networking.networkmanager.enable = true;                  # Wi-Fi: re-enter the Vodafone password once
  # MT7922 Wi-Fi (mt7921e): ASPM and Wi-Fi power saving off. Tried for the handshake problem
  # above before the kernel turned out to be the cause; kept because they're harmless on a
  # desktop and every sleep test since ran with them.
  boot.extraModprobeConfig = "options mt7921e disable_aspm=1";
  networking.networkmanager.wifi.powersave = false;
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  # Vietnamese input (Telex / Unikey), like fcitx5-unikey on Kubuntu
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [ qt6Packages.fcitx5-unikey kdePackages.fcitx5-configtool ];
  };
  # Run Chromium/Electron apps (Edge, VS Code, Discord, Slack) natively on Wayland. Their
  # nixpkgs launchers then add --enable-wayland-ime, which they need to type Vietnamese
  # through fcitx5. KWin must also start fcitx5: System Settings > Keyboard > Virtual
  # Keyboard = Fcitx 5 (kwinrc [Wayland] InputMethod, set outside this config).
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # ---------- Desktop: KDE Plasma 6 on Wayland ----------
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;
  # Omarchy-style Hyprland as a second session (chosen at the login screen); Plasma stays as
  # the fallback until it works properly. The desktop itself is configured in hyprland.nix.
  programs.hyprland = { enable = true; withUWSM = true; };
  # Screen recording in the Hyprland session (ALT + PRINT): the module adds the capability
  # wrapper gpu-screen-recorder needs for direct (KMS) screen capture.
  programs.gpu-screen-recorder.enable = true;
  security.pam.services.hyprlock = { };                     # lock screen password check
  # Omarchy's font plus more Nerd Fonts (with the bar's icons) for gear menu > Font, including
  # Google Fonts' Space / Roboto / Ubuntu Mono and a few very distinct looks
  fonts.packages = with pkgs.nerd-fonts; [
    jetbrains-mono caskaydia-mono fira-code hack
    space-mono roboto-mono ubuntu-mono comic-shanns-mono _3270 departure-mono victor-mono
  ];
  # Default Plasma apps Chinh removed on Kubuntu too (PDFs open in GNOME Papers).
  environment.plasma6.excludePackages = with pkgs.kdePackages; [ okular ];

  # ---------- Graphics: AMD RX 9070 XT ----------
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;                     # 32-bit games / Proton

  # ---------- Sound, Bluetooth, printing, firmware ----------
  services.pipewire = { enable = true; alsa.enable = true; alsa.support32Bit = true; pulse.enable = true; };
  security.rtkit.enable = true;                             # realtime priority for PipeWire
  # Ignore the audio of PlayStation controllers (headphone jack/speaker): plugged in, they
  # became the default output and took the game sound. The gamepad itself is unaffected.
  services.pipewire.wireplumber.extraConfig."51-ignore-playstation-controller-audio" = {
    "monitor.alsa.rules" = [{
      matches = [
        { "device.name" = "~alsa_card.usb-Sony_Interactive_Entertainment_Wireless_Controller.*"; }
        { "device.name" = "~alsa_card.usb-Sony_Interactive_Entertainment_DualSense.*"; }
      ];
      actions.update-props."device.disabled" = true;
    }];
  };
  hardware.bluetooth.enable = true;
  services.printing = {
    enable = true;
    drivers = with pkgs; [ hplip brlaser gutenprint foo2zjs splix ];
  };
  # Scanning (GNOME Document Scanner; Skanpage is hidden in home.nix): SANE with driverless network scanning
  # (AirScan/eSCL) and HP devices; Avahi finds network scanners and printers like on Kubuntu.
  hardware.sane = {
    enable = true;
    extraBackends = with pkgs; [ sane-airscan hplip ];
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
  # Don't freeze user programs before sleep. With the rclone OneDrive mount (FUSE), a program
  # reading ~/OneDrive (Baloo, 2026-10-02) waits on the already-frozen rclone and can't freeze
  # itself, so sleep gave up after 100 s and the PC stayed on.
  systemd.services.systemd-suspend.environment.SYSTEMD_SLEEP_FREEZE_USER_SESSIONS = "false";
  # On kernel 6.18 a program waiting on a FUSE read can't be frozen at all, so any OneDrive
  # activity (Baloo, Dolphin PDF previews) still blocked sleep. Unmount OneDrive (rclone) just
  # before sleep and mount it again after waking; "|| true" so a failure never blocks sleep.
  powerManagement.powerDownCommands = "${pkgs.coreutils}/bin/timeout 20 ${pkgs.systemd}/bin/systemctl --user --machine=chinh@ stop rclone-onedrive.service || true";
  powerManagement.resumeCommands = "${pkgs.systemd}/bin/systemctl --user --machine=chinh@ start --no-block rclone-onedrive.service || true";
  services.fwupd.enable = true;
  services.power-profiles-daemon.enable = true;
  services.locate = { enable = true; package = pkgs.plocate; };
  services.flatpak.enable = true;                           # optional fallback for apps

  # ---------- Gaming ----------
  programs.steam = {
    enable = true;
    gamescopeSession.enable = false;
  };
  programs.gamemode.enable = true;

  # ---------- Apps with NixOS modules ----------
  # RGB lighting: MSI Mystic Light on the board (USB 0db0:0076), the G502 mouse, and anything on
  # the board's ARGB headers. Also loads the SMBus (i2c) drivers OpenRGB needs on AMD boards.
  services.hardware.openrgb = { enable = true; motherboard = "amd"; };
  programs.kdeconnect.enable = true;
  programs.ausweisapp = { enable = true; openFirewall = true; };
  programs.partition-manager.enable = true;

  # ---------- Local AI (planned): Ollama on ROCm for the RX 9070 XT ----------
  services.ollama = {
    enable = true;
    package = pkgs.ollama-rocm;
  };

  # ---------- User ----------
  users.users.chinh = {
    isNormalUser = true;
    description = "Chinh Mai";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "lp" "scanner" ];
  };

  # ---------- System-wide tools ----------
  environment.systemPackages = with pkgs; [
    git curl wget vim unzip zip zsync
    mesa-demos vulkan-tools evtest
    wimlib cdrkit efibootmgr
    btrfs-progs xfsprogs
  ];

  system.stateVersion = "26.05";   # do not change after install
}
