# Normalcy

A keyboard command bar for macOS, inspired by Neovim. Press a hotkey, type a short command, and Normalcy opens apps, switches between them, changes desktops, moves tabs out into their own windows, or snaps the current window into place.

## Requirements

- macOS 14 or later
- Swift 5.9 or later (Xcode or the Command Line Tools)

## Run

```sh
swift run Normalcy
```

Press **Option+Space** (change it in Settings > General) to open the command bar. **Enter** runs the command; **Shift+Enter** runs it and keeps the bar open for the next one; **Esc** clears what you typed, or closes the bar when nothing is typed. **Ctrl+U** clears everything and **Ctrl+W** the last word.

## Commands

| Command | Action |
|---|---|
| `o Safari` | Open or launch an app |
| `b saf` | Switch to a running app whose name starts with the text. The list shows what Cmd+Tab shows: apps with a window on this desktop, plus Finder. `b h` / `b l` / `b k` / `b j` switch to the nearest window on the left / right / above / below |
| `d 2` | Go to desktop 2 (1–9) |
| `d h` / `d l` | Go to the desktop on the left / right |
| `m 2` / `m h` / `m l` | Move the current window to desktop 2 / left / right, and follow it |
| `t` | Move the current tab into its own window |
| `t h` | Move the current tab into its own window and put it on the left half (works with any window position) |
| `h` / `l` | Move the window to the left / right half |
| `k` / `j` | Move the window to the top / bottom half |
| `f` | Make the window fill the screen |
| `c` | Center the window |
| `+` / `-` | Make the window 10% bigger / smaller (step set in Settings > General), staying centered (Shift+Enter to repeat) |
| `s` then `j` / `k` / `h` / `l` | Scroll the window down / up / left / right a quarter window per key, as you press them (no Enter); Esc to stop |
| `re l` / `re h` / `re j` / `re k` | Make the window wider / narrower / taller / shorter by 5% of the screen (step set in Settings > General); repeat the key for more steps (`re ll`), or Shift+Enter to keep `re ` ready. A window right next to it gives up or takes the space (turn off in Settings > General) |
| `h3` / `c3` / `l3` | Move the window to the left / center / right third |
| `hk` / `lk` | Move the window to the top-left / top-right quarter |
| `hj` / `lj` | Move the window to the bottom-left / bottom-right quarter |
| `set` | Open Settings |

These are the default triggers. Change them in Settings.

### Keys in the command bar

- **Arrow keys** work like `h` `j` `k` `l`: ← is left, ↓ bottom, ↑ top, → right. Two arrows make a corner quarter, in either order: ← ↑ is top-left. An arrow also stands in for its letter in other triggers, so ← 3 is the left third (`h3`). After `t`, `d` or `m` they add the space for you, so `t` then ← becomes `t ←`. They keep working even if you rename those triggers.
- **Tab** / **Shift+Tab** or **Ctrl+N** / **Ctrl+P** move the highlight in the command list.
- **Enter** on a highlighted command that needs more (like `o`) fills in its trigger so you can keep typing; other commands run straight away.

### What the bar shows

- **Command list:** matches what you type, by trigger or by name (`half` finds all four half-screen commands).
- **Window preview:** while a position command is typed or highlighted, a translucent box shows where the window will go.
- **Desktop thumbnails:** `d` and `m` show your desktops, with the current one outlined and the target highlighted. Click a thumbnail to go or move there. Each desktop shows a snapshot from the last time you visited it, or your wallpaper until then.

## Settings

Open Settings from the ⌘ icon in the menu bar or with the `set` command.

**General**

- **Style:** *Command bar* shows a text field with the list under it. *Minimal* hides the text field and shows what you type as key caps.
- **Show command list:** turn off to hide the list in either style.
- **Position** (Minimal only): show the key caps at the top, center or bottom of the screen.
- **Show spaces as ␣** (Minimal only): give each space its own key cap.

**Commands** and **Windows**

- Each command shows its trigger as a key cap. **Click it to change it**, for example `o` to `open`. Triggers can't be empty, contain spaces, or repeat another visible command's trigger.
- **Switch a command off** to hide it. A hidden command does nothing when typed.
- **Windows** also sets the direction keys (H J K L, W A S D, I J K L or your own) and the resize steps.

**Keys** lists the fixed keys in the command bar.

Changes save immediately. **Reset These** restores the original triggers on that page.

## Setup

**Accessibility permission.** Moving windows, moving tabs and switching desktops need it. Normalcy asks on first launch. When you start it with `swift run`, macOS grants the permission to your terminal app, so turn that app on in System Settings › Privacy & Security › Accessibility.

**Screen Recording permission** (optional). Desktop thumbnails need it to take snapshots. Without it, every desktop shows your wallpaper. Turn your terminal app on in System Settings › Privacy & Security › Screen Recording.

**Desktop shortcuts** (optional). `d` and `m` press the Mission Control shortcuts for you, in System Settings › Keyboard › Keyboard Shortcuts › Mission Control:

- "Move left a space" and "Move right a space" are on by default and are all Normalcy needs.
- Turning on "Switch to Desktop 1", "Switch to Desktop 2", and so on makes `d 1`–`d 9` jump straight there. Without them, Normalcy steps through the desktops in between.

## Scripting

Run a command in the running Normalcy, against the front app, as if you'd typed it:

```sh
.build/debug/Normalcy --run "t h"
```

Any program running under your account can do this.

## Development

All code is in `Sources/Normalcy/`:

- `Normalcy.swift`: hotkey, command parsing, and the actions
- `Palette.swift`: the command bar, list, key caps, desktop thumbnails and window preview
- `Desktops.swift`: reading desktops, desktop snapshots and the wallpaper
- `Settings.swift`: the command list, saved settings, and the Settings window

Check the command parser and command bar logic with:

```sh
swift build && .build/debug/Normalcy --selftest
```

`.build/debug/Normalcy --desktops` prints the desktops Normalcy can see.

## Limitations

- Window commands and the preview use the screen that shows the command bar, and desktop thumbnails only cover the first display, so multiple monitors aren't handled well yet.
- Reading desktops uses a private macOS function, since there's no public one. A future macOS update could break it.
- `m` works by briefly dragging the window by its title bar while switching desktops. It fails on windows with no empty title bar space just right of the green button.
- `t` clicks the app's "Move Tab to New Window" menu item, so it only works in apps that have one (Safari, Finder, Terminal, Ghostty and other apps using standard macOS tabs) and only when macOS is set to English.
- You can rename and hide the built-in commands, but you can't add new ones yet.
