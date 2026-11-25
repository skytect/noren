# noren

A noren is the split curtain hung across the top of a shop doorway. This one hangs across the top
of a Mac's screen, around the [AeroSpace](https://github.com/nikitabobko/AeroSpace) tiling window
manager: a bar over the menu bar with AeroSpace's workspaces, a strip that follows three-finger
swipes between workspaces, and a border around the focused window.

**Status: early.** noren is being rewritten in Swift from an earlier Objective-C version, and
does nothing useful yet.

## Requirements

- A Mac with Apple silicon, on macOS 26 or later
- AeroSpace

## Building

With [Nix](https://nixos.org):

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

## The Dock payload

`Dock/` holds an optional payload that noren puts into the Dock: it hides each new window until
AeroSpace has put it in place, and turns off window shadows. It needs System Integrity Protection
partly off; see [docs/dock.md](docs/dock.md).

## License

MIT; see [LICENSE](LICENSE). `Dock/inject.m` is adapted from
[yabai](https://github.com/asmvik/yabai)'s loader, under yabai's MIT license, quoted in the file.
