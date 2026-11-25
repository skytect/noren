{
  description = "Bar, workspace strip and window border for the AeroSpace window manager";

  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

  outputs =
    { self, nixpkgs }:
    let
      # Apple silicon only: the Dock payload is arm64e
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system}.default = pkgs.callPackage ./nix/package.nix { };
      # The package's build runs the tests (its check phase)
      checks.${system}.tests = self.packages.${system}.default;
      formatter.${system} = pkgs.nixfmt;
    };
}
