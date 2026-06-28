{
  description = "Root router flake (delegates to env flakes)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    kiln = {
      url = "github:XilongYang/kiln";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    server = {
      url = "path:./envs/server";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
      inputs.kiln.follows = "kiln";
    };

    mac = {
      url = "path:./envs/mac";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = { nixpkgs, server, mac, ... }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in {
    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        lua-language-server
      ];
    };

    nixosConfigurations =
      (server.nixosConfigurations or {});

    homeConfigurations = 
      (mac.homeConfigurations or {});
  };
}
