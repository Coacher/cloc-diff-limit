.POSIX:
.PHONY: lint test test-shells test-integration

# Static checks: ShellCheck (POSIX sh) and checkbashisms on the hook, ShellCheck on the tests.
lint:
	shellcheck -s sh cloc-diff-limit
	shellcheck test/*.bats test/integration/*.bats
	checkbashisms --posix --extra cloc-diff-limit

# Unit tests under one shell: HOOK_SHELL="yash --posix" make test (default: sh).
test:
	bats test/

# Unit tests under every POSIX shell that is installed.
test-shells:
	@for s in dash posh "yash --posix" "busybox sh" "bash --posix"; do \
	  if command -v "$${s%% *}" >/dev/null 2>&1; then \
	    echo "== $$s"; HOOK_SHELL="$$s" bats test/ || exit 1; \
	  else echo "== $$s: not installed, skipped"; fi; \
	done

# End-to-end tests through pre-commit, for both hook ids.
test-integration:
	HOOK_ID=cloc-diff-limit bats test/integration/
	HOOK_ID=cloc-diff-limit-npm bats test/integration/
