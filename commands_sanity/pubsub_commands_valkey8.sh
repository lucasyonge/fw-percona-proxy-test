#!/bin/bash
# shellcheck disable=SC2059,SC2089,SC2090
# shellcheck disable=SC2317
# shellcheck disable=SC2086
# shellcheck disable=SC2329
VALKEY_HOST="${VALKEY_HOST:-localhost}"
VALKEY_PORT="${VALKEY_PORT:-7777}"
VALKEY_PASSWORD="${VALKEY_PASSWORD:-}"

CONN_OPTS=(-h "$VALKEY_HOST" -p "$VALKEY_PORT" -d '\n' --no-auth-warning --raw)
if [[ -n "$VALKEY_PASSWORD" ]]; then
    CONN_OPTS+=(-a "$VALKEY_PASSWORD")
fi
script_dir=$(dirname "${BASH_SOURCE[0]}")
script_name="${0##*/}"
TEST_CASES_FILE="${script_dir}/data/${script_name/.sh/.csv}"
TEST_CASES_FILE_2="${TEST_CASES_FILE/_valkey8/}"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Function to execute Valkey commands
valkey_cmd() {
    valkey-cli -e "${CONN_OPTS[@]}" "$@" 2>&1
}

# Function for background SUBSCRIBE/PSUBSCRIBE (no filtering to preserve streaming output)
# Use stdbuf to disable buffering so output appears immediately in log files
valkey_subscribe() {
    timeout 5 stdbuf -oL -eL valkey-cli "${CONN_OPTS[@]}" "$@" 2>&1
}
test_command() {
    test_case="${1:?"function invoked without specifying test case"}"
    cmd="$(echo "${test_case}" | cut -d '|' -f1)"
    expected_output="$(echo "${test_case}" | cut -d '|' -f2)"
    check_error_code="$(echo "${test_case}" | cut -d '|' -f3)"
    ignore="$(echo "${test_case}" | cut -d '|' -f4)"
    printf "$(date) : =======================================\n"
    printf "$(date) : Running Test Case ${MAGENTA}${cmd}${NC}\n"
    printf "$(date) : Checking Command Error Code? ${GREEN}$(if [[ ${check_error_code} == 1 ]]; then printf "true"; else printf "false"; fi)${NC}\n"

    CLI="valkey_cmd"
    if [[ "${cmd}" == *SUBSCRIBE* ]]; then
        CLI="valkey_subscribe"
    fi
    if [[ "${ignore}" == "1" ]]; then
        echo "$(date) : Test case skipped!"
        return 0
    fi
    if [[ "${check_error_code}" == "1" ]]; then
        if output="$($CLI ${cmd})"; then
            echo "$(date) : PASSED : ✅ Command successful"
        else
            echo "$(date) : FAILED : ❌ Unexpected result: '${output}'"
            export ERROR_CNT=$((ERROR_CNT + 1))
        fi
    else
        output="$($CLI ${cmd})"
        if [[ "${output}" == "${expected_output}" ]]; then
            echo "$(date) : PASSED : ✅ Command successful"
        else
            echo "$(date) : FAILED : ❌ Unexpected result: ${output}"
            echo "$(date) : Expected : ${expected_output}"
            export ERROR_CNT=$((ERROR_CNT + 1))
        fi
    fi
}

grep -vE '^#' "$TEST_CASES_FILE" | while read -r line; do
    test_command "${line}"
done
