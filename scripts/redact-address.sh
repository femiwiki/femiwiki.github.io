#!/usr/bin/env bash
set -euo pipefail
in=$1
out=$2
dpi=150
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pdftotext -bbox-layout -f 1 -l 1 "$in" "$tmp/bbox.html"
read -r lines x1 x2 top bottom < <(awk -v dpi="$dpi" '
  function attr(name,   s) { match($0, name "=\"[^\"]+\""); s = substr($0, RSTART + length(name) + 2, RLENGTH - length(name) - 3); return s + 0 }
  /<line / { lx = attr("xMin"); ly1 = attr("yMin"); ly2 = attr("yMax"); text = ""; wx1 = 1e9; wx2 = 0 }
  /<word / { match($0, />[^<]+</); text = text " " substr($0, RSTART + 1, RLENGTH - 2)
             if (attr("xMin") < wx1) wx1 = attr("xMin"); if (attr("xMax") > wx2) wx2 = attr("xMax") }
  /<\/line>/ { if (text ~ /Bill to Address/) { top = ly1; col = lx; next }
               if (text ~ /ATTN:/) { on = 1; if (wx1 < X1 || !X1) X1 = wx1; if (wx2 > X2) X2 = wx2; next }
               if (text ~ /TOTAL AMOUNT/) { on = 0 }
               if (on && lx - col < 2 && col - lx < 2) { n++; bottom = ly2; if (wx1 < X1 || !X1) X1 = wx1; if (wx2 > X2) X2 = wx2 } }
  END { if (!n) exit 1; s = dpi / 72; printf "%d %d %d %d %d\n", n, (X1 - 4) * s, (X2 + 4) * s, (top - 2) * s, (bottom + 2) * s }' "$tmp/bbox.html")

pdftoppm -r "$dpi" -f 1 -l 1 -png "$in" "$tmp/p"
mapfile -t runs < <(convert "$tmp"/p-*.png -crop "$((x2 - x1))x$((bottom - top))+$x1+$top" +repage \
  -colorspace gray -threshold 70% -negate -scale 1x! -depth 8 txt:- \
  | awk -F'[,: ()]+' -v top="$top" 'NR > 1 && $3 + 0 > 0 { print $2 + top }' \
  | awk 'NR == 1 { s = $1; p = $1; next } $1 != p + 1 { print s, p; s = $1 } { p = $1 } END { print s, p }')
[ "${#runs[@]}" -eq $((lines + 2)) ] || { echo "expected ${lines} address lines under a label and ATTN, found ${#runs[@]} rows of ink" >&2; exit 1; }
y1=$(( ${runs[1]% *} - 3 ))
y2=$(( ${runs[-1]#* } + 3 ))

convert "$tmp"/p-*.png -fill white -draw "rectangle $x1,$y1 $x2,$y2" -units PixelsPerInch -density "$dpi" "$tmp/p1.pdf"
if [ "$(pdfinfo "$in" | awk '/^Pages:/ { print $2 }')" -gt 1 ]; then
  gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -dFirstPage=2 -o "$tmp/rest.pdf" "$in"
  gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -o "$out" "$tmp/p1.pdf" "$tmp/rest.pdf"
else
  cp "$tmp/p1.pdf" "$out"
fi
