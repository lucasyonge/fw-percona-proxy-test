#!/bin/bash

# Configuration
VALKEYCLI_AUTH="${VALKEY_PWD}"
export VALKEYCLI_AUTH
VALKEY_HOST="${VALKEY_HOST:?Set VALKEY_HOST to the proxy host}"
VALKEY_PORT="${VALKEY_PORT:-6379}"
NUM_CHANNELS="${NUM_CHANNELS:-7000}"
NUM_PATTERNS="${NUM_PATTERNS:-3000}"                           # Number of patterns to subscribe to
PUBLISH_DURATION="${PUBLISH_DURATION:-1800}"                   # 1800 / 30 minutes in seconds
PUBLISH_IOPS="${PUBLISH_IOPS:-100}"                            # Messages per second
RANDOM_OPERATIONS_INTERVAL="${RANDOM_OPERATIONS_INTERVAL:-10}" # Seconds
ITERATIONS="${ITERATIONS:-2000}"                               # Number of iterations to run the script

# Function to generate a random channel name
generate_channel_name() {
    echo "channel_$(openssl rand -hex 8)"
}

# Function to generate a random pattern
generate_pattern() {
    echo "pattern_$(openssl rand -hex 4)*"
}

# Function to subscribe to channels and patterns
subscribe_channels_and_patterns() {
    local num_channels=${1}
    local num_patterns=${2}
    local channels=()
    local patterns=()

    for ((i = 0; i < num_channels; i++)); do
        channel=$(generate_channel_name)
        channels+=("${channel}")
        valkey-cli -h ${VALKEY_HOST} -p ${VALKEY_PORT} SUBSCRIBE "${channel}" >/dev/null 2>&1 &
    done

    for ((i = 0; i < num_patterns; i++)); do
        pattern=$(generate_pattern)
        patterns+=("${pattern}")
        valkey-cli -h ${VALKEY_HOST} -p ${VALKEY_PORT} PSUBSCRIBE "${pattern}" >/dev/null 2>&1 &
    done

    echo "${channels[@]}|${patterns[@]}"
}

# Function to publish messages
publish_messages() {
    local channels=("$@")
    local start_time=$(date +%s)
    local message_count=0

    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))

        if [ ${elapsed} -ge ${PUBLISH_DURATION} ]; then
            break
        fi

        for channel in "${channels[@]}"; do
            message="Message to ${channel} at $(date)"
            valkey-cli -h ${VALKEY_HOST} -p ${VALKEY_PORT} PUBLISH "${channel}" "${message}" >/dev/null
            message_count=$((message_count + 1))

            if [ $((message_count % PUBLISH_IOPS)) -eq 0 ]; then
                sleep 1
            fi
        done
    done
}

# Function to unsubscribe from channels and patterns
unsubscribe_channels_and_patterns() {
    local channels_and_patterns=("$@")
    IFS='|' read -ra split <<<"${channels_and_patterns}"
    local channels=(${split[0]})
    local patterns=(${split[1]})

    for channel in "${channels[@]}"; do
        valkey-cli -h ${VALKEY_HOST} -p ${VALKEY_PORT} UNSUBSCRIBE "${channel}" >/dev/null 2>&1
    done

    for pattern in "${patterns[@]}"; do
        valkey-cli -h ${VALKEY_HOST} -p ${VALKEY_PORT} PUNSUBSCRIBE "${pattern}" >/dev/null 2>&1
    done
}

# Function to perform random operations
perform_random_operations() {
    local op_type=$((RANDOM % 5))
    local channel=$(generate_channel_name)
    local pattern=$(generate_pattern)

    case ${op_type} in
    0)
        # Subscribe
        valkey-cli -h ${VALKEY_HOST} -p ${VALKEY_PORT} SUBSCRIBE "${channel}" >/dev/null 2>&1 &
        echo "Subscribed to ${channel}"
        ;;
    1)
        # Publish
        message="Random message to ${channel} at $(date)"
        valkey-cli -h ${VALKEY_HOST} -p ${VALKEY_PORT} PUBLISH "${channel}" "${message}" >/dev/null
        echo "Published to ${channel}"
        ;;
    2)
        # Unsubscribe
        valkey-cli -h ${VALKEY_HOST} -p ${VALKEY_PORT} UNSUBSCRIBE "${channel}" >/dev/null 2>&1
        echo "Unsubscribed from ${channel}"
        ;;
    3)
        # PSubscribe
        valkey-cli -h ${VALKEY_HOST} -p ${VALKEY_PORT} PSUBSCRIBE "${pattern}" >/dev/null 2>&1 &
        echo "PSubscribed to ${pattern}"
        ;;
    4)
        # PUnsubscribe
        valkey-cli -h ${VALKEY_HOST} -p ${VALKEY_PORT} PUNSUBSCRIBE "${pattern}" >/dev/null 2>&1
        echo "PUnsubscribed from ${pattern}"
        ;;
    esac
}

# Main loop using the ITERATIONS variable
for ((iter = 1; iter <= ITERATIONS; iter++)); do
    echo "Starting iteration ${iter} of ${ITERATIONS}..."

    # Subscribe to channels and patterns
    echo "Subscribing to ${NUM_CHANNELS} channels and ${NUM_PATTERNS} patterns..."
    channels_and_patterns=$(subscribe_channels_and_patterns ${NUM_CHANNELS} ${NUM_PATTERNS})
    IFS='|' read -ra split <<<"${channels_and_patterns}"
    channels=(${split[0]})

    # Start publishing messages in the background
    echo "Starting to publish messages for ${PUBLISH_DURATION} seconds..."
    publish_messages "${channels[@]}" &
    publish_pid=$!

    # Perform random operations while publishing
    echo "Performing random operations..."
    start_time=$(date +%s)
    while kill -0 ${publish_pid} 2>/dev/null; do
        perform_random_operations
        sleep ${RANDOM_OPERATIONS_INTERVAL}
    done

    # Wait for publishing to complete
    wait ${publish_pid}

    # Unsubscribe from channels and patterns
    echo "Unsubscribing from channels and patterns..."
    unsubscribe_channels_and_patterns "${channels_and_patterns}"

    echo "Iteration ${iter} of ${ITERATIONS} complete."

    if [ ${iter} -lt ${ITERATIONS} ]; then
        echo "Pausing before next iteration..."
        sleep 5 # Small pause between iterations
    fi
done

echo "All iterations complete."
