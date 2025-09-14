#!/bin/sh
set -e

OUT="index.html"

cat > "$OUT" <<EOF
<!DOCTYPE html>
<html>
  <body>
    <h1>ARTEMIS Binary Artifacts</h1>
    <ul>
EOF

for f in *.so; do
  echo "      <li><a href=\"$f\">$f</a></li>" >> "$OUT"
done

cat >> "$OUT" <<EOF
    </ul>
  </body>
</html>
EOF