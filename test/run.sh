#!/usr/bin/env bash
# Snapshot tests for the built package.
#
#   test/run.sh            build, then fail on any case whose alerts differ from expected.json
#   test/run.sh --update   build, then rewrite every expected.json from the current output
#
# Each test/cases/<name>/ holds a consumer .vale.ini (the shape a repo would commit) and an
# expected.json. Every case lints the same corpus in test/fixtures. The package reaches Vale
# the way it reaches a repo: `vale sync` downloads dist/fd-vale.zip over HTTP, from a local
# server here. That exercises the zip layout and Vale's config merge, not only the rules.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
update=0
[ "${1:-}" = "--update" ] && update=1

for tool in vale jq python3; do
  command -v "$tool" >/dev/null || { echo "test: $tool is required" >&2; exit 2; }
done

"$ROOT/test/check-config.py"
"$ROOT/scripts/build.sh"

WORK=$(mktemp -d)
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT/dist" >/dev/null 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null; rm -rf "$WORK"' EXIT
for _ in $(seq 50); do curl -sf -o /dev/null "http://127.0.0.1:$PORT/fd-vale.zip" && break; sleep 0.1; done

failed=0
for case_dir in "$ROOT"/test/cases/*/; do
  name=$(basename "$case_dir")
  dir="$WORK/$name"
  cp -R "$ROOT/test/fixtures" "$dir"
  # Case-local files (a repo vocabulary, for example) land on top of the shared corpus.
  [ -d "$case_dir/files" ] && cp -R "$case_dir/files/." "$dir/"
  sed "s#@PACKAGE_URL@#http://127.0.0.1:$PORT/fd-vale.zip#" "$case_dir/vale.ini" > "$dir/.vale.ini"

  (cd "$dir" && vale sync >/dev/null)
  # Vale exits 1 when it reports an error-level alert; only a higher code is a failure here.
  # Vale runs directly, not through xargs: GNU xargs turns a child's exit 1 into 123.
  rc=0
  files=$(cd "$dir" && find . -type f ! -path './.vale/*' ! -name .vale.ini | sed 's#^\./##' | LC_ALL=C sort)
  # shellcheck disable=SC2086 # fixture paths have no spaces; word splitting is the point
  (cd "$dir" && vale --output=JSON $files) > "$WORK/$name.out.json" || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "FAIL $name: vale exited $rc" >&2
    cat "$WORK/$name.out.json" >&2
    failed=1
    continue
  fi
  # One flat, sorted list, so a diff names the file, line and rule that changed.
  jq -S '[to_entries[] | .key as $p | .value[] | {path: $p, line: .Line, span: .Span, check: .Check, severity: .Severity, match: .Match}] | sort_by(.path, .line, .span[0], .check)' "$WORK/$name.out.json" > "$WORK/$name.actual.json"

  if [ "$update" = 1 ]; then
    cp "$WORK/$name.actual.json" "$case_dir/expected.json"
    echo "updated $name ($(jq length "$WORK/$name.actual.json") alerts)"
  elif diff -u "$case_dir/expected.json" "$WORK/$name.actual.json" > "$WORK/$name.diff"; then
    echo "ok   $name ($(jq length "$WORK/$name.actual.json") alerts)"
  else
    echo "FAIL $name" >&2
    cat "$WORK/$name.diff" >&2
    failed=1
  fi
done
exit "$failed"
