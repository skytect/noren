# The nix-darwin module: the Dock payload's loader as a root launchd daemon (docs/dock.md). It
# needs System Integrity Protection's debugging restrictions off; until then it logs why it cannot
# get into the Dock, to /var/log/noren-dock.log.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.noren-dock;
in
{
  options.services.noren-dock = {
    enable = lib.mkEnableOption "noren's Dock payload";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "noren.packages.\${system}.default";
      description = "The noren package.";
    };

    app = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.package}/Applications/Noren.app";
      defaultText = lib.literalExpression ''"''${config.services.noren-dock.package}/Applications/Noren.app"'';
      example = "/Applications/Noren.app";
      description = "The Noren.app whose loader and payload run; the same one noren runs from.";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.daemons.noren-dock.serviceConfig = {
      Label = "local.noren.dock";
      ProgramArguments = [
        "${cfg.app}/Contents/MacOS/noren-dock"
        "${cfg.app}/Contents/Resources/dock-payload.dylib"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/var/log/noren-dock.log";
      StandardErrorPath = "/var/log/noren-dock.log";
    };
  };
}
