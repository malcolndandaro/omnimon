#!/usr/bin/env bash
# Minimal, dependency-free assertion helpers for Omnimon's tests.
# Sourced by the *_test.sh scripts. Tracks failures in $FAILS.

FAILS=0
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

_green() { printf '\033[32m%s\033[0m' "$1"; }
_red()   { printf '\033[31m%s\033[0m' "$1"; }

pass() { printf '  %s  %s\n' "$(_green ok)" "$1"; }
fail() { printf '  %s %s\n' "$(_red FAIL)" "$1"; FAILS=$((FAILS + 1)); }

# assert_file <path> <description>
assert_file() {
	if [ -f "$ROOT/$1" ]; then pass "$2"; else fail "$2 — missing file: $1"; fi
}

# assert_grep <path> <fixed-string> <description>   (literal substring match)
assert_grep() {
	if grep -Fq -- "$2" "$ROOT/$1"; then pass "$3"; else fail "$3 — not found in $1: $2"; fi
}

# assert_regex <path> <ere> <description>
assert_regex() {
	if grep -Eq -- "$2" "$ROOT/$1"; then pass "$3"; else fail "$3 — pattern not in $1: $2"; fi
}

# refute_grep <path> <fixed-string> <description>  (must NOT be present)
refute_grep() {
	if grep -Fq -- "$2" "$ROOT/$1"; then fail "$3 — unexpectedly found in $1: $2"; else pass "$3"; fi
}

summary() {
	echo
	if [ "$FAILS" -eq 0 ]; then
		printf '%s\n' "$(_green "All checks passed.")"
		return 0
	fi
	printf '%s\n' "$(_red "$FAILS check(s) failed.")"
	return 1
}
