#!/usr/bin/env bats
# Tests for cloc-diff-limit.
#
# The hook runs under $HOOK_SHELL (default: sh), so the same suite checks every
# POSIX shell, e.g.:  HOOK_SHELL="busybox sh" bats test/

HOOK="${BATS_TEST_DIRNAME}/../cloc-diff-limit"
HOOK_SHELL="${HOOK_SHELL:-sh}"

setup() {
  # Isolate from the user's git and cloc configuration.
  export HOME="${BATS_TEST_TMPDIR}/home"
  export GIT_CONFIG_NOSYSTEM=1
  mkdir -p "${HOME}"
  git config --global user.name test
  git config --global user.email test@example.com
  git config --global init.defaultBranch main
  git config --global commit.gpgsign false

  cd "${BATS_TEST_TMPDIR}" || return 1
  git init -q repo
  cd repo || return 1

  # Baseline: 4 code + 1 comment lines of Python, 1 test line, 1 SQL line.
  printf 'def a():\n    # c\n    return 1\n\ndef b():\n    return 2\n' >a.py
  mkdir tests
  printf 'x = 1\n' >tests/t.py
  printf 'SELECT 1;\n' >q.sql
  commit_all baseline
}

# Run the hook under the shell being tested.
hook() {
  # shellcheck disable=SC2086 # HOOK_SHELL may be several words, e.g. "busybox sh"
  run ${HOOK_SHELL} "${HOOK}" "$@"
}

commit_all() {
  git add -A
  git commit -qm "$1" --no-verify
}

# A change with every kind of line, staged. cloc reports, for code lines:
#   added 5 (3 Python, 1 SQL, 1 C), changed 5 (4 Python, 1 SQL), removed 0
# and with comments: added 6, changed 6.
stage_mixed_change() {
  printf 'def a():\n    # changed comment\n    return 10\n\ndef c():\n    return 3\n\ndef d():\n    return 4\n' >a.py
  printf 'x=1\ny=2\n' >tests/t.py
  printf 'SELECT 2;\n-- note\nSELECT 3;\n' >q.sql
  printf 'int main(){return 0;}\n' >n.c
  git add -A
}

assert_counts() {
  [[ "${output}" == *"total $1 (added $2, removed $3, changed $4)"* ]]
}

# --- counting ---------------------------------------------------------------

@test "counts added, removed and changed code lines" {
  stage_mixed_change
  hook -v
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"code lines:"* ]]
  assert_counts 10 5 0 5
}

@test "--include-comments also counts comment lines" {
  stage_mixed_change
  hook -v --include-comments
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"code+comment lines:"* ]]
  assert_counts 12 6 0 6
}

@test "blank lines are never counted" {
  printf '\n\n\n' >>a.py
  git add a.py
  hook -v --max-total 0
  [ "${status}" -eq 0 ]
  assert_counts 0 0 0 0
}

@test "removed lines are counted" {
  git rm -q a.py
  hook -v
  [ "${status}" -eq 0 ]
  assert_counts 4 0 4 0
}

@test "the root commit counts everything as added" {
  rm -rf .git
  git init -q
  git add -A
  hook -v
  [ "${status}" -eq 0 ]
  assert_counts 6 6 0 0
}

@test "an empty diff counts zero and passes a zero limit" {
  hook -v --max-total 0
  [ "${status}" -eq 0 ]
  assert_counts 0 0 0 0
}

@test "only staged changes are counted, not the working tree" {
  printf 'y = 2\nz = 3\n' >>tests/t.py
  hook -v --max-total 0
  [ "${status}" -eq 0 ]
  assert_counts 0 0 0 0
}

@test "a pure rename counts zero" {
  git mv a.py renamed.py
  hook -v --max-total 0
  [ "${status}" -eq 0 ]
}

@test "identical new files are each counted" {
  printf 'int main(){return 0;}\n' >one.c
  cp one.c two.c
  git add -A
  hook -v
  assert_counts 2 2 0 0
}

# --- limits ------------------------------------------------------------------

@test "passes silently when within every limit" {
  stage_mixed_change
  hook --max-total 10 --max-added 5 --max-removed 0 --max-changed 5
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "--max-total fails when exceeded" {
  stage_mixed_change
  hook --max-total 9
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"total        10 > 9"* ]]
}

@test "--max-added fails when exceeded" {
  stage_mixed_change
  hook --max-added 4
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"added         5 > 4"* ]]
}

@test "--max-removed fails when exceeded" {
  git rm -q a.py
  hook --max-removed 3
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"removed       4 > 3"* ]]
}

@test "--max-changed fails when exceeded" {
  stage_mixed_change
  hook --max-changed 4
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"changed       5 > 4"* ]]
}

@test "every exceeded limit is reported" {
  stage_mixed_change
  hook --max-total 1 --max-added 1 --max-changed 1 --max-removed 1
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"total"*"added"*"changed"* ]]
  [[ "${output}" != *"removed  "* ]]
}

@test "a limit of 0 forbids any such line" {
  stage_mixed_change
  hook --max-removed 0
  [ "${status}" -eq 0 ]
  hook --max-added 0
  [ "${status}" -eq 1 ]
}

@test "-1 means no limit, and is the default" {
  stage_mixed_change
  hook --max-total -1 --max-added -1 --max-removed -1 --max-changed -1
  [ "${status}" -eq 0 ]
  hook
  [ "${status}" -eq 0 ]
}

@test "--option=value works as well as --option value" {
  stage_mixed_change
  hook --max-total=9
  [ "${status}" -eq 1 ]
  hook --max-total=-1
  [ "${status}" -eq 0 ]
}

@test "--include-comments applies to the limits" {
  stage_mixed_change
  hook --max-total 10
  [ "${status}" -eq 0 ]
  hook --max-total 10 --include-comments
  [ "${status}" -eq 1 ]
}

# --- excluding files (options passed through to cloc) -------------------------

@test "--exclude-dir and --exclude-ext exclude files" {
  stage_mixed_change
  hook -v --exclude-dir=tests --exclude-ext=sql
  assert_counts 6 3 0 3
}

@test "--not-match-f excludes files by regex" {
  stage_mixed_change
  hook -v '--not-match-f=\.(sql|c)$'
  assert_counts 7 3 0 4
}

@test "--exclude-dir excludes nested directories at any depth" {
  mkdir -p src/tests/unit
  printf 'u = 1\n' >src/tests/unit/u.py
  printf 'keep = 1\n' >keep.py
  git add -A
  hook -v --exclude-dir=tests
  assert_counts 1 1 0 0
}

@test "--fullpath --not-match-d matches nested directory paths" {
  mkdir -p vendor/lib src/vendorized
  printf 'v = 1\n' >vendor/lib/v.py
  printf 'keep = 1\n' >src/vendorized/k.py
  git add -A
  hook -v --fullpath '--not-match-d=/vendor(/|$)'
  assert_counts 1 1 0 0
}

@test "--exclude-list-file excludes the directories it names" {
  mkdir gen
  printf 'g = 1\n' >gen/g.py
  printf 'keep = 1\n' >keep.py
  printf 'gen\n' >"${BATS_TEST_TMPDIR}/ignore"
  git add -A
  hook -v "--exclude-list-file=${BATS_TEST_TMPDIR}/ignore"
  assert_counts 1 1 0 0
}

@test "pass-through arguments containing spaces are kept intact" {
  mkdir 'my dir'
  printf 'k = 1\n' >'my dir/k.py'
  git add -A
  hook -v '--not-match-d=my dir'
  assert_counts 0 0 0 0
}

# --- git situations ----------------------------------------------------------

@test "merge commits are skipped" {
  git checkout -qb feature
  printf 'v%s = 1\n' 1 2 3 4 5 6 7 8 >big.py
  commit_all big
  git checkout -q main
  printf 'w = 1\n' >w.py
  commit_all w
  git merge -q --no-commit --no-ff feature
  hook --max-total 0
  [ "${status}" -eq 0 ]
}

@test "--base re-enables the check during a merge" {
  git checkout -qb feature
  printf 'v%s = 1\n' 1 2 3 4 5 6 7 8 >big.py
  commit_all big
  git checkout -q main
  printf 'w = 1\n' >w.py
  commit_all w
  git merge -q --no-commit --no-ff feature
  hook -v --max-total 5 --base HEAD
  [ "${status}" -eq 1 ]
  assert_counts 8 8 0 0
}

@test "--base diffs against another revision" {
  printf 'w = 1\n' >w.py
  commit_all w
  hook -v --base HEAD~1 --max-added 0
  [ "${status}" -eq 1 ]
  assert_counts 1 1 0 0
}

# --- errors ------------------------------------------------------------------

@test "rejects a limit below -1" {
  hook --max-total -2
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"--max-total expects an integer >= -1, got '-2'"* ]]
}

@test "rejects a non-numeric limit" {
  hook --max-added abc
  [ "${status}" -eq 2 ]
  hook --max-added ''
  [ "${status}" -eq 2 ]
}

@test "rejects a limit option without a value" {
  hook --max-removed
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"--max-removed needs a value"* ]]
}

@test "reports an unknown cloc option as a cloc failure" {
  hook --no-such-cloc-option
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"cloc failed"* ]]
}

@test "refuses cloc output-format options instead of silently passing" {
  stage_mixed_change
  hook --csv --max-total 0
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"no SUM: block"* ]]
}

@test "fails clearly outside a git repository" {
  rm -rf .git
  hook
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"not inside a git repository"* ]]
}

@test "fails clearly when cloc is not installed" {
  # Keep the real PATH (some shells find printf and [ there), but replace each
  # directory holding cloc with a shadow copy that has everything except cloc.
  local path="" dir file n=0
  local -a dirs
  IFS=: read -ra dirs <<<"${PATH}"
  for dir in "${dirs[@]}"; do
    if [ -e "${dir}/cloc" ]; then
      n=$((n + 1))
      mkdir "${BATS_TEST_TMPDIR}/shadow${n}"
      for file in "${dir}"/*; do
        [ "${file##*/}" = cloc ] || ln -s "${file}" "${BATS_TEST_TMPDIR}/shadow${n}/"
      done
      dir="${BATS_TEST_TMPDIR}/shadow${n}"
    fi
    path="${path:+${path}:}${dir}"
  done
  run env PATH="${path}" sh -c 'command -v cloc'
  [ "${status}" -ne 0 ]

  PATH="${path}" hook
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"cloc not found on PATH"* ]]
}

@test "--help prints usage" {
  hook --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage: cloc-diff-limit"* ]]
}
