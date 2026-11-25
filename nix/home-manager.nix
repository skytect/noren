# The home-manager module: noren as a launchd agent in the login session, its noren.toml, and the
# `noren` command on PATH.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.noren;
  toml = pkgs.formats.toml { };
in
{
  options.services.noren = {
    enable = lib.mkEnableOption "noren";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "noren.packages.\${system}.default";
      description = "The noren package. Its `noren` command goes on PATH.";
    };

    app = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.package}/Applications/Noren.app";
      defaultText = lib.literalExpression ''"''${config.services.noren.package}/Applications/Noren.app"'';
      example = "/Applications/Noren.app";
      description = ''
        The Noren.app the agent runs. macOS ties the privacy grants noren needs (Accessibility,
        Input Monitoring, Screen Recording) to the app's code signature. The package's app is
        ad-hoc signed, so each update asks for them again; a copy signed with a certificate of your
        own keeps them.
      '';
    };

    settings = lib.mkOption {
      inherit (toml) type;
      default = { };
      example = lib.literalExpression ''
        {
          bar.accent = "89b4fa";
          border.width = 3;
          stay.close-bindings = [ "alt-q" ];
        }
      '';
      description = ''
        noren.toml, as described in
        <https://github.com/skytect/noren/blob/main/docs/configuration.md>. Left empty, no file is
        written and every part runs with its defaults.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.agents.noren = {
      enable = true;
      config = {
        ProgramArguments = [ "${cfg.app}/Contents/MacOS/noren" ];
        RunAtLoad = true;
        KeepAlive = true;
        ProcessType = "Interactive";
        LimitLoadToSessionType = "Aqua";
      };
    };

    xdg.configFile."noren/noren.toml" = lib.mkIf (cfg.settings != { }) {
      source = toml.generate "noren.toml" cfg.settings;
    };

    # Only the command: the whole package would add a second Noren.app to the applications
    home.packages = [
      (pkgs.runCommand "noren-command" { meta.mainProgram = "noren"; } ''
        mkdir -p $out/bin
        ln -s ${lib.getExe cfg.package} $out/bin/noren
      '')
    ];

    # Applying trackpad settings, as an activation may, stops their touches reaching noren until
    # it attaches to the trackpads again
    home.activation.norenReattachTrackpads = lib.hm.dag.entryAfter [ "setupLaunchAgents" ] ''
      run /usr/bin/notifyutil -p local.noren.reattach-trackpads
    '';
  };
}
