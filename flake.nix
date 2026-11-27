{
  description = "A Hyprland-like desktop for macOS, with AeroSpace inside";

  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

  outputs =
    { self, nixpkgs }:
    let
      # Apple silicon only: the Dock payload is arm64e
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = {
        default = pkgs.callPackage ./nix/package.nix { inherit (self.packages.${system}) aerospace; };
        # The AeroSpace noren carries, on its own
        aerospace = pkgs.callPackage ./nix/aerospace/package.nix { };
      };
      # noren in the login session, and its config (services.noren)
      homeManagerModules.default = import ./nix/home-manager.nix self;
      # The Dock payload's root loader (services.noren-dock)
      darwinModules.default = import ./nix/darwin.nix self;
      # The package's build runs the tests (its check phase)
      checks.${system}.tests = self.packages.${system}.default;
      formatter.${system} = pkgs.nixfmt;
    };
}
