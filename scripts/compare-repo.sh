#!/usr/bin/env bash
# Migration check: lints a repo's tracked Markdown with its current .vale.ini and with a
# candidate .vale.ini that uses fd-vale, then reports what changed.
#
#   scripts/compare-repo.sh <repo-path> <candidate-vale.ini> [out-dir]
#
# The candidate may contain @PACKAGE_URL@, which is replaced with dist/fd-vale.zip served
# from localhost, so a candidate can be checked before any release exists. A candidate
# that names a real release URL is used as written.
#
# Both runs use a `git archive` of the repo's HEAD in a temp dir, so the repo's working
# tree and its .vale/styles are never touched. Files are linted one at a time because Vale
# stops a whole run on one file with malformed frontmatter; such files are listed and
# skipped in both runs.
#
# Output in out-dir (default: a temp dir, printed at the end):
#   rules.tsv     per-rule alert counts: rule, severity, old, new, delta
#   alerts.diff   every alert that appears in only one run
#   skipped.txt   files Vale could not parse
#
# Not covered: chat text (reply.reply, *.publish) and commit messages exist only
# at run time, so the fixture tests in test/ cover those sections.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 2 ] || { echo "usage: $0 <repo-path> <candidate-vale.ini> [out-dir]" >&2; exit 2; }
REPO=$(cd "$1" && pwd)
CANDIDATE=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
OUT=${3:-$(mktemp -d)}
mkdir -p "$OUT"

for tool in vale jq git python3; do
  command -v "$tool" >/dev/null || { echo "compare-repo: $tool is required" >&2; exit 2; }
done

WORK=$(mktemp -d)
SERVER=
cleanup() { [ -n "$SERVER" ] && kill "$SERVER" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

if grep -q '@PACKAGE_URL@' "$CANDIDATE"; then
  "$ROOT/scripts/build.sh"
  PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT/dist" >/dev/null 2>&1 &
  SERVER=$!
  for _ in $(seq 50); do curl -sf -o /dev/null "http://127.0.0.1:$PORT/fd-vale.zip" && break; sleep 0.1; done
fi

git -C "$REPO" ls-files -z '*.md' > "$WORK/files"
echo "compare-repo: $(tr -cd '\0' < "$WORK/files" | wc -c | tr -d ' ') tracked Markdown files at $(git -C "$REPO" rev-parse --short HEAD)"

lint() { # name config-source
  local dir="$WORK/$1"
  mkdir -p "$dir" "$WORK/$1.out"
  git -C "$REPO" archive HEAD | tar -x -C "$dir"
  if [ "$1" = new ]; then
    sed "s#@PACKAGE_URL@#http://127.0.0.1:${PORT:-0}/fd-vale.zip#" "$CANDIDATE" > "$dir/.vale.ini"
  fi
  (cd "$dir" && vale sync >/dev/null)
  # One Vale process per file. $0 is the output dir, $1 the file.
  (cd "$dir" && xargs -0 -n 1 -P 8 sh -c '
    out="$0/$(printf "%s" "$1" | tr / _).json"
    vale --output=JSON "$1" > "$out" 2>"$out.err" || true
  ' "$WORK/$1.out" < "$WORK/files")
}

echo "compare-repo: linting with the repo's current .vale.ini"
lint old
echo "compare-repo: linting with $(basename "$CANDIDATE")"
lint new

# A file is skipped from both runs if either run could not parse it.
: > "$OUT/skipped.txt"
for run in old new; do
  find "$WORK/$run.out" -name '*.json' -print0 | while IFS= read -r -d '' f; do
    if [ -s "$f.err" ] || ! jq -e 'type == "object" and (has("Code") | not)' "$f" >/dev/null 2>&1; then
      basename "$f" .json >> "$OUT/skipped.txt"
    fi
  done
done
sort -u -o "$OUT/skipped.txt" "$OUT/skipped.txt"

flatten() { # run -> one alert per line: path:line:col severity check match
  find "$WORK/$1.out" -name '*.json' -print0 | while IFS= read -r -d '' f; do
    grep -qxF "$(basename "$f" .json)" "$OUT/skipped.txt" && continue
    jq -r 'to_entries[] | .key as $p | .value[] | "\($p):\(.Line):\(.Span[0])\t\(.Severity)\t\(.Check)\t\(.Match | gsub("\\s+"; " "))"' "$f"
  done | LC_ALL=C sort
}
flatten old > "$WORK/old.tsv"
flatten new > "$WORK/new.tsv"

diff "$WORK/old.tsv" "$WORK/new.tsv" > "$OUT/alerts.diff" || true

count() { cut -f2,3 "$1" | LC_ALL=C sort | uniq -c | awk '{print $3"\t"$2"\t"$1}'; }
count "$WORK/old.tsv" > "$WORK/old.count"
count "$WORK/new.tsv" > "$WORK/new.count"
python3 - "$WORK/old.count" "$WORK/new.count" > "$OUT/rules.tsv" <<'EOF'
import sys
def load(p):
    d = {}
    for line in open(p):
        rule, sev, n = line.rstrip("\n").split("\t")
        d[(rule, sev)] = int(n)
    return d
old, new = load(sys.argv[1]), load(sys.argv[2])
print("rule\tseverity\told\tnew\tdelta")
for key in sorted(set(old) | set(new), key=lambda k: (-abs(new.get(k, 0) - old.get(k, 0)), k)):
    o, n = old.get(key, 0), new.get(key, 0)
    if o != n:
        print(f"{key[0]}\t{key[1]}\t{o}\t{n}\t{n - o:+d}")
EOF

for sev in error warning suggestion; do
  o=$(awk -F'\t' -v s="$sev" '$2==s' "$WORK/old.tsv" | wc -l | tr -d ' ')
  n=$(awk -F'\t' -v s="$sev" '$2==s' "$WORK/new.tsv" | wc -l | tr -d ' ')
  printf 'compare-repo: %-10s old %6s  new %6s\n' "$sev" "$o" "$n"
done
echo "compare-repo: $(($(wc -l < "$OUT/rules.tsv") - 1)) rule/severity pairs changed; $(wc -l < "$OUT/skipped.txt" | tr -d ' ') files skipped"
echo "compare-repo: report in $OUT"
