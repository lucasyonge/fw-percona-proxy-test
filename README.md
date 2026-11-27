# fw-percona-proxy-test

Build and deploy Valkey Proxy on kind, run command sanity and endurance tests against a Valkey or proxy endpoint, and check Envoy's Redis proxy for memory leaks.

## Layout

| Folder | What it contains |
|---|---|
| [`commands_sanity/`](commands_sanity) | Functional, pub/sub, MULTI/EXEC, and negative tests for a Valkey or proxy endpoint. |
| [`k8s/`](k8s) | Docker build and Kubernetes deployment for Valkey Proxy on kind. |
| [`valgrind-memory-leak-scripts/`](valgrind-memory-leak-scripts) | Drives blocking, non-blocking and transaction workloads against an Envoy binary running under Valgrind to detect leaks. |
| [`address-sanitiser-scripts/`](address-sanitiser-scripts) | Same style of workload for an Envoy build compiled with AddressSanitizer. |
| [`endurance-test-scripts/`](endurance-test-scripts) | Long-running load (redis-benchmark-go, pub/sub churn, streams) and periodic client kills to check proxy stability over time. |

## Run Valkey Proxy on kind

Use Docker, a running default kind cluster, and a `kubectl` context pointing to that cluster. The proxy expects a Valkey Cluster backend at `valkey-benchmark-cluster.default.svc.cluster.local:6379` by default. Set `server-ip` and `server-port` in the manifest if your backend uses a different address. [Proxy manifest](k8s/cr/proxy.yaml)

From the repository root, build and deploy the image and forward the Service to your local machine.

```bash
cd k8s
./build-valkey-proxy.sh
kubectl rollout status deployment/valkey-proxy
kubectl port-forward service/valkey-proxy 7777:7777
```

Keep the port-forward running. From a second shell, check the endpoint with `valkey-cli -h localhost -p 7777 PING`, then run the command sanity examples below from the repository root. [Deployment reference](TEST_SCRIPTS.md#deploy-valkey-proxy-on-kind)

## Command sanity tests

Run the scripts from this repository with Bash and `valkey-cli` on your `PATH`. They connect directly to the configured endpoint from your shell. The old `envoy_commands_sanity/` directory and `test_params_envoy.cfg` were replaced by `commands_sanity/` and the connection settings below.

| Script | Coverage | Connection settings |
|---|---|---|
| [`commands_sanity.sh`](commands_sanity/commands_sanity.sh) | General command coverage, including strings, sets, sorted sets, blocking lists, streams, hashes, scripts, and cluster commands. Uses `valkey-cli -c`. | `PROXY_HOST` defaults to `localhost` and `PROXY_PORT` to `7777`. |
| [`commands_sanity_valkey8.sh`](commands_sanity/commands_sanity_valkey8.sh) | Focused checks for `SET IFEQ`, nested `MULTI`, `WATCH` inside `MULTI`, `SCAN` and bit-command errors, `BGSAVE CANCEL`, and client filters. | Connects to `localhost`. `PROXY_PORT` defaults to `7777`. |
| [`pubsub_commands.sh`](commands_sanity/pubsub_commands.sh) | Checks publish counts with and without a subscriber, channel and pattern subscriptions, and `PUBSUB` counters and channel listings. | `VALKEY_HOST` defaults to `localhost` and `VALKEY_PORT` to `7777`. Set `VALKEY_PASSWORD` when authentication is required. |
| [`pubsub_commands_valkey8.sh`](commands_sanity/pubsub_commands_valkey8.sh) | Runs pipe-delimited pub/sub and client-command cases from [`data/pubsub_commands_valkey8.csv`](commands_sanity/data/pubsub_commands_valkey8.csv). | Same settings as `pubsub_commands.sh`. |
| [`transaction_commands.sh`](commands_sanity/transaction_commands.sh) and [`transaction_commands_valkey8.sh`](commands_sanity/transaction_commands_valkey8.sh) | Run command cases inside `MULTI`/`EXEC`. The Valkey 8 entry point sources the shared transaction runner. | Set `VALKEY_HOST`. `VALKEY_PORT` defaults to `6379`. Set `VALKEY_PASSWORD` when authentication is required. |
| [`negative_testing_commands_valkey8.sh`](commands_sanity/negative_testing_commands_valkey8.sh) | Checks authentication, wrong-type operations, malformed commands, and missing arguments. | `VALKEY_HOST` defaults to `localhost` and `VALKEY_PORT` to `7777`. Set `VALKEY_PASSWORD` for authentication checks against a password-protected endpoint. |

The general, Valkey 8 feature, transaction, and negative suites issue `FLUSHALL`. Run them against a disposable test endpoint. The general and pub/sub suites use `timeout`, and the Valkey 8 pub/sub suite also uses `stdbuf`. The transaction runner requires Bash with `readarray`.

Run these examples from the repository root with a test endpoint on `localhost:7777`.

```bash
PROXY_HOST=localhost PROXY_PORT=7777 ./commands_sanity/commands_sanity.sh
PROXY_PORT=7777 ./commands_sanity/commands_sanity_valkey8.sh
VALKEY_HOST=localhost VALKEY_PORT=7777 ./commands_sanity/pubsub_commands_valkey8.sh
VALKEY_HOST=localhost VALKEY_PORT=7777 ./commands_sanity/transaction_commands.sh
```

Review the scripts’ result logs for failed checks. Some suites continue after logging a failure.

## Other test suites

See the script reference for [Valgrind](TEST_SCRIPTS.md#valgrind-memory-leak-scripts), [AddressSanitizer](TEST_SCRIPTS.md#address-sanitiser-scripts), and [endurance tests](TEST_SCRIPTS.md#endurance-test-scripts).

## License

[Apache License 2.0](LICENSE)
