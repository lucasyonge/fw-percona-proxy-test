#!/bin/bash

PROXY_HOST="${PROXY_HOST:?Set PROXY_HOST}"
PROXY_PORT="${PROXY_PORT:-7777}"
REQUESTS=${REQUESTS:-2000}
CONNECTIONS=${CONNECTIONS:-200}

list_key="${KEY_PREFIX:-}mylist"
string_key="${KEY_PREFIX:-}mykey"
stream_key="${KEY_PREFIX:-}mystream"
group=mygroup
lua_script="return server.call('set', KEYS[1], ARGV[1])"

commands=(
  'LPUSH "$list_key" value1'
  'LSET "$list_key" 0 new_value'
  'LPOS "$list_key" new_value'
  'BITPOS "$string_key" 1'
  'XADD "$stream_key" "*" field1 value1'
  'XRANGE "$stream_key" - +'
  'XREVRANGE "$stream_key" + -'
  'XLEN "$stream_key"'
  'XDEL "$stream_key" "$entry_id"'
  'XTRIM "$stream_key" MAXLEN 1000'
  'XGROUP SETID "$stream_key" "$group" 0'
  'EVAL "$lua_script" 1 "$string_key" myvalue'
  'SCRIPT LOAD "$lua_script"'
  'EVALSHA "$script_id" 1 "$string_key" myvalue'
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

OUTPUT_FILENAME="${0/.sh/_result.csv}"
export OUTPUT_FILENAME

cli=(valkey-cli -h "$PROXY_HOST" -p "$PROXY_PORT" --raw -e)
benchmark=(valkey-benchmark -h "$PROXY_HOST" -p "$PROXY_PORT")
if [[ -n ${VALKEY_PWD:-} ]]; then
  export VALKEYCLI_AUTH="$VALKEY_PWD"
  benchmark+=(-a "$VALKEY_PWD")
fi

script_id=$("${cli[@]}" SCRIPT LOAD "$lua_script" 2>&1) || {
  printf 'SCRIPT LOAD failed: %s\n' "$script_id" >&2
  exit 1
}

# Reuse the group when the script runs again against the same stream.
if ! group_result=$("${cli[@]}" XGROUP CREATE "$stream_key" "$group" 0 MKSTREAM 2>&1); then
  if [[ $group_result != BUSYGROUP\ * ]]; then
    printf 'XGROUP CREATE failed: %s\n' "$group_result" >&2
    exit 1
  fi
fi

entry_id=$("${cli[@]}" XADD "$stream_key" '*' field1 value1 2>&1) || {
  printf 'XADD setup failed: %s\n' "$entry_id" >&2
  exit 1
}

# truncate old benchmark result
echo "" >"${OUTPUT_FILENAME}"

status=0
run_benchmark() {
  printf "${BLUE}Running benchmark for${NC}"
  printf ' %q' "$@"
  printf '\n'
  "${benchmark[@]}" --rps "$REQUESTS" -c "$CONNECTIONS" --csv -- "$@" 2> >(grep -v "WARNING: Could not fetch server CONFIG" >&2) | tail -1 >>"${OUTPUT_FILENAME}" || status=1
  # printf "${GREEN} benchmark for '$@' completed${NC}"
}

for cmd in "${commands[@]}"; do
  eval run_benchmark $cmd &
  sleep 2
done
printf "${CYAN} waiting for benchmarking processes to complete...${NC}\n"
wait
printf "${GREEN} benchmark completed, view result in '${OUTPUT_FILENAME}'${NC}\n"
exit "$status"
