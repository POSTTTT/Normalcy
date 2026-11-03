# Normalcy

A keyboard command bar for macOS, inspired by Neovim. Press a hotkey, type a short command, and Normalcy opens apps, switches between them, changes desktops, or snaps the current window into place.

## Requirements

- macOS 14 or later
- Swift 5.9 or later (Xcode or the Command Line Tools)

## Run

```sh
swift run Normalcy
```

Press **Option+Space** to open the command bar. **Enter** runs the command; **Esc** closes the bar.

## Commands

| Command | Action |
|---|---|
| `o Safari` | Open or launch an app |
| `b saf` | Switch to a running app whose name starts with the text |
| `d 2` | Go to desktop 2 (1–9) |
| `d h` / `d l` | Go to the desktop on the left / right |
| `m 2` / `m h` / `m l` | Move the current window to desktop 2 / left / right, and follow it |
| `h` / `l` | Move the window to the left / right half |
| `k` / `j` | Move the window to the top / bottom half |
| `f` | Make the window fill the screen |
| `c` | Center the window |
| `set` | Open Settings |

These are the default triggers. Change them in Settings.

## Settings

Open Settings from the ⌘ icon in the menu bar or with the `set` command. For each command you can:

- **Show / hide** it. A hidden command does nothing when typed.
- **Change its trigger**, for example `o` to `open`. Triggers can't be empty, contain spaces, or repeat another visible command's trigger.

Changes save immediately. **Reset to Defaults** restores the original triggers.

## Setup

**Accessibility permission.** Moving windows and switching desktops need it. Normalcy asks on first launch. When you start it with `swift run`, macOS grants the permission to your terminal app, so turn that app on in System Settings › Privacy & Security › Accessibility.

**Desktop shortcuts.** `d` works by pressing the Mission Control shortcuts for you. Turn them on in System Settings › Keyboard › Keyboard Shortcuts › Mission Control:

- "Move left a space" and "Move right a space" for `d h` / `d l`
- "Switch to Desktop 1", "Switch to Desktop 2", and so on for `d 1`–`d 9`. Each one only appears once that desktop exists.

## Development

All code is in `Sources/Normalcy/`:

- `Normalcy.swift`: hotkey, command bar, command parsing, and actions
- `Settings.swift`: the command list, saved settings, and the Settings window

Check the command parser with:

```sh
swift build && .build/debug/Normalcy --selftest
```

## Limitations

- Window commands use the screen that shows the command bar, so multiple monitors aren't handled well yet.
- `m` works by briefly dragging the window by its title bar while switching desktops. It needs the same desktop shortcuts as `d`, and it fails on windows with no empty title bar space just right of the green button.
- The hotkey is fixed at Option+Space.
- You can rename and hide the built-in commands, but you can't add new ones yet.
