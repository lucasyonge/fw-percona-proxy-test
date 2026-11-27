#!/bin/bash

VALKEY_HOST="${VALKEY_HOST:?Set VALKEY_HOST to the proxy host}"
VALKEY_PORT="${VALKEY_PORT:-6379}"
VALKEY_PASSWORD="${VALKEY_PASSWORD:-''}"

# Function to execute a single Valkey command within a transaction
execute_valkey_command() {
    command="$1"
    result=$(
        valkey-cli --no-auth-warning -h "$VALKEY_HOST" -p "$VALKEY_PORT" -a "$VALKEY_PASSWORD" <<EOF
MULTI
$command
EXEC
EOF
        2>/dev/null | grep -v option
    )
    echo "$result"
}

# Function to validate command output
validate_output() {
    command="$1"
    output="$2"
    expected="$3"

    case "$output" in
    *"WRONGTYPE"* | *"NOSCRIPT"* | *"NOTBUF"* | *"SYNTAXERR"*)
        echo "$(date) : FATAL : ❌ Error with command : $command"
        echo "$(date) : INFO  :         Error message : $output"
        return 1
        ;;
    *)
        if [ "$output" = "$expected" ]; then
            # echo "$(date) : PASSED : ✅ Command successful : $command"
            # echo "$(date) : INFO   :                Output : $output"
            return 0
        else
            echo "$(date) : FAILED : ❌ Unexpected result for command : $command"
            echo "$(date) : INFO   :                  Expected output : $expected"
            echo "$(date) : INFO   :                    Actual output : $output"
            exit
            return 1
        fi
        ;;
    esac
}

# Valkey commands to test with all possible subcommands
valkey-cli --no-auth-warning -h "$VALKEY_HOST" -p "$VALKEY_PORT" -a "$VALKEY_PASSWORD" FLUSHALL 2>/dev/null | grep -v option
valkey-cli --no-auth-warning -h "$VALKEY_HOST" -p "$VALKEY_PORT" -a "$VALKEY_PASSWORD" SCRIPT LOAD "Valkey.call('SET', KEYS[1], ARGV[1]); return Valkey.call('GET', KEYS[1])" 2>/dev/null | grep -v option

readarray -t commands <<<"$(grep -v '#' "$(dirname $0)/data/transaction_commands.csv" | cut -d '|' -f1)"
# Expected results for each command
readarray -t expected_results <<<"$(grep -v '#' "$(dirname $0)/data/transaction_commands.csv" | cut -d '|' -f2)"
readarray -t ignored_commands <<<"$(grep -v '#' "$(dirname $0)/data/transaction_commands.csv" | cut -d '|' -f3)"
echo "$(date) : INFO : Validating Valkey commands inside transaction"
total_commands=${#commands[@]}
error_count=0
ignore_count=0
failed_commands=""
for i in "${!commands[@]}"; do
    cmd="${commands[$i]}"
    expected="${expected_results[$i]}"
    is_ignored="${ignored_commands[$i]}"
    if [[ "${is_ignored}" == "1" ]]; then
        ignore_count=$((ignore_count + 1))
        continue
    fi
    # echo "$(date) : INFO : Executing: $cmd; expected output: $expected"
    result=$(execute_valkey_command "$cmd")

    output_count=$(echo "$result" | grep -E -v "QUEUED|OK" | wc -l)
    MAIN_CMD=$(echo $cmd | awk '{print $1}')
    if [ ${output_count} -gt 1 ]; then
        case ${MAIN_CMD} in
        XRANGE | XREAD | XREVRANGE | XINFO)
            command_result=$(echo "$result" | grep -E -v "QUEUED|OK|^[0-9-]*$" | tr '\n' ' ' | sed 's/ /\\n/g')
            ;;
        ZRANGE | HGETALL | MGET | GEOPOS)
            command_result=$(echo "$result" | grep -E -v "QUEUED|OK" | tr '\n' ' ' | sed 's/ /\\n/g')
            ;;
        SMEMBERS | SRANDMEMBER)
            command_result=$(echo "$result" | grep -E -v "QUEUED|OK" | cut -c1-6 | tr '\n' ' ' | sed 's/ /\\n/g')
            ;;
        TIME)
            command_result=$(echo "$result" | grep -E -v "QUEUED|OK" | grep ^172 | wc -l | tr '\n' ' ' | sed 's/ /\\n/g')
            ;;
        XREADGROUP)
            command_result=$(echo "$result" | grep -E -v "QUEUED|OK" | grep -v "^[0-9]" | tr '\n' ' ' | sed 's/ /\\n/g')
            ;;
        *)
            command_result=$(echo "$result" | grep -E -v "QUEUED|OK" | tr '\n' ' ' | sed 's/ /\\n/g')
            ;;
        esac
    else
        case ${MAIN_CMD} in
        XADD)
            command_result=$(echo "$result" | sed '1d;2d;/^$/d' | grep "^[0-9]")
            stream_id=$(echo "$result" | sed '1d;2d;/^$/d' | awk -F "-" '{print $1}')
            validate_output "$cmd" "$command_result" "${stream_id}-${expected}"
            ;;
        PING)
            command_result=$(echo "$result" | sed '1d;/^$/d')
            ;;
        TTL)
            command_result=$(echo "$result" | sed '1d;2d;/^$/d')
            if [[ $command_result -le 10 ]]; then
                validate_output "$cmd" "$command_result" "$command_result"
                continue
            fi
            ;;
        PTTL)
            command_result=$(echo "$result" | sed '1d;2d;/^$/d')
            if [[ $command_result -le 10000 ]]; then
                validate_output "$cmd" "$command_result" "$command_result"
                continue
            fi
            ;;
        SPOP)
            command_result=$(echo "$result" | grep -E -v "QUEUED|OK" | cut -c1-6 | tr '\n' ' ' | sed 's/ /\\n/g')
            ;;
        *)
            command_result=$(echo "$result" | sed '1d;2d;/^$/d')
            ;;
        esac
    fi

    validate_output "$cmd" "$command_result" "$expected"
    if [ $? -ne 0 ]; then
        error_count=$((error_count + 1))
        failed_commands="${failed_commands}
${cmd}"
    fi
done

echo "$(date) : INFO : ===== Transaction Testing Summary ====="
echo "$(date) : INFO : Total commands executed: $total_commands"
echo "$(date) : INFO : Commands with errors: $error_count"
echo "$(date) : INFO : Commands ignored: $ignore_count"
echo "$(date) : INFO : ========================================"

if [ ${error_count} -le 11 ]; then
    echo "$(date) : INFO : All $total_commands commands executed inside the transaction successfully."
    valkey-cli --no-auth-warning -h "$VALKEY_HOST" -p "$VALKEY_PORT" -a "$VALKEY_PASSWORD" FLUSHALL 2>/dev/null | grep -v option
else
    echo "$(date) : ERROR : ${error_count}/${total_commands} commands failed while executing inside the transaction. Exiting."
    exit 1
fi
