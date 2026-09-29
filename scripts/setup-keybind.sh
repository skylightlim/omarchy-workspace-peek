#!/usr/bin/env bash
# Bind the Super key to the widget's reveal shortcut, or remove that binding.
#
#   scripts/setup-keybind.sh            # add the binding (safe to re-run)
#   scripts/setup-keybind.sh --remove   # take it out again
#
# The widget registers a Hyprland global shortcut, quickshell:workspaceNumber,
# and reveals the numbers while it is held. Hyprland only fires a global
# shortcut when a bind points at it, and `omarchy plugin add` has no install
# hook to add one, so without this step holding Super does nothing.
#
# The bind is transparent and ignores modifiers, so SUPER+<key> combos keep
# working. It goes in a marked block, which is how --remove finds it again.
set -euo pipefail

hypr="$HOME/.config/hypr"
begin="# >>> skylightlim.workspaces: Super reveal >>>"
end="# <<< skylightlim.workspaces: Super reveal <<<"

# Omarchy 4 configures Hyprland in Lua; older installs use hyprlang .conf files.
if [[ -f $hypr/bindings.lua ]]; then
  file="$hypr/bindings.lua"
  begin="--${begin#\#}"
  end="--${end#\#}"
  bind='hl.bind("Super_L", hl.dsp.global("quickshell:workspaceNumber"), { ignore_mods = true, transparent = true, description = "Workspace Peek: show numbers" })'
elif [[ -f $hypr/bindings.conf ]]; then
  file="$hypr/bindings.conf"
  bind='bindit = , Super_L, global, quickshell:workspaceNumber'
else
  echo "no ~/.config/hypr/bindings.lua or bindings.conf found; add this bind by hand:" >&2
  echo "  Super_L -> global quickshell:workspaceNumber (flags: ignore_mods, transparent)" >&2
  exit 1
fi

reload() {
  command -v hyprctl >/dev/null || return 0
  hyprctl reload >/dev/null
  local errors
  errors=$(hyprctl configerrors)
  if [[ -n ${errors// /} ]]; then
    echo "Hyprland reported config errors after the change:" >&2
    echo "$errors" >&2
    exit 1
  fi
}

remove_block() {
  local tmp
  tmp=$(mktemp)
  awk -v b="$begin" -v e="$end" '$0 == b {skip = 1} !skip {print} $0 == e {skip = 0}' "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

if [[ ${1:-} == --remove ]]; then
  if ! grep -qxFe "$begin" "$file"; then
    echo "no Workspace Peek binding in $file; nothing to remove"
    exit 0
  fi
  cp "$file" "$file.bak.$(date +%s)"
  remove_block
  reload
  echo "Removed the Super binding from $file"
  exit 0
elif [[ -n ${1:-} ]]; then
  echo "usage: setup-keybind.sh [--remove]" >&2
  exit 1
fi

if grep -qxFe "$begin" "$file"; then
  echo "Super binding already present in $file"
  exit 0
fi
if grep -q 'quickshell:workspaceNumber' "$file"; then
  echo "$file already binds quickshell:workspaceNumber outside this script's block; leaving it alone"
  exit 0
fi

cp "$file" "$file.bak.$(date +%s)"
printf '\n%s\n%s\n%s\n' "$begin" "$bind" "$end" >>"$file"
reload
echo "Added the Super binding to $file — hold Super to peek at workspace numbers"
