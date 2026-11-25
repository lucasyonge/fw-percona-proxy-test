#!/bin/bash
set -e
# Sample command to run
# ./endurance_automation.sh <redis_password> <proxy_host> <proxy_port> 500 200 result_cx.txt commands.txt

if [[ $# -ne 7 ]]; then
    printf 'Usage: %s <password_or_empty> <proxy_host> <proxy_port> <rps> <connections> <result_prefix> <commands_file>\n' "$0" >&2
    exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# init the streams
if [[ "$(valkey-cli -h $2 -p $3 --raw EXISTS order_stream)" == "0" ]]; then
    valkey-cli -h "$2" -p "$3" XGROUP CREATE order_stream order_processors '$' MKSTREAM
fi
benchmark=(valkey-benchmark -h "$2" -p "$3" --rps "$4" -c "$5" --csv)
if [[ -n $1 ]]; then
    benchmark+=(-a "$1")
fi
if [[ -n ${BENCHMARK_REQUESTS:-} ]]; then
    benchmark+=(-n "$BENCHMARK_REQUESTS")
fi
result_prefix=$6
commands_file=$7
delay="${BENCHMARK_START_DELAY:-2}"
if [[ ! $delay =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]]; then
    printf 'BENCHMARK_START_DELAY must be a nonnegative number of seconds\n' >&2
    exit 1
fi

# Split a line into arguments, honoring quotes and escapes without shell expansion.
parse_command() {
    local line=$1 char next quote= word= started= i
    args=()
    for ((i = 0; i < ${#line}; i++)); do
        char=${line:i:1}
        if [[ -n $quote ]]; then
            if [[ $char == "$quote" ]]; then
                quote=
            else
                next=${line:i+1:1}
                if [[ $quote == '"' && $char == '\' && ($next == '"' || $next == '\') ]]; then
                    char=$next
                    i=$((i + 1))
                fi
                word+=$char
            fi
            continue
        fi

        case $char in
        "'" | '"')
            quote=$char
            started=1
            ;;
        '\')
            i=$((i + 1))
            ((i < ${#line})) || return 1
            word+=${line:i:1}
            started=1
            ;;
        [[:space:]])
            if [[ -n $started ]]; then
                args+=("$word")
                word=
                started=
            fi
            ;;
        *)
            word+=$char
            started=1
            ;;
        esac
    done
    [[ -z $quote ]] || return 1
    if [[ -n $started ]]; then
        args+=("$word")
    fi
}

commands=()
line_numbers=()
arg_counts=()
command_args=()
line_number=0

while IFS= read -r line || [[ -n $line ]]; do
    line_number=$((line_number + 1))
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [[ -z $line || $line == \#* ]] && continue
    if ! parse_command "$line" || [[ -z ${args[0]} ]]; then
        printf '%s:%s: invalid command or unterminated quote or escape\n' "$commands_file" "$line_number" >&2
        exit 1
    fi
    commands+=("$line")
    line_numbers+=("$line_number")
    arg_counts+=("${#args[@]}")
    command_args+=("${args[@]}")
done <"$commands_file"

if ((${#commands[@]} == 0)); then
    printf '%s: no benchmark commands\n' "$commands_file" >&2
    exit 1
fi

pids=()
logs=()
offset=0
for index in "${!commands[@]}"; do
    printf -v log_path 'results_endurance/%s_%03d.log' "$result_prefix" "${line_numbers[index]}"
    mkdir -p "${log_path%/*}"
    if ((index > 0)); then
        sleep "$delay"
    fi
    count=${arg_counts[index]}
    "${benchmark[@]}" -- "${command_args[@]:offset:count}" >"$log_path" 2>&1 &
    pids+=("$!")
    logs+=("$log_path")
    printf 'Started PID %s for %s\n' "$!" "${commands[index]}"
    offset=$((offset + count))
done

failed=0
for index in "${!pids[@]}"; do
    result=0
    wait "${pids[index]}" || result=$?
    rps=
    p50=
    if ((result == 0)); then
        while IFS= read -r line; do
            [[ $line == '"'* && $line != '"test","rps",'* ]] || continue
            # Read metric columns from the end because command titles can contain commas.
            IFS=, read -r -a fields <<<"$line"
            count=${#fields[@]}
            if ((count >= 8)); then
                rps=${fields[count - 7]//\"/}
                p50=${fields[count - 4]//\"/}
            fi
        done <"${logs[index]}"
    fi
    if ((result != 0)) || [[ -z $rps || -z $p50 ]]; then
        failed=$((failed + 1))
        printf "${RED}FAIL${NC} %s (benchmark exit %s, see %s)\n" "${commands[index]}" "$result" "${logs[index]}" >&2
    else
        printf "${GREEN}PASS${NC} %s (%s requests/sec, p50 %s ms)\n" "${commands[index]}" "$rps" "$p50"
    fi
done

printf '%s/%s benchmarks passed\n' "$((${#pids[@]} - failed))" "${#pids[@]}"
((failed == 0))
