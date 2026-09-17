#!/usr/bin/env bash
# Render an app mark into icons/ at the size and colour this widget expects.
#
#   scripts/add-icon.sh <simple-icons-slug> [process-name] [#hex]
#   scripts/add-icon.sh claude              # -> icons/claude.png, in Claude's brand colour
#   scripts/add-icon.sh kubernetes k9s      # -> icons/k9s.png
#   scripts/add-icon.sh foo bar '#3B82F6'   # -> icons/bar.png, explicit colour
#
# The file name is what matters: the widget matches icons/<process>.png against
# the process it finds running inside a terminal. No config file to edit.
#
# Marks are rendered in their BRAND colour, never white. On a light theme the
# widget deliberately skips tinting so icons keep their own colours — a white
# mark is invisible there. A brand colour reads on light and dark alike, which
# is why simple-icons publishes one per icon.
set -euo pipefail

slug=${1:?usage: add-icon.sh <simple-icons-slug> [process-name] [#hex]}
name=${2:-$slug}
colour=${3:-}
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/icons"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

url="https://cdn.jsdelivr.net/npm/simple-icons@latest/icons/${slug}.svg"
if ! curl -sfL --max-time 20 "$url" -o "$tmp/m.svg"; then
  echo "no simple-icons mark named '$slug' (check https://simpleicons.org)" >&2
  exit 1
fi

if [[ -z $colour ]]; then
  # Brand colours live in the package's metadata, keyed by title rather than by
  # slug, so the slug is recomputed from each title to match.
  data="${TMPDIR:-/tmp}/simple-icons-data.json"
  [[ -s $data ]] || curl -sfL --max-time 30 \
    "https://cdn.jsdelivr.net/npm/simple-icons@latest/_data/simple-icons.json" -o "$data"
  colour=$(python3 - "$data" "$slug" <<'PY'
import json, re, sys
data, want = sys.argv[1], sys.argv[2]
def slugify(t):
    t = t.lower()
    for a, b in (("+","plus"),(".","dot"),("&","and"),("đ","d"),("ħ","h"),
                 ("ı","i"),("ĸ","k"),("ŀ","l"),("ł","l"),("ß","ss"),("ŧ","t")):
        t = t.replace(a, b)
    return re.sub(r"[^a-z0-9]", "", t)
try:
    print(next("#" + e["hex"] for e in json.load(open(data)) if slugify(e["title"]) == want))
except (StopIteration, OSError, ValueError):
    print("")
PY
)
  if [[ -z $colour ]]; then
    # A handful of marks ship an SVG with no metadata entry. Mid-grey is the
    # only safe guess: it reads on a light bar and on a dark one.
    colour="#8B8B8B"
    echo "note: simple-icons lists no brand colour for '$slug'; using $colour — pass one to override" >&2
  fi
fi

sed "s|<path |<path fill=\"$colour\" |" "$tmp/m.svg" > "$tmp/c.svg"
rsvg-convert -w 118 -h 118 -b none "$tmp/c.svg" -o "$tmp/m.png"
mkdir -p "$dir"
magick "$tmp/m.png" -background none -gravity center -extent 128x128 "$dir/$name.png"

# %[channels] reads like "srgba 4.0"; only the colourspace token carries the
# alpha suffix, and "srgb" without it must still fail the check.
channels=$(magick identify -format '%[channels]' "$dir/$name.png" | awk '{print $1}')
case "$channels" in
  *a) echo "icons/$name.png  $colour  ($channels, transparent)" ;;
  *)  echo "icons/$name.png has no alpha channel ($channels)" >&2; exit 1 ;;
esac
