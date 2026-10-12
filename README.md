# cloc-diff-limit

[![CI](https://github.com/Coacher/cloc-diff-limit/actions/workflows/ci.yml/badge.svg)](https://github.com/Coacher/cloc-diff-limit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![pre-commit](https://img.shields.io/badge/pre--commit-hook-FAB040?logo=pre-commit&logoColor=white)](https://pre-commit.com)
[![POSIX sh](https://img.shields.io/badge/shell-POSIX%20sh-4EAA25?logo=gnubash&logoColor=white)](cloc-diff-limit)

A [pre-commit](https://pre-commit.com) hook that keeps commits small. It blocks a commit when its staged changes exceed your limits on lines of code added, removed, changed, or in total.

```console
$ git commit -m "Add the new importer"
limit lines of code per commit (cloc)....................................Failed
- hook id: cloc-diff-limit
- exit code: 1

cloc-diff-limit: code lines: total 30 (added 30, removed 0, changed 0)
cloc-diff-limit: commit exceeds limits:
  total        30 > 20
```

Counting is done by [cloc](https://github.com/AlDanial/cloc), so blank lines never count and comments count only if you ask. The hook itself is a small, strictly POSIX `sh` wrapper.

## Quick start

1. Add the hook to `.pre-commit-config.yaml`:

   ```yaml
   repos:
     - repo: https://github.com/Coacher/cloc-diff-limit
       rev: v1.0.0
       hooks:
         - id: cloc-diff-limit
           args: [--max-total, "400", --exclude-dir=tests]
   ```

2. Install it into your clone:

   ```sh
   pre-commit install
   ```

> [!IMPORTANT]
> `cloc-diff-limit` needs [cloc](https://github.com/AlDanial/cloc#install-via-package-manager) 1.86 or later on your `PATH`, for example `brew install cloc` or `sudo apt install cloc`.
> If you'd rather not install it, use the `cloc-diff-limit-npm` hook id instead: pre-commit then installs cloc itself, and only Perl is needed.

## Options

| Option | Default | Meaning |
|---|---|---|
| `--max-total N` | `-1` | Limit on added + removed + changed lines |
| `--max-added N` | `-1` | Limit on added lines |
| `--max-removed N` | `-1` | Limit on removed lines |
| `--max-changed N` | `-1` | Limit on changed (modified) lines |
| `--include-comments` | off | Count comment lines as well as code lines |
| `--base REF` | `HEAD` | Revision to compare the staged changes against |
| `-v`, `--verbose` | off | Print the counts even when the commit passes |
| `-h`, `--help` | | Print usage |
| *any other option* | | Passed to cloc unchanged |

`N` is an integer `>= 0`, or `-1` for no limit. A limit of `0` allows no lines of that kind. Both `--max-total 400` and `--max-total=400` work.

### Excluding files

Every cloc filter works, because options the hook doesn't recognise go straight to cloc:

```sh
--exclude-dir=tests,migrations                # directory names, at any depth
--exclude-ext=sql,lock                        # file extensions
--exclude-lang=Markdown,JSON,YAML             # cloc language names (see: cloc --show-lang)
--not-match-f='(_test\.go|\.min\.js)$'        # regex on file names
--fullpath --not-match-d='/generated(/|$)'    # regex on directory paths
--exclude-list-file=.clocignore               # one file or directory name per line
```

> [!WARNING]
> Repeating an option such as `--exclude-dir` replaces the earlier value instead of adding to it. List several values in one option, separated by commas: `--exclude-dir=tests,migrations`.
>
> Without `--fullpath`, `--not-match-d` only looks at the name of the folder a file is directly in, so `--not-match-d=vendor` misses `vendor/lib/x.py`.

> [!TIP]
> cloc treats Markdown, JSON, YAML and plain text as languages. Add `--exclude-lang=Markdown,JSON,YAML,Text` if docs and config files shouldn't count against the limit.

> [!NOTE]
> pre-commit's own `files:` and `exclude:` settings have no effect on this hook, because it checks the whole commit rather than a list of files. Use the cloc options above instead.

### Examples

<details>
<summary>Keep every commit under 300 changed lines, ignoring tests and generated SQL</summary>

```yaml
- id: cloc-diff-limit
  args: [--max-total, "300", --exclude-dir=tests, --exclude-ext=sql]
```
</details>

<details>
<summary>Separate limits, comments included</summary>

```yaml
- id: cloc-diff-limit
  args: [--max-added, "200", --max-removed, "-1", --max-changed, "100", --include-comments]
```
</details>

<details>
<summary>Check a whole branch in CI</summary>

The hook works outside pre-commit too. Here it checks everything a branch changes since it split off `main` (fetch with enough history for the merge base to exist):

```sh
./cloc-diff-limit --base "$(git merge-base origin/main HEAD)" --max-total 1000 --verbose
```
</details>

## How lines are counted

- **Added, removed and changed** follow cloc's diff. An edited line counts once as *changed*, not as one removal plus one addition the way `git diff --numstat` reports it.
- **Total** is added + removed + changed.
- **Blank lines** never count. **Comment lines** count only with `--include-comments`.
- **Files cloc doesn't recognise** as source code, such as binaries, are ignored.
- **Only staged changes** count. Unstaged edits in your working tree are ignored.

## How it works

All counting is one cloc call:

```sh
cloc --git --diff HEAD "$(git write-tree)" --quiet --hide-rate --skip-uniqueness [your cloc options]
```

`git write-tree` turns the staged index into a tree object, the same thing `git commit` is about to record. cloc compares it with `HEAD` directly from git's object store, so nothing is checked out to disk. Its report ends with totals:

```text
SUM:
 same                            0              0              0              1
 modified                        3              0              1              5
 added                           1              1              1              5
 removed                         0              0              0              0
```

The columns are files, blank, comment and code. The hook reads these rows with the shell's built-in `read` and compares them with your limits. If the block is missing, it fails with an error instead of silently passing.

## Behaviour notes

- **First commit:** compared against the empty tree, so every line counts as added.
- **Merge commits** are skipped, because their diff against `HEAD` is the whole merged branch. Passing `--base` turns the check back on.
- **`git commit --amend`** is compared against the commit being amended, not its parent. A pre-commit hook can't tell that an amend is happening.
- **Bypassing** the check once: `git commit --no-verify`, or `SKIP=cloc-diff-limit git commit` with pre-commit.
- **Exit codes:** `0` within limits, `1` a limit was exceeded, `2` invalid options, cloc missing or failing, or not in a git repository.

## Using it without pre-commit

<details>
<summary>Install as a plain git hook</summary>

Copy `cloc-diff-limit` into your repository's `.git/hooks/` folder and create `.git/hooks/pre-commit` with your options:

```sh
#!/bin/sh
exec "$(dirname "$0")/cloc-diff-limit" --max-total 400 --exclude-dir=tests "$@"
```

Then make both files executable:

```sh
chmod +x .git/hooks/pre-commit .git/hooks/cloc-diff-limit
```
</details>

## Compatibility

| | Tested in CI |
|---|---|
| **cloc** | Releases 1.86 and 2.10 (every release in between passes too), Ubuntu's package, and the npm package |
| **Shells** | dash, posh, yash (`--posix`), busybox sh, bash (`--posix`), macOS `/bin/sh` |
| **Tools** | Only git and cloc; everything else is shell built-ins (`--help` also uses `sed`) |

cloc 1.84 and older miscount some cases, such as renamed files.

## Performance

The wrapper adds a few milliseconds; the rest is cloc. cloc only reads the files changed in the commit, so repository size doesn't matter. Measured with cloc 2.10:

| Staged change | Time |
|---|---|
| 41 new files, 3,080 lines | about 0.25 s |
| 1,000 modified lines in one file, plus 40 edited files | about 0.45 s |

## Why cloc?

This hook deliberately counts nothing itself. cloc was the only mature tool that does all three things it needs:

| Tool | Knows code from comments | Compares git revisions | Reports changed lines separately |
|---|---|---|---|
| **cloc** | ✅ | ✅ (`--git --diff`, any revision or tree) | ✅ |
| scc, tokei, gocloc, loc | ✅ | ❌ totals only | ❌ |
| sccdiff, git-loc | ✅ | net difference only | ❌ |
| rloc (Rust cloc port) | ✅ | directories only, not git | ✅ |
| `git diff --numstat` | ❌ counts blanks and comments | ✅ | ❌ |

## Development

You need [bats](https://github.com/bats-core/bats-core), cloc, [ShellCheck](https://www.shellcheck.net) and `checkbashisms` (from Debian's `devscripts`). The integration tests also need pre-commit and Node.

```sh
make lint               # ShellCheck and checkbashisms
make test               # unit tests under sh (HOOK_SHELL="yash --posix" make test for another shell)
make test-shells        # unit tests under every installed POSIX shell
make test-integration   # real commits through pre-commit, for both hook ids
```

[CI](.github/workflows/ci.yml) runs all of these on every push and pull request: the unit tests under five shells on Linux and under macOS `/bin/sh`, with the newest and oldest supported cloc releases plus the Ubuntu and npm packages.

## License

[MIT](LICENSE). cloc itself is a separate project under the GPL-2.0 and is not bundled.
