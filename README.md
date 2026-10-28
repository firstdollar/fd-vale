# fd-vale

First Dollar's shared [Vale](https://vale.sh) configuration. Each release publishes one Vale package, `fd-vale.zip`. It contains every style a First Dollar repo lints with and a base `.vale.ini` with the house levels. A repo pins that zip and keeps only its own exceptions.

## Use it in a repo

Put this in the repo's `.vale.ini`, then run `vale sync`:

```ini
StylesPath = .vale/styles
Packages = https://github.com/firstdollar/fd-vale/releases/download/v0.1.0/fd-vale.zip
```

Add `.vale/styles/` to `.gitignore`. Vale 3.25.1 or later is required. Older versions read comments in `.mjs`, `.cjs`, `.mts` and `.cts` files as plain text, and lint code examples inside JavaScript and TypeScript comments as prose. fd-vale's CI pins 3.25.1.

### Package contents

| Style | Source | License |
|---|---|---|
| `ai-tells` | [tbhb/vale-ai-tells](https://github.com/tbhb/vale-ai-tells) v1.37.0 | MIT |
| `ai-tells-commits` | [tbhb/vale-ai-tells](https://github.com/tbhb/vale-ai-tells) v1.37.0 | MIT |
| `STE` | [Syntaf/vale-llm-slop](https://github.com/Syntaf/vale-llm-slop) v0.1.0 | MIT |
| `JustSaySo` | [ifandelse/just-say-so](https://github.com/ifandelse/just-say-so) v0.18.1 | MIT |
| `Prompts` | [jdkato/prompts](https://github.com/jdkato/prompts) at `0fb3361da35a` | MIT |
| `FirstDollar` | This repo. `We` and `Avoid` come from Docker's docs-toolkit. | MIT. `We` and `Avoid` are Apache-2.0. |

The package also includes the `FirstDollar` vocabulary (product names) and the ai-tells output template. `fd-vale/.vale.ini` sets the levels and records the measured reason for each one.

### Package layout

The base config follows [just-say-so's layout](https://github.com/ifandelse/just-say-so/blob/main/docs/vale.md). The shared styles and levels live once in `[*]`, and each target narrows them.

| Text | Name Vale sees | Rules |
|---|---|---|
| A Markdown, MDX or HTML file, or a page the Artifact tool publishes | its path, or `artifact.<file>.html` | `[*]` |
| An agent instruction file | `AGENTS.md`, `CLAUDE.md`, `SKILL.md` | `[*]` plus Prompts |
| A chat reply | `reply.reply` | `[*]`, with every ai-tells, JustSaySo and FirstDollar rule at warning except nine at error. FirstDollar.We is off. |
| A `gh` or MCP field an agent publishes | `<source>.<tool>.<field>.publish`, such as `gh.pr.body.publish` | `[*]`, with FirstDollar.NobodySubject at error |
| A commit message | `COMMIT_EDITMSG` | ai-tells, ai-tells-commits and STE, with the `[*]` levels |
| Comments in source code: `.ts`, `.tsx`, `.mts`, `.cts`, `.js`, `.jsx`, `.mjs`, `.cjs`, `.py`, `.go`, `.rb`, `.rs`, `.java`, C and C++, `.cs`, `.swift`, `.scala`, `.proto`, CSS, and a few more | its path | `[*]`, comments only. DoubleHyphen (divider lines), FirstDollar.We and the five heading rules are off. Vale leaves the code itself alone, and in JavaScript and TypeScript it also skips code examples inside comments. |
| Every other file: shell scripts, SQL, YAML, JSON, `.env`, config | its path | none |

just-say-so 0.9.0 and later chooses the reply and publish names. `[formats]` maps both extensions to Markdown, so Vale skips code spans in them.

just-say-so lints every file an agent writes. For the source types in the table, Vale checks the comments and skips the code. For every other type, Vale would read the whole file as prose, code and config values included. A section of the base config, `[!*.{...}]`, turns every style off for those types.

In JavaScript and TypeScript, `[formats]` maps each extension to Markdown, so Vale reads comments as Markdown and skips code spans, fences and JSDoc `@example` blocks. Turning off the five heading rules for source files goes with that mapping: under it, a comment line directly above `// ---` parses as a heading.

⚠️ In the other source types, Vale reads a comment as plain text, so a code example inside one is checked as prose. A semicolon followed by a member access, such as `load(x); self.save(x)`, trips SemicolonUsage at error. In the measured comments this was rare. When it happens, the agent cannot reword the code, so just-say-so lets the turn end after one unsuccessful rewrite.

⚠️ just-say-so's commit gate checks only `.md`, `.mdx`, `.markdown`, `.html` and `.htm`. Code comments are checked when an agent writes them, and not at commit or in CI. To lint another type, add a section for it, such as `[*.txt]`, and list every style you want there. The `[*]` levels do not reach that type.

### Turn on reply checks one repo at a time

The package's `[*.reply]` section holds the rules for chat replies. Whether a repo checks replies is a just-say-so setting. Each repo turns it on when it is ready. A repo starts with reply checks off in its `.just-say-so.json`:

```json
{ "reply": { "mode": "off" } }
```

With `reply.mode` off, just-say-so still checks written files and Artifact pages, and still gives the model the rules text at session start. It doesn't report broken reply rules on the next prompt. Its local events log still records per-rule counts for each reply, which gives a baseline before the repo turns checks on. To turn them on, change `"off"` to `"warn"`. `warn` reports broken rules on the next prompt and never blocks a reply.

In replies, an error-level alert means "remind the agent about this rule on the next prompt". The package keeps nine rules at error: EmDashUsage, SemicolonUsage, CataphoricForecasting, NegatedObject, NegatedSubject, ContrastiveNegation, ContrastiveFormulas, ExplainerHeadings and FirstDollar.SentenceCap. These are the habits to train out of replies first. Every other rule is at warning. Warnings stay out of the report and are still counted in the events log. To start training another rule, raise it to error in `[*.reply]`. A repo can raise one for itself in its own `[*.reply]`.

Vale can't detect every complaint about a reply, for example shorthand or a term used before it is defined. For those, run `/just-say-so:restate` with a tag, such as `/just-say-so:restate #undefined-term what is a "pin"?`. `/just-say-so:summary` counts the tags, and `/just-say-so:advise` suggests a rules bullet or a Vale rule for a tag that recurs.

A repo's `.just-say-so.json` overrides each person's `~/.config/just-say-so/just-say-so.json`. While a repo has reply checks off, nobody can turn them on for themselves in that repo.

### Change a rule in your repo

Vale reads the package's `.vale.ini` first and the repo's second. Under the same section header, `BasedOnStyles` lists are combined, and every other key takes the repo's value.

- **Change a level for every target:** set it in the repo's `[*]`, such as `ai-tells.ShipOveruse = error`.
- **Change a level for one target:** set it in that target's section, such as `STE.PassiveVoice = NO` under `[*.md]` or `[*.reply]`.
- **Add a style:** list it in the repo's `[*]`. Vale adds it to the package's `[*]` list.
- **Turn a style off:** write `STE = NO`. A repo cannot remove a style from the package's `BasedOnStyles`. A level set on one rule of a disabled style turns that one rule back on.
- **Exempt a path:** add a section with an empty list, such as `[**/archive/**]` followed by `BasedOnStyles =`.
- **Add your own terms:** create a vocabulary under a different name and list both: `Vocab = FirstDollar, MyRepo`. ⚠️ Give a repo vocabulary any name except `FirstDollar`. `vale sync` overwrites `StylesPath/config/vocabularies/FirstDollar` with the package's copy.

🔥 Write `BasedOnStyles` only in `[*]`. A `BasedOnStyles` line under a narrower header such as `[*.md]` replaces the `[*]` list for those files. The package's JustSaySo and FirstDollar styles then drop out of Markdown with no warning. The `repo-md-basedonstyles` test case records this behavior.

### Verify the download

`vale sync` downloads the zip with no checksum. Each release's notes give the zip's SHA-256 and a two-line check for CI to run before `vale sync`. Releases are immutable: once a release is published, GitHub refuses any change to its tag or its assets.

## Change the package

### Update a third-party style

1. Edit the style's entry in `upstream.json`: the tag, the commit, each URL and each SHA-256. Take the zip's hash from the `digest` field of the GitHub release asset, then confirm it against your own download.
2. Run `scripts/fetch-upstream.sh`. When a download's hash does not match, it stops before it writes any file.
3. Review the diff under `fd-vale/styles/`. That diff is every rule change the upgrade brings.
4. Run `test/run.sh`. Read each changed alert, then run `test/run.sh --update` to accept them.

CI runs `scripts/fetch-upstream.sh --check`, which fails when a committed third-party file differs from what `upstream.json` pins. Edit third-party rules only by changing the manifest.

### Change a First Dollar rule or a level

Edit `fd-vale/styles/FirstDollar/` or `fd-vale/.vale.ini`, run `test/run.sh`, and update the snapshots once each changed alert is the intended one. Record the measurement behind a new level in a comment next to it.

To see what a change does to a real repo, run:

```sh
scripts/compare-repo.sh ~/git/some-repo candidate.vale.ini
```

The script lints the repo's tracked Markdown with its current config and with the candidate config, then writes per-rule counts (`rules.tsv`) and every changed alert (`alerts.diff`). It works on a `git archive` copy, so the repo's working tree is never touched.

### Release

Merge to `main`, then push a tag:

```sh
git tag v0.2.0 && git push origin v0.2.0
```

The release workflow refuses a tag whose commit is not on `main`. It runs the tests, builds the zip, and publishes the release with the zip's SHA-256 in the notes.

Versions follow SemVer, measured by what a repo's CI sees:

- **Major:** a new error-level alert. This covers a new rule at error, a raised level, or a removed exemption.
- **Minor:** new warnings or suggestions only.
- **Patch:** changes that only remove alerts or change messages.

Until v1.0.0, each release is a GitHub pre-release, and each number moves down one place. A new error-level alert raises the minor version (0.1.0 to 0.2.0). Every other change raises the patch version. A tag with a pre-release suffix, such as `v1.0.0-rc.1`, is also published as a pre-release.

## Tests

`test/run.sh` builds `dist/fd-vale.zip`, serves it from localhost, and lints `test/fixtures/` once for each case in `test/cases/`. Each case is a `.vale.ini` written the way a repo would write it. Every run goes through a real `vale sync` and a real config merge. The run fails on any difference from the case's `expected.json`.

Before it builds, the script runs `test/check-config.py`. It fails when a section in the base config writes a `BasedOnStyles` list that leaves out a `[*]` style, unless the script lists that section as intended. It also fails when a section sets a style-wide level, such as `ai-tells = warning`, without repeating each `= NO` that `[*]` sets for that style. A style-wide level turns those rules back on.

| Case | What it checks |
|---|---|
| `base` | The package alone. One fixture line per level decision in `fd-vale/.vale.ini`, across Markdown, HTML, a reply, a PR body and a commit message. |
| `overrides` | A repo vocabulary next to `FirstDollar`, a level raised in `[*]` for every target, an exempt directory |
| `repo-md-section` | A level set under `[*.md]` reaches Markdown only, and every package style still runs |
| `repo-star-section` | A style listed in the repo's `[*]` adds to the package's list |
| `repo-md-basedonstyles` | A `BasedOnStyles` line under `[*.md]` replaces the `[*]` list. This case records a hazard and does not show a supported setup. |

The zip is reproducible. `scripts/build.sh` sets a fixed timestamp and fixed permissions on each file and sorts the entries. Building the same commit twice gives the same SHA-256.

## License

MIT, except `fd-vale/styles/FirstDollar/We.yml` and `Avoid.yml` (Apache-2.0, Docker). Each third-party style keeps its own `LICENSE` file.
