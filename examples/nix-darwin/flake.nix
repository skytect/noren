{
  description = "A Mac set up around AeroSpace, kanata and noren: one person's setup, as an example";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noren = {
      url = "github:skytect/noren";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nix-darwin,
      home-manager,
      noren,
      ...
    }:
    let
      # Your macOS account name
      username = "you";
      # kanata's TCP server, where noren's focus rule (home.nix) changes kanata's layers
      kanataPort = "5829";
      args = { inherit noren username kanataPort; };
    in
    {
      darwinConfigurations.example = nix-darwin.lib.darwinSystem {
        specialArgs = args;
        modules = [
          ./darwin.nix
          home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = args;
              users.${username} = ./home.nix;
            };
          }
        ];
      };
    };
}
