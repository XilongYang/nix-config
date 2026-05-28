{
  description = "Xilong's Server";

  nixConfig = {
    substituters = [
      "https://cache.nixos.org"
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    kiln.url = "github:XilongYang/kiln";
    kiln.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{nixpkgs, home-manager, ...}:
  let
    homeManagerImports = [
      ../base/home.d/home.nix
      ./home.d/home.nix
    ];

    homeManagerModule = {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = false;
      home-manager.users.xilong.imports = homeManagerImports;
    };
  in {
    nixosConfigurations.server = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./os.d/os.nix
        ({ ... }: {
          nixpkgs.overlays = [ inputs.kiln.overlays.default ];
        })
        home-manager.nixosModules.home-manager
        homeManagerModule
      ];
    };
  };
}
