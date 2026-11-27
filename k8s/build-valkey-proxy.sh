#!/bin/bash
docker build -f valkey-proxy.Dockerfile -t valkey-proxy:latest .
kind load docker-image valkey-proxy:latest
kubectl apply -f cr/proxy.yaml
