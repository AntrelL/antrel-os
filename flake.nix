{
  description = "antrel-os: personal NixOS system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Not following our nixpkgs: omp is built exactly as upstream locks and tests it.
    omp.url = "github:can1357/oh-my-pi";
  };

  outputs =
    inputs@{ nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in
    {
      nixosConfigurations.uiux-2680 = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [ ./hosts/uiux-2680 ];
      };

      # Live ISO with a text boot menu: the stock ISO's graphical GRUB hangs on this board.
      nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
        modules = [ ./hosts/installer ];
      };
      packages.x86_64-linux.iso = inputs.self.nixosConfigurations.installer.config.system.build.isoImage;

      # Installer for the live ISO: `nix run github:AntrelL/antrel-os` (see README).
      apps.x86_64-linux.default = {
        type = "app";
        program = nixpkgs.lib.getExe (
          pkgs.writeShellApplication {
            name = "antrel-os-install";
            # nixos-install, nixos-enter, nixos-generate-config come from the live ISO.
            runtimeInputs = with pkgs; [
              btrfs-progs
              coreutils
              curl
              git
              util-linux
            ];
            text = builtins.readFile ./install.sh;
          }
        );
        meta.description = "Install antrel-os onto the prepared nixos partition";
      };
    };
}
