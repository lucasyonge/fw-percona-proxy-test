#!/bin/bash

helm repo add valkey https://valkey.io/valkey-helm
helm repo update
helm install valkey-operator valkey/valkey-operator -n valkey-operator-system --create-namespace

kubectl apply -f ./cr/valkey-cluster.yaml
