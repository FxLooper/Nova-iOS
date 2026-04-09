#!/bin/bash
# Generate all PNG icon sizes from icon.svg
# Requires: rsvg-convert (brew install librsvg) OR sips (built-in macOS)
#
# Usage: cd to this directory, then run: bash generate-icons.sh

DIR="$(cd "$(dirname "$0")" && pwd)"
SVG="$DIR/icon.svg"

SIZES=(1024 180 120 167 152 76)

# Try rsvg-convert first (best SVG rendering quality)
if command -v rsvg-convert &> /dev/null; then
  echo "Using rsvg-convert..."
  for SIZE in "${SIZES[@]}"; do
    rsvg-convert -w "$SIZE" -h "$SIZE" "$SVG" -o "$DIR/icon-${SIZE}.png"
    echo "  Created icon-${SIZE}.png"
  done

# Try Python + cairosvg
elif python3 -c "import cairosvg" 2>/dev/null; then
  echo "Using cairosvg..."
  for SIZE in "${SIZES[@]}"; do
    python3 -c "
import cairosvg
cairosvg.svg2png(url='$SVG', write_to='$DIR/icon-${SIZE}.png', output_width=$SIZE, output_height=$SIZE)
"
    echo "  Created icon-${SIZE}.png"
  done

# Try Inkscape
elif command -v inkscape &> /dev/null; then
  echo "Using Inkscape..."
  for SIZE in "${SIZES[@]}"; do
    inkscape "$SVG" --export-type=png --export-filename="$DIR/icon-${SIZE}.png" -w "$SIZE" -h "$SIZE" 2>/dev/null
    echo "  Created icon-${SIZE}.png"
  done

else
  echo "ERROR: No SVG-to-PNG converter found."
  echo "Install one of these:"
  echo "  brew install librsvg     # recommended"
  echo "  pip3 install cairosvg    # Python option"
  echo "  brew install inkscape    # heavyweight option"
  exit 1
fi

echo ""
echo "Done! All icons generated in: $DIR"
echo ""
echo "Files:"
ls -la "$DIR"/icon-*.png 2>/dev/null
