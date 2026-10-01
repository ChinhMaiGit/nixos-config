# Draft NixOS flake for ChinhMaiPC (9800X3D + RX 9070 XT).
# Written on Kubuntu before the switch; NOT yet built. The first `nixos-rebuild build`
# will show any typos or renamed options; fix them before `switch`.
{
  description = "ChinhMaiPC: NixOS + Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }: {
    nixosConfigurations.ChinhMaiPC = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix   # copy from /etc/nixos after installing
        ./configuration.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-backup";
          home-manager.users.chinh = import ./home.nix;
        }
      ];
    };
  };
}
