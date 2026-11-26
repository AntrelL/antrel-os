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
    {
      nixosConfigurations.uiux-2680 = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [ ./hosts/uiux-2680 ];
      };
    };
}
