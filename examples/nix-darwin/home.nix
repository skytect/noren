# The session: AeroSpace and noren, both running from their signed copies (signing.nix).
{
  lib,
  pkgs,
  noren,
  username,
  kanataPort,
  signed,
  ...
}:
let
  profile = "/etc/profiles/per-user/${username}";
  aerospace = "${profile}/bin/aerospace";

  # Changes kanata to `layer` through its TCP server (darwin.nix): one JSON line, then the
  # connection closes
  kanataLayer = layer: [
    "/bin/bash"
    "-c"
    ''printf '{"ChangeLayer":{"new":"%s"}}\n' ${layer} > /dev/tcp/127.0.0.1/${kanataPort}''
  ];
in
{
  imports = [ noren.homeManagerModules.default ];

  home.stateVersion = "26.05";

  # AeroSpace: the CLI from the package, the app from its signed copy, which keeps its
  # Accessibility grant across updates
  home.packages = [ pkgs.aerospace ];
  home.file.".aerospace.toml".source = pkgs.replaceVars ./aerospace.toml {
    inherit profile;
    home = "/Users/${username}";
  };
  launchd.agents.aerospace = {
    enable = true;
    config = {
      ProgramArguments = [ "${signed.aerospace.path}/Contents/MacOS/AeroSpace" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Interactive";
      LimitLoadToSessionType = "Aqua";
    };
  };
  # AeroSpace reads its config only at start and on reload-config
  home.activation.reloadAerospaceConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${aerospace} reload-config 2>/dev/null || true
  '';

  # Ctrl+Q (aerospace.toml): close the focused window. A script rather than AeroSpace's `close`,
  # for an app that refuses a plain window close and is quit instead
  home.file.".local/bin/aerospace-close" = {
    executable = true;
    text = ''
      #!/bin/sh
      if [ "$(${aerospace} list-windows --focused --format '%{app-bundle-id}')" = dev.herdr.app ]; then
        exec /usr/bin/osascript -e 'quit app "Herdr"'
      fi
      exec ${aerospace} close
    '';
  };

  services.noren = {
    enable = true;
    app = signed.noren.path;
    # noren.toml (docs/configuration.md). Left out, so noren works them out: the bar's height (the
    # notch's menu bar), the key that opens Notification Center (darwin.nix), and the apps
    # AeroSpace floats (aerospace.toml's rules).
    settings = {
      # One Dark
      bar = {
        accent = "61afef";
        text = "abb2bf";
        dim = "676f7d";
        warn = "e5c07b";
        base = "282c34";
      };
      # Ctrl+Q runs a script rather than AeroSpace's `close`, so noren cannot work it out
      stay.close-bindings = [ "ctrl-q" ];
      # Blue into purple, as Hyprland's gradient borders
      border = {
        color = "61afef";
        color-end = "c678dd";
        width = 3;
        opacity = 0.85;
      };
      displays = {
        wallpaper = "/System/Library/CoreServices/DefaultDesktop.heic";
        place = [
          # A monitor above the laptop, left edges lined up. Its numbers come from
          # CGDisplayVendorNumber, CGDisplayModelNumber and CGDisplaySerialNumber
          {
            display = {
              vendor = 1234;
              model = 5678;
              serial = 12345678;
            };
            position = "above";
            align = "left";
          }
          # An iPad in the corner below the monitor
          {
            display = "sidecar";
            position = "right";
            align = "top";
          }
        ];
      };
      # A remote desktop's session windows take every key: AeroSpace passes them all through, and
      # kanata changes to its layers without the Ctrl/Cmd swap. The session windows are named after
      # the computer they show.
      focus-rule = [
        {
          "if" = {
            app-id = "com.p5sys.jump.mac.viewer";
            title-regex = "^(desktop|server)$";
          };
          enter = [
            [
              "aerospace"
              "mode"
              "passthrough"
            ]
            (kanataLayer "weird-jump")
          ];
          leave = [
            [
              "aerospace"
              "mode"
              "main"
            ]
            (kanataLayer "weird")
          ];
        }
      ];
    };
  };
}
