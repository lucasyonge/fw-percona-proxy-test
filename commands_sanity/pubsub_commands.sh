#!/bin/bash
# shellcheck disable=SC2329

VALKEY_HOST="${VALKEY_HOST:-localhost}"
VALKEY_PORT="${VALKEY_PORT:-7777}"
VALKEY_PASSWORD="${VALKEY_PASSWORD:-}"

CONN_OPTS=(-h "$VALKEY_HOST" -p "$VALKEY_PORT" -d '\n' --no-auth-warning --raw)
if [[ -n "$VALKEY_PASSWORD" ]]; then
    CONN_OPTS+=(-a "$VALKEY_PASSWORD")
fi

TEST_CHANNEL="test_channel_100"
SUBSCRIBER_LOG="./subscriber_output.log"

# Function to execute Valkey commands
valkey_cmd() {
    valkey-cli -e "${CONN_OPTS[@]}" "$@" 2>&1
}
# Function to validate command output
validate_output() {
    command="$1"
    output="$2"
    expected="$3"

    if [ "$output" = "$expected" ]; then
        echo "$(date) : PASSED : ✅ Command successful : $command"
        echo "$(date) : INFO   :                Output : $output"
    else
        echo "$(date) : FAILED : ❌ Unexpected result for command : $command"
        echo "$(date) : INFO   :                         Expected : $expected"
        echo "$(date) : INFO   :                           Actual : $output"
    fi
}
kill_clients() {
    SUB_CLIENTS=$(valkey_cmd CLIENT LIST | grep -ic cmd=subscribe)
    if [ "${SUB_CLIENTS}" -gt 0 ]; then
        echo "$(date) : INFO : ${SUB_CLIENTS} subscribe connections found for ${VALKEY_HOST}. Killing them."
        ps -aef | grep -i subscribe | grep "${VALKEY_HOST}" | grep -v grep | awk '{print $2}' | xargs kill -9
        SUB_CLIENTS=$(valkey_cmd CLIENT LIST | grep -ic cmd=subscribe)
        if [ "${SUB_CLIENTS}" -gt 0 ]; then
            echo "$(date) : FAILED : ${SUB_CLIENTS} subscribe connections still found for ${VALKEY_HOST}."
        else
            echo "$(date) : INFO : All subscribe connections killed for ${VALKEY_HOST}"
        fi
    else
        echo "$(date) : INFO : No subscribe connections found for ${VALKEY_HOST}"
    fi
}

validate_pubsub_numsub() {
    EXP_CNT="$1"
    EXP_VALUE="${TEST_CHANNEL}\\n$EXP_CNT"
    command_result=$(valkey_cmd pubsub numsub ${TEST_CHANNEL})
    if [[ "${command_result}" == "${EXP_VALUE}" ]]; then
        echo "$(date) : INFO : numsub validation succeeded : ${command_result} subscribers for ${TEST_CHANNEL}."
    else
        echo "$(date) : FAILED : numsub validation failed : ${command_result} subscribers for ${TEST_CHANNEL} as against ${EXP_CNT} subscribers."
    fi
}

validate_pubsub_numpat() {
    EXP_VALUE=$1
    command_result=$(valkey_cmd pubsub numpat | awk '{print $NF}' | sed 's/\r//g' | sed 's/ //g')
    if [ ${command_result} -eq ${EXP_VALUE} ]; then
        echo "$(date) : INFO : numpat validation succeeded : ${command_result} patterns found."
    else
        echo "$(date) : FAILED : numpat validation failed : ${command_result} patterns as against ${EXP_VALUE} patterns."
    fi
}

test_publish_with_no_existing_subscribers() {
    echo "$(date) : INFO : Executing PUBLISH command when no subscribers are present for ${TEST_CHANNEL}."
    # Existing validations
    kill_clients
    validate_pubsub_numsub 0
    validate_pubsub_numpat 0
    result=$(valkey_cmd PUBLISH ${TEST_CHANNEL} "Hello")
    command_result=$(echo $result | awk '{print $NF}' | sed 's/\r//g' | sed 's/ //g')
    validate_output "PUBLISH" "$command_result" "0"
}
test_subscribe_to_channel() {
    echo "$(date) : INFO : Subscribing to ${TEST_CHANNEL}"
    command_result="$(timeout 5 valkey-cli -e "${CONN_OPTS[@]}" SUBSCRIBE "${TEST_CHANNEL}")"
    validate_output "SUBSCRIBE" "$command_result" "subscribe\n${TEST_CHANNEL}\n1"
}
test_publish_when_having_subscriber() {
    echo "$(date) : INFO : Executing PUBLISH command when 1 subscribe connection is present for ${TEST_CHANNEL}."
    validate_pubsub_numsub 0
    echo "$(date) : INFO : Creating a subscriber for ${TEST_CHANNEL}"
    timeout 15 valkey-cli -e "${CONN_OPTS[@]}" SUBSCRIBE "${TEST_CHANNEL}" >/dev/null &
    validate_pubsub_numsub 1
    result="$(valkey_cmd PUBLISH ${TEST_CHANNEL} "Hello")"
    validate_output "PUBLISH" "$result" "1"
    kill_clients
    command_result="$(timeout 5 valkey-cli -e "${CONN_OPTS[@]}" SUBSCRIBE "${TEST_CHANNEL}")"
    validate_output "SUBSCRIBE" "$command_result" "subscribe\n${TEST_CHANNEL}\n1"

}

test_psubscribe() {
    echo "$(date) : INFO : PSubscribing to ${TEST_CHANNEL}*"
    validate_pubsub_numpat 0
    command_result="$(timeout 5 valkey-cli -e "${CONN_OPTS[@]}" PSUBSCRIBE "${TEST_CHANNEL}*")"
    validate_output "PSUBSCRIBE" "$command_result" "psubscribe\n${TEST_CHANNEL}*\n1"
}

test_unsubscribe() {
    echo "$(date) : INFO : Unsubscribing from channel ${TEST_CHANNEL}"
    command_result=$(valkey_cmd unsubscribe ${TEST_CHANNEL})
    validate_output "UNSUBSCRIBE" "$command_result" "unsubscribe\n${TEST_CHANNEL}\n0"

    echo "$(date) : INFO : PUnsubscribing from ${TEST_CHANNEL}*"
    command_result=$(valkey_cmd unsubscribe ${TEST_CHANNEL})
    validate_output "PUNSUBSCRIBE" "$command_result" "unsubscribe\n${TEST_CHANNEL}\n0"
    kill_clients
}

test_list_subscribed_channels() {
    echo "$(date) : INFO : Listing the subscribed channels and validating if the ${TEST_CHANNEL} is present."
    timeout 15 valkey-cli -e "${CONN_OPTS[@]}" SUBSCRIBE "${TEST_CHANNEL}" >/dev/null &
    sleep 1
    command_result=$(valkey_cmd pubsub channels ${TEST_CHANNEL})
    validate_output "PUBSUB CHANNELS" "$command_result" "${TEST_CHANNEL}"
    kill_clients

}

test_publish_with_no_existing_subscribers
test_subscribe_to_channel
test_publish_when_having_subscriber
test_psubscribe
test_unsubscribe
test_list_subscribed_channels
