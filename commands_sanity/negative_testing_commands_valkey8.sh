#!/bin/bash

VALKEY_HOST="${VALKEY_HOST:-localhost}"
VALKEY_PORT="${VALKEY_PORT:-7777}"
VALKEY_PASSWORD="${VALKEY_PASSWORD:-''}"
CLI_OPTS="-h ${VALKEY_HOST} -p ${VALKEY_PORT} -a ${VALKEY_PASSWORD} --no-auth-warning --raw"
VALKEY_CMD="valkey-cli $CLI_OPTS"

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
    FAILED* | FAIL:* | ERROR* | FATAL*) COLOR=$RED ;;
    PASSED* | PASS:*)
        COLOR=$GREEN
        ;;
    INFO*)
        COLOR=$YELLOW
        ;;
    DEBUG*)
        COLOR=$DIM
        ;;
    *)
        COLOR=$NC
        ;;
    esac
    printf "${CUR_TIME} : ${COLOR}$1${NC}\n"
}

# Function to run a Valkey command and check for expected error
function run_negative_test() {
    local test_name="$1"
    local command="$2"
    local expected_error="$3"

    ((TOTAL_TESTS++))

    result=$($VALKEY_CMD $command 2>/dev/null | grep -v option)
    if [[ "$result" == *"$expected_error"* ]]; then
        log_result "PASS:$test_name"
        ((PASSED_TESTS++))
    else
        log_result "FAIL:$test_name - Expected '$expected_error', but got '$result'"
        ((FAILED_TESTS++))
    fi
}

# Authentication tests
function authentication_tests_negative() {
    log_result "INFO : Running Authentication Tests..."

    # Test connection without password
    result=$($VALKEY_CMD PING 2>&1 | grep -v option)
    if [[ "$result" == "PONG" ]]; then
        log_result "FAILED : Connected without password, but Valkey should require authentication"
    elif [[ "$result" == *"NOAUTH"* ]]; then
        log_result "PASSED : Valkey correctly requires authentication"
    else
        log_result "FATAL: $result"
    fi

    # Test connection with wrong password
    result=$($VALKEY_CMD -a "wrong_password" PING 2>&1 | grep -v option)
    if [[ "$result" == *"invalid password"* ]] || [[ "$result" == *"NOAUTH"* ]]; then
        log_result "PASSED : Valkey correctly rejected wrong password"
    else
        log_result "FAILED : Unexpected result with wrong password: $result"
    fi

    # Test connection with correct password
    if [ -n "$VALKEY_PASSWORD" ]; then
        result=$($VALKEY_CMD PING 2>&1 | grep -v option)
        if [[ "$result" == "PONG" ]]; then
            log_result "PASSED : Successfully authenticated with correct password"
        else
            log_result "FAILED : Could not authenticate with correct password: $result"
        fi
    fi
}

# String Operations
function string_operations_negative() {
    log_result "INFO : Running String Operations Tests..."
    run_negative_test "Empty the DB before starting" "flushall" "OK"
    run_negative_test "Create list" "lpush {negative_list}1 Hello" "1"
    run_negative_test "APPEND to non-string" "APPEND {negative_list}1 World" "WRONGTYPE"
    run_negative_test "BITCOUNT on non-string" "BITCOUNT {negative_list}1" "WRONGTYPE"
    run_negative_test "BITOP on non-string" "BITOP AND {negative_list}3 {negative_list}1 {negative_list}2" "WRONGTYPE"
    run_negative_test "Set a sample string" "SET {negative_string}1 HELLO" "OK"
    run_negative_test "DECR on non-integer" "DECR {negative_string}1" "ERR value is not an integer or out of range"
    run_negative_test "GET non-existent key" "GET {negative_list}134" ""
    run_negative_test "INCR on non-integer" "INCR {negative_string}1" "ERR value is not an integer or out of range"
    run_negative_test "STRLEN on non-string" "STRLEN {negative_list}1" "WRONGTYPE"
    run_negative_test "SETBIT out of range" "SETBIT {negative_string}1 -1 1" "ERR bit offset is not an integer or out of range"
    run_negative_test "GETBIT out of range" "GETBIT {negative_string}1 -1" "ERR bit offset is not an integer or out of range"
    run_negative_test "SETRANGE with negative offset" "SETRANGE {negative_string}1 -1 test" "ERR offset is out of range"
    run_negative_test "GETRANGE with invalid range" "GETRANGE {negative_string}1 5 1" ""
}

# List Operations
function list_operations_negative() {
    log_result "INFO : Running List Operations Tests..."
    run_negative_test "BLPOP with negative timeout" "BLPOP {negative_list}1 -1" "ERR timeout is negative" &
    CMD_PID=$!
    sleep 2
    kill -TERM "${CMD_PID}"
    run_negative_test "LINDEX on non-list" "LINDEX {negative_string}1 0" "WRONGTYPE"
    run_negative_test "LINSERT on non-list" "LINSERT {negative_string}1 BEFORE John Doe" "WRONGTYPE"
    run_negative_test "LPOP on non-list" "LPOP {negative_string}1" "WRONGTYPE"
    run_negative_test "LPUSH to non-list" "LPUSH {negative_string}1 John" "WRONGTYPE"
    run_negative_test "LRANGE on non-list" "LRANGE {negative_string}1 0 -1" "WRONGTYPE"
    run_negative_test "LSET on non-list" "LSET {negative_string}1 0 value" "WRONGTYPE"
    run_negative_test "LTRIM on non-list" "LTRIM {negative_string}1 0 -1" "WRONGTYPE"
    run_negative_test "LPUSH to a list" "LPUSH {negative_stringlist}2 1 2 3" "3"
    run_negative_test "Set a key of string type" "SET {negative_stringlist}1 hello" "OK"
    run_negative_test "RPOPLPUSH with non-list source" "RPOPLPUSH {negative_stringlist}1 {negative_stringlist}2" "WRONGTYPE"
    run_negative_test "RPOPLPUSH with non-list destination" "RPOPLPUSH {negative_stringlist}2 {negative_stringlist}1" "WRONGTYPE"
    run_negative_test "RPOPLPUSH with non-list source and destination" "RPOPLPUSH {negative_stringlist}1 {negative_stringlist}1" "WRONGTYPE"
}

# Set Operations
function set_operations_negative() {
    log_result "INFO : Running Set Operations Tests..."
    run_negative_test "SADD to non-set" "SADD {negative_list}1 John" "WRONGTYPE"
    run_negative_test "SCARD on non-set" "SCARD {negative_list}1" "WRONGTYPE"
    run_negative_test "SDIFF with non-set" "SDIFF {negative_list}2 {negative_list}1" "WRONGTYPE"
    run_negative_test "SINTER with non-set" "SINTER {negative_list}2 {negative_list}1" "WRONGTYPE"
    run_negative_test "SISMEMBER on non-set" "SISMEMBER {negative_list}1 TRY" "WRONGTYPE"
    run_negative_test "SMEMBERS on non-set" "SMEMBERS {negative_list}1" "WRONGTYPE"
    run_negative_test "SMOVE with non-set source" "SMOVE {negative_list}1 {negative_list}2 member" "WRONGTYPE"
    run_negative_test "SPOP on non-set" "SPOP {negative_list}1" "WRONGTYPE"
    run_negative_test "SRANDMEMBER on non-set" "SRANDMEMBER {negative_list}1" "WRONGTYPE"
    run_negative_test "SREM from non-set" "SREM {negative_list}1 member" "WRONGTYPE"
}

# Hash Operations
function hash_operations_negative() {
    log_result "INFO : Running Hash Operations Tests..."
    run_negative_test "HDEL from non-hash" "HDEL {negative_list}1 firstname" "WRONGTYPE"
    run_negative_test "HEXISTS on non-hash" "HEXISTS {negative_list}1 firstname" "WRONGTYPE"
    run_negative_test "HGET from non-hash" "HGET {negative_list}1 firstname" "WRONGTYPE"
    run_negative_test "HGETALL on non-hash" "HGETALL {negative_list}1" "WRONGTYPE"
    run_negative_test "HINCRBY on non-hash" "HINCRBY {negative_list}1 age 1" "WRONGTYPE"
    run_negative_test "HKEYS on non-hash" "HKEYS {negative_list}1" "WRONGTYPE"
    run_negative_test "HLEN on non-hash" "HLEN {negative_list}1" "WRONGTYPE"
    run_negative_test "HMGET from non-hash" "HMGET {negative_list}1 field1 field2" "WRONGTYPE"
    run_negative_test "HMSET to non-hash" "HMSET {negative_list}1 field1 value1 field2 value2" "WRONGTYPE"
    run_negative_test "HSETNX to non-hash" "HSETNX {negative_list}1 field value" "WRONGTYPE"
}

# Sorted Set Operations
function sorted_set_operations_negative() {
    log_result "INFO : Running Sorted Set Operations Tests..."
    run_negative_test "ZADD to non-zset" "ZADD {negative_list}1 1 John" "WRONGTYPE"
    run_negative_test "ZCARD on non-zset" "ZCARD {negative_list}1" "WRONGTYPE"
    run_negative_test "ZCOUNT on non-zset" "ZCOUNT {negative_list}1 0 100" "WRONGTYPE"
    run_negative_test "ZINCRBY on non-zset" "ZINCRBY {negative_list}1 1 John" "WRONGTYPE"
    run_negative_test "ZRANGE on non-zset" "ZRANGE {negative_list}1 0 -1" "WRONGTYPE"
    run_negative_test "ZRANK on non-zset" "ZRANK {negative_list}1 John" "WRONGTYPE"
    run_negative_test "ZREM from non-zset" "ZREM {negative_list}1 John" "WRONGTYPE"
    run_negative_test "ZREVRANGE on non-zset" "ZREVRANGE {negative_list}1 0 -1" "WRONGTYPE"
    run_negative_test "ZSCORE on non-zset" "ZSCORE {negative_list}1 John" "WRONGTYPE"
    run_negative_test "ZUNIONSTORE with non-zset" "ZUNIONSTORE {negative_list}3 2 {negative_list}1 {negative_list}2" "WRONGTYPE"
}

# HyperLogLog Operations
function hyperloglog_operations_negative() {
    log_result "INFO : Running HyperLogLog Operations Tests..."
    run_negative_test "PFADD to non-HyperLogLog" "PFADD {negative_list}1 John" "WRONGTYPE"
    run_negative_test "PFCOUNT on non-HyperLogLog" "PFCOUNT {negative_list}1" "WRONGTYPE"
    run_negative_test "PFMERGE with non-HyperLogLog" "PFMERGE {negative_list}2 {negative_list}1" "WRONGTYPE"
}

# Geo Operations
function geo_operations_negative() {
    log_result "INFO : Running Geo Operations Tests..."
    run_negative_test "GEOADD to non-geo" "GEOADD {negative_list}1 13.361389 38.115556 John" "WRONGTYPE"
    run_negative_test "GEODIST on non-geo" "GEODIST {negative_list}1 John Jane" "WRONGTYPE"
    run_negative_test "GEOHASH on non-geo" "GEOHASH {negative_list}1 John" "WRONGTYPE"
    run_negative_test "GEOPOS on non-geo" "GEOPOS {negative_list}1 John" "WRONGTYPE"
    run_negative_test "GEORADIUS on non-geo" "GEORADIUS {negative_list}1 15 37 100 km" "WRONGTYPE"
    run_negative_test "GEORADIUSBYMEMBER on non-geo" "GEORADIUSBYMEMBER {negative_list}1 John 100 km" "WRONGTYPE"
}

# Pub/Sub Operations
function pubsub_operations_negative() {
    log_result "INFO : Running Pub/Sub Operations Tests..."
    run_negative_test "PUBLISH with empty channel" "PUBLISH \"\" {negative_list}1" "NOPERM"
    run_negative_test "PUBSUB with invalid subcommand" "PUBSUB INVALID_SUBCOMMAND" "ERR unknown PUBSUB subcommand"
}

# Transaction Operations - UPDATED FOR VALKEY 8
function transaction_operations_negative() {
    log_result "INFO : Running Transaction Operations Tests (Valkey 8 updated)..."
    run_negative_test "EXEC without MULTI" "EXEC" "EXEC without MULTI"
    run_negative_test "DISCARD without MULTI" "DISCARD" "DISCARD without MULTI"

    # NEW: Test nested MULTI (Valkey 8 breaking change)
    log_result "INFO : Testing nested MULTI (Valkey 8 breaking change)..."
    result=$(
        $VALKEY_CMD < <(printf 'MULTI\r\nMULTI\r\nSET key1 value1\r\nEXEC')
    )
    if echo "$result" | grep -q "MULTI calls can not be nested"; then
        log_result "PASS:Nested MULTI correctly rejected in Valkey 8"
        ((PASSED_TESTS++))
    else
        log_result "FAIL:Nested MULTI should be rejected in Valkey 8"
        echo "DEBUG: Actual result: $result"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))

    # NEW: Test WATCH inside MULTI (Valkey 8 breaking change)
    log_result "INFO : Testing WATCH inside MULTI (Valkey 8 breaking change)..."
    result=$(
        $VALKEY_CMD < <(printf 'MULTI\r\nWATCH key1\r\nSET key1 value1\r\nEXEC')
    )
    if echo "$result" | grep -q "ERR WATCH inside MULTI is not allowed"; then
        log_result "PASS:WATCH inside MULTI correctly rejected in Valkey 8"
        ((PASSED_TESTS++))
    else
        log_result "FAIL:WATCH inside MULTI should be rejected in Valkey 8"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
}

# Connection Operations
function connection_operations_negative() {
    log_result "INFO : Running Connection Operations Tests..."
    run_negative_test "AUTH with wrong password" "AUTH incorrect_password" "ERR invalid password"
    run_negative_test "ECHO without message" "ECHO" "ERR wrong number of arguments for 'echo' command"
    run_negative_test "SELECT invalid DB" "SELECT 99" "ERR SELECT is not allowed in cluster mode"
    run_negative_test "CLIENT SETNAME with invalid name" "CLIENT SETNAME ''" "OK"
}

# Server Operations
function server_operations_negative() {
    log_result "INFO : Running Server Operations Tests..."
    run_negative_test "INFO with invalid section" "INFO invalidSection" "ERR Invalid section"
    run_negative_test "BGSAVE in cluster mode" "BGSAVE" "ERR unsupport command"
    run_negative_test "SLAVEOF in cluster mode" "SLAVEOF 127.0.0.1 6379" "ERR unsupport command"
}

# Scripting Operations
function scripting_operations_negative() {
    log_result "INFO : Running Scripting Operations Tests..."
    run_negative_test "EVAL with syntax error" "EVAL \"return {KEYS[1]\" 1 {negative_list}1" "ERR"
    run_negative_test "EVALSHA with non-existent script" "EVALSHA 1234567890123456789012345678901234567890 1 {negative_list}1" "NOSCRIPT"
    run_negative_test "SCRIPT LOAD with empty script" "SCRIPT LOAD \"\"" "ERR"
    run_negative_test "SCRIPT KILL when no script is running" "SCRIPT KILL" "NOTBUSY"
}

# Key Operations
function key_operations_negative() {
    log_result "INFO : Running Key Operations Tests..."
    run_negative_test "DEL non-existent key" "DEL {non_existent_key}1" "0"
    run_negative_test "EXPIRE on non-existent key" "EXPIRE {non_existent_key}1 100" "0"
    run_negative_test "RENAME non-existent key" "RENAME {non_existent_key}1 {non_existent_key}2" "ERR no such key"
    run_negative_test "TYPE non-existent key" "TYPE {non_existent_key}1" "none"
    run_negative_test "DUMP non-existent key" "DUMP {non_existent_key}1" ""
}

# Stream Operations
function stream_operations_negative() {
    log_result "INFO : Running Stream Operations Tests..."
    run_negative_test "Create a new list" "LPUSH {negative_list}10 1 2 3" "3"
    run_negative_test "Delete a new list" "del {negative_list}10" "1"
    run_negative_test "Create a new list" "LPUSH {negative_list}10 1 2 3" "3"
    run_negative_test "XADD to non-stream" "XADD {negative_list}10 1234567890-0 field1 value1" "WRONGTYPE"
    run_negative_test "XLEN on non-stream" "XLEN {negative_list}10" "WRONGTYPE"
    run_negative_test "XRANGE on non-stream" "XRANGE {negative_list}10 - +" "WRONGTYPE"
    run_negative_test "XREAD from non-stream" "XREAD COUNT 1 STREAMS {negative_list}10 0" "WRONGTYPE"
    run_negative_test "XREVRANGE on non-stream" "XREVRANGE {negative_list}10 + -" "WRONGTYPE"
    run_negative_test "XDEL from non-stream" "XDEL {negative_list}10 1234567890123-0" "WRONGTYPE"
    run_negative_test "XTRIM on non-stream" "XTRIM {negative_list}10 MAXLEN 100" "WRONGTYPE"
    run_negative_test "XGROUP CREATE on non-stream" "XGROUP CREATE {negative_list}10 mygroup $" "WRONGTYPE"
    run_negative_test "XREADGROUP on non-stream" "XREADGROUP GROUP mygroup consumer STREAMS {negative_list}10 >" "WRONGTYPE"
}

# NEW: SCAN Operations - UPDATED FOR VALKEY 8
function scan_operations_negative() {
    log_result "INFO : Running SCAN Operations Tests (Valkey 8 updated)..."

    # Valkey 8 breaking change: SCAN with invalid TYPE returns error
    log_result "INFO : Testing SCAN with invalid TYPE (Valkey 8 breaking change)..."
    result=$($VALKEY_CMD SCAN 0 TYPE faketype 2>/dev/null | grep -v option)
    if echo "$result" | grep -q "ERR unknown type name"; then
        log_result "PASS:SCAN with invalid TYPE returns error in Valkey 8"
        ((PASSED_TESTS++))
    else
        log_result "FAIL:SCAN should return error for invalid TYPE in Valkey 8, got: $result"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))

    run_negative_test "SCAN with invalid cursor" "SCAN -1" "ERR invalid cursor"
    run_negative_test "SCAN with non-integer cursor" "SCAN abc" "ERR invalid cursor"
}

# NEW: BITCOUNT/BITPOS Operations - UPDATED FOR VALKEY 8
function bitcount_bitpos_operations_negative() {
    log_result "INFO : Running BITCOUNT/BITPOS Operations Tests (Valkey 8 updated)..."

    # Valkey 8 breaking change: BITCOUNT with invalid arguments returns error
    log_result "INFO : Testing BITCOUNT with invalid arguments (Valkey 8 breaking change)..."
    result=$($VALKEY_CMD BITCOUNT {nonexistent}key 0 invalid 2>/dev/null | grep -v option)
    if echo "$result" | grep -q "ERR value is not an integer or out of range"; then
        log_result "PASS:BITCOUNT returns error for invalid arguments in Valkey 8"
        ((PASSED_TESTS++))
    else
        log_result "FAIL:BITCOUNT should return error for invalid arguments in Valkey 8, got: $result"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))

    # Valkey 8 breaking change: BITPOS with invalid arguments returns error
    log_result "INFO : Testing BITPOS with invalid arguments (Valkey 8 breaking change)..."
    result=$($VALKEY_CMD BITPOS {nonexistent}key 0 0 1 hello 2>/dev/null | grep -v option)
    if echo "$result" | grep -q "ERR syntax error"; then
        log_result "PASS:BITPOS returns error for invalid arguments in Valkey 8"
        ((PASSED_TESTS++))
    else
        log_result "FAIL:BITPOS should return error for invalid arguments in Valkey 8, got: $result"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))

    # Valkey 8 breaking change: BITCOUNT validates arguments before key check
    log_result "INFO : Testing BITCOUNT argument validation order (Valkey 8 breaking change)..."
    result=$($VALKEY_CMD BITCOUNT {no}key invalid1 invalid2 2>/dev/null | grep -v option)
    if echo "$result" | grep -q "ERR value is not an integer or out of range"; then
        log_result "PASS:BITCOUNT validates arguments before key existence in Valkey 8"
        ((PASSED_TESTS++))
    else
        log_result "FAIL:BITCOUNT should validate arguments first in Valkey 8, got: $result"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
}

function display_summary_negative() {
    log_result "INFO : ===== Negative Testing Summary ====="
    log_result "INFO : Total tests run: $TOTAL_TESTS"
    log_result "INFO : Tests passed: $PASSED_TESTS"
    log_result "INFO : Tests failed: $FAILED_TESTS"
    log_result "INFO : ===================================="
}

function negative_testing() {
    authentication_tests_negative
    string_operations_negative
    list_operations_negative
    set_operations_negative
    hash_operations_negative
    sorted_set_operations_negative
    hyperloglog_operations_negative
    geo_operations_negative
    pubsub_operations_negative
    transaction_operations_negative
    connection_operations_negative
    server_operations_negative
    scripting_operations_negative
    key_operations_negative
    stream_operations_negative
    scan_operations_negative
    bitcount_bitpos_operations_negative
    display_summary_negative

    if [[ $FAILED_TESTS -le 5 ]]; then
        log_result "PASSED : Negative testing on wrong type validated successfully. Failed tests : ${FAILED_TESTS}"
    else
        log_result "FAILED : Negative testing on wrong type validation failed. Exiting. Total failures : ${FAILED_TESTS}"
        exit 1
    fi
}

function check_VALKEY_connection() {
    until $VALKEY_CMD ping &>/dev/null; do
        log_result "INFO : Waiting for Valkey connection..."
        sleep 5
    done
    log_result "Valkey connection established!"
}

function execute_command_no_args() {
    local command=$1
    log_result "INFO : Testing command: $command"
    check_VALKEY_connection
    result=$($VALKEY_CMD $command 2>/dev/null | grep -v option)

    # Commands that are valid without arguments (should NOT return error)
    case "$command" in
    PING | FLUSHALL | FLUSHDB | TIME | RANDOMKEY | DBSIZE | MULTI | EXEC | DISCARD | UNWATCH)
        # These commands don't require arguments, so we skip them
        log_result "SKIPPED : Command $command doesn't require arguments"
        return 0
        ;;
    esac

    # For all other commands, expect "invalid request" or "wrong number of arguments"
    if echo "$result" | grep -qE "invalid request|wrong number of arguments|ERR|syntax error"; then
        log_result "PASSED : ✅ Expected error for: $command : $result"
    else
        log_result "FAILED : ⚠️ Unexpected result for: $command : $result"
        let FAILED_COUNT=${FAILED_COUNT}+1
    fi
}

function negative_testing_no_args() {
    FAILED_COUNT=0
    commands=(
        # String Commands
        SET GET APPEND BITCOUNT BITFIELD BITOP BITPOS DECR DECRBY GETBIT GETDEL
        GETEX GETRANGE GETSET INCR INCRBY INCRBYFLOAT LCS MGET MSET MSETNX
        PSETEX SETBIT SETEX SETNX SETRANGE STRLEN SUBSTR

        # Hash Commands
        HDEL HEXISTS HGET HGETALL HINCRBY HINCRBYFLOAT HKEYS HLEN HMGET HMSET
        HRANDFIELD HSCAN HSET HSETNX HSTRLEN HVALS

        # List Commands
        BLMOVE BLMPOP BLPOP BRPOP BRPOPLPUSH LINDEX LINSERT LLEN LMOVE LMPOP
        LPOP LPOS LPUSH LPUSHX LRANGE LREM LSET LTRIM RPOP RPOPLPUSH RPUSH RPUSHX

        # Set Commands
        SADD SCARD SDIFF SDIFFSTORE SINTER SINTERCARD SINTERSTORE SISMEMBER
        SMEMBERS SMISMEMBER SMOVE SPOP SRANDMEMBER SREM SSCAN SUNION SUNIONSTORE

        # Sorted Set Commands
        ZADD ZCARD ZCOUNT ZDIFF ZDIFFSTORE ZINCRBY ZINTER ZINTERCARD ZINTERSTORE
        ZLEXCOUNT ZMPOP ZMSCORE ZPOPMAX ZPOPMIN ZRANDMEMBER ZRANGE ZRANGEBYLEX
        ZRANGEBYSCORE ZRANGESTORE ZRANK ZREM ZREMRANGEBYLEX ZREMRANGEBYRANK
        ZREMRANGEBYSCORE ZREVRANGE ZREVRANGEBYLEX ZREVRANGEBYSCORE ZREVRANK
        ZSCAN ZSCORE ZUNION ZUNIONSTORE

        # HyperLogLog Commands
        PFADD PFCOUNT PFMERGE

        # Connection Commands
        AUTH ECHO PING SELECT

        # Server Commands
        BGREWRITEAOF BGSAVE DBSIZE FLUSHALL FLUSHDB INFO LASTSAVE SAVE TIME

        # Scripting Commands
        EVAL EVALSHA

        # Geo Commands
        GEOADD GEODIST GEOHASH GEOPOS GEORADIUS GEORADIUSBYMEMBER

        # Stream Commands
        XACK XADD XCLAIM XDEL XGROUP XINFO XLEN XPENDING XRANGE XREAD
        XREADGROUP XREVRANGE XTRIM

        # Generic Commands
        DEL DUMP EXISTS EXPIRE EXPIREAT KEYS MIGRATE MOVE OBJECT PERSIST
        PEXPIRE PEXPIREAT PTTL RANDOMKEY RENAME RENAMENX RESTORE SORT
        TOUCH TTL TYPE UNLINK WAIT SCAN
    )
    for cmd in "${commands[@]}"; do
        execute_command_no_args "$cmd"
    done

    if [[ $FAILED_COUNT -le 6 ]]; then
        log_result "PASSED : Negative testing without args validated successfully. Failed count : $FAILED_COUNT"
    else
        log_result "FAILED : Negative testing without args validation failed(${FAILED_COUNT}). Exiting."
        exit 1
    fi
}

start_time=$(date +%s)
$VALKEY_CMD flushall SYNC 2>/dev/null | grep -v option | grep -wq OK
log_result "Test case 01 ============= Negative Testing - Wrong Type =========================="
negative_testing
sleep 5
log_result "Test case 02 ============= Negative Testing - No Arguments ========================"
negative_testing_no_args
$VALKEY_CMD flushall SYNC 2>/dev/null | grep -v option | grep -wq OK
