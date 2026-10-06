#!/bin/sh

set -u

BIN_DIR=${BIN_DIR:-./build/bin}
TEE="$BIN_DIR/tee"

pass=0
fail=0

TMPDIR=${TMPDIR:-/tmp}
TEST_DIR="$TMPDIR/coreutils-tee-test.$$"

cleanup() {
  rm -rf "$TEST_DIR"
}

trap cleanup 0
trap 'exit 1' 1 2 3 15

mkdir "$TEST_DIR"

pass() {
  printf 'PASS: %s\n' "$1"
  pass=$((pass + 1))
}

fail() {
  printf 'FAIL: %s\n' "$1"
  fail=$((fail + 1))
}

# Setup target files template for testing
reset_targets() {
  rm -f "$TEST_DIR"/my_out_* "$TEST_DIR"/sys_out_*
  if [ "${1:-}" = "prefill" ]; then
    printf "Pre-existing Line\n" >"$TEST_DIR/my_out_1.txt"
    printf "Pre-existing Line\n" >"$TEST_DIR/my_out_2.txt"
    printf "Pre-existing Line\n" >"$TEST_DIR/sys_out_1.txt"
    printf "Pre-existing Line\n" >"$TEST_DIR/sys_out_2.txt"
  fi
}

check_tee() {
  name=$1
  shift

  >"$TEST_DIR/stdin.tmp"

  if [ ! -t 0 ]; then
    cat >"$TEST_DIR/stdin.tmp"
  fi

  # 1. Run your custom utility
  eval "$TEE" "$@" <"$TEST_DIR/stdin.tmp" >"$TEST_DIR/my.stdout" 2>"$TEST_DIR/my.stderr"
  exit_my=$?

  # 2. Run system reference implementation
  sys_args=$(printf '%s' "$*" | sed "s|my_out_|sys_out_|g")

  eval "tee" "$sys_args" <"$TEST_DIR/stdin.tmp" >"$TEST_DIR/sys.stdout" 2>"$TEST_DIR/sys.stderr"
  exit_sys=$?

  # Check exit code
  if [ "$exit_my" -ne "$exit_sys" ]; then
    fail "$name (exit code mismatch: expected $exit_sys, got $exit_my)"
    return 1
  fi

  # Check standard output bytes
  if ! cmp -s "$TEST_DIR/my.stdout" "$TEST_DIR/sys.stdout"; then
    fail "$name (stdout mismatch)"
    return 1
  fi

  # Check standard error presence matches
  if [ -s "$TEST_DIR/sys.stderr" ] && [ ! -s "$TEST_DIR/my.stderr" ]; then
    fail "$name (expected error on stderr, but got none)"
    return 1
  elif [ ! -s "$TEST_DIR/sys.stderr" ] && [ -s "$TEST_DIR/my.stderr" ]; then
    fail "$name (unexpected error on stderr: '$(cat "$TEST_DIR/my.stderr")')"
    return 1
  fi

  # Validate generated/modified files
  i=1
  while [ $i -le 2 ]; do
    if printf '%s' "$*" | grep -q "my_out_${i}.txt"; then
      if ! cmp -s "$TEST_DIR/my_out_${i}.txt" "$TEST_DIR/sys_out_${i}.txt"; then
        fail "$name (file output mismatch on target $i)"
        return 1
      fi
    fi
    i=$((i + 1))
  done

  pass "$name"
}

#
# Basic operations (Overwrite / Default mode)
#

reset_targets
check_tee "single file output" "$TEST_DIR/my_out_1.txt" <<EOF
Hello through custom tee
EOF

reset_targets
check_tee "multiple file outputs" "$TEST_DIR/my_out_1.txt" "$TEST_DIR/my_out_2.txt" <<EOF
Streaming to multiple destinations
EOF

reset_targets "prefill"
check_tee "default truncation behavior" "$TEST_DIR/my_out_1.txt" <<EOF
Fresh contents overwriting the old line
EOF

#
# POSIX Flags & Special Targets
#

reset_targets "prefill"
check_tee "append flag (-a)" "-a" "$TEST_DIR/my_out_1.txt" "$TEST_DIR/my_out_2.txt" <<EOF
This string should sit underneath the pre-existing text
EOF

reset_targets
check_tee "ignore interrupts flag parsing (-i)" "-i" "$TEST_DIR/my_out_1.txt" <<EOF
Parsing check for signal intercept configurations
EOF

reset_targets
check_tee "combined flags (-ai)" "-ai" "$TEST_DIR/my_out_1.txt" <<EOF
Evaluating clustered standard argument parsing strings
EOF

#
# Error Boundaries
#

reset_targets
check_tee "non-existent folder directory error path" "$TEST_DIR/nonexistent_folder/file.txt" <<EOF
Data drops out to stdout but file creation triggers an expected runtime failure
EOF

#
# Summary
#

printf '\n'
printf '%d passed, %d failed\n' "$pass" "$fail"

[ "$fail" -eq 0 ]
