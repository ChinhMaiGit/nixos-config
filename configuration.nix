# System-level configuration (draft, untested). Mirrors the Kubuntu 26.04 setup of 2026-10-01.
{ config, pkgs, ... }:

{
  # ---------- Boot ----------
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 3;          # keep 3 generations in the menu
  boot.loader.systemd-boot.memtest86.enable = true;         # was memtest86+ on Kubuntu
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;          # newest kernel for RDNA 4

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
  # MediaTek MT7922 Wi-Fi (mt7921e): after waking from sleep the 4-way handshake timed out
  # and NetworkManager asked for the "wrong" password again (2026-10-02). PCIe ASPM and
  # Wi-Fi power saving off is the usual fix for this card's resume problems.
  boot.extraModprobeConfig = "options mt7921e disable_aspm=1";
  networking.networkmanager.wifi.powersave = false;
  # Neither fixed it. Reloading the driver around sleep and iwd instead of wpa_supplicant
  # didn't either (2026-10-02): with both, the router itself drops the PC with
  # "4-way handshake timeout" 1-4 times on almost every 5 GHz connect, after boot as
  # well as after sleep, while 2.4 GHz connects first try. Next suspect: the router.
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
  # Default Plasma apps Chinh removed on Kubuntu too (PDFs open in GNOME Papers).
  environment.plasma6.excludePackages = with pkgs.kdePackages; [ okular ];

  # ---------- Graphics: AMD RX 9070 XT ----------
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;                     # 32-bit games / Proton

  # ---------- Sound, Bluetooth, printing, firmware ----------
  services.pipewire = { enable = true; alsa.enable = true; alsa.support32Bit = true; pulse.enable = true; };
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
