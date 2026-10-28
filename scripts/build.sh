#!/usr/bin/env bash
# Builds dist/fd-vale.zip: one top-level fd-vale/ folder holding .vale.ini and styles/,
# the layout Vale expects of a complete package.
#
# The zip is reproducible: entries are sorted, every mtime is fixed, permissions are
# normalised and zip -X drops uid/gid and extended timestamps. Building the same commit
# twice, or on another machine, gives the same SHA-256. That lets anyone check a release
# asset against the tag it claims to come from.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=fd-vale
DIST="$ROOT/dist"
# 2026-01-01 00:00 UTC. Any fixed value works; this one is after DOS-time's 1980 floor.
STAMP=202601010000

command -v zip >/dev/null || { echo "build: zip is required" >&2; exit 2; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$ROOT/$NAME" "$STAGE/$NAME"
find "$STAGE/$NAME" -type d -exec chmod 755 {} +
find "$STAGE/$NAME" -type f -exec chmod 644 {} +
find "$STAGE/$NAME" -name .DS_Store -delete
find "$STAGE/$NAME" -exec env TZ=UTC touch -h -t "$STAMP" {} +

mkdir -p "$DIST"
rm -f "$DIST/$NAME.zip"
# The list includes directories, so the zip holds a directory entry for each one, as the
# upstream zips do. LC_ALL=C makes the sort order byte-wise on every platform.
(cd "$STAGE" && find "$NAME" -print | LC_ALL=C sort | TZ=UTC zip -q -X -@ "$DIST/$NAME.zip")

if command -v sha256sum >/dev/null; then sum=$(sha256sum "$DIST/$NAME.zip" | cut -d' ' -f1); else sum=$(shasum -a 256 "$DIST/$NAME.zip" | cut -d' ' -f1); fi
echo "$sum  $NAME.zip" > "$DIST/$NAME.zip.sha256"
echo "build: dist/$NAME.zip $(wc -c < "$DIST/$NAME.zip" | tr -d ' ') bytes, sha256 $sum"
