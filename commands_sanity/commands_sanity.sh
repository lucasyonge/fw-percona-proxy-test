#!/bin/bash
# shellcheck disable=SC1083
start_time=$(date +%s)
PROXY_HOST="${PROXY_HOST:-localhost}"
PROXY_PORT="${PROXY_PORT:-7777}"
VALKEY_CMD="valkey-cli -c -h ${PROXY_HOST} -p ${PROXY_PORT} --no-auth-warning --raw"
EXIT_ON_ERROR=0

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
    FAILED* | ERROR*) COLOR=$RED ;;
    PASSED*)
        COLOR=$GREEN
        ;;
    INFO*)
        COLOR=$YELLOW
        ;;
    DEBUG*)
        COLOR=$DIM
        ;;
    esac
    printf "${CUR_TIME} : ${COLOR}$1${NC}\n"
}

# Display the set contents
function display_set_members() {
    log_result "INFO : $1 set members are listed below"
    ${VALKEY_CMD} -d ' ' smembers $2 2>/dev/null | grep -v option
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

# Create couple of sample sets for testing set commands
function create_sets() {
    ODD_ARR=(1 3 5 7 9)
    PRIME_ARR=(2 3 5 7 11)
    ${VALKEY_CMD} del {set}.odd {set}.prime {set}.inter 2>/dev/null 1>&2
    ${VALKEY_CMD} sadd {set}.odd ${ODD_ARR[*]} 2>/dev/null | grep -v option | grep -q 5
    ORV=$?
    ${VALKEY_CMD} sadd {set}.prime ${PRIME_ARR[*]} 2>/dev/null | grep -v option | grep -q 5
    PRV=$?
    if [[ ${ORV} -eq 0 ]] && [[ ${PRV} -eq 0 ]]; then
        log_result "INFO : Both sample sets are created. SADD and DEL commands are verified successfully."
        for set_name in "odd" "prime"; do
            display_set_members ${set_name} "{set}.${set_name}"
        done
    else
        log_result "ERROR : Failed to create sets : ${ORV},${PRV}. Exiting."
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

# Function to validate union of 2 sets
function set_union() {
    RES=$(${VALKEY_CMD} sunion {set}.odd {set}.prime 2>/dev/null | grep -v option | egrep -v "1|2|3|5|7|9|11" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]; then
        log_result "PASSED : Set union (SUNION) verified successfully."
    else
        log_result "FAILED : Validation failed for set union(sunion) (${RES}). Exiting."
        ${VALKEY_CMD} sunion {set}.odd {set}.prime 2>/dev/null | grep -v option
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    ${VALKEY_CMD} sunionstore {set}.union {set}.odd {set}.prime 2>/dev/null | grep -v option >/dev/null 2>&1
    RES=$(${VALKEY_CMD} smembers {set}.union 2>/dev/null | grep -v option | egrep -v "1|2|3|5|7|9|11" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]; then
        log_result "PASSED : Set union (SUNIONSTORE) verified successfully."
        display_set_members "union" "{set}.union"
    else
        log_result "FAILED : Validation failed for storing set union(sunionstore) (${RES}). Exiting."
        ${VALKEY_CMD} sunion {set}.odd {set}.prime 2>/dev/null | grep -v option
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

# Function to validate intersection of 2 sets and storing in another set as well
function set_intersection() {
    RES=$(${VALKEY_CMD} sinter {set}.odd {set}.prime 2>/dev/null | grep -v option | egrep -v "3|5|7" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]; then
        log_result "PASSED : Set intersection (SINTER) verified successfully."
    else
        log_result "FAILED : Validation failed for set intersection(sinter) (${RES}). Exiting."
        ${VALKEY_CMD} sinter {set}.odd {set}.prime 2>/dev/null | grep -v option
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    ${VALKEY_CMD} sinterstore {set}.inter {set}.odd {set}.prime 2>/dev/null | grep -v option >/dev/null 2>&1
    RES=$(${VALKEY_CMD} smembers {set}.inter 2>/dev/null | grep -v option | egrep -v "3|5|7" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]; then
        log_result "PASSED : Set intersection (SINTERSTORE) verified successfully."
        display_set_members "intersected" "{set}.inter"
    else
        log_result "FAILED : Validation failed for storing set intersection(sinterstore) (${RES}). Exiting."
        ${VALKEY_CMD} sinter {set}.odd {set}.prime 2>/dev/null | grep -v option
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

# Function to validate difference between 2 sets
function set_diff() {
    RES=$(${VALKEY_CMD} sdiff {set}.prime {set}.odd 2>/dev/null | grep -v option | egrep -vw "2|11" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]; then
        log_result "PASSED : Set difference (SDIFF) verified successfully."
    else
        log_result "FAILED : Validation failed for set difference(sdiff) (${RES}). Exiting."
        ${VALKEY_CMD} sdiff {set}.prime {set}.odd 2>/dev/null | grep -v option
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    ${VALKEY_CMD} sdiffstore {set}.diff {set}.odd {set}.prime 2>/dev/null | grep -v option >/dev/null 2>&1
    RES=$(${VALKEY_CMD} smembers {set}.diff 2>/dev/null | grep -v option | egrep -v "1|9" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]; then
        log_result "PASSED : Set difference (SDIFFSTORE) verified successfully."
        display_set_members "difference" "{set}.diff"
    else
        log_result "FAILED : Validation failed for storing set diff(sdiffstore) (${RES}). Exiting."
        ${VALKEY_CMD} sdiff {set}.odd {set}.prime 2>/dev/null | grep -v option
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

# Function to validate the existence of an element(s) in a set
function set_membership() {
    RES1=$(${VALKEY_CMD} sismember {set}.union 1 2>/dev/null | grep -v option | awk '{print $NF}' | egrep -w "1" | wc -l | sed 's/ //g')
    RES2=$(${VALKEY_CMD} sismember {set}.union -1 2>/dev/null | grep -v option | awk '{print $NF}' | egrep -w "0" | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]]; then
        log_result "PASSED : Set member command (SISMEMBER) verified successfully."
    else
        log_result "FAILED : Validation failed for set member (SISMEMBER) (${RES1} and ${RES2}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    RES1=$(${VALKEY_CMD} smismember {set}.union 1 -1 3 5 100 2>/dev/null | grep -v option | awk '{print $NF}' | egrep -w "1" | wc -l | sed 's/ //g')
    RES2=$(${VALKEY_CMD} smismember {set}.union 1 -1 3 5 100 2>/dev/null | grep -v option | awk '{print $NF}' | egrep -w "0" | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 3 ]] && [[ ${RES2} -eq 2 ]]; then
        log_result "PASSED : Multiple set member command (SMISMEMBER) verified successfully."
    else
        log_result "FAILED : Validation failed for multiple set members(smismember) (${RES1} and ${RES2}). Exiting."
        ${VALKEY_CMD} smismember {set}.union 1 -1 3 5 100 2>/dev/null | grep -v option
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

# All commands related to sets
function set_operations() {
    create_sets
    set_union
    set_intersection
    set_diff
    set_membership
}

# Function to display zset elements
function display_zset_members() {
    log_result "INFO : $1 zset members withscores are listed below"
    ${VALKEY_CMD} -d ' ' zrange $2 0 -1 withscores 2>/dev/null | grep -v option
}

# Create 2 sorted sets of odd and prime number
function create_zsets() {
    ODD_ZSET=(1 one 3 three 5 five 7 seven 9 nine)
    PRIME_ZSET=(2 two 3 three 5 five 7 seven 11 eleven)
    ${VALKEY_CMD} del {zset}.odd {zset}.prime 2>/dev/null | grep -v option
    ${VALKEY_CMD} zadd {zset}.odd ${ODD_ZSET[*]} 2>/dev/null | grep -v option | grep -q 5
    ORV=$?
    ${VALKEY_CMD} zadd {zset}.prime ${PRIME_ZSET[*]} 2>/dev/null | grep -v option | grep -q 5
    PRV=$?
    if [[ ${ORV} -eq 0 ]] && [[ ${PRV} -eq 0 ]]; then
        log_result "INFO : Both sample sorted sets are created. zadd and del commands are verified successfully."
        for zset_name in "odd" "prime"; do
            display_zset_members ${zset_name} "{zset}.${zset_name}"
        done
    else
        log_result "ERROR : Failed to create sets : ${ORV},${PRV}. Exiting."
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

# Function to validate union of 2 sorted sets with their scores and storing them in a different sorted set
function zset_union() {
    RES=$(${VALKEY_CMD} zunion 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option | egrep -vw "1|2|6|9|10|11|14|one|two|three|five|seven|nine|eleven" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]; then
        log_result "PASSED : Sorted set union (ZUNION) verified successfully."
    else
        log_result "FAILED : Validation failed for sorted set union(zunion) (${RES}). Exiting."
        ${VALKEY_CMD} zunion 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    ${VALKEY_CMD} zunionstore {zset}.zunion 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option >/dev/null 2>&1
    RES=$(${VALKEY_CMD} zrange {zset}.zunion 0 -1 withscores 2>/dev/null | grep -v option | egrep -vw "1|2|6|9|10|11|14|one|two|three|five|seven|nine|eleven" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]; then
        log_result "PASSED : Storing sorted set union (ZUNIONSTORE) verified successfully."
        display_zset_members "union" "{zset}.zunion"
    else
        log_result "FAILED : Validation failed for storing sorted set union(zunionstore) (${RES}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

# Function to validate intersection of 2 sorted sets with their scores and storing them in a different sorted set
function zset_inter() {
    RES=$(${VALKEY_CMD} zinter 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option | egrep -v "6|10|14|three|five|seven" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]; then
        log_result "PASSED : Sorted set intersection (ZINTER) verified successfully."
    else
        log_result "FAILED : Validation failed for sorted set intersection(zinter) (${RES}). Exiting."
        ${VALKEY_CMD} zinter 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    ${VALKEY_CMD} zinterstore {zset}.zinter 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option >/dev/null 2>&1
    RES=$(${VALKEY_CMD} zrange {zset}.zinter 0 -1 withscores 2>/dev/null | grep -v option | egrep -v "6|10|14|three|five|seven" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]; then
        log_result "PASSED : Storing sorted set intersection (ZINTERSTORE) verified successfully."
        display_zset_members "intersected" "{zset}.zinter"
    else
        log_result "FAILED : Validation failed for storing sorted set intersection(zinterstore) (${RES}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

# Function to validate difference of 2 sorted sets with their scores and storing them in a different sorted set
function zset_diff() {
    RES=$(${VALKEY_CMD} zdiff 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option | egrep -v "one|nine" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]; then
        log_result "PASSED : Sorted set difference (ZDIFF) verified successfully."
    else
        log_result "FAILED : Validation failed for sorted set difference(zdiff) (${RES}). Exiting."
        ${VALKEY_CMD} zdiff 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    ${VALKEY_CMD} zdiffstore {zset}.zdiff 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option >/dev/null 2>&1
    RES=$(${VALKEY_CMD} zrange {zset}.zdiff 0 -1 withscores 2>/dev/null | grep -v option | egrep -vw "1|9|one|nine" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]; then
        log_result "PASSED : Storing sorted set difference (ZDIFFSTORE) verified successfully."
        display_zset_members "intersected" "{zset}.zinter"
    else
        log_result "FAILED : Validation failed for storing sorted set intersection(zinterstore) (${RES}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

# Function to validate other commands related to sorted sets with their scores
function zset_other() {
    MEM_VAL=$(${VALKEY_CMD} zrandmember {zset}.odd 2 2>/dev/null | grep -v option | sort | uniq | wc -l | sed 's/ //g')
    MEM=$(${VALKEY_CMD} zrandmember {zset}.odd 2>/dev/null | grep -v option | sort | uniq | sed 's/ //g')
    RES=$(${VALKEY_CMD} zrange {zset}.odd 0 -1 2>/dev/null | grep -v option | grep -w "${MEM}" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 1 ]] && [[ ${MEM_VAL} -eq 2 ]]; then
        log_result "PASSED : Fetching random member from sorted set (ZRANDMEMBER) verified successfully."
    else
        log_result "FAILED : Validation failed for random member fetch in sorted set(zrandmember) (${RES} and ${MEM_VAL}). Exiting."
        ${VALKEY_CMD} zrandmember {zset}.odd 2>/dev/null | grep -v option
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    ${VALKEY_CMD} zrangestore {zset}.zdest {zset}.odd 2 -1 2>/dev/null | grep -v option >/dev/null 2>&1
    RES=$(${VALKEY_CMD} zrange {zset}.zdest 0 -1 withscores 2>/dev/null | grep -v option | egrep -vw "5|7|9|five|seven|nine" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]; then
        log_result "PASSED : Storing part of sorted set in another sorted set (ZRANGESTORE) verified successfully."
        display_zset_members "store" "{zset}.zdest"
    else
        log_result "FAILED : Validation failed for storing a part of sorted set in another sorted set(zrangestore) (${RES}). Exiting."
        display_zset_members "store" "{zset}.zdest"
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    RES=$(${VALKEY_CMD} zmscore {zset}.odd one two three 2>/dev/null | grep -v option | grep -vE "^$" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 2 ]]; then
        log_result "PASSED : Fetching the member score in a sorted set (ZMSCORE) verified successfully."
        display_zset_members "store" "{zset}.zdest"
    else
        log_result "FAILED : Validation failed for fetching score for a member of sorted set (ZMSCORE) (${RES}). Exiting."
        ${VALKEY_CMD} zmscore {zset}.odd one two three 2>/dev/null | grep -v option
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

# Perform all sorted set operations
function zset_operations() {
    create_zsets
    zset_union
    zset_inter
    zset_diff
    zset_other
}

# To display the contents of the list
function display_list_members() {
    log_result "INFO : $1 list members are listed below"
    ${VALKEY_CMD} -d ' ' lrange $2 0 -1 2>/dev/null | grep -v option
}

# To create test lists
function create_lists() {
    ODD_ARR=(1 3 5 7 9)
    PRIME_ARR=(2 3 5 7 11)
    ${VALKEY_CMD} del {list}.odd {list}.prime 2>/dev/null | grep -v option
    ${VALKEY_CMD} lpush {list}.odd ${ODD_ARR[*]} 2>/dev/null | grep -v option | grep -q 5
    ORV=$?
    ${VALKEY_CMD} rpush {list}.prime ${PRIME_ARR[*]} 2>/dev/null | grep -v option | grep -q 5
    PRV=$?
    if [[ ${ORV} -eq 0 ]] && [[ ${PRV} -eq 0 ]]; then
        log_result "INFO : Both sample lists are created. lpush, rpush and del commands are verified successfully."
        for list_name in "odd" "prime"; do
            display_list_members ${list_name} "{list}.${list_name}"
        done
    else
        log_result "ERROR : Failed to create lists : ${ORV},${PRV}. Exiting."
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

# Pop min (first element) from sorted list
function zset_pop_min() {
    RES=$(${VALKEY_CMD} bzpopmin {zset}.odd 3 2>/dev/null | grep -v option | egrep -v "one|1|odd" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]; then
        log_result "PASSED : Popping the first element from sorted set (BZPOPMIN) verified successfully."
        display_zset_members "odd" "{zset}.odd"
    else
        log_result "FAILED : Validation failed for popping min element from sorted set(bzpopmin) (${RES}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

# Pop max (last element) from sorted list
function zset_pop_max() {
    RES=$(${VALKEY_CMD} bzpopmax {zset}.odd 3 2>/dev/null | grep -v option | egrep -v "nine|9|odd" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]; then
        log_result "PASSED : Popping the last element from sorted set (BZPOPMAX) verified successfully."
        display_zset_members "odd" "{zset}.odd"
    else
        log_result "FAILED : Validation failed for popping max element from sorted set(bzpopmax) (${RES}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

# Pop the first element of the list
function list_pop() {
    if [[ $1 == "left" ]]; then
        PUSH_CMD="lpush"
        POP_CMD="blpop"
    else
        PUSH_CMD="rpush"
        POP_CMD="brpop"
    fi
    ${VALKEY_CMD} del {list}.block 2>/dev/null | grep -v option
    ${VALKEY_CMD} ${PUSH_CMD} {list}.block 3 4 2>/dev/null | grep -v option | grep -q 2
    BRV=$?
    if [[ ${BRV} -eq 0 ]]; then
        log_result "INFO : Sample list created with 2 elements."
        display_list_members "block" "{list}.block"
    else
        log_result "ERROR : Failed to create a sample list with 2 elements : ${BRV}. Exiting."
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
    log_result "INFO : Running ${POP_CMD}"
    ${VALKEY_CMD} ${POP_CMD} {list}.block 0 2>/dev/null | grep -v option | grep -q 4
    if [[ $? -eq 0 ]]; then
        log_result "PASSED : ${POP_CMD} validation successful."
    else
        log_result "FAILED : ${POP_CMD} failed for list with 1 element. Exiting."
        display_list_members "block" "{list}.block"
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    TEMP_TEST_BLOCK_FILE="./test_block_cmd.log"
    rm -f ${TEMP_TEST_BLOCK_FILE}
    touch ${TEMP_TEST_BLOCK_FILE}
    log_result "INFO : Testing the blocking command with timeout."
    grep -qw "^$" ${TEMP_TEST_BLOCK_FILE}
    RVB=$?
    ${VALKEY_CMD} ${POP_CMD} {list}.block2 5 2>/dev/null >${TEMP_TEST_BLOCK_FILE}
    grep -qw "^$" ${TEMP_TEST_BLOCK_FILE}
    RVA=$?
    if [[ ${RVB} -eq 1 ]] && [[ ${RVA} -eq 0 ]]; then
        log_result "INFO : ${POP_CMD} command with specific timeout validated successfully."
        rm -f ${TEMP_TEST_BLOCK_FILE}
    else
        log_result "ERROR : Failed to validate the ${POP_CMD} with specific timeout value. (${RVB} and ${RVA}) Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

# Pop the last element of one list and push it into the second list
function right_pop_left_push_lmove() {
    log_result "INFO : Testing the brpoplpush command..."
    display_list_members "prime" "{list}.prime"
    display_list_members "odd" "{list}.odd"
    ${VALKEY_CMD} brpoplpush {list}.prime {list}.odd 4 2>/dev/null | grep -v option | grep -q 11
    if [[ $? -eq 0 ]]; then
        log_result "INFO : brpoplpush command executed successfully."
        RES=$(${VALKEY_CMD} lrange {list}.prime 0 -1 2>/dev/null | grep -v option | egrep -v "2|3|5|7" | wc -l | sed 's/ //g')
        if [[ ${RES} -eq 0 ]]; then
            log_result "PASSED : brpop on the prime list validated successfully as part of brpoplpush command."
            display_list_members "prime" "{list}.prime"
            RES=$(${VALKEY_CMD} lrange {list}.odd 0 -1 2>/dev/null | grep -v option | egrep -v "1|3|5|7|9|11" | wc -l | sed 's/ //g')
            if [[ ${RES} -eq 0 ]]; then
                log_result "PASSED : blpush on the odd list validated successfully as part of brpoplpush command."
                display_list_members "odd" "{list}.odd"
            else
                log_result "FAILED : Validation failed for blpush on the odd list as part of brpoplpush command (${RES}). Exiting."
                display_list_members "odd" "{list}.odd"
                display_list_members "prime" "{list}.prime"
                time_calculation
                if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
            fi
        else
            log_result "FAILED : Validation failed for brpop on the prime list as part of brpoplpush command (${RES}). Exiting."
            display_list_members "prime" "{list}.prime"
            display_list_members "odd" "{list}.odd"
            time_calculation
            if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
        fi
    else
        log_result "FAILED : brpoplpush command did not execute as expected. Exiting."
        display_list_members "prime" "{list}.prime"
        display_list_members "odd" "{list}.odd"
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    log_result "INFO : Testing the blmove command..."
    display_list_members "prime" "{list}.prime"
    display_list_members "odd" "{list}.odd"
    RES1=$(${VALKEY_CMD} blmove {list}.odd {list}.prime LEFT LEFT 4 2>/dev/null | grep -v option | grep -w 11 | wc -l | sed 's/ //g')
    RES2=$(${VALKEY_CMD} lrange {list}.prime 0 -1 2>/dev/null | grep -v option | head -1 | grep -w 11 | wc -l | sed 's/ //g')
    RES3=$(${VALKEY_CMD} lrange {list}.odd 0 -1 2>/dev/null | grep -v option | head -1 | grep -w 9 | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]] && [[ ${RES3} -eq 1 ]]; then
        log_result "INFO : blmove command executed successfully with LEFT LEFT option."
    else
        log_result "FAILED : blmove command failed while executing with LEFT LEFT option. Exiting."
        display_list_members "prime" "{list}.prime"
        display_list_members "odd" "{list}.odd"
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    RES1=$(${VALKEY_CMD} blmove {list}.odd {list}.prime LEFT RIGHT 4 2>/dev/null | grep -v option | grep -w 9 | wc -l | sed 's/ //g')
    RES2=$(${VALKEY_CMD} lrange {list}.prime 0 -1 2>/dev/null | grep -v option | tail -1 | grep -w 9 | wc -l | sed 's/ //g')
    RES3=$(${VALKEY_CMD} lrange {list}.odd 0 -1 2>/dev/null | grep -v option | head -1 | grep -w 7 | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]] && [[ ${RES3} -eq 1 ]]; then
        log_result "INFO : blmove command executed successfully with LEFT RIGHT option."
    else
        log_result "FAILED : blmove command failed while executing with LEFT RIGHT option. Exiting."
        display_list_members "prime" "{list}.prime"
        display_list_members "odd" "{list}.odd"
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    RES1=$(${VALKEY_CMD} blmove {list}.odd {list}.prime RIGHT LEFT 4 2>/dev/null | grep -v option | grep -w 1 | wc -l | sed 's/ //g')
    RES2=$(${VALKEY_CMD} lrange {list}.prime 0 -1 2>/dev/null | grep -v option | head -1 | grep -w 1 | wc -l | sed 's/ //g')
    RES3=$(${VALKEY_CMD} lrange {list}.odd 0 -1 2>/dev/null | grep -v option | tail -1 | grep -w 3 | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]] && [[ ${RES3} -eq 1 ]]; then
        log_result "INFO : blmove command executed successfully with RIGHT LEFT option."
    else
        log_result "FAILED : blmove command failed while executing with RIGHT LEFT option. Exiting."
        display_list_members "prime" "{list}.prime"
        display_list_members "odd" "{list}.odd"
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    RES1=$(${VALKEY_CMD} blmove {list}.odd {list}.prime RIGHT RIGHT 4 2>/dev/null | grep -v option | grep -w 3 | wc -l | sed 's/ //g')
    RES2=$(${VALKEY_CMD} lrange {list}.prime 0 -1 2>/dev/null | grep -v option | tail -1 | grep -w 3 | wc -l | sed 's/ //g')
    RES3=$(${VALKEY_CMD} lrange {list}.odd 0 -1 2>/dev/null | grep -v option | tail -1 | grep -w 5 | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]] && [[ ${RES3} -eq 1 ]]; then
        log_result "INFO : blmove command executed successfully with RIGHT RIGHT option."
    else
        log_result "FAILED : blmove command failed while executing with RIGHT RIGHT option. Exiting."
        display_list_members "prime" "{list}.prime"
        display_list_members "odd" "{list}.odd"
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function sort_list() {
    ${VALKEY_CMD} del {list}.mix 2>/dev/null | grep -v option
    ${VALKEY_CMD} lpush {list}.mix 4 three five 1 six
    display_list_members "mix" "{list}.mix"
    CNT=$(${VALKEY_CMD} sort {list}.mix alpha 2>/dev/null | egrep -v 'option|three|five|six|1|4' | wc -l)
    if [[ $CNT -eq 0 ]]; then
        log_result "PASSED : sort command validation in ascending order succeeded."
        ${VALKEY_CMD} sort {list}.mix alpha desc 2>/dev/null | tr '\n' ' ' | sed 's/ //g' | grep -wq threesixfive41
        if [[ $? -eq 0 ]]; then
            log_result "PASSED : sort command validation in descending order succeeded."
        else
            log_result "FAILED : Failed to validate sort command in descending order. Exiting."
            time_calculation
            #if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1;fi
        fi
    else
        log_result "FAILED : Failed to validate sort command in ascending order. Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function lpos_command() {
    ${VALKEY_CMD} del {list}.trial 2>/dev/null | grep -v option
    ${VALKEY_CMD} lpush {list}.trial 1 235 4 6 3 67 2 67 3 7 36 4
    display_list_members "trial" "{list}.trial"
    RES1=$(${VALKEY_CMD} lpos {list}.trial 3 2>/dev/null | grep -v option | awk '{print $NF}' | grep -c 3)
    RES2=$(${VALKEY_CMD} lpos {list}.trial 3 RANK -1 2>/dev/null | grep -v option | awk '{print $NF}' | grep -c 7)
    RES3=$(${VALKEY_CMD} lpos {list}.trial 3 COUNT 2 2>/dev/null | grep -v option | awk '{print $NF}' | grep -Ec "3|7")
    RES4=$(${VALKEY_CMD} lpos {list}.trial 3 COUNT 2 RANK -3 2>/dev/null | grep -v option | grep -c "^$")
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]] && [[ ${RES3} -eq 2 ]] && [[ ${RES4} -eq 1 ]]; then
        log_result "PASSED : lpos command validation succeeded."
    else
        log_result "FAILED : Failed to validate lpos command(${RES1},${RES2},${RES3},${RES4}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function validate_with_timeout_for_blocking_commands() {
    TIMEOUT=$1
    log_result "INFO : Validating ${BLK_CMD} with timeout value as ${TIMEOUT}"
    ${VALKEY_CMD} del {list}.block1 {list}.block2 2>/dev/null | grep -v option
    if [[ ${BLK_CMD} == "brpoplpush" ]]; then
        timeout --kill-after=1s 10s ${VALKEY_CMD} ${BLK_CMD} {list}.block1 {list}.block2 ${TIMEOUT} 2>/dev/null
        RET_VAL=$?
    elif [[ ${BLK_CMD} == "blmove" ]]; then
        timeout --kill-after=1s 10s ${VALKEY_CMD} ${BLK_CMD} {list}.block1 {list}.block2 LEFT RIGHT ${TIMEOUT} 2>/dev/null
        RET_VAL=$?
    else
        timeout --kill-after=1s 10s ${VALKEY_CMD} ${BLK_CMD} {list}.block1 ${TIMEOUT} 2>/dev/null
        RET_VAL=$?
    fi
    if [[ ${TIMEOUT} -eq 0 ]]; then
        if [[ ${RET_VAL} -eq 137 ]] || [[ ${RET_VAL} -eq 124 ]]; then
            log_result "PASSED : ${BLK_CMD} succeeded for en empty list and waited forever."
        else
            log_result "FAILED : ${BLK_CMD} failed for an empty list without waiting forever. Exiting."
            time_calculation
            if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
        fi
    else
        if [[ ${RET_VAL} -ne 137 ]] && [[ ${RET_VAL} -ne 124 ]]; then
            log_result "PASSED : ${BLK_CMD} succeeded for en empty list and did not wait forever."
        else
            log_result "FAILED : ${BLK_CMD} failed for an empty list and waited forever. Exiting."
            time_calculation
            if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
        fi
    fi
}

# Perform all blocking command operations on sets and sorted sets
function blocking_list_operations() {
    create_lists
    list_pop "left"
    list_pop "right"
    zset_pop_min
    zset_pop_max
    right_pop_left_push_lmove
    sort_list
    lpos_command

    for BLK_CMD in blpop brpop bzpopmin bzpopmax blmove brpoplpush; do
        validate_with_timeout_for_blocking_commands 0
        #validate_with_timeout_for_blocking_commands 5
    done
}

function select_command() {
    ${VALKEY_CMD} select 0 2>/dev/null | grep -v option | grep -q OK
    if [[ $? -eq 0 ]]; then
        log_result "PASSED : select 0 succeeded."
    else
        log_result "FAILED : select 0 failed. Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function client_commands() {
    ${VALKEY_CMD} client setname 2>/dev/null | grep -v option | grep -q OK
    if [[ $? -eq 0 ]]; then
        log_result "FAILED : NULL value is set as client name. Exiting."
        #time_calculation
        #if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1;fi
    else
        log_result "PASSED : Failed to set null entry as client name."
    fi
}

function script_command() {
    SHA_VAL_KEYS=$(${VALKEY_CMD} script load "return KEYS[1]" 2>/dev/null | grep -v option | sed 's/ //g')
    SHA_VAL_ARGS=$(${VALKEY_CMD} script load "return ARGV[1]" 2>/dev/null | grep -v option | sed 's/ //g')
    if [[ $(echo ${SHA_VAL_KEYS} | wc -c) -eq 41 ]] && [[ $(echo ${SHA_VAL_ARGS} | wc -c) -eq 41 ]]; then
        log_result "INFO : SHA values generated successfully for script load of keys and args tables' function call."
        ${VALKEY_CMD} evalsha ${SHA_VAL_ARGS} 1 hello world 2>/dev/null | grep -v option | grep -q world
        if [[ $? -eq 0 ]]; then
            log_result "PASSED : evalsha on ARGS verified successfully."
            ${VALKEY_CMD} evalsha ${SHA_VAL_KEYS} 1 hello world 2>/dev/null | grep -v option | grep -q hello
            if [[ $? -eq 0 ]]; then
                log_result "PASSED : evalsha on KEYS verified successfully."
            else
                log_result "FAILED : Verification failed for evalsha on KEYS table. Exiting."
                time_calculation
                if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
            fi
        else
            log_result "FAILED : Verification failed for evalsha on ARGS table. Exiting."
            time_calculation
            if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
        fi
    else
        log_result "FAILED : Issue in generating SHA values for script load of keys and args tables' function call (${SHA_VAL_KEYS} and ${SHA_VAL_ARGS}). Exiting."
        time_calculation
        #if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1;fi
    fi

    SEV=$(${VALKEY_CMD} script exists ${SHA_VAL_KEYS} ${SHA_VAL_ARGS} 2>/dev/null | grep -v option | awk '{print $NF}' | grep 1 | wc -l)
    if [[ $SEV -eq 2 ]]; then
        log_result "PASSED : script exists command before flushing validated successfully."
    else
        log_result "FAILED : script exists command before flushing validation failed. Exiting."
        time_calculation
        #if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1;fi
    fi

    ${VALKEY_CMD} script flush SYNC 2>/dev/null | grep -v option | grep -q OK
    if [[ $? -eq 0 ]]; then
        log_result "PASSED : script cache flushed successfully."
        SEV=$(${VALKEY_CMD} script exists ${SHA_VAL_KEYS} ${SHA_VAL_ARGS} 2>/dev/null | grep -v option | awk '{print $NF}' | grep 0 | wc -l)
        if [[ $SEV -eq 2 ]]; then
            log_result "PASSED : script exists command after flushing validated successfully."
        else
            log_result "FAILED : script exists command after flushing validation failed. Exiting."
            time_calculation
            #if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1;fi
        fi
    else
        log_result "FAILED : Flushing of script cache failed. Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function scs_commands() {
    select_command
    client_commands
    script_command
}

function cluster_commands() {
    KST1=$(${VALKEY_CMD} cluster keyslot {test}1 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//g')
    KST2=$(${VALKEY_CMD} cluster keyslot {test}2 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//g')
    if [[ ${KST1} -eq ${KST2} ]] && [[ ${KST1} -eq 6918 ]]; then
        log_result "PASSED : Cluster keyslot command validated successfully."
    else
        log_result "FAILED : Cluster keyslot command validation failed(${KST1} and ${KST2}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    CSC="$(${VALKEY_CMD} --csv cluster slots | sed 's|,,|\n|g')"
    total_slots=0
    while read -r line; do
        i="$(echo "$line" | cut -d ',' -f1)"
        j="$(echo "$line" | cut -d ',' -f2)"
        let total_slots="$((total_slots + (j - i) + 1))"
        log_result "DEBUG : Total Slots:${total_slots}, i:$i , j:$j"
    done < <(echo "${CSC}")
    echo "${total_slots}"
    if [[ ${total_slots} -eq 16384 ]]; then
        log_result "PASSED : Cluster slots command validated successfully."
    else
        log_result "FAILED : Cluster slots command validation failed(${CSC[*]} and ${total_slots}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function string_commands() {
    ${VALKEY_CMD} set {strkey}sample "Hello Test" 2>/dev/null | grep -wq OK
    RES1=$(${VALKEY_CMD} substr {strkey}sample -4 -1 2>/dev/null | grep -v option | grep -w Test | wc -l | sed 's/ //g')
    RES2=$(${VALKEY_CMD} substr {strkey}sample 0 4 2>/dev/null | grep -v option | grep -w Hello | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]]; then
        log_result "PASSED : substr command validation succeeded."
    else
        log_result "FAILED : Failed to validate substr command(${RES1},${RES2}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    RES1=$(${VALKEY_CMD} getrange {strkey}sample -4 -1 2>/dev/null | grep -v option | grep -w Test | wc -l | sed 's/ //g')
    RES2=$(${VALKEY_CMD} getrange {strkey}sample 0 4 2>/dev/null | grep -v option | grep -w Hello | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]]; then
        log_result "PASSED : getrange command validation succeeded."
    else
        log_result "FAILED : Failed to validate getrange command(${RES1},${RES2}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    ${VALKEY_CMD} del {key}1 {key}2 {key}3 2>/dev/null | grep -v option
    ${VALKEY_CMD} set {key}1 value1 2>/dev/null | grep -v option | grep -q OK
    ${VALKEY_CMD} set {key}2 value2 2>/dev/null | grep -v option | grep -q OK
    ${VALKEY_CMD} renamenx {key}1 {key}2 2>/dev/null | grep -v option | grep -q 0
    RES1=$(${VALKEY_CMD} mget {key}1 {key}2 {key}3 2>/dev/null | grep -v option | head -2 | egrep -w "value1|value2" | wc -l | sed 's/ //g')
    ${VALKEY_CMD} renamenx {key}1 {key}3 2>/dev/null | grep -v option | grep -q 0
    RES2=$(${VALKEY_CMD} mget {key}1 {key}2 {key}3 2>/dev/null | grep -v option | tail -2 | egrep -w "value1|value2" | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 2 ]] && [[ ${RES2} -eq 2 ]]; then
        log_result "PASSED : renamenx command validation succeeded."
    else
        log_result "FAILED : Failed to validate renamenx command(${RES1},${RES2}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function validate_stream_commands() {
    if [[ $2 =~ $3 ]]; then
        log_result "PASSED : $1 command validation succeeded."
    else
        log_result "FAILED : Failed to validate $1 command($2,$3). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function xadd_xtrim_xdel() {
    log_result "INFO : Executing xadd command"
    #${VALKEY_CMD} flushall SYNC 2>/dev/null | grep -v option | grep -wq OK
    id1=$(${VALKEY_CMD} xadd test_stream \* sensor-id 1234 temperature 29.5 2>/dev/null | grep -v option)
    id2=$(${VALKEY_CMD} xadd test_stream \* sensor-id 1235 temperature 30.0 2>/dev/null | grep -v option)
    result=$(${VALKEY_CMD} XRANGE test_stream - + 2>/dev/null | grep -v option | sed 's/\r//g' | tr '\n' ' ' | sed 's/ //g' | sed 's/)//g' | sed 's/\"//g')
    #expected="11`echo $id1`21sensor-id212343temperature429.521`echo $id2`21sensor-id212353temperature430.0"
    expected=".*sensor.*"
    validate_stream_commands "xadd" ${result} ${expected}
    RES1="$(${VALKEY_CMD} xinfo stream test_stream | grep -A1 'length' | tail -1)"
    log_result "INFO : Executing xtrim command"
    ${VALKEY_CMD} xtrim test_stream MAXLEN 1 2>/dev/null | grep -v option | grep -q integer
    result=$(${VALKEY_CMD} xrange test_stream - + 2>/dev/null | grep -v option | sed 's/\r//g' | tr '\n' ' ' | sed 's/ //g' | sed 's/)//g' | sed 's/\"//g')
    #expected="11`echo $id2`21sensor-id212353temperature430.0"
    expected=".*sensor.*"
    validate_stream_commands "xtrim" ${result} ${expected}

    log_result "INFO : Executing xdel command"
    ${VALKEY_CMD} xdel test_stream "$id2" 2>/dev/null | grep -v option | grep -q integer
    result=$(${VALKEY_CMD} xrange test_stream - + 2>/dev/null | grep -v option | sed 's/\r//g' | tr '\n' ' ' | sed 's/ //g' | sed 's/)//g' | sed 's/\"//g')
    expected=""
    validate_stream_commands "xdel" ${result} ${expected}
}

function xinfo_xread() {
    log_result "INFO : Executing info command to validate the length and last-entry"
    id=$(${VALKEY_CMD} xadd test_stream \* sensor-id 1234 temperature 29.5 2>/dev/null | grep -v option)
    # there is only one message in stream since XDEL was executed
    RES1="$(${VALKEY_CMD} xinfo stream test_stream | grep -A1 'length' | tail -1)"
    RES2=$(${VALKEY_CMD} xinfo stream test_stream 2>/dev/null | grep -v option | grep "last-entry" -A1 | grep -c "$id" | sed 's/\r//g' | sed 's/\"//g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]]; then
        log_result "PASSED : xinfo command validation succeeded for stream."
    else
        log_result "FAILED : Failed to validate xinfo command for streams(${RES1},${RES2}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function xgroup_create() {
    log_result "INFO : Executing xgroup command to add test_stream to test_group."
    ${VALKEY_CMD} xgroup create test_stream test_group 0 2>/dev/null | grep -v option | grep -q OK
    if [[ $? -eq 0 ]]; then
        log_result "INFO : test_group created successfully and test_stream is added to it."
        RES=$(${VALKEY_CMD} xinfo groups test_stream 2>/dev/null | grep test_group)
        if [[ ${RES} == "test_group" ]]; then
            log_result "PASSED : xinfo command validation succeeded for group(xinfo groups)."
        else
            log_result "FAILED : Failed to validate xinfo command for group(${RES}). Exiting."
            time_calculation
            if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
        fi
    else
        log_result "FAILED : test_group creation failed. Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function xgroup_create_consumers() {
    log_result "INFO : Executing xgroup command to add test_consumers to test_group."
    ${VALKEY_CMD} xgroup createconsumer test_stream test_group test_consumer1 2>/dev/null | grep -v option | grep -q 1
    RES1=$?
    ${VALKEY_CMD} xgroup createconsumer test_stream test_group test_consumer2 2>/dev/null | grep -v option | grep -q 1
    RES2=$?
    ${VALKEY_CMD} xgroup createconsumer test_stream test_group test_consumer3 2>/dev/null | grep -v option | grep -q 1
    RES3=$?
    ${VALKEY_CMD} xgroup createconsumer test_stream test_group test_consumer2 2>/dev/null | grep -v option | grep -q 1
    RES4=$?
    if [[ ${RES1} -eq 0 ]] && [[ ${RES2} -eq 0 ]] && [[ ${RES3} -eq 0 ]] && [[ ${RES4} -ne 0 ]]; then
        log_result "INFO : test consumers created successfully and validation succeeded for xgroup createconsumers command."
        RES=$(${VALKEY_CMD} xinfo consumers test_stream test_group 2>/dev/null | grep -v option | egrep "test_consumer[1-3]" | wc -l | sed 's/ //g')
        if [[ ${RES} -eq 3 ]]; then
            log_result "PASSED : xinfo command validation succeeded for consumers(xinfo consumers)."
        else
            log_result "FAILED : Failed to validate xinfo command for consumers(${RES}). Exiting."
            time_calculation
            if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
        fi
    else
        log_result "FAILED : test_consumers addition failed. Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function xgroup_delete_consumer() {
    log_result "INFO : Executing xgroup command to delete test_consumer from test_group."
    RES1=$(${VALKEY_CMD} xinfo consumers test_stream test_group 2>/dev/null | grep -v option | grep -w "test_consumer3" | wc -l | sed 's/ //g')
    ${VALKEY_CMD} xgroup delconsumer test_stream test_group test_consumer3 2>/dev/null | grep -v option | grep -q integer
    RES2=$(${VALKEY_CMD} xinfo consumers test_stream test_group 2>/dev/null | grep -v option | grep -w "test_consumer3" | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 0 ]]; then
        log_result "PASSED : test consumer deleted successfully and validation succeeded for xgroup delconsumer command."
    else
        log_result "FAILED : test consumer deletion failed. Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function xgroup_setid() {
    log_result "INFO : Executing xgroup command to set id for the test_group."
    RES1=$(${VALKEY_CMD} xinfo groups test_stream 2>/dev/null | grep -v option | grep -w "4325" | wc -l | sed 's/ //g')
    ${VALKEY_CMD} xgroup setid test_stream test_group 4325 2>/dev/null | grep -v option | grep -q OK
    RES2=$?
    RES3=$(${VALKEY_CMD} xinfo groups test_stream 2>/dev/null | grep -v option | grep -w "4325" | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 0 ]] && [[ ${RES2} -eq 0 ]] && [[ ${RES3} -eq 1 ]]; then
        log_result "PASSED : group id set successfully and validation succeeded for xgroup setid command."
    else
        log_result "FAILED : xgroup setid command validation failed(${RES1},${RES2} and ${RES3}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function xreadgroup() {
    log_result "INFO : Executing xreadgroup command to read messages from test_stream in the test_group."
    RES1=$(${VALKEY_CMD} xreadgroup group test_group test_consumer1 streams test_stream \> 2>/dev/null | grep -v option | grep -w "temperature" | wc -l | sed 's/ //g')
    RES2=$(${VALKEY_CMD} xreadgroup group test_group test_consumer1 streams test_stream \> 2>/dev/null | grep -v option | grep -w "temperature" | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 2 ]] && [[ ${RES2} -eq 0 ]]; then
        log_result "PASSED : xreadgroup validation succeeded."
    else
        log_result "FAILED : xreadgroup command validation failed(${RES1} and ${RES2}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function xrange_xrevrange() {
    log_result "INFO : Executing xrange and xrevrange commands to list the stream messages."
    id2=$(${VALKEY_CMD} xadd test_stream \* sensor-id 1234 temperature 30 2>/dev/null | grep -v option)
    ${VALKEY_CMD} xrange test_stream - + 2>/dev/null | grep -v option | head -1 | grep -q "$id"
    RES1=$?
    ${VALKEY_CMD} xrevrange test_stream + - 2>/dev/null | grep -v option | head -1 | grep -q "$id2"
    RES2=$?
    if [[ ${RES1} -eq 0 ]] && [[ ${RES2} -eq 0 ]]; then
        log_result "PASSED : xrange and xrevrange commands validated successfully."
    else
        log_result "FAILED : xrange and xrevrange commands validation failed(${RES1} and ${RES2}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function xclaim_xack_xautoclaim() {
    log_result "INFO : Executing xrange and xrevrange commands to list the stream messages."
    ${VALKEY_CMD} xreadgroup group test_group test_consumer1 count 1 streams test_stream 0 2>/dev/null | grep -v option | grep -q "${id}"
    RES1=$?
    ${VALKEY_CMD} xack test_stream test_group ${id} 2>/dev/null | grep -v option | head -1 | grep -q 1
    RES2=$?
    ${VALKEY_CMD} xack test_stream test_group ${id} 2>/dev/null | grep -v option | head -1 | grep -q 0
    RES3=$?
    if [[ ${RES1} -eq 0 ]] && [[ ${RES2} -eq 0 ]] && [[ ${RES3} -eq 0 ]]; then
        log_result "PASSED : xack validated successfully."
    else
        log_result "FAILED : xack validation failed(${RES1}, ${RES2} and ${RES3}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function xgroup_destroy() {
    log_result "INFO : Executing xgroup destroy command to remove test_stream from the test_group."
    RES1=$(${VALKEY_CMD} xinfo groups test_stream 2>/dev/null | grep -v option | grep test_group | wc -l | sed 's/\r//g' | sed 's/ //g')
    ${VALKEY_CMD} xgroup destroy test_stream test_group 2>/dev/null | grep -v option | grep -q 1
    RES2=$?
    ${VALKEY_CMD} xgroup destroy test_stream test_group 2>/dev/null | grep -v option | grep -q 1
    RES3=$?
    RES4=$(${VALKEY_CMD} xinfo groups test_stream 2>/dev/null | grep -v option | grep test_group | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 0 ]] && [[ ${RES3} -ne 0 ]] && [[ ${RES4} -eq 0 ]]; then
        log_result "PASSED : xgroup destroy validation succeeded."
    else
        log_result "FAILED : xgroup destroy command validation failed(${RES1}, ${RES2}, ${RES3} and ${RES4}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function validate_blocking_command() {
    RES1=$(${VALKEY_CMD} del test_stream 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//g' | sed 's/ //g')
    RES2=$(${VALKEY_CMD} xadd test_stream \* field1 value1 field2 value2 2>/dev/null | grep -v option | grep 17* | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES3=$(${VALKEY_CMD} xlen test_stream 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//g' | sed 's/ //g')
    RES4=$(${VALKEY_CMD} xrange test_stream - + count 1 2>/dev/null | grep -v option | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]] && [[ ${RES3} -eq 1 ]] && [[ ${RES4} -eq 5 ]]; then
        log_result "INFO : Prevalidations succeeded for validating xread command."
        timeout --kill-after=1s 10s ${VALKEY_CMD} xread block 5 streams test_stream 0
        RES5=$?
        timeout --kill-after=1s 10s ${VALKEY_CMD} xread block 0 streams test_stream $
        RES6=$?
        if [[ ${RES5} -eq 0 ]] && ([[ ${RES6} -eq 137 ]] || [[ ${RES6} -eq 124 ]]); then
            log_result "PASSED : xread command validation succeeded."
            RES7=$(${VALKEY_CMD} del test_stream 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//g' | sed 's/ //g')
            if [[ ${RES7} -eq 1 ]]; then
                log_result "INFO : Test stream deletion validated succeessfully."
            else
                log_result "FAILED : Issue in deleting test stream."
            fi
        else
            log_result "FAILED : xread command validation failed (${RES5} and ${RES6}). Exiting."
            time_calculation
            if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
        fi
    else
        log_result "FAILED : Prevalidations failed for executing xread command(${RES1}, ${RES2}, ${RES3} and ${RES4}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function xgroup_xreadgroup() {
    xgroup_create
    xgroup_create_consumers
    xgroup_delete_consumer
    xgroup_setid
    xreadgroup
}

function stream_commands() {
    xadd_xtrim_xdel
    xinfo_xread
    xgroup_xreadgroup
    #xrange_xrevrange
    #xclaim_xack_xautoclaim
    xgroup_destroy
    validate_blocking_command
}

function default_commands() {
    PING_RESP=$(${VALKEY_CMD} ping 2>/dev/null | grep -v option | sed 's/\r//g')
    if [[ ${PING_RESP} == "PONG" ]]; then
        log_result "INFO : Ping command validated successfully."
    else
        log_result "ERROR : Ping command validation failed(${PING_RESP}). Exiting"
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    TIME_RESP=$(${VALKEY_CMD} time 2>/dev/null | grep -v option | head -1 | sed 's/\r//g')
    sleep 2
    CUR_TIME=$(date +%s)
    DIFF=$((${CUR_TIME} - ${TIME_RESP}))
    if [[ ${DIFF} -ge 2 ]] && [[ ${DIFF} -le 4 ]]; then
        log_result "INFO : Time command validated successfully."
    else
        log_result "ERROR : Time command validation failed(${TIME_RESP}, ${CUR_TIME} and ${DIFF}). Exiting"
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    RES1=$(${VALKEY_CMD} quit 2>/dev/null | grep -v option | sed 's/\r//g')
    RES2=$(${VALKEY_CMD} exit 2>/dev/null | grep -v option | sed 's/\r//g')
    if [[ ${RES1} == "OK" ]] && [[ ${RES2} == "OK" ]]; then
        log_result "PASSED : Commands quit and exit verified successfully."
    else
        log_result "FAILED : Validation failed for quit and exit commands (${RES1} and ${RES2}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function hset_operations() {
    ${VALKEY_CMD} del {hset}.keys 2>/dev/null | grep -v option
    RES1=$(${VALKEY_CMD} hset {hset}.keys key1 value1 key2 value2 2>/dev/null | grep -v option | awk '{print $NF}' | grep -w 2 | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES2=$(${VALKEY_CMD} hset {hset}.keys key1 value1 key2 value2 key3 value3 2>/dev/null | grep -v option | awk '{print $NF}' | grep -w 1 | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]]; then
        log_result "INFO : hset command validated successfully."
    else
        log_result "ERROR : hset command validation failed(${RES1} and ${RES2}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    ${VALKEY_CMD} del {hset}.keys 2>/dev/null | grep -v option
    RES1=$(${VALKEY_CMD} hmset {hset}.keys key1 value1 key2 value2 2>/dev/null | grep -v option | grep -w OK | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES2=$(${VALKEY_CMD} hmset {hset}.keys key1 value1 key2 value2 key3 value3 2>/dev/null | grep -v option | grep -w OK | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]]; then
        log_result "INFO : hmset command validated successfully."
    else
        log_result "ERROR : hmset command validation failed(${RES1} and ${RES2}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    RES1=$(${VALKEY_CMD} hrandfield {hset}.keys 2>/dev/null | grep -v option | grep -w "key[1-3]" | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES2=$(${VALKEY_CMD} hrandfield {hset}.keys 2 2>/dev/null | grep -v option | grep -w "key[1-3]" | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES3=$(${VALKEY_CMD} hrandfield {hset}.keys 2 withvalues 2>/dev/null | grep -v option | egrep -w "key[1-3]|value[1-3]" | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 2 ]] && [[ ${RES3} -eq 4 ]]; then
        log_result "INFO : hrandfield command validated successfully."
    else
        log_result "ERROR : hrandfield command validation failed(${RES1}, ${RES2} and ${RES3}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function bitop() {
    OPERATION=$1
    EXP_RES=$2
    if [[ ${OPERATION} == "not" ]]; then
        ${VALKEY_CMD} bitop ${OPERATION} {key}${OPERATION} {key}1 2>/dev/null | grep -v option
    else
        ${VALKEY_CMD} bitop ${OPERATION} {key}${OPERATION} {key}1 {key}2 2>/dev/null | grep -v option
    fi
    echo "=====1====="
    ${VALKEY_CMD} get {key}${OPERATION} 2>/dev/null | grep -v option | sed 's/\\x//g' | sed 's/\r//g'
    echo "=====2====="
    ${VALKEY_CMD} get {key}${OPERATION} 2>/dev/null | grep -v option | sed 's/\\x//g'
    echo "=====3====="
    ${VALKEY_CMD} get {key}${OPERATION} 2>/dev/null | grep -v option
    echo "=====4====="
    CUR_RES=$(${VALKEY_CMD} get {key}${OPERATION} 2>/dev/null | grep -v option | sed 's/\\x//g' | sed 's/\r//g' | sed 's/ //g')
    if [[ ${CUR_RES} == ${EXP_RES} ]]; then
        log_result "PASSED : bitwise ${OPERATION} operation succeeded."
    else
        log_result "FAILED : bitise ${OPERATION} operation failed(${CUR_RES},${EXP_RES}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function bitwise_operations() {
    ${VALKEY_CMD} set {key}1 hello 2>/dev/null | grep -v option | grep -wq OK
    ${VALKEY_CMD} set {key}2 hai 2>/dev/null | grep -v option | grep -wq OK
    RES=$(${VALKEY_CMD} mget {key}1 {key}2 2>/dev/null | grep -v option | egrep -w "hello|hai" | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES} -eq 2 ]]; then
        log_result "INFO : Sample keys set successfully."
        bitop and "hah0000"
        bitop or "hemlo"
        bitop xor "000405lo"
        bitop not "979a939390"
    else
        log_result "ERROR : Setting sample keys failed(${RES}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function keys_and_flushall_commands() {
    ${VALKEY_CMD} flushall SYNC 2>/dev/null | grep -v option | grep -wq OK
    ${VALKEY_CMD} xadd test_stream \* field1 value1 field2 value2 2>/dev/null | grep -v option
    zset_keys_count=$(${VALKEY_CMD} scan 0 2>/dev/null | grep -v option | grep "test_stream" | wc -l)
    if [[ ${zset_keys_count} -ge 1 ]]; then
        log_result "PASSED : keys command validated successfully before flushing."
        ${VALKEY_CMD} flushall SYNC 2>/dev/null | grep -v option | grep -wq OK
        if [[ $? -eq 0 ]]; then
            log_result "PASSED : flushall command executed successfully."
            zset_keys_count=$(${VALKEY_CMD} scan 0 2>/dev/null | grep -v option | grep "test_stream" | wc -l)
            if [[ ${zset_keys_count} -eq 0 ]]; then
                log_result "PASSED : flushall and keys command validated successfully."
            else
                log_result "FAILED : flushall and keys command validation failed. Exiting."
                time_calculation
                if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
            fi
        else
            log_result "FAILED : flushall command execution failed. Exiting."
            time_calculation
            if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
        fi
    else
        log_result "FAILED : keys command validation failed before flushing. Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function info_and_config_commands() {
    MAXMEM=$(${VALKEY_CMD} info 2>/dev/null | grep -v option | grep maxmemory_policy | awk -F ':' '{print $2}' | sed 's/\r//g' | sed 's/ //g')
    if [[ ${MAXMEM} == "noeviction" ]]; then
        log_result "PASSED : info command executed successfully(${INFO})."
        HEADER_COUNT=$(${VALKEY_CMD} info replication 2>/dev/null | grep -v option | grep ^# | wc -l)
        if [[ ${HEADER_COUNT} -gt 1 ]]; then
            log_result "FAILED : info sub command validation failed. Exiting."
            #time_calculation
            #if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1;fi
        else
            log_result "PASSED : info sub command validated successfully."
        fi
    else
        log_result "FAILED : info command execution failed(${INFO}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
    ${VALKEY_CMD} config resetstat 2>/dev/null | grep -v option | grep -wq OK
    if [[ $? -eq 0 ]]; then
        log_result "INFO : Config resetstat command executed successfully."
        INFO_COUNT=$(${VALKEY_CMD} info 2>/dev/null | grep -v option | grep keyspace_hits | awk -F ':' '{print $2}' | sed 's/\r//g')
        if [[ ${INFO_COUNT} -eq 0 ]]; then
            log_result "PASSED : Config command validation succeeded."
            MEM_VAL=$(${VALKEY_CMD} config get maxmemory 2>/dev/null | grep -v option | grep "^[0-9]" | sed 's/ //g')
            if [[ ${MEM_VAL} -gt 0 ]]; then
                log_result "INFO : Config get command executed successfully on maxmemory(${MEM_VAL})."
                let MEM_VAL=$((${MEM_VAL} + 500))
                ${VALKEY_CMD} config set maxmemory ${MEM_VAL} 2>/dev/null | grep -v option | grep -wq OK
                if [[ $? -eq 0 ]]; then
                    log_result "INFO : Config set command executed successfully on maxmemory(${MEM_VAL})."
                    CUR_VAL=$(${VALKEY_CMD} config get maxmemory 2>/dev/null | grep -v option | grep "^[0-9]" | sed 's/ //g')
                    if [[ ${CUR_VAL} -eq ${MEM_VAL} ]]; then
                        log_result "PASSED : Config set and get validation succeeded on maxmemory."
                    else
                        log_result "FAILED : Config set and get validation failed on maxmemory(${MEM_VAL} and ${CUR_VAL}). Exiting."
                        time_calculation
                        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
                    fi
                else
                    log_result "FAILED : Config set command execution failed on maxmemory(${MEM_VAL}). Exiting."
                    time_calculation
                    if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
                fi
            else
                log_result "FAILED : Config get command execution failed on maxmemory(${MEM_VAL})."
                time_calculation
                if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
            fi
        else
            log_result "FAILED : Config command validation failed. Exiting."
            time_calculation
            if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
        fi
    else
        log_result "FAILED : Config resetstat command execution failed. Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function slowlog_validation {
    SLOWLOG_COUNT=$(${VALKEY_CMD} slowlog len 2>/dev/null | grep -v option | sed 's/ //g' | sed 's/\r//g')
    if [[ ${SLOWLOG_COUNT} -ge 1 ]]; then
        log_result "PASSED : Slowlog validated successfully."
    else
        log_result "FAILED : Slowlog validation failed(${SLOWLOG_COUNT}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function generate_slowlogs {
    SHA_VAL=$(${VALKEY_CMD} script load "for i = 1, 10000000 do local x = 1 end return 'done'" 2>/dev/null | grep -v option | sed 's/ //g')
    ${VALKEY_CMD} evalsha ${SHA_VAL} 0 hello >/dev/null 2>&1
    ${VALKEY_CMD} slowlog len 2>/dev/null | grep -v option | grep -w "0"
    if [[ $? -ne 0 ]]; then
        log_result "PASSED : Slowlogs generated successfully."
        slowlog_validation
    else
        log_result "FAILED : Failed to generate slowlogs. Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function slowlog_command() {
    ${VALKEY_CMD} slowlog get 2>/dev/null | grep -v option | grep -wq "nil"
    if [[ $? -ne 0 ]]; then
        log_result "INFO : Slowlogs found. Clearing them."
        ${VALKEY_CMD} slowlog reset >/dev/null 2>&1 | grep -v option
        ${VALKEY_CMD} slowlog get 2>/dev/null | grep -v option | grep -q "empty"
        if [[ $? -eq 0 ]]; then
            log_result "INFO : Slowlogs cleared. Generating slowlogs."
            generate_slowlogs
        else
            log_result "FAILED : Failed to clear slowlogs. Exiting."
            time_calculation
            if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
        fi
    else
        log_result "INFO : No slowlogs found. Generating slowlogs."
        generate_slowlogs
    fi
}

function getex_getdel_msetnx_commands() {
    ${VALKEY_CMD} set hello world 2>/dev/null | grep -v option | grep -q OK
    ${VALKEY_CMD} get hello 2>/dev/null | grep -v option | grep -wq world
    if [[ $? -eq 0 ]]; then
        log_result "INFO : Set sample value(world) for the key(hello). Executing getex on the key"
        ${VALKEY_CMD} getex hello ex 10 2>/dev/null | grep -v option | grep -wq world
        if [[ $? -eq 0 ]]; then
            log_result "INFO : getex command executed successfully. Validating it."
            sleep 10
            ${VALKEY_CMD} get hello 2>/dev/null | grep -v option | grep -wq "^$"
            if [[ $? -eq 0 ]]; then
                log_result "PASSED : getex command validated successfully."
            else
                log_result "FAILED : getex validation failed.Exiting."
                time_calculation
                if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
            fi
        else
            log_result "FAILED : getex command execution failed.Exiting."
            time_calculation
            if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
        fi
    else
        log_result "FAILED : Failed to set the value(world) to the key(hello)."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    ${VALKEY_CMD} set hello world 2>/dev/null | grep -v option | grep -q OK
    ${VALKEY_CMD} get hello 2>/dev/null | grep -v option | grep -wq world
    if [[ $? -eq 0 ]]; then
        log_result "INFO : Set sample value(world) for the key(hello). Executing getdel on the key"
        ${VALKEY_CMD} getdel hello 2>/dev/null | grep -v option | grep -wq world
        if [[ $? -eq 0 ]]; then
            log_result "INFO : getdel command executed successfully. Validating it."
            ${VALKEY_CMD} get hello 2>/dev/null | grep -v option | grep -wq "^$"
            if [[ $? -eq 0 ]]; then
                log_result "PASSED : getdel command validated successfully."
            else
                log_result "FAILED : getdel validation failed. Exiting."
                time_calculation
                if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
            fi
        else
            log_result "FAILED : getdel command execution failed.Exiting."
            time_calculation
            if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
        fi
    else
        log_result "FAILED : Failed to set the value(world) to the key(hello)."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    ${VALKEY_CMD} del {key}1 {key}2 {key}3 2>/dev/null | grep -v option
    ${VALKEY_CMD} msetnx {key}1 value1 {key}2 value2 2>/dev/null | grep -v option | grep -q 1
    RES=$(${VALKEY_CMD} mget {key}1 {key}2 2>/dev/null | grep -v option | egrep -vw "value1|value2" | wc -l)
    if [[ $RES -eq 0 ]]; then
        log_result "INFO : msetnx command executed on non-existing keys successfully."
        ${VALKEY_CMD} msetnx {key}1 value1 {key}2 value2 {key}3 value3 2>/dev/null | grep -v option | grep -q 0
        RES=$(${VALKEY_CMD} mget {key}1 {key}2 {key}3 2>/dev/null | grep -v option | egrep -vw "value1|value2|nil" | wc -l)
        if [[ $? -eq 0 ]]; then
            log_result "INFO : msetnx command validation succeeded."
        else
            log_result "FAILED : msetnx command validation failed.Exiting."
            time_calculation
            if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
        fi
    else
        log_result "FAILED : Failed to execute msetnx command on non-existing keys. Exiting."
    fi
}

function del_and_exists_commands() {
    ${VALKEY_CMD} set {key}1 hello 2>/dev/null | grep -v option | grep -wq OK
    ${VALKEY_CMD} set {key}2 hai 2>/dev/null | grep -v option | grep -wq OK
    RES=$(${VALKEY_CMD} mget {key}1 {key}2 2>/dev/null | grep -v option | egrep -w "hello|hai" | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES} -eq 2 ]]; then
        log_result "INFO : Sample keys set successfully."
    else
        log_result "ERROR : Setting sample keys failed(${RES}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    RES1=$(${VALKEY_CMD} exists {key}1 {key}2 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//' | sed 's/ //g')
    RES2=$(${VALKEY_CMD} exists {key}does_not_exist 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//' | sed 's/ //g')
    RES3=$(${VALKEY_CMD} exists {key}1 {key}does_not_exist {key}2 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//' | sed 's/ //g')
    if [[ ${RES1} -eq 2 ]] && [[ ${RES2} -eq 0 ]] && [[ ${RES3} -eq 2 ]]; then
        log_result "INFO : exists command validation succeeded."
    else
        log_result "ERROR : Validation failed for exists command(${RES1}, ${RES2}, and ${RES3}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    RES1=$(${VALKEY_CMD} del {key}1 {key}2 2>/dev/null)
    RES2=$(${VALKEY_CMD} del {key}1 {key}2 2>/dev/null)
    RES3=$(${VALKEY_CMD} mget {key}1 {key}2 2>/dev/null | grep -v option | grep -c '^$')
    if [[ ${RES1} -eq 2 ]] && [[ ${RES2} -eq 0 ]] && [[ ${RES3} -eq 2 ]]; then
        log_result "INFO : del command validation succeeded."
    else
        log_result "ERROR : Validation failed for del command(${RES1}, ${RES2}, and ${RES3}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function copy_and_scan_commands() {
    ${VALKEY_CMD} mset {key}1 value1 {key}2 value2 2>/dev/null | grep -v option | grep -wq OK
    RES1=$(${VALKEY_CMD} copy {key}1 {key}2 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//g' | sed 's/ //g')
    RES2=$(${VALKEY_CMD} mget {key}1 {key}2 2>/dev/null | grep -v option | egrep "value1|value2" | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES3=$(${VALKEY_CMD} copy {key}1 {key}2 REPLACE 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//g' | sed 's/ //g')
    RES4=$(${VALKEY_CMD} mget {key}1 {key}2 2>/dev/null | grep -v option | grep "value1" | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES1} -eq 0 ]] && [[ ${RES2} -eq 2 ]] && [[ ${RES3} -eq 1 ]] && [[ ${RES4} -eq 2 ]]; then
        log_result "INFO : Copy command validated successfully for with and without REPLACE options."
    else
        log_result "ERROR : Validation failed for copy command.(${RES1}, ${RES2}, ${RES3} and ${RES4}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi

    log_result "INFO : Scan command validation in progress..."
    ${VALKEY_CMD} flushall SYNC 2>/dev/null | grep -v option | grep -wq OK
    i=1
    while [ $i -le 10 ]; do
        ${VALKEY_CMD} set {key}_$i value_$i 2>/dev/null | grep -v option | grep -wq OK
        ${VALKEY_CMD} set {key}-$i value-$i 2>/dev/null | grep -v option | grep -wq OK
        i=$((i + 1))
    done

    # CHANGE: check for >0, since per the document:
    # > the server will usually return count or a few more than count elements per call.
    # > Please check the why SCAN may return all the elements at once section later in this document.
    RES1=$(${VALKEY_CMD} scan 0 type string count 5 2>/dev/null | grep -v option | grep key | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES2=$(${VALKEY_CMD} scan 0 type string count 5 match {key}-* 2>/dev/null | grep -v option | grep key | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES3=$(${VALKEY_CMD} scan 0 count 5 type string match {key}-* 2>/dev/null | grep -v option | grep key | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES4=$(${VALKEY_CMD} scan 0 count 5 match {key}-* type string 2>/dev/null | grep -v option | grep key | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES1} -gt 0 ]] && [[ ${RES2} -gt 0 ]] && [[ ${RES3} -gt 0 ]] && [[ ${RES4} -gt 0 ]]; then
        log_result "INFO : Scan command validated successfully for positive test cases."
    else
        log_result "ERROR : Validation failed for +ve testing of scan command.(${RES1}, ${RES2}, ${RES3} and ${RES4}). Exiting."
        time_calculation
        #if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1;fi
    fi

    RES1=$(${VALKEY_CMD} scan -1 2>/dev/null | grep -v option | grep "ERR invalid cursor" | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES2=$(${VALKEY_CMD} scan a 2>/dev/null | grep -v option | grep "ERR invalid cursor" | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES3=$(${VALKEY_CMD} scan 1.5 2>/dev/null | grep -v option | grep "ERR invalid cursor" | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES4=$(${VALKEY_CMD} scan 324567890987654323456789 2>/dev/null | grep -v option | grep "ERR invalid cursor" | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES5=$(${VALKEY_CMD} scan 0 type sdfgdsfg 2>/dev/null | grep -v option | grep "empty" | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES6=$(${VALKEY_CMD} scan 0 type string count 5 match {keys}-* 2>/dev/null | grep -v option | grep "empty" | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]] && [[ ${RES3} -eq 1 ]] && [[ ${RES4} -eq 1 ]] && [[ ${RES5} -eq 1 ]] && [[ ${RES6} -eq 1 ]]; then
        log_result "INFO : Scan command validated successfully for negative test cases."
    else
        log_result "ERROR : Validation failed for -ve testing of scan command.(${RES1}, ${RES2}, ${RES3} and ${RES4}). Exiting."
        time_calculation
        if [[ $EXIT_ON_ERROR -eq 1 ]]; then exit 1; fi
    fi
}

function other_commands() {
    #slowlog_command
    #info_and_config_commands
    keys_and_flushall_commands
    getex_getdel_msetnx_commands
    del_and_exists_commands
    copy_and_scan_commands
}

#MAIN
${VALKEY_CMD} flushall SYNC 2>/dev/null | grep -v option | grep -wq OK
echo "$(date) ================ Test case 01 ============= Set Commands ==========================================="
set_operations
echo "$(date) ================ Test case 02 ============= Sorted Set Commands ===================================="
zset_operations
echo "$(date) ================ Test case 03 ============= List Commands =========================================="
blocking_list_operations
echo "$(date) ================ Test case 04 ============= Script, Client and Select Commands ====================="
scs_commands
echo "$(date) ================ Test case 05 ============= Cluster Commands ======================================="
cluster_commands
echo "$(date) ================ Test case 06 ============= String Commands ========================================"
string_commands
echo "$(date) ================ Test case 07 ============= Stream Commands ========================================"
stream_commands
echo "$(date) ================ Test case 08 ============= Default Commands ======================================="
default_commands
echo "$(date) ================ Test case 09 ============= Hashset Commands ======================================="
hset_operations
#echo "$(date) ================ Test case 10 ============= Bitwise Commands ======================================="
#bitwise_operations
echo "$(date) ================ Test case 11 ============= Other Commands ========================================="
other_commands
${VALKEY_CMD} flushall SYNC 2>/dev/null | grep -v option | grep -wq OK
time_calculation
