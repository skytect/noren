# The Dock payload

Only the Dock's connection to the window server may change other apps' windows, so this part of
noren runs inside the Dock:

- `Dock/payload.m` turns off every app window's shadow, and hides each new document window until
  noren says AeroSpace has put it in place. A window is never held for more than a second, and
  nothing is hidden while noren is not running. It also puts tiled windows one level below the
  others, so floating windows stay above them, and moves windows for `[drag]`.
- `Dock/inject.m` (`noren-dock` in the app bundle) puts the payload into the Dock, and again each
  time the Dock restarts. It runs as root.

## Setup

1. Turn off System Integrity Protection's debugging restrictions, which keep other processes out
   of the Dock. In macOS Recovery (hold the power button at startup, then Options, then
   Utilities > Terminal):

   ```sh
   csrutil enable --without fs --without debug --without nvram
   ```

   Restart; `csrutil status` shows the result. macOS 27.2 loads the arm64e payload without the
   `-arm64e_preview_abi` boot argument that yabai's guide adds; earlier versions may need it.

2. Run the loader as root at startup, with the payload's path. With nix-darwin, the flake's
   module does it (`services.noren-dock.enable = true`; see the README). Otherwise, as a launchd
   daemon running:

   ```
   /Applications/Noren.app/Contents/MacOS/noren-dock \
     /Applications/Noren.app/Contents/Resources/dock-payload.dylib
   ```

Until both are done the loader logs why it cannot get into the Dock, windows keep their shadows,
and new windows show as they open.
