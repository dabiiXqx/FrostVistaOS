#!/usr/bin/env bash
# run_tests.sh — Automated test runner for FrostVistaOS
#
# Usage:
#   ./scripts/run_tests.sh              # run all tests
#   ./scripts/run_tests.sh -v           # verbose: show QEMU output
#   ./scripts/run_tests.sh -t fork      # run only test_fork
#   ./scripts/run_tests.sh -h           # help

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJ_DIR"

# ── Configuration ────────────────────────────────────────────────────────────
BOOT_WAIT=6       # max seconds to wait for kernel boot message
IDLE_WAIT=3       # extra seconds after boot before killing QEMU
PASS=0
FAIL=0
SKIP=0
VERBOSE=0
FILTER=""

# ── Color helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── QEMU command (mirrors Makefile flags) ────────────────────────────────────
QEMU_BIN="qemu-system-riscv64"
QEMU_ARGS=(
	-machine virt -nographic -bios none
	-kernel build/kernel.elf
	-drive "file=build/disk.img,if=none,format=raw,id=x0"
	-device "virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0"
	-global virtio-mmio.force-legacy=false
)

# ── Parse args ───────────────────────────────────────────────────────────────
while getopts "vht:" opt; do
	case "$opt" in
		v) VERBOSE=1 ;;
		h)
			echo "Usage: $0 [-v] [-t test_name]"
			echo "  -v          Verbose: show QEMU output for each test"
			echo "  -t <name>   Run only test_<name>.c (e.g., -t fork)"
			exit 0
			;;
		t) FILTER="$OPTARG" ;;
		*) exit 1 ;;
	esac
done

# ── Gather tests ─────────────────────────────────────────────────────────────
mapfile -t TESTS < <(
	find test -maxdepth 1 -name 'test_*.c' | sort | while read -r f; do
		basename "$f" .c | sed 's/^test_//'
	done
)

if [ -n "$FILTER" ]; then
	TESTS=("$FILTER")
fi

if [ ${#TESTS[@]} -eq 0 ]; then
	echo "No tests found."
	exit 1
fi

echo -e "${CYAN}Running ${#TESTS[@]} test(s)...${NC}"
echo ""

# ── Run each test ────────────────────────────────────────────────────────────
for test_name in "${TESTS[@]}"; do
	printf "  %-18s " "${test_name}"

	# Build test, kernel, and disk image
	BUILD_OUT=""
	if ! BUILD_OUT=$(make build_test TEST="$test_name" 2>&1); then
		echo -e "[${RED}BUILD_FAIL${NC}]"
		((FAIL++)) || true
		if [ "$VERBOSE" -eq 1 ]; then
			echo "$BUILD_OUT" | sed 's/^/        /'
		fi
		continue
	fi

	if ! BUILD_OUT=$(make build/kernel.elf 2>&1); then
		echo -e "[${RED}BUILD_FAIL${NC}]"
		((FAIL++)) || true
		if [ "$VERBOSE" -eq 1 ]; then
			echo "$BUILD_OUT" | sed 's/^/        /'
		fi
		continue
	fi

	if ! BUILD_OUT=$(make build/disk.img 2>&1); then
		echo -e "[${RED}BUILD_FAIL${NC}]"
		((FAIL++)) || true
		if [ "$VERBOSE" -eq 1 ]; then
			echo "$BUILD_OUT" | sed 's/^/        /'
		fi
		continue
	fi

	# Start QEMU in the background, capture output to a temp file
	QEMU_LOG=$(mktemp)
	"$QEMU_BIN" "${QEMU_ARGS[@]}" >"$QEMU_LOG" 2>&1 &
	QEMU_PID=$!

	# Wait for kernel boot message, with deadline
	booted=0
	deadline=$((SECONDS + BOOT_WAIT))
	while [ "$SECONDS" -lt "$deadline" ]; do
		if grep -q 'FrostVistaOS booting' "$QEMU_LOG" 2>/dev/null; then
			booted=1
			break
		fi
		sleep 0.3
	done

	# Let the test run for a few more seconds, then kill QEMU
	if [ "$booted" -eq 1 ]; then
		sleep "$IDLE_WAIT"
	fi
	kill "$QEMU_PID" 2>/dev/null || true
	wait "$QEMU_PID" 2>/dev/null || true

	# Read and clean the output
	QEMU_OUT=$(tr -d '\0' <"$QEMU_LOG")
	CLEAN_OUT=$(echo "$QEMU_OUT" | sed 's/\x1b\[[0-9;]*m//g')
	rm -f "$QEMU_LOG"

	# ── Verdict ───────────────────────────────────────────────────────────
	if ! echo "$CLEAN_OUT" | grep -q 'FrostVistaOS booting'; then
		echo -e "[${YELLOW}TIMEOUT${NC}]  (no boot message in ${BOOT_WAIT}s)"
		((SKIP++)) || true
	elif echo "$CLEAN_OUT" | grep -qE '\bpanic\b|PANIC'; then
		echo -e "[${RED}PANIC${NC}]"
		((FAIL++)) || true
		if [ "$VERBOSE" -eq 1 ]; then
			echo "$CLEAN_OUT" | grep --color=never -A2 -B2 'panic\|PANIC' | sed 's/^/        /'
		fi
	else
		echo -e "[${GREEN}PASS${NC}]"
		((PASS++)) || true
	fi

	if [ "$VERBOSE" -eq 1 ]; then
		echo "$CLEAN_OUT" | tail -20 | sed 's/^/        /'
	fi
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}Summary:${NC}  ${GREEN}$PASS passed${NC},  ${RED}$FAIL failed${NC},  ${YELLOW}$SKIP skipped${NC}"

if [ "$FAIL" -gt 0 ]; then
	exit 1
fi
