#!/usr/bin/env bats
# End-to-end tests through the pre-commit framework: install the hook, make
# real commits. Needs pre-commit on PATH (and node for cloc-diff-limit-npm).
#
#   HOOK_ID=cloc-diff-limit     bats test/integration/   # uses cloc from PATH
#   HOOK_ID=cloc-diff-limit-npm bats test/integration/   # cloc from npm

HOOK_ID="${HOOK_ID:-cloc-diff-limit}"

setup_file() {
  export HOME="${BATS_FILE_TMPDIR}/home"
  export GIT_CONFIG_NOSYSTEM=1
  export PRE_COMMIT_HOME="${BATS_FILE_TMPDIR}/pre-commit-cache"
  mkdir -p "${HOME}"
  git config --global user.name test
  git config --global user.email test@example.com
  git config --global init.defaultBranch main
  git config --global commit.gpgsign false

  # Snapshot the working tree as a hook repository, so uncommitted edits are
  # what gets tested.
  local src="${BATS_TEST_DIRNAME}/../.."
  local hook_repo="${BATS_FILE_TMPDIR}/hook-repo"
  mkdir "${hook_repo}"
  cp "${src}/cloc-diff-limit" "${src}/.pre-commit-hooks.yaml" "${src}/package.json" "${hook_repo}/"
  git -C "${hook_repo}" init -q
  git -C "${hook_repo}" add -A
  git -C "${hook_repo}" commit -qm snapshot
  HOOK_REPO="${hook_repo}"
  HOOK_REV=$(git -C "${hook_repo}" rev-parse HEAD)
  export HOOK_REPO HOOK_REV
}

setup() {
  cd "${BATS_TEST_TMPDIR}" || return 1
  git init -q repo
  cd repo || return 1
  cat >.pre-commit-config.yaml <<EOF
repos:
  - repo: ${HOOK_REPO}
    rev: ${HOOK_REV}
    hooks:
      - id: ${HOOK_ID}
        args: [--max-added, "10", --exclude-dir=tests]
EOF
  git add .pre-commit-config.yaml
  git commit -qm config --no-verify
  pre-commit install >/dev/null
}

python_lines() { # count prefix
  local i=1
  while [ "${i}" -le "$1" ]; do
    printf '%s_%s = %s\n' "$2" "${i}" "${i}"
    i=$((i + 1))
  done
}

@test "${HOOK_ID}: a commit within the limit goes through" {
  python_lines 10 ok >ok.py
  git add ok.py
  run git commit -m within
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Passed"* ]]
  [ "$(git log --format=%s -1)" = within ]
}

@test "${HOOK_ID}: a commit over the limit is blocked" {
  python_lines 11 big >big.py
  git add big.py
  run git commit -m over
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Failed"* ]]
  [[ "${output}" == *"added        11 > 10"* ]]
  [ "$(git log --format=%s -1)" = config ]
}

@test "${HOOK_ID}: arguments from the config reach cloc" {
  mkdir tests
  python_lines 50 t >tests/test_big.py
  git add tests
  run git commit -m excluded
  [ "${status}" -eq 0 ]
  [ "$(git log --format=%s -1)" = excluded ]
}
