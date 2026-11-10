# Commands

Every command, what it does and what you type after it.

Press **Option+Space**, type the trigger, add the input if there is one, and press
**Return**. **Shift+Return** runs it and keeps the bar open for the next command.

Triggers below are the defaults. Rename any of them in Settings, and pick other
direction keys in Settings › Windows (the window triggers follow). `h` `j` `k` `l`
below stand for your left, down, up and right keys. The arrow keys always work as
well.

After a command that takes an input, a direction key adds the space for you: `d`
then `h` gives `d h`.

## Apps

| Trigger | Command | Input | What it does |
| --- | --- | --- | --- |
| `o` | Open App | an app name | Opens the app. The list shows installed apps as you type: `o saf` |
| `b` | Switch to App | an app name, or a direction | Brings a running app to the front, matching the start of its name: `b saf`. With a direction, switches to the nearest window that way: `b l` |

## Desktops and tabs

| Trigger | Command | Input | What it does |
| --- | --- | --- | --- |
| `d` | Go to Desktop | `1`–`9`, `h` or `l` | Goes to that desktop, or the one to the left or right: `d 2`, `d l` |
| `m` | Move Window to Desktop | `1`–`9`, `h` or `l` | Takes the front window to that desktop: `m 3`, `m h` |
| `t` | Move Tab to New Window | optional: a window position | Moves the current tab out into its own window. Add a position to place it: `t h` (left half), `t l3`, `t hk`, `t f` |
| `tn` | Next Tab | none | Shows the next tab in the front app (presses Cmd+Shift+]) |
| `tp` | Previous Tab | none | Shows the previous tab in the front app (presses Cmd+Shift+[) |
| `ts` | Switch Tabs | `h` `l` | Then `l` / → shows the next tab and `h` / ← the previous one, as you press them. Return or Esc closes the bar |
| `bk` | Back | none | Goes back, like a two-finger swipe right (presses Cmd+[) |
| `fw` | Forward | none | Goes forward, like a two-finger swipe left (presses Cmd+]) |

## Window position

These take no input.

| Trigger | Command | What it does |
| --- | --- | --- |
| `h` `l` `k` `j` | Left, Right, Top, Bottom Half | Fills that half of the screen |
| `h3` `c3` `l3` | Left, Center, Right Third | Fills that third |
| `hk` `lk` `hj` `lj` | Top Left, Top Right, Bottom Left, Bottom Right Quarter | Fills that quarter. Either order works: `kh` = `hk` |
| `f` | Fill Screen | Fills the screen |
| `c` | Center | Puts the window in the middle, 70% wide and 80% tall |

## Window size

| Trigger | Command | Input | What it does |
| --- | --- | --- | --- |
| `+` | Make Bigger | none | Grows the window around its center, 10% by default |
| `-` | Make Smaller | none | Shrinks it the same way |
| `re` | Resize by Direction | one or more directions | Moves the window's free edge that way, one step per key: `re ll`. The free edge is the right or bottom edge, or the left or top edge of a window against the right or bottom of the screen. A full-screen window gives up the edge on the side you type away from. The window beside it makes room |

Step sizes for `+` `-` and `re` are in Settings › Windows.

## Scroll

| Trigger | Command | Input | What it does |
| --- | --- | --- | --- |
| `s` | Scroll | directions, as you press them | Scrolls the front window as each key is pressed, no Return needed. Hold a key to keep going. **Esc** stops |

## Pointer

Both modes move the pointer as you press keys, with no Return needed. Uppercase
`H` `J` `K` `L` nudge it 10 points. Then:

- **Return** clicks where the pointer is.
- `r` then **Return** right-clicks.
- `2` then **Return** double-clicks.
- **Shift+Return** clicks and keeps the mode ready for the next move.

| Trigger | Command | Input | What it does |
| --- | --- | --- | --- |
| `mo` | Pointer by Halves | directions | Each key keeps that half of what's left of the screen and puts the pointer in its middle, so a few keys reach any spot. A box shows the area left. **Space** starts over with the pointer centered |
| `ms` | Pointer by Steps | directions | Each key moves the pointer one step, 50 points by default |
| `cl` | Click by Label | a label | Puts a letter label on every button, link, field and row in the front window. Type a label and it clicks there, no Return needed: `cl a`, `cl sd`. `r` first right-clicks, `2` first double-clicks: `cl ra` |

The step size, whether `mo` shows its box, and the pointer's own direction keys (say W A S D, while windows keep H J K L) are in Settings › Commands › Pointer.

## App shortcuts

Your own commands, made in Settings › App Shortcuts. Each one presses a shortcut in one
app, and is in the bar only while that app is in front. For example, in Ghostty, `cp`
presses Ctrl+C to stop the running process. If one matches a built-in trigger, it wins
in that app.

## Other

| Trigger | Command | What it does |
| --- | --- | --- |
| `set` | Settings | Opens Settings |

## Keys in the bar

| Key | What it does |
| --- | --- |
| **Return** | Runs the command, or fills in the highlighted one's trigger when it needs input |
| **Shift+Return** | Runs it and keeps the bar open. In `s`, `re` or `cl` with nothing left to run, it ends that command instead, leaving the bar empty: no need to reach for Esc |
| **Tab** / **Shift+Tab**, **Ctrl+N** / **Ctrl+P** | Move the highlight in the list |
| **Esc** | Clears what's typed, then closes the bar |
| **Ctrl+W** | Deletes the last word |
| **Ctrl+U** | Deletes everything typed |
