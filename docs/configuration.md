# Configuration

noren reads `~/.config/noren/noren.toml` (`$XDG_CONFIG_HOME/noren/noren.toml` when that is
set). Without the file, every part runs with its defaults.

Every key may be left out. Where a default says *worked out*, noren finds the value itself:
from the screens, from macOS's settings, or from AeroSpace's own config, which it asks AeroSpace
for (`aerospace config --config-path`).

A key noren does not know is an error, as is a value of the wrong type. noren names the key and
what is wrong in a notification and in its log, and keeps running as it was. Saving a file that
reads well restarts noren with it.

Colours are `"RRGGBB"` or `"#RRGGBB"`.

## Parts

Each part has `enable` (default `true`).

| Table | Part |
| --- | --- |
| `[bar]` | The bar over the menu bar: workspaces, the focused app, status items, the clock |
| `[status]` | The bar's status items: microphone, camera, network, volume, battery |
| `[strip]` | Three-finger swipes between workspaces, and the strip shown on a switch |
| `[stay]` | Staying on a workspace whose last window closed |
| `[pointer]` | The pointer following keyboard focus |
| `[border]` | The focused window's border |
| `[drag]` | Moving a window by dragging anywhere in it with a key held |
| `[dwindle]` | New windows nesting as in a dwindle layout |
| `[appear]` | New windows shown only once in place (needs the [Dock payload](dock.md)) |
| `[displays]` | Where the screens sit, and the wallpaper |
| `[restore]` | Apps and their windows brought back after a restart |

## `[bar]`

| Key | Default | |
| --- | --- | --- |
| `height` | worked out | In points, more than 0: each screen's own menu bar height. Set, the least on every screen |
| `accent` | the system blue | The focused workspace |
| `text` | `d9d9d9` | |
| `dim` | `808080` | Workspaces without windows |
| `warn` | the system yellow | Status items that need a look |
| `base` | `000000` | Behind the bar on workspaces with windows |
| `notification-center-key` | worked out | The key code the clock presses to open Notification Center; by default the shortcut set for it in Keyboard settings. A configured key, from 0 to 127, is pressed with fn, as an F key is |

## `[stay]`

| Key | Default | |
| --- | --- | --- |
| `close-bindings` | worked out | AeroSpace bindings that close a window, such as `["alt-q"]`; by default those AeroSpace's config binds to `close` |

## `[border]`

| Key | Default | |
| --- | --- | --- |
| `width` | `2` | In points, inside the window's edge |
| `opacity` | `1` | From 0 to 1 |
| `color` | the system accent colour | At the top-left corner |
| `color-end` | `color` | At the bottom-right corner, blended from `color` |

## `[aerospace]`

| Key | Default | |
| --- | --- | --- |
| `start` | `true` | Whether noren starts the AeroSpace inside it, registering the login agent `local.noren.aerospace`. `false` says something else runs that agent, and noren withdraws a registration it made before. The home-manager module runs the agent itself and sets this to `false` |

## `[drag]`

| Key | Default | |
| --- | --- | --- |
| `modifier` | `"alt"` | The key held: `"alt"`, `"ctrl"` or `"cmd"` |

A drag with the key held moves the window under the pointer, in any app. It needs noren allowed Accessibility,
which it asks for when it starts. With the [Dock payload](dock.md) the window moves as smoothly as
one dragged by its title bar; without it, through Accessibility, which a busy app answers late.
A click with the key held over a window no longer reaches the app (with Ctrl: no right-click).

## `[appear]`

| Key | Default | |
| --- | --- | --- |
| `floating-apps` | worked out | Bundle ids of apps whose windows float, which are never hidden; by default those AeroSpace's config floats by app id alone |

## `[displays]`

| Key | Default | |
| --- | --- | --- |
| `wallpaper` | none | An image put on every screen, and on each screen that arrives |
| `place` | none | Where displays are kept, relative to the built-in screen |

Each `[[displays.place]]` has:

- `display`: a monitor as `{ vendor = …, model = …, serial = … }` (CGDisplayVendorNumber,
  ModelNumber and SerialNumber), or `"sidecar"` for an iPad.
- `position`: `above`, `below`, `left` or `right`.
- `align`: which edges line up. Use `left`, `right` or `center` with `above` and `below`, and
  `top`, `bottom` or `center` with `left` and `right`. The default is `center`.

A display that is connected and out of place is moved back after any change to the screens.

The bar paints the wallpaper under itself, over the menu bar. For a dynamic wallpaper that
changes with the time of day, it paints the frame macOS shows at the time; one that follows the
sun's position or the appearance shows its first frame there.

## `[restore]`

While noren runs, it keeps a snapshot of the running apps and each window's workspace in
`~/Library/Application Support/noren/snapshot.json`. After a restart or a logout, it reopens
those apps hidden, moves their windows back to their workspaces, and closes any extra window
(through Accessibility).

Turn off macOS's own reopening of windows, or both reopen the apps. That is the "Reopen windows
when logging back in" box in the restart dialog, or:

```sh
defaults write com.apple.loginwindow TALLogoutSavesState -bool false
```

## Focus rules

Commands run as keyboard focus moves into and out of matching windows. For example, these rules
pass every key to a remote desktop's session windows:

```toml
[[focus-rule]]
if = { app-id = "com.example.remote-desktop", title-regex = "^(office|lab)$" }
enter = [["aerospace", "mode", "passthrough"]]
leave = [["aerospace", "mode", "main"]]
```

- `if`: `app-id`, `title-regex` (a regular expression the title must contain a match of), or
  both.
- `enter`: commands run when focus moves into a matching window from one that is not.
- `leave`: commands run when focus moves out of a matching window to one that is not.

Each command is a list: the program, then its arguments. An `aerospace` command goes straight
to AeroSpace. Any other program is looked up on `PATH` unless it is a path, and runs without a
shell.

When noren starts, and when AeroSpace comes back, noren cannot know what ran before. So every
rule runs `enter` if the focused window matches it, and `leave` if not. Write `leave` commands
that do no harm when nothing was entered.

## Trackpads

The strip follows three-finger swipes on every trackpad, which needs the Input Monitoring
permission. Turn off macOS's own three-finger swipe between full-screen apps (Trackpad settings,
More Gestures), or both follow the same swipe.

macOS stops sending a trackpad's touches after sleep, a screen lock, or the trackpad settings
being applied again. noren attaches the trackpads afresh after the first two by itself. Whatever
applies trackpad settings can have it do so too, by posting a Darwin notification:

```sh
notifyutil -p local.noren.reattach-trackpads
```

## Logs

```sh
log stream --predicate 'subsystem == "local.noren"' --info
```
