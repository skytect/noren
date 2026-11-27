# A Mac set up around noren

One person's setup, as a working [nix-darwin](https://github.com/nix-darwin/nix-darwin) flake: a
MacBook that behaves like a Linux desktop running [Hyprland](https://hyprland.org), with
[AeroSpace](https://github.com/nikitabobko/AeroSpace) tiling the windows,
[kanata](https://github.com/jtroo/kanata) remapping the keyboard,
[Vicinae](https://github.com/vicinaehq/vicinae) as the launcher, and noren drawing the bar, the
workspace strip and the border. It is a snapshot, refreshed now and then, not a template
kept in step with every change; take the parts you want.

| File | |
| --- | --- |
| [`flake.nix`](flake.nix) | The inputs and the one `darwinConfigurations.example`; your account name goes here |
| [`darwin.nix`](darwin.nix) | macOS's settings, kanata and its driver, noren's Dock payload |
| [`home.nix`](home.nix) | AeroSpace, Vicinae, noren and its settings (`noren.toml`) |
| [`aerospace.toml`](aerospace.toml) | AeroSpace's config: the key bindings, workspaces, floating apps |
| [`kanata.kbd`](kanata.kbd) | kanata's config: home-row modifiers and the Ctrl/Cmd trade |
| [`signing.nix`](signing.nix) | Stable signatures, so macOS's permissions survive updates |

## How the pieces fit

**The keyboard.** kanata trades Ctrl and Cmd in everything it sends, so the key in Ctrl's place
sends Cmd and copies, pastes and opens tabs as Ctrl does on Linux, and the key in Super's place
sends Ctrl. No Mac app needs Ctrl for its shortcuts, so AeroSpace's bindings all use it: Ctrl
here plays Hyprland's Super. Its modifiers sit on the home row (Miryoku style), and the
Spotlight key sends F18, which opens the launcher.

**The bindings** ([`aerospace.toml`](aerospace.toml)), with Ctrl as Super:

| Keys | |
| --- | --- |
| Ctrl+H/J/K/L | Focus left, down, up, right, across screens |
| Ctrl+Shift+H/J/K/L | Move the window that way |
| Ctrl+Alt+H/J/K/L | Resize (held, it repeats) |
| Ctrl+1…0, Ctrl+Alt+1…0 | Workspaces 1-10 and 11-20 |
| Ctrl+Shift+1…0 | Move the window to a workspace and follow it |
| Ctrl+Cmd+H/L | The previous or next workspace |
| Ctrl+Q | Close the window (focus stays on the workspace) |
| Ctrl+Esc | Float or tile the window |
| Spotlight key, Ctrl+/ | Vicinae, the launcher |
| Ctrl+V | Vicinae's clipboard history |
| Ctrl+Return, Ctrl+W | A terminal, a browser window |
| Ctrl+P | Connect or disconnect the iPad as a screen (`noren sidecar`) |
| Ctrl+\\ | Lock the screen (`noren lock`) |
| Three fingers left/right | The next or previous workspace (noren's strip) |
| Ctrl+drag | Move a window from anywhere in it (noren) |

**The launcher.** Vicinae replaces Spotlight and Raycast: apps, clipboard history, a
calculator. It runs as a launchd agent, and AeroSpace opens it, so its key works the same in
every app. Its settings window owns `settings.json`, so the settings kept in nix go in a
`nix.json` it imports. The Dock keeps nothing pinned: apps open from Vicinae.

**The screens.** Workspaces 1-5 belong to the laptop, 6-10 to a monitor and 11-20 to an iPad,
falling back to the screens that are there. noren keeps the monitor above the laptop and the
iPad to its right, wherever macOS puts them when they arrive.

**A remote Linux desktop.** In a remote desktop window, the keys should reach the remote
Hyprland as they are. noren's focus rule (in [`home.nix`](home.nix)) puts AeroSpace in a mode
that binds nothing, and asks kanata, through its TCP port, to change to a copy of its layers
without the Ctrl/Cmd trade. Focusing any other window undoes both.

**macOS's settings** ([`darwin.nix`](darwin.nix)), each for a part of the above:

- Three-finger swipes between Spaces off, as noren's strip takes them; Mission Control's,
  App Exposé's and Launchpad's gestures off, as AeroSpace's workspaces stand in for them.
- The menu bar always shown, as noren's bar covers it; the Dock hidden for good.
- Notification Center on F19, which noren presses on a click on its clock.
- macOS's own reopening of windows after a restart off, as noren restores them itself.

**Permissions.** AeroSpace, kanata and noren need Accessibility, Input Monitoring and, for noren,
Screen Recording. [`signing.nix`](signing.nix) copies each to a fixed path and signs it with a
certificate made on the Mac, so a nix update does not make macOS ask again.

## Using it

1. Install [Nix](https://nixos.org/download) and read nix-darwin's README.
2. Copy this folder. In `flake.nix`, set `username`; in `home.nix`, set your monitor's numbers in
   `displays.place` (or drop it) and your remote desktop's window titles in the focus rule.
3. `sudo darwin-rebuild switch --flake .#example`
4. Approve Karabiner's driver in System Settings > General > Login Items & Extensions, and give
   AeroSpace, kanata and Noren the permissions they ask for.
5. For the Dock payload, turn off part of System Integrity Protection
   ([docs/dock.md](../../docs/dock.md)). Without it, the rest works.

The other apps the bindings open (Ghostty, Yab, Telegram, Shottr, Jump Desktop) are not
installed by this flake; swap in your own.
