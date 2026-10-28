#!/usr/bin/env bash
# Rebuilds the third-party styles under fd-vale/styles from upstream.json.
#
#   scripts/fetch-upstream.sh           replace the committed copies with fresh downloads
#   scripts/fetch-upstream.sh --check   download into a temp dir and fail if the committed copies differ
#
# Every download is checked against the SHA-256 recorded in upstream.json, and a mismatch
# stops the script before anything is written. `vale sync` checks nothing, so this check and
# code review of the resulting diff are the only integrity controls on third-party rules.
#
# Only the paths named in each style's `extract` and `files` entries are touched. FirstDollar
# and config/vocabularies are ours and never written here.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MANIFEST="$ROOT/upstream.json"
COMMITTED="$ROOT/fd-vale/styles"

mode=write
case "${1:-}" in
  --check) mode=check ;;
  "") ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

for tool in curl jq unzip; do
  command -v "$tool" >/dev/null || { echo "fetch-upstream: $tool is required" >&2; exit 2; }
done

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# Everything lands in OUT first, so a failed hash leaves the committed tree untouched.
OUT="$WORK/styles"
mkdir -p "$OUT"

fetch() { # url expected-sha256 destination
  curl -sSfL --retry 3 -o "$3" "$1"
  local got
  got=$(sha256 "$3")
  if [ "$got" != "$2" ]; then
    echo "fetch-upstream: SHA-256 mismatch for $1" >&2
    echo "  expected $2" >&2
    echo "  got      $got" >&2
    exit 1
  fi
}

count=$(jq '.styles | length' "$MANIFEST")
for ((i = 0; i < count; i++)); do
  style=$(jq -c ".styles[$i]" "$MANIFEST")
  name=$(jq -r .name <<<"$style")
  echo "fetch-upstream: $name $(jq -r '.tag // .commit[0:12]' <<<"$style")"

  if jq -e .archive >/dev/null <<<"$style"; then
    zip="$WORK/$name.zip"
    fetch "$(jq -r .archive.url <<<"$style")" "$(jq -r .archive.sha256 <<<"$style")" "$zip"
    unzip -q "$zip" -d "$WORK/$name.unzipped"
    while IFS=$'\t' read -r from to; do
      mkdir -p "$(dirname "$OUT/$to")"
      cp -R "$WORK/$name.unzipped/$from" "$OUT/$to"
    done < <(jq -r '.extract[] | [.from, .to] | @tsv' <<<"$style")
  fi

  while IFS=$'\t' read -r url sum to; do
    mkdir -p "$(dirname "$OUT/$to")"
    fetch "$url" "$sum" "$OUT/$to"
  done < <(jq -r '.files[] | [.url, .sha256, .to] | @tsv' <<<"$style")
done

# The top-level paths this manifest owns: whole style directories, plus single files outside them.
owned=$(jq -r '.styles[] | ((.extract // [])[].to, .files[].to) | split("/") | if .[0] == "config" then join("/") else .[0] end' "$MANIFEST" | sort -u)

if [ "$mode" = check ]; then
  status=0
  for p in $owned; do
    if ! diff -r "$OUT/$p" "$COMMITTED/$p" >/dev/null 2>&1; then
      echo "fetch-upstream: fd-vale/styles/$p differs from upstream.json" >&2
      status=1
    fi
  done
  [ "$status" = 0 ] && echo "fetch-upstream: committed styles match upstream.json"
  exit "$status"
fi

for p in $owned; do
  rm -rf "${COMMITTED:?}/$p"
  mkdir -p "$(dirname "$COMMITTED/$p")"
  cp -R "$OUT/$p" "$COMMITTED/$p"
done
echo "fetch-upstream: wrote $(echo "$owned" | wc -l | tr -d ' ') paths under fd-vale/styles"
