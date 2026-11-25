#!/bin/bash

# Configuration
NAMESPACE="${NAMESPACE:?Set NAMESPACE to the k8s namespace of the Valkey cluster}"
LABEL_SELECTOR="${LABEL_SELECTOR:-role=primary}"
VALKEY_PASSWORD="${VALKEY_PASSWORD:-""}"
VALKEY_PORT="6379"
INTERVAL_MINUTES=900

# Function to kill Valkey clients
kill_valkey_clients() {
    local pod_ip=$1
    local client_types=("normal" "pubsub")

    for client_type in "${client_types[@]}"; do
        echo "Killing $client_type clients on $pod_ip"
        kubectl exec -n "$NAMESPACE" "$pod_name" -c server -- \
            valkey-cli -h "$pod_ip" -p $VALKEY_PORT --user default -a "$VALKEY_PASSWORD" --no-auth-warning \
            CLIENT KILL TYPE "$client_type"
    done
}

# Main loop
while true; do
    echo "Starting client kill process at $(date)"

    # Get pod IPs
    pod_list=$(kubectl get valkeynodes -n "$NAMESPACE" \
        -o go-template='{{range .items}}{{with .status}}{{if and (eq .role "primary") .podIP}}{{printf "%s %s\n" .podIP .podName}}{{end}}{{end}}{{end}}')

    # Process each pod
    while IFS=$' ' read -r pod_ip pod_name; do
        echo "Processing pod: $pod_name ($pod_ip)"
        kill_valkey_clients "$pod_ip"
    done <<<"$pod_list"

    echo "Finished client kill process at $(date)"
    echo "Waiting for $INTERVAL_MINUTES minutes before next iteration..."
    sleep $INTERVAL_MINUTES
done
