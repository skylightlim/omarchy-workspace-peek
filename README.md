# Workspace Peek

An Omarchy (Quickshell) bar widget that shows one slot per Hyprland workspace. Occupied
slots show the app's icon; hold **Super** to peek at the workspace numbers, with an
animated indicator tracking the active one.

The part other workspace widgets get wrong: **a terminal's window class is `kitty`, never
what is running inside it.** Workspace Peek probes each window's process tree, so yazi,
btop, lazygit and Claude Code show their own icon instead of a wall of identical terminal
icons.

The look and the Super-hold reveal are inspired by
[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) — all credit to
[@end-4](https://github.com/end-4) for the original illogical-impulse design.

## Install

```bash
omarchy plugin add https://github.com/skylightlim/omarchy-workspace-peek.git --enable
```

Then `omarchy restart shell`. Settings live in the bar's widget settings UI — no JSON
editing required.

### Update

```bash
omarchy plugin update skylightlim.workspaces
```

### Remove

```bash
omarchy plugin remove skylightlim.workspaces
omarchy restart shell
```

Removal takes the widget out of your bar and deletes its plugin directory. It writes
nothing outside that directory, so nothing else needs undoing — unless you added
`iconOverrides` entries by hand, which stay in `~/.config/omarchy/shell.json` until you
remove them yourself.

## Do I have to add an icon for every app?

No. Icons resolve in four tiers, and the first three need no configuration at all:

| What you're running | Where its icon comes from | You do |
|---|---|---|
| Any GUI app (Zen, Chrome, Steam…) | its `.desktop` entry + your icon theme | nothing |
| TUI apps with a system icon — `btop`, `nvim`, `vim`, `htop`, `docker` | your icon theme | nothing |
| Apps in the bundled pack — `claude`, `opencode`, `helix`/`hx`, `herdr`, `k9s`, `yazi`, `obsidian`, `spotify_player` | `icons/` in this repo | nothing |
| Anything else | a file you drop in | one command |

For that last row, the filename *is* the configuration — `icons/<process>.png` is matched
against the process name found running inside the terminal:

```bash
./scripts/add-icon.sh lazydocker          # icons/lazydocker.png, from simpleicons.org
./scripts/add-icon.sh kubernetes k9s      # different mark, saved under the process name
```

It is picked up within 30 seconds, no restart needed. Any transparent 128×128 PNG you
drop in yourself works the same way.

`add-icon.sh` renders each mark in its **brand colour** (Claude terracotta, Spotify green,
Kubernetes blue), taken from simple-icons' own metadata. That matters because of how the
widget tints:

| Theme | `monochromeIcons` | What you see |
|---|---|---|
| Dark | on (default) | hue shifted to the bar's foreground — but the mark's **luminance is kept**, so a dark mark stays dark |
| **Light** | on or off | **no tint: the icon's own colour, as-is** |
| Dark | off | the icon's own colour |

So a mark has to clear both ends. On a light theme it is painted exactly as authored, so it
must not be white. On a dark theme the tint is `MultiEffect.colorization`, which recolours
the mark but **preserves its luminance** — so it must not be near-black either. Tinting
cannot rescue a dark mark; it only renders that same dark mark in a different hue.

A mid-to-bright brand colour clears both, which is what `add-icon.sh` produces. Any
transparent 128×128 PNG works if its colour reads on your bar.

One bundled mark is a deliberate exception: `herdr`'s own brand colour really is near-white
(`#eae8ee`), so it is shipped that way and is ideal on a dark bar but will vanish on a light
one. On a light theme, recolour it:

```bash
magick icons/herdr.png -fill '#8B8B8B' -colorize 100 icons/herdr.png
```

### When the process name isn't the icon name

Only if a name can't line up (the process is `nvim` but you want `neovim.png`) do you need
an override. These are the one setting with no UI, so they go in
`~/.config/omarchy/shell.json` — note the keys sit **flat** next to `"id"`, not nested
inside a `"settings"` block:

```bash
jq '(.bar.layout.left[] | select(.id=="skylightlim.workspaces") | .iconOverrides)
      += [{"process":"nvim","icon":"icons/neovim.png"}]' \
   ~/.config/omarchy/shell.json > /tmp/s.json && mv /tmp/s.json ~/.config/omarchy/shell.json
```

### Finding a process name

It is not always the command you type — wrappers can show up as `node` or `python3`. List
what is actually running under each window:

```bash
hyprctl clients -j | jq -r '.[] | "\(.pid)\t\(.class)"' | while IFS=$'\t' read -r pid class; do
  echo "  $class ($pid): $(pstree -p "$pid" | grep -oE '[a-zA-Z0-9_][a-zA-Z0-9_-]*\([0-9]+\)' \
    | sed 's/([0-9]*)//' | sort -u | grep -vxE "$class|bash|zsh|fish|sh|kitten|pstree|grep|sed|sort|paste|jq" | paste -sd' ')"
done
```

Shells and multiplexers are deliberately not detected: the probe takes the first match in
the process tree, so matching `tmux` would shadow whatever is running inside it.

## Settings

| Setting | Default | What it does |
|---|---|---|
| Show app icons | on | Off gives plain numbers everywhere |
| Tint icons to the bar colour | on | Ignored on light themes and transparent bars |
| Icon size multiplier | `1.0` | Relative to the bar's icon size |
| Super-hold before numbers appear | `100` ms | `0` reveals instantly |

## How detection works

A TUI app is a child process of the terminal, so each window's owner pid is scanned with
`pstree` roughly every 3 seconds, through a single serialized process. Results are cached
per pid and attributed by the pid captured at launch rather than by timing. When rescanning,
entries for dead pids are pruned and everything else is kept until a fresh probe lands —
blanking the cache first makes icons flicker terminal↔app once per cycle.

Icons follow app start and stop: quitting btop reverts the slot to the terminal's icon
within ~3 s while the terminal stays open.

## Troubleshooting

### One app's slot is blank while terminal apps still work

Almost always your **icon theme is set to a theme that isn't installed** — not a bug in the
widget. A GUI app's icon comes from the `Icon=` name in its `.desktop` entry, and that name
only resolves through a theme, so when the theme is missing Qt finds nothing and the slot
paints empty.

Terminal slots keep working and disguise the problem. `kitty` and `nvim` ship icons in
`/usr/share/pixmaps`, which Qt still searches when it has no usable theme, and the bundled
pack in `icons/` is loaded straight from disk. So `kitty` renders normally while `zen`,
`btop`, `foot` and `chromium` all go blank together.

Check whether the configured theme actually exists:

```bash
gsettings get org.gnome.desktop.interface icon-theme    # e.g. 'Yaru-gray'
ls -d /usr/share/icons/*/ ~/.local/share/icons/*/       # is that name in the list?
```

If it isn't, point it at one that is:

```bash
gsettings set org.gnome.desktop.interface icon-theme 'Yaru'
omarchy restart shell
```

Under `QT_QPA_PLATFORMTHEME=gtk3` (the Omarchy default) Qt reads its icon theme from that
GTK setting, and it does not fall back to `hicolor` when the name is wrong. A stale value
left behind by a theme switch therefore breaks themed icons for every Qt app, not just this
widget.

## Requirements

Omarchy 4.x (Quickshell shell), `pstree` (`psmisc`), `jq`. `scripts/add-icon.sh`
additionally needs `rsvg-convert` (`librsvg`) and `magick` (`imagemagick`).

## Credits

The behaviour and look are modelled on
[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)'s illogical-impulse
workspaces — thanks to [@end-4](https://github.com/end-4), who designed the interaction
this widget reimplements for Omarchy.

Built on Omarchy's own `omarchy.workspaces` bar widget (MIT). Bundled marks from
[simple-icons](https://simpleicons.org) (CC0). MIT licensed — see `LICENSE`.
