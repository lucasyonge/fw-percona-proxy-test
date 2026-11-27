#!/bin/bash
# shellcheck disable=SC1083,SC2086,SC2181
start_time=$(date +%s)
PROXY_HOST=localhost
PROXY_PORT="${PROXY_PORT:-7777}"
VALKEY_CMD="valkey-cli -h ${PROXY_HOST} -p ${PROXY_PORT} --no-auth-warning --raw"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

function log_result() {
    CUR_TIME="$(date)"
    case "${1}" in
    FAILED*)
        printf "${CUR_TIME} : ${RED}$1${NC}\n"
        ;;
    PASSED*)
        printf "${CUR_TIME} : ${GREEN}$1${NC}\n"
        ;;
    INFO*)
        printf "${CUR_TIME} : ${YELLOW}$1${NC}\n"
        ;;
    esac
}
# Display the set contents
function display_set_members() {
    log_result "INFO : $1 set members are listed below"
    ${VALKEY_CMD} smembers $2 2>/dev/null | grep -v option
}

# For calculating the script execution time
function time_calculation() {
    end_time=$(date +%s)
    total_time_in_secs=$((end_time - start_time))
    seconds=${total_time_in_secs}
    hours=$((seconds / 3600))
    minutes=$(((seconds % 3600) / 60))
    seconds=$((seconds % 60))
    printf "Total script execution time is (HH:MM:SS) - %02d:%02d:%02d\n" "$hours" "$minutes" "$seconds"
}

# NEW: Test SET IFEQ command (Valkey 8 feature)
function test_set_ifeq() {
    log_result "INFO : Testing SET command with IFEQ argument (Valkey 8 feature)..."
    ${VALKEY_CMD} del {key}version 2>/dev/null | grep -v option
    ${VALKEY_CMD} set {key}version "v1" 2>/dev/null 1>&2
    if [[ $? != 0 ]]; then
        log_result "FAILED : Failed to set initial value. Exiting."
        time_calculation
        exit 1
    fi
    log_result "INFO : Initial value v1 set successfully."
    # Test successful IFEQ update
    ${VALKEY_CMD} set {key}version "v2" IFEQ "v1" 2>/dev/null 1>&2
    if [[ $? != 0 ]]; then
        log_result "FAILED : SET IFEQ should have succeeded. Exiting."
        time_calculation
        exit 1
    fi
    log_result "PASSED : SET IFEQ succeeded when value matches."
    # Test failed IFEQ update
    ${VALKEY_CMD} set {key}version "v3" IFEQ "v1" 2>/dev/null 1>&2
    if [[ $? != 0 ]]; then
        log_result "FAILED : SET IFEQ should have failed but didn't. Exiting."
        time_calculation
        exit 1
    fi

    log_result "PASSED : SET IFEQ correctly failed when value doesn't match."
    # Verify value is still v2
    result="$(${VALKEY_CMD} get {key}version)"
    if [[ "${result}" != "v2" ]]; then
        log_result "FAILED : Value not preserved after failed IFEQ. Exiting."
        time_calculation
        exit 1
    fi
    log_result "PASSED : SET IFEQ validation complete."

}

# NEW: Test MULTI/WATCH nested calls that should abort (Valkey 8 breaking change)
function test_multi_watch_nested() {
    log_result "INFO : Testing MULTI nested calls (Valkey 8 breaking change)..."
    # Send both MULTI commands in a single valkey-cli session to test nesting
    result="$(printf 'MULTI\r\nMULTI\r\nEXEC' | $VALKEY_CMD)"
    # Filter out kubectl and valkey-cli noise, keep only error line
    filtered_result=$(echo "$result" | grep -v "Defaulted container" | grep -v "option" | grep -v "Warning")
    if echo "$filtered_result" | grep -q "MULTI calls can not be nested"; then
        log_result "PASSED : Nested MULTI correctly rejected in Valkey 8."
    else
        log_result "FAILED : Nested MULTI should be rejected in Valkey 8. Got: $filtered_result"
        time_calculation
        exit 1
    fi
    log_result "INFO : Testing WATCH inside MULTI (Valkey 8 breaking change)..."
    # Send MULTI and WATCH in a single valkey-cli session
    result="$(printf 'multi\r\nwatch {key}test\r\ndiscard' | $VALKEY_CMD)"
    # Filter out kubectl noise
    filtered_result=$(echo "$result" | grep -v "Defaulted container" | grep -v "option" | grep -v "Warning")

    if echo "$filtered_result" | grep -q "ERR WATCH inside MULTI is not allowed"; then
        log_result "PASSED : WATCH inside MULTI correctly rejected in Valkey 8."
    else
        log_result "FAILED : WATCH inside MULTI should be rejected in Valkey 8. Got: $filtered_result"
        time_calculation
        exit 1
    fi
}

# NEW: Test SCAN with invalid TYPE returns error (Valkey 8 breaking change)
function test_scan_invalid_type() {
    log_result "INFO : Testing SCAN with invalid TYPE (Valkey 8 breaking change)..."
    ${VALKEY_CMD} scan 0 TYPE "faketype" 2>/dev/null | grep -v option | grep -q "ERR unknown type name"
    if [[ $? -eq 0 ]]; then
        log_result "PASSED : SCAN with invalid TYPE returns error in Valkey 8."
    else
        log_result "FAILED : SCAN should return error for invalid TYPE in Valkey 8. Exiting."
        time_calculation
        # exit 1
    fi
}

# NEW: Test BITCOUNT/BITPOS error handling for non-existing keys (Valkey 8 breaking change)
function test_bitcount_bitpos_errors() {
    log_result "INFO : Testing BITCOUNT/BITPOS error handling (Valkey 8 breaking change)..."
    # delete key before continuing
    ${VALKEY_CMD} del {key}nonexistent 2>/dev/null 1>&2

    # Test BITPOS with invalid arguments
    res="$(${VALKEY_CMD} bitpos {key}nonexistent 0 0 1 hello)"
    if [[ "${res}" == ERR* ]]; then
        log_result "PASSED : BITPOS returns error for invalid arguments in Valkey 8."
    else
        log_result "FAILED : BITPOS should return error for invalid arguments. Exiting."
        time_calculation
        exit 1
    fi

    # Test BITCOUNT with invalid arguments
    ${VALKEY_CMD} bitcount {key}nonexistent 0 asd 2>/dev/null | grep -v option | grep -q "ERR value is not an integer or out of range"
    if [[ $? -eq 0 ]]; then
        log_result "PASSED : BITCOUNT returns error for invalid arguments in Valkey 8."
    else
        log_result "FAILED : BITCOUNT should return error for invalid arguments. Exiting."
        time_calculation
        exit 1
    fi

    # Test BITCOUNT argument validation before key check
    ${VALKEY_CMD} bitcount {key}no-key invalid1 invalid2 2>/dev/null | grep -v option | grep -q "ERR value is not an integer or out of range"
    if [[ $? -eq 0 ]]; then
        log_result "PASSED : BITCOUNT validates arguments before key existence in Valkey 8."
    else
        log_result "FAILED : BITCOUNT should validate arguments first. Exiting."
        time_calculation
        exit 1
    fi
}

# NEW: Test BGSAVE CANCEL command (Valkey 8 feature)
function test_bgsave_cancel() {
    log_result "INFO : Testing BGSAVE CANCEL command (Valkey 8 feature)..."
    # Note: In a test environment, we can't really trigger a long-running BGSAVE
    # So we just test that the command is recognized
    RES="$(${VALKEY_CMD} bgsave cancel 2>/dev/null)"
    # Command should either succeed (OK) or return an error that there's no save in progress
    if [[ ${RES} == ERR* ]]; then
        log_result "FAILED : ${RES}"
    else
        log_result "PASSED : BGSAVE CANCEL command is recognized in Valkey 8."
    fi
}

# NEW: Test CLIENT KILL MAXAGE command (Valkey 8 feature)
function test_client_kill_maxage() {
    log_result "INFO : Testing CLIENT KILL MAXAGE command (Valkey 8 feature)..."
    # Kill clients older than 3600 seconds
    RES="$(${VALKEY_CMD} client kill MAXAGE 3600 2>/dev/null)"
    if [[ "${RES}" == ERR* ]]; then
        log_result "FAILED : ${RES}"
    else
        log_result "PASSED : CLIENT KILL MAXAGE command works in Valkey 8."
    fi
}

# NEW: Test CLIENT LIST with additional filters (Valkey 8 feature)
function test_client_list_filters() {
    log_result "INFO : Testing CLIENT LIST with new filters (Valkey 8 feature)..."
    # Test SKIPME YES filter
    cmd='CLIENT INFO\r\nCLIENT LIST SKIPME YES'
    result="$(printf "%s" "$cmd" | $VALKEY_CMD)"
    client_info_me="$(echo "${result}" | head -n 1)"
    client_info_me_count="$(echo "${result}" | grep -c "${client_info_me}")"
    if [[ "${client_info_me_count}" -eq 1 ]]; then
        log_result "PASSED : CLIENT LIST SKIPME filter works in Valkey 8."
    else
        log_result "FAILED : CLIENT LIST SKIPME filter failed. Exiting."
        time_calculation
        exit 1
    fi

    # Test MAXAGE filter
    result="$(${VALKEY_CMD} client list MAXAGE 60)"
    if [[ "${result}" == ERR* ]]; then
        log_result "FAILED : CLIENT LIST MAXAGE filter failed. Exiting."
        time_calculation
        exit 1
    else
        log_result "PASSED : CLIENT LIST MAXAGE filter works in Valkey 8."
    fi
}

# NEW: Valkey 8 specific tests
function valkey8_new_features() {
    test_set_ifeq
    test_multi_watch_nested
    test_scan_invalid_type
    test_bitcount_bitpos_errors
    test_bgsave_cancel
    test_client_kill_maxage
    test_client_list_filters
}

#MAIN
${VALKEY_CMD} flushall SYNC 2>/dev/null | grep -v option | grep -wq OK
valkey8_new_features
${VALKEY_CMD} flushall SYNC 2>/dev/null | grep -v option | grep -wq OK
time_calculation
