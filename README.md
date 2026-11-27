# noren

A noren is the split curtain hung across the top of a shop doorway. This one hangs across the top
of a Mac's screen, around the [AeroSpace](https://github.com/nikitabobko/AeroSpace) tiling window
manager, which comes inside it:

- AeroSpace, built with fixes it does not have yet, and a Hyprland-like config on the Alt key
  that it runs with until you write your own ([assets/aerospace.toml](assets/aerospace.toml));
- a bar over the menu bar: AeroSpace's workspaces, the focused app, status items and the clock;
- a strip that follows three-finger swipes between workspaces;
- a border around the focused window;
- focus kept on a workspace whose last window closed, and the pointer following keyboard focus;
- Alt+drag to move a window, in any app, and new windows nesting as in a dwindle layout;
- the screens kept where they belong, and the apps and their windows brought back after a restart;
- commands run as focus moves into and out of chosen windows.

Every part can be turned off; see [docs/configuration.md](docs/configuration.md).

## Requirements

A Mac with Apple silicon, on macOS 26 or later. noren runs the AeroSpace inside it, as a login
agent of its own, and quits any other AeroSpace it finds running: two would fight over the
windows.

## Installing

With [Homebrew](https://brew.sh):

```sh
brew install --cask skytect/tap/noren
open -a Noren
```

Then add Noren to System Settings > General > Login Items to start it at login, and turn it on
under "Allow in the Background" there when macOS asks: that is AeroSpace's agent.

With [Nix](https://nixos.org), the flake has a home-manager module for the app and a nix-darwin
module for the [Dock payload](docs/dock.md):

```nix
# flake inputs
noren.url = "github:skytect/noren";

# home-manager
imports = [ inputs.noren.homeManagerModules.default ];
services.noren = {
  enable = true;
  settings.border.width = 3; # noren.toml
};

# nix-darwin, for the Dock payload
imports = [ inputs.noren.darwinModules.default ];
services.noren-dock.enable = true;
```

The nix build is ad-hoc signed, so macOS asks for noren's permissions again after each update,
unless `services.noren.app` points at a copy signed with a certificate of your own. Releases
are signed with one certificate, so their permissions carry over.

noren asks for three permissions: Accessibility (window titles on the bar, the border, dragging
windows, closing extra windows on restore), Input Monitoring (trackpad swipes) and Screen
Recording (the still cover over the screen while a new window is placed). AeroSpace asks for
Accessibility of its own.

[examples/nix-darwin](examples/nix-darwin) is one whole setup as a nix-darwin flake: noren with
AeroSpace's bindings, kanata's keyboard layers and the macOS settings they need.

## Building

```sh
nix build      # result/Applications/Noren.app; runs the tests too
```

With Xcode or the Swift toolchain:

```sh
swift build
swift test
```

`swift build` builds the app's binary alone; the bundle, with the Dock payload, comes from
`nix build`.

## Configuration

`~/.config/noren/noren.toml`; see [docs/configuration.md](docs/configuration.md). Without it,
every part runs with its defaults.

## Commands

The same binary runs a few one-shot commands instead of the app: `noren sidecar` (connect or
disconnect an iPad as a screen), `noren lock` (lock the screen) and `noren display-mode` (list or
change the built-in screen's size). Any other argument prints the usage.

## The Dock payload

`Dock/` holds an optional payload that noren puts into the Dock: it hides each new window until
AeroSpace has put it in place, and turns off window shadows. It needs System Integrity Protection
partly off; see [docs/dock.md](docs/dock.md).

## License

MIT; see [LICENSE](LICENSE). `Dock/inject.m` is adapted from
[yabai](https://github.com/asmvik/yabai)'s loader, under yabai's MIT license, quoted in the file.
