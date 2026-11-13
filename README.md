<div align="center">

<img src="Sources/Normalcy/Resources/AppIcon.png" width="128" alt="Normalcy icon">

# Normalcy

**Press a key. Type `h`. The window snaps left.**

A keyboard command bar for macOS, inspired by Neovim's normal mode:
short commands for apps, desktops, tabs and windows, without touching the mouse.

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Keys](https://img.shields.io/badge/keys-h%20j%20k%20l-4C6EF5)](#using-it)

**[Commands](docs/commands.md)** · [Install](#install) · [Using it](#using-it) · [Settings](#settings) · [Scripting](#scripting)

</div>

```
   ⌥ Space ──▶ type  b saf  ──▶ Return ──▶ Safari is in front
   ⌥ Space ──▶ type  re ll  ──▶ Return ──▶ window two steps wider, the one beside it narrower
```

- **Vim-style triggers.** `h` `j` `k` `l` for halves, `h3` `c3` `l3` for thirds,
  `hk` for the top-left quarter, `d 2` for desktop 2. Arrow keys work too.
- **Everything is yours to rename.** Every trigger, and the direction keys
  themselves: pick W A S D or I J K L and the thirds and quarters follow.
- **See before you commit.** A translucent box shows where the window will go,
  `d` and `m` show your desktops as thumbnails, and `b` previews the app's window.
- **Keep going.** Shift+Return runs a command and keeps the bar open for the next one.
- **Stays out of the way.** A menu bar app with no Dock icon. The bar appears on
  the hotkey and disappears when you're done.

## Requirements

- macOS 14 or later, Apple silicon
- To run from source: Swift 5.9 or later (Xcode or the Command Line Tools)

## Install

1. Download `Normalcy-x.y.z.zip` from the [latest release](https://github.com/POSTTTT/Normalcy/releases/latest).
2. Unzip it and move **Normalcy.app** to Applications.
3. Open it. Normalcy isn't notarized by Apple, so the first time macOS says
   *"Normalcy" Not Opened*. Click **Done** (not Move to Trash), then let it open either way:
   - **In System Settings:** Privacy & Security, scroll down to *"Normalcy" was blocked*,
     click **Open Anyway**, enter your password, then open Normalcy again and choose **Open**.
   - **Or in Terminal:**
     ```sh
     xattr -dr com.apple.quarantine /Applications/Normalcy.app
     ```
     then open Normalcy as usual.

After that, Normalcy updates itself: Settings › General › Updates shows new versions, and
nothing installs until you click **Install**.

Or run it from source:

```sh
git clone https://github.com/POSTTTT/Normalcy.git
cd Normalcy
swift run Normalcy
```

Normalcy lives in the menu bar as a ⌘ icon. On first launch macOS asks for:

- **Accessibility**, to move windows, move tabs and switch desktops. When you
  start Normalcy with `swift run`, macOS grants it to your terminal app, so turn
  that app on in System Settings › Privacy & Security › Accessibility.
- **Screen Recording** (optional), for desktop thumbnails and app previews.
  Without it, every desktop shows your wallpaper and `b` shows app icons.

## Using it

Press **Option+Space**, type a command, press **Return**. The bar lists every
command with its trigger, and Settings › Commands is where you rename them.
[`docs/commands.md`](docs/commands.md) describes each command and what to type after it.

- **Shift+Return** runs a command and keeps the bar open for the next one.
- Return on a highlighted command that needs more (like `o`) fills in its
  trigger so you can keep typing.
- The list matches by trigger or by name: `half` finds all four half-screen
  commands.
- `b`'s app list shows what Cmd+Tab shows: apps with a window on this desktop,
  plus Finder, most recent first.

## Settings

Open Settings from the ⌘ menu bar icon or with `set`. Changes save immediately.

| Tab | What's there |
| --- | --- |
| **General** | The hotkey. The bar's style: *Command bar* (a text field with the list under it) or *Minimal* (what you type as key caps, at the top, center or bottom of the screen) or *Dynamic Island* (what you type in a black pill that grows from the top of the screen, around the notch). Whether to show the command list, and its layout |
| **Commands** | App, desktop, tab, scroll and pointer commands, and the pointer step |
| **Windows** | The direction keys (H J K L, W A S D, I J K L or your own), the window commands, and how far `+` `-` and `re` resize |
| **App Shortcuts** | Shortcuts you know in an app, each given a trigger. Add an app, then for each shortcut type a trigger (say `cp`), click **Record** and press the keys (say Ctrl+C). The trigger shows in the bar only while that app is in front |
| **Keys** | The fixed keys in the command bar, for reference. Whether special keys show as symbols (⌘ ⌥ ↩) or text (Command Option Return) |

Each command shows its trigger as a key cap: click it to change it, or switch the
command off to hide it. **Reset These** restores a page's original triggers.

### Desktop shortcuts

`d` and `m` press the Mission Control shortcuts for you, in System Settings ›
Keyboard › Keyboard Shortcuts › Mission Control. "Move left a space" and "Move
right a space" are on by default and are all Normalcy needs. Turn on "Switch to
Desktop 1", "Switch to Desktop 2" and so on to make `d 1`–`d 9` jump straight
there instead of stepping through the desktops in between.

## Scripting

Run a command in the running Normalcy, against the front app, as if you'd typed it:

```sh
.build/debug/Normalcy --run "t h"
```

Any program running under your account can do this.

## Development

```sh
swift build                              # build
.build/debug/Normalcy --selftest         # command parser and command bar checks
.build/debug/Normalcy --desktops         # print the desktops Normalcy can see
swift scripts/make-icon.swift            # redraw Sources/Normalcy/Resources/AppIcon.png
scripts/build-app.sh                     # dist/Normalcy.app and a .zip for a release
```

`Normalcy.app` is signed with a self-made "Normalcy Signing" certificate, so macOS keeps its
Accessibility permission across builds and updates. Without that certificate in your keychain,
`build-app.sh` signs ad hoc instead, and macOS asks for Accessibility again after each build.
It isn't notarized either way: see [Install](#install) for opening a downloaded copy.

### Layout

| File | Role |
| --- | --- |
| `Normalcy.swift` | Hotkey, command parsing, and the actions |
| `Palette.swift` | The command bar, list, key caps, desktop thumbnails and window preview |
| `Desktops.swift` | Reading desktops, desktop snapshots and the wallpaper |
| `Settings.swift` | The commands, saved settings, and the Settings window |

## Limitations

- Window commands and the preview use the screen that shows the command bar, and
  desktop thumbnails only cover the first display, so multiple monitors aren't
  handled well yet.
- Reading desktops uses a private macOS function, since there's no public one. A
  future macOS update could break it.
- `m` works by briefly dragging the window by its title bar while switching
  desktops. It fails on windows with no empty title bar space just right of the
  green button.
- `t` clicks the app's "Move Tab to New Window" menu item, so it only works in apps
  that have one (Safari, Finder, Terminal, Ghostty and other apps using standard
  macOS tabs) and only when macOS is set to English.
- `tn` and `tp` press Cmd+Shift+] and Cmd+Shift+[, so they only work in apps
  that use those for next and previous tab. Likewise `nt` and `ct` press Cmd+T
  and Cmd+W. And `bk` and `fw` press Cmd+[
  and Cmd+], standing in for a two-finger swipe, which apps can't be sent.
- You can rename and hide the built-in commands, but you can't add new ones yet.
