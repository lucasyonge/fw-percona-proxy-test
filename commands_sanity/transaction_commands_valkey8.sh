#!/bin/bash

script_dir=$(dirname "${BASH_SOURCE[0]}")
transaction_commands_file="$script_dir/data/transaction_commands_valkey8.csv"
valkey8_prechecks_file="$script_dir/data/transaction_commands_valkey8_prechecks.csv"
if [[ ! -r $valkey8_prechecks_file ]]; then
    printf 'Cannot read Valkey 8 transaction prechecks from %s\n' "$valkey8_prechecks_file" >&2
    exit 1
fi

run_valkey8_transaction_checks() {
    local steps expected passed failure_level failed request result
    echo "$(date) : INFO : ========== RUNNING VALKEY 8 SPECIFIC TRANSACTION TESTS =========="
    while IFS='|' read -r steps expected passed failure_level failed || [[ -n $steps ]]; do
        [[ -z $steps || $steps == \#* ]] && continue
        request=${steps//\\n/$'\n'}
        result=$("${valkey_cli[@]}" <<< "$request")
        if [[ $result == *"$expected"* ]]; then
            printf '%s : PASSED : %s\n' "$(date)" "$passed"
        else
            printf '%s : %s : %s\n' "$(date)" "$failure_level" "$failed"
            if [[ $failure_level == FAILED ]]; then
                printf '%s : DEBUG : Actual result: %s\n' "$(date)" "$result"
            fi
        fi
    done < "$valkey8_prechecks_file"
    echo "$(date) : INFO : ========== VALKEY 8 SPECIFIC TESTS COMPLETE =========="
}

source "$script_dir/transaction_commands.sh"
