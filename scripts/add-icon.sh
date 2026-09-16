#!/usr/bin/env bash
# Render a monochrome app mark into icons/ at the size this widget expects.
#
#   scripts/add-icon.sh <simple-icons-slug> [process-name]
#   scripts/add-icon.sh claude              # -> icons/claude.png
#   scripts/add-icon.sh kubernetes k9s      # -> icons/k9s.png
#
# The file name is what matters: the widget matches icons/<process>.png against
# the process it finds running inside a terminal. No config file to edit.
set -euo pipefail

slug=${1:?usage: add-icon.sh <simple-icons-slug> [process-name]}
name=${2:-$slug}
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/icons"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

url="https://cdn.jsdelivr.net/npm/simple-icons@latest/icons/${slug}.svg"
if ! curl -sfL --max-time 20 "$url" -o "$tmp/m.svg"; then
  echo "no simple-icons mark named '$slug' (check https://simpleicons.org)" >&2
  exit 1
fi

# White fill: with monochromeIcons on, the bar tints it and only alpha matters;
# with tinting off it still reads on a dark bar.
sed 's|<path |<path fill="#fff" |' "$tmp/m.svg" > "$tmp/w.svg"
rsvg-convert -w 118 -h 118 -b none "$tmp/w.svg" -o "$tmp/m.png"
mkdir -p "$dir"
magick "$tmp/m.png" -background none -gravity center -extent 128x128 "$dir/$name.png"

# %[channels] reads like "graya 2.0"; only the colourspace token carries the
# alpha suffix, and "gray" without it must still fail the check.
channels=$(magick identify -format '%[channels]' "$dir/$name.png" | awk '{print $1}')
case "$channels" in
  *a) echo "icons/$name.png  ($channels, transparent)" ;;
  *)  echo "icons/$name.png has no alpha channel ($channels)" >&2; exit 1 ;;
esac
