# The system: macOS settings that make room for AeroSpace and noren, kanata with its keyboard
# driver, and noren's Dock payload.
{
  pkgs,
  noren,
  username,
  kanataPort,
  signed,
  ...
}:
let
  # kanata reaches macOS through Karabiner's virtual keyboard driver, at the version this kanata
  # release supports
  driver = pkgs.kanata.passthru.darwinDriver;
  managerApp = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app";
  pqrsDir = "/Library/Application Support/org.pqrs";
  supportDir = "${pqrsDir}/Karabiner-DriverKit-VirtualHIDDevice";
  driverMarker = "${pqrsDir}/.nix-karabiner-dk";

  # The key that shows Notification Center: F19, which no keyboard here has. noren reads the
  # shortcut from macOS's settings and presses it on a click on its bar's clock, since the menu
  # bar's own clock is under noren's bar.
  f19 = 80; # kVK_F19
in
{
  imports = [
    noren.darwinModules.default
    ./signing.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.overlays = [ (_: _: { noren = noren.packages.aarch64-darwin.default; }) ];

  system.primaryUser = username;
  users.users.${username}.home = "/Users/${username}";
  # home.nix runs the signed copies too
  home-manager.users.${username}._module.args.signed = signed;

  # noren's Dock payload (docs/dock.md): no window shadows, and each new window hidden until it is
  # in place. Needs System Integrity Protection partly off; until then it logs why it cannot start.
  services.noren-dock = {
    enable = true;
    app = signed.noren.path;
  };

  # kanata: home-row modifiers, and Ctrl and Cmd traded so the keys work as on Linux (kanata.kbd)
  environment.systemPackages = [ pkgs.kanata ];
  launchd.daemons.kanata.serviceConfig = {
    Label = "org.nixos.kanata";
    ProgramArguments = [
      signed.kanata.path
      "--cfg"
      "${./kanata.kbd}"
      "--port"
      "127.0.0.1:${kanataPort}"
    ];
    RunAtLoad = true;
    KeepAlive = true; # also retries until the driver's daemon is up
    ProcessType = "Interactive";
    StandardOutPath = "/var/log/kanata.log";
    StandardErrorPath = "/var/log/kanata.log";
  };
  launchd.daemons.karabiner-vhid-daemon.serviceConfig = {
    Label = "org.pqrs.Karabiner-VirtualHIDDevice-Daemon";
    ProgramArguments = [
      "${supportDir}/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
    ];
    RunAtLoad = true;
    KeepAlive = true;
    ProcessType = "Interactive";
  };
  # The driver's system extension activates only from an app in /Applications, so its files go
  # where its own installer puts them, once per version. The first time, macOS asks for approval in
  # System Settings.
  system.activationScripts.postActivation.text = ''
    if [ "$(cat "${driverMarker}" 2>/dev/null)" != "${driver}" ]; then
      rm -rf "${managerApp}" "${supportDir}"
      mkdir -p "${pqrsDir}"
      cp -R "${driver}/Applications/.Karabiner-VirtualHIDDevice-Manager.app" /Applications/
      cp -R "${driver}/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice" "${pqrsDir}/"
      echo "${driver}" > "${driverMarker}"
    fi
    "${managerApp}/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager" activate || true
  '';

  system.defaults = {
    NSGlobalDomain = {
      # The menu bar stays shown, never sliding: noren's bar covers it
      _HIHideMenuBar = false;
      NSAutomaticWindowAnimationsEnabled = false;
      NSWindowResizeTime = 0.001;
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      ApplePressAndHoldEnabled = false;
    };
    dock = {
      # Never shown: AeroSpace and noren's bar stand in for it. It still runs, for noren's payload,
      # but a pointer at the screen's edge waits this many seconds before it slides out.
      autohide = true;
      autohide-delay = 1000.0;
      mru-spaces = false; # AeroSpace wants a stable order of Spaces
      persistent-apps = [ ];
      show-recents = false;
      showMissionControlGestureEnabled = false;
      showAppExposeGestureEnabled = false;
      showDesktopGestureEnabled = false;
      showLaunchpadGestureEnabled = false;
    };
    trackpad = {
      # Three-finger horizontal swipes belong to noren's strip, not to macOS's Spaces
      TrackpadThreeFingerHorizSwipeGesture = 0;
      # AeroSpace's workspaces stand in for Mission Control, App Exposé, the desktop and Launchpad
      TrackpadThreeFingerVertSwipeGesture = 0;
      TrackpadFourFingerPinchGesture = 0;
      TrackpadThreeFingerDrag = false;
    };
    # A click on the wallpaper does nothing: by default it sweeps every window aside, and on a
    # workspace without tiled windows the wallpaper is most of the screen
    WindowManager.EnableStandardClickToShowDesktop = false;

    # macOS reopens no apps after a restart or logout: noren brings them back itself, each window
    # on its workspace. The checkbox in the restart dialog writes the same key.
    CustomUserPreferences."com.apple.loginwindow".TALLogoutSavesState = false;

    CustomUserPreferences."com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
      # "Show Notification Center" on F19: no character, the key code, and the function-key
      # modifier every F key carries
      "163" = {
        enabled = true;
        value = {
          parameters = [
            65535
            f19
            8388608
          ];
          type = "standard";
        };
      };
    };
  };

  system.stateVersion = 7;
}
