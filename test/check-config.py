#!/usr/bin/env python3
"""Fails when fd-vale/.vale.ini breaks one of four rules that snapshots can miss.

1. A BasedOnStyles line in a narrower section replaces the [*] list instead of adding
   to it. A section that needs one more style (Prompts for agent instruction files)
   has to repeat every [*] style; one left out stops running with no warning. The
   commit section and the allow-list replace the list on purpose. Turning a style off
   is written `Style = NO`, which this check leaves alone.
2. Of two sections that match one file, Vale applies the later one. The commit section
   has to come after the allow-list, which also matches COMMIT_EDITMSG.
3. The comments section and the allow-list both name the source types, and the two
   lists have to match.
4. A style-wide level in a narrower section, such as `ai-tells = warning` under
   [*.reply], turns back on every rule of that style that [*] turns off. Each of those
   `= NO` lines has to be repeated in that section.
"""
import os
import re
import sys

CONFIG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fd-vale", ".vale.ini")

STYLES_DIR = os.path.join(os.path.dirname(CONFIG), "styles")
STYLES = {d for d in os.listdir(STYLES_DIR) if d != "config"}
COMMIT = "{COMMIT_EDITMSG,.git/COMMIT_EDITMSG}"
PROSE = {"md", "mdx", "markdown", "html", "htm", "reply", "publish"}


def types(header, prefix):
    """The extensions in a header such as *.{ts,js} or !*.{md,ts}."""
    return set(header[len(prefix) + 1:-1].split(","))


def parse(path):
    sections, current = {}, None
    for raw in open(path, encoding="utf-8"):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        header = re.fullmatch(r"\[(.+)\]", line)
        if header:
            current = header.group(1)
            if current in sections:
                sys.exit(f"check-config: [{current}] appears twice")
            sections[current] = {}
            continue
        if current is None or "=" not in line:
            continue
        key, value = (part.strip() for part in line.split("=", 1))
        if key in sections[current]:
            sys.exit(f"check-config: [{current}] sets {key} twice")
        sections[current][key] = value


    return sections


def styles(value):
    return {s.strip() for s in value.split(",") if s.strip()}


def main():
    sections = parse(CONFIG)
    shared = styles(sections["*"]["BasedOnStyles"])
    problems = []

    # The allow-list is the one negated header; the comments section is the *.{...}
    # header that names source types.
    allow = next((h for h in sections if h.startswith("!*.{")), None)
    comments = next((h for h in sections if h.startswith("*.{") and types(h, "*.") - PROSE), None)
    if allow is None:
        problems.append("the allow-list section [!*.{...}] is missing")
    if comments is None:
        problems.append("the comments section for source types is missing")

    # These replace the [*] list on purpose: commit messages use ai-tells-commits, and
    # the allow-list turns every style off for non-prose types.
    intended = {COMMIT, allow}
    for header, keys in sections.items():
        if header in ("*", "formats") or "BasedOnStyles" not in keys or header in intended:
            continue
        missing = shared - styles(keys["BasedOnStyles"])
        if missing:
            problems.append(f"[{header}] BasedOnStyles leaves out {', '.join(sorted(missing))}; "
                            f"list every [*] style, or turn one off with `Style = NO`")

    # Of two sections that both match a file, Vale applies the later one. The allow-list
    # also matches COMMIT_EDITMSG, so the commit section has to come after it.
    order = list(sections)
    if allow and COMMIT in sections and order.index(COMMIT) < order.index(allow):
        problems.append(f"[{COMMIT}] must come after [{allow}], or commit messages get no rules")

    # A source type named in one list and not the other is either linted with the wrong
    # rules or not linted at all.
    if allow and comments:
        allowed, named = types(allow, "!*.") - PROSE, types(comments, "*.")
        if allowed != named:
            problems.append(f"source types differ: only in the allow-list {sorted(allowed - named)}, "
                            f"only in the comments section {sorted(named - allowed)}")

    # A style-wide level such as `ai-tells = warning` re-enables the style's rules that
    # [*] sets to NO, so the section has to turn each of them off again.
    disabled = {k for k, v in sections["*"].items() if "." in k and v == "NO"}
    for header, keys in sections.items():
        if header in ("*", "formats"):
            continue
        for style in (k for k, v in keys.items() if k in STYLES and v != "NO"):
            for rule in sorted(r for r in disabled if r.split(".")[0] == style):
                if keys.get(rule) != "NO":
                    problems.append(f"[{header}] sets `{style} = {keys[style]}`, which turns {rule} back on; "
                                    f"add `{rule} = NO` to that section")

    if problems:
        print("check-config:", *problems, sep="\n  ", file=sys.stderr)
        sys.exit(1)
    print(f"check-config: style lists keep the {len(shared)} [*] styles; section order, source types "
          f"and style-wide levels agree")


main()
