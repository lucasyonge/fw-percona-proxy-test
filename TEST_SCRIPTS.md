# Test scripts reference

This page describes every script in the repository: what it tests, how to run it, and how it reports pass/fail. For setup and an overview, see the [README](README.md).

| Script | Type | Summary |
| --- | --- | --- |
| [`commands_sanity.sh`](#commands_sanitysh) | Functional | General Valkey command checks, including blocking operations, scripting, streams, and cluster commands |
| [`commands_sanity_valkey8.sh`](#commands_sanity_valkey8sh) | Functional | Standalone checks for Valkey 8 features and error replies |
| [`pubsub_commands.sh`](#pubsub_commandssh) | Functional | Publish counts, channel and pattern subscriptions, and PUBSUB introspection |
| [`pubsub_commands_valkey8.sh`](#pubsub_commands_valkey8sh) | Functional | CSV-driven pub/sub and client-command cases |
| [`transaction_commands.sh`](#transaction_commandssh) / [`transaction_commands_valkey8.sh`](#transaction_commands_valkey8sh) | Functional | Commands wrapped in MULTI/EXEC |
| [`negative_testing_commands_valkey8.sh`](#negative_testing_commands_valkey8sh) | Negative | Authentication, wrong-type operations, and malformed commands |
| [`k8s/build-valkey-proxy.sh`](#deploy-valkey-proxy-on-kind) | Setup | Builds the Valkey Proxy image and deploys it to a kind cluster |
| [`valgrind-memory-leak-scripts/*`](#valgrind-memory-leak-scripts) | Memory | Workloads against Envoy running under Valgrind |
| [`address-sanitiser-scripts/*`](#address-sanitiser-scripts) | Memory | Workloads against an ASan-instrumented Envoy build |
| [`endurance-test-scripts/*`](#endurance-test-scripts) | Endurance | Long-running benchmark, pub/sub churn, streams and periodic client kills |

## `commands_sanity/`

All seven scripts invoke `valkey-cli` from the local shell. Install Bash and `valkey-cli`, then use the connection variables listed below. Environment variables replace the former Kubernetes config file. The two command sanity scripts use `PROXY_*` variables. The pub/sub, transaction, and negative scripts use `VALKEY_*` variables. Run the examples from the repository root.

**Use a disposable test endpoint.** The general, Valkey 8 feature, transaction, and negative scripts issue `FLUSHALL`. Some pub/sub and feature checks also terminate client connections.

### `commands_sanity.sh`

This suite connects with `valkey-cli -c --raw`. `PROXY_HOST` defaults to `localhost` and `PROXY_PORT` to `7777`. The cluster cases expect a cluster-aware endpoint. Install a `timeout` that supports `--kill-after`, such as GNU coreutils `timeout`.

```bash
PROXY_HOST=localhost PROXY_PORT=7777 ./commands_sanity/commands_sanity.sh
```

| Case | Coverage |
| --- | --- |
| 01–02 | Set and sorted-set operations, including union, intersection, and difference. |
| 03 | List and sorted-set pops, `BRPOPLPUSH`, `BLMOVE`, `SORT`, and `LPOS`. Empty-list `BLPOP` and `BRPOP` checks look for a blank raw reply after the server timeout. Six blocking commands with a server timeout of `0` must keep waiting until the local 10-second timeout stops the client. |
| 04 | `SELECT 0`, missing arguments to `CLIENT SETNAME`, and `SCRIPT LOAD`, `EVALSHA`, `SCRIPT EXISTS`, and `SCRIPT FLUSH SYNC`. |
| 05 | `CLUSTER KEYSLOT` expects slot 6918 for both `{test}1` and `{test}2`. `CLUSTER SLOTS` is parsed from CSV output and the slot ranges must total 16384. |
| 06–09 | String operations, streams and consumer groups, `PING`/`TIME`/`QUIT`/`EXIT`, and hashes. The blocking stream test attempts both a short read and a read that waits for the local timeout. |
| 11 | `FLUSHALL`, `GETEX` expiration, `GETDEL`, `MSETNX`, `EXISTS`, `DEL`, `COPY`, and `SCAN`. Positive `SCAN` checks require at least one matching key. Invalid cursor values must return `ERR invalid cursor`. |

Run the full suite in order because some groups reuse data created earlier. The bitwise group, SLOWLOG checks, and INFO/CONFIG checks are disabled in the script.

The script prints timestamped `INFO`, `PASSED`, `FAILED`, `ERROR`, and `DEBUG` messages. `EXIT_ON_ERROR` is set to `0` in the script, so inspect the log for failures even when the run reaches the elapsed-time line. The BLPOP/BRPOP timeout checks use `./test_block_cmd.log` and delete it when the check passes.

### `commands_sanity_valkey8.sh`

This standalone suite runs the Valkey 8 feature and error checks. The host is fixed to `localhost`, and `PROXY_PORT` defaults to `7777`. Point it at an endpoint that supports the commands and options below.

```bash
PROXY_PORT=7777 ./commands_sanity/commands_sanity_valkey8.sh
```

- `SET ... IFEQ` tests a matching and nonmatching update, then verifies that the stored value is still `v2`.
- Nested `MULTI` and `WATCH` inside `MULTI` each use one local CLI session. The checks look for `MULTI calls can not be nested` and `ERR WATCH inside MULTI is not allowed`, respectively.
- `SCAN 0 TYPE faketype` expects `ERR unknown type name`. The `BITPOS` and `BITCOUNT` cases check invalid arguments on nonexistent keys.
- Server and client checks cover `BGSAVE CANCEL`, `CLIENT KILL MAXAGE 3600`, and the `CLIENT LIST` filters `SKIPME YES` and `MAXAGE 60`. `CLIENT KILL` can disconnect other clients.

The script flushes at startup and again after the checks complete. The invalid `SCAN` type, `BGSAVE CANCEL`, and `CLIENT KILL` checks can log failures and continue. Other failed checks can exit with code 1. A full run prints elapsed time.

### `pubsub_commands.sh`

`VALKEY_HOST` defaults to `localhost` and `VALKEY_PORT` to `7777`. The script adds the `-a` option when `VALKEY_PASSWORD` is nonempty. It requires `timeout`.

```bash
VALKEY_HOST=localhost VALKEY_PORT=7777 ./commands_sanity/pubsub_commands.sh
```

- Publishes `Hello` to `test_channel_100` and expects counts of `0` without a subscriber and `1` with a subscriber. It checks `PUBSUB NUMSUB`, `NUMPAT`, and `CHANNELS`.
- Checks the acknowledgments for `SUBSCRIBE` and `PSUBSCRIBE` using five-second invocations and raw output with literal `\n` separators. Background subscribers used for publish and channel-list checks have a 15-second timeout.
- The check labelled `PUNSUBSCRIBE` currently repeats `UNSUBSCRIBE test_channel_100`.
- Cleanup checks `CLIENT LIST` for `cmd=subscribe`. If it finds an active subscriber, it can kill local processes whose command lines match `subscribe` and `VALKEY_HOST`, including processes started outside the script.

The script prints expected and actual values on failures. Use the `FAILED` lines to determine which checks failed.

### `pubsub_commands_valkey8.sh`

This runner uses the same connection variables as `pubsub_commands.sh` and requires `timeout` and `stdbuf` for timed subscriptions. It reads [`pubsub_commands_valkey8.csv`](commands_sanity/data/pubsub_commands_valkey8.csv) relative to the script.

```bash
VALKEY_HOST=localhost VALKEY_PORT=7777 ./commands_sanity/pubsub_commands_valkey8.sh
```

Each pipe-delimited row contains `command | expected reply | check exit status | ignore`. A third column of `1` checks the CLI exit status. Other values compare the raw reply with the expected text, using literal `\n` separators. A fourth column of `1` skips the row. Lines beginning with `#` are ignored.

The shipped rows cover `UNSUBSCRIBE`, `PUNSUBSCRIBE`, `CLIENT LIST` filters, `CLIENT KILL MAXAGE 3600`, `PUBSUB NUMSUB` and `NUMPAT`, `PUBLISH` with no subscribers, and the `SUBSCRIBE` acknowledgment. The runner bounds the uppercase `SUBSCRIBE` row with a five-second `timeout` and uses `stdbuf` to line-buffer the reply. Review the per-row `PASSED` or `FAILED` messages. Failures are logged without an aggregate failure exit status.

### `transaction_commands.sh`

The runner loads [`transaction_commands.csv`](commands_sanity/data/transaction_commands.csv) and sends each enabled command in a separate `MULTI` / command / `EXEC` session. Each pipe-delimited row contains the command, expected result, and optional ignore flag. A third field of `1` skips the row. Cases run in file order and can depend on keys created earlier. The expected replies include cluster errors and proxy-specific transaction rejections.

Set `VALKEY_HOST` explicitly. `VALKEY_PORT` defaults to `6379`. Set `VALKEY_PASSWORD` for an authenticated endpoint. Use a Bash version with `readarray`.

```bash
VALKEY_HOST=localhost VALKEY_PORT=7777 ./commands_sanity/transaction_commands.sh
```

The runner issues `FLUSHALL` and loads a small SET/GET Lua script before the sweep. It normalizes replies before comparing them with the fixture, including flattening multiline output into literal `\n` separators and applying command-specific handling for replies such as stream IDs and TTLs.

**Command coverage**

- Strings: SET, GET, APPEND, STRLEN, SETEX, PSETEX, TTL, PTTL, SETNX, MSETNX (a cross-slot case that expects `CROSSSLOT` + `EXECABORT`, and a hash-tagged case), MSET, MGET, SETRANGE, GETRANGE, INCR, INCRBY, INCRBYFLOAT, DECR, DECRBY, SETBIT, GETBIT, BITCOUNT, BITPOS, GETSET.
- Lists: LPUSH, RPUSH, LPUSHX, RPUSHX, LLEN, LRANGE, LPOP, RPOP, LINDEX, LSET, LREM, LTRIM, LINSERT, RPOPLPUSH, BLPOP, BRPOP (timeouts 1 and 0), BRPOPLPUSH (timeouts 0 and 1).
- Sets: SADD, SCARD, SMEMBERS, SISMEMBER, SREM, SRANDMEMBER, SMOVE, SDIFF, SDIFFSTORE, SINTER, SINTERSTORE, SUNION, SUNIONSTORE, SPOP.
- Hashes: HSET, HSETNX, HGET, HMSET, HMGET, HGETALL, HDEL, HEXISTS, HKEYS, HVALS, HLEN, HINCRBY, HINCRBYFLOAT, HSCAN.
- Sorted sets: ZADD, ZRANGE … WITHSCORES, ZREVRANGE, ZRANK, ZREVRANK, ZCOUNT, ZINCRBY, ZREM, ZRANGEBYSCORE, ZREVRANGEBYSCORE, ZREMRANGEBYRANK, ZREMRANGEBYSCORE, ZCARD, ZSCORE, ZUNIONSTORE, ZINTERSTORE, ZSCAN, ZRANGEBYLEX, ZLEXCOUNT, ZREMRANGEBYLEX.
- HyperLogLog: PFADD, PFCOUNT, PFMERGE.
- Geo: GEOADD, GEODIST, GEOHASH, GEOPOS, GEORADIUS, GEORADIUSBYMEMBER.
- Streams: XADD (auto and explicit IDs), XLEN, XRANGE, XREVRANGE, XPENDING (before and after the group exists), XGROUP CREATE/DESTROY, XREAD, XREADGROUP, XACK, XINFO STREAM/GROUPS, XTRIM, XDEL.
- Transaction commands nested inside the wrapper: MULTI, SET, GET, EXEC, DISCARD, WATCH, UNWATCH.
- Scripting: EVAL; EVALSHA with an unknown SHA (expects `NOSCRIPT`) and with the SHA of the script loaded at startup (expects `hello`); SCRIPT LOAD/EXISTS/FLUSH (expected to be rejected inside a transaction).
- Connection/server: PING, ECHO and TIME. The CLIENT LIST/GETNAME/SETNAME rows are marked to skip. CONFIG GET, SLOWLOG GET and INFO have fixtures for transaction rejections.
- Keyspace: TYPE, EXISTS, DEL, UNLINK, EXPIRE, PERSIST, TTL, MOVE, RENAME, RENAMENX, SORT … ALPHA. RANDOMKEY, SCAN and KEYS are expected to be rejected inside a transaction.
- Pub/sub: PUBLISH, PUBSUB CHANNELS, UNSUBSCRIBE and PUNSUBSCRIBE are all expected to be rejected inside a transaction. SUBSCRIBE and PSUBSCRIBE are commented out.
- Database: SELECT 1 (expects `DB index is out of range`), SELECT 0 (expects `OK`). FLUSHDB, FLUSHALL, DBSIZE and SWAPDB are expected to be rejected inside a transaction.
- Cluster/modules: CLUSTER INFO/NODES/SLOTS (expected to be rejected), MODULE LIST (expects `(nil)`), MODULE LOAD/UNLOAD (expect an empty result).
- Blocking commands: BLPOP, BRPOP, BRPOPLPUSH, BZPOPMIN, BZPOPMAX and BLMOVE (all four LEFT/RIGHT combinations), with non-zero and zero timeouts, checked with LRANGE.
- XREAD/XREADGROUP argument permutations: 19 XREAD and 23 XREADGROUP orderings of `BLOCK`/`COUNT`/`STREAMS`/`GROUP`/consumer (the XREAD cases include `COUNT 0` and `COUNT -1`). Depending on the ordering, the expected result is a valid read, an empty result, `ERR syntax error`, `CROSSSLOT` + `EXECABORT`, or the "Unbalanced XREAD list of streams" error.
- COPY: `COPY {key}1 {key}2` without `REPLACE` (expects `0`) and with `REPLACE` (expects `1`), verified with MGET.

**Reading the results**

- Matching cases are quiet. A reply containing `WRONGTYPE`, `NOSCRIPT`, `NOTBUF`, or `SYNTAXERR` is logged as `FATAL` and counted as an error. This also applies when the fixture itself expects `NOSCRIPT`.
- An ordinary reply mismatch logs `FAILED` and triggers a bare `exit` in the validator. That can end the run before the summary with status 0.
- If the runner reaches its summary, it reports total fixture rows, errors, and skipped rows. At most 11 counted errors take the final `FLUSHALL` path. More than 11 exits with code 1.

### `transaction_commands_valkey8.sh`

This entry point checks that [`transaction_commands_valkey8_prechecks.csv`](commands_sanity/data/transaction_commands_valkey8_prechecks.csv) is readable, then sources `transaction_commands.sh`. It uses the same connection settings, prerequisites, and reporting.

```bash
VALKEY_HOST=localhost VALKEY_PORT=7777 ./commands_sanity/transaction_commands_valkey8.sh
```

The wrapper sets a path to [`transaction_commands_valkey8.csv`](commands_sanity/data/transaction_commands_valkey8.csv) and defines a helper for the nested `MULTI`, `WATCH`, `SET IFEQ`, `BITCOUNT`, and `BITPOS` prechecks. The shared runner reads `transaction_commands.csv` directly, and the wrapper's normal entry point leaves the precheck helper uncalled.

### `negative_testing_commands_valkey8.sh`

This is the negative suite in `commands_sanity/`. It uses `VALKEY_HOST` and `VALKEY_PORT`, which default to `localhost` and `7777`. For the authentication cases, set `VALKEY_PASSWORD` in your shell to the password for the test endpoint.

```bash
VALKEY_HOST=localhost VALKEY_PORT=7777 ./commands_sanity/negative_testing_commands_valkey8.sh
```

- **Case 01** checks authentication and runs wrong-type operations and malformed commands across strings, lists, sets, hashes, sorted sets, HyperLogLog, geospatial data, pub/sub, transactions, scripting, keys, and streams. It also checks invalid `SCAN` types and cursors and invalid `BITCOUNT`/`BITPOS` arguments. The transaction cases send nested `MULTI` and `WATCH` inside `MULTI` in separate CLI sessions.
- **Case 02** sends a command list with no arguments. It runs a `PING` check before each command and retries every five seconds when the CLI reports a failure. Replies matching `invalid request`, `wrong number of arguments`, `ERR`, or `syntax error` pass. Commands such as `PING`, `FLUSHALL`, `FLUSHDB`, and `DBSIZE` are sent before they are reported as `SKIPPED`.

Case 01 prints a counted summary and exits with code 1 above five counted failures. Authentication messages are logged separately from those counters. Case 02 exits with code 1 above six failures. If both sections stay within their thresholds, the final exit status comes from checking the final `FLUSHALL SYNC` reply for `OK`.

Some expectations depend on endpoint policy and reply wording. For example, the pub/sub case expects `NOPERM` and `SELECT 99` expects a cluster-mode error. Cases with an empty expected substring accept any reply.

---

## Deploy Valkey Proxy on kind

[`build-valkey-proxy.sh`](k8s/build-valkey-proxy.sh) builds the image with Docker, loads `valkey-proxy:latest` into the default kind cluster, and applies the Kubernetes manifest. Run it from `k8s/` because the build context and manifest path are relative to the working directory.

Use a running kind cluster, a `kubectl` context pointing to that cluster, and an existing Valkey Cluster backend. The manifest targets `valkey-benchmark-cluster.default.svc.cluster.local:6379` by default. Update `server-ip` and `server-port` in the ConfigMap if your backend uses a different address.

```bash
cd k8s
./build-valkey-proxy.sh
kubectl rollout status deployment/valkey-proxy
kubectl port-forward service/valkey-proxy 7777:7777
```

- [`valkey-proxy.Dockerfile`](k8s/valkey-proxy.Dockerfile) clones and builds Valkey Proxy from the repository's default branch, then copies the binary into a Debian 12 runtime image.
- [`cr/proxy.yaml`](k8s/cr/proxy.yaml) creates the proxy ConfigMap, a single-replica Deployment, and a ClusterIP Service on port `7777` in the current namespace. The Deployment mounts the config at `/opt/proxy.conf`.

With the port-forward running, use `localhost:7777` for the command sanity examples from a second shell.

---

## valgrind-memory-leak-scripts/

All three scripts check the proxy for memory leaks the same way. For each test group they start Envoy under `valgrind --leak-check=full --show-leak-kinds=all`, wait until the proxy answers `PING`, and send a fixed set of Redis commands through it. They then stop Envoy with SIGTERM, wait 10 s, and pull the valgrind `LEAK SUMMARY` from that group's log.

**Prerequisites shared by all three** (every value is hard-coded; there are no env vars or CLI args):

- Linux with `valgrind` and `redis-cli` on `PATH`.
- An Envoy binary at `./bazel-bin/source/exe/envoy-static`. In practice this means running from the root of an Envoy source tree after a Bazel build.
- An Envoy config named `envoy.yaml` in the current directory, with a `redis_proxy` listener on `127.0.0.1:1999` in front of your Redis/Valkey cluster. **This file is not included**, so you have to write it yourself.
- Python scripts: Python 3.6+ with the standard library only (no pip packages).

---

### `non_blocking_commands.py`

**Purpose**: Runs a wide range of mostly non-transactional Redis commands through the proxy, one group at a time. Each of its 69 groups (66 unique names) gets a fresh valgrind-wrapped Envoy, and the script records the valgrind leak summary for each group.

**What it tests** (each command is sent once, with `redis-cli -p 1999 <command>`):
- **Streams**: XADD (MAXLEN ~, NOMKSTREAM, MINID ~, LIMIT), XRANGE (COUNT), XREVRANGE (COUNT), XLEN, XDEL (single and multiple IDs), XTRIM (MAXLEN, MAXLEN ~, MINID, MINID ~ LIMIT), XGROUP (CREATE, CREATECONSUMER, SETID, DESTROY, DELCONSUMER, CREATE ... MKSTREAM, SETID ... ENTRIESREAD), XREADGROUP (COUNT, BLOCK 5000, NOACK, multi-stream, explicit ID), XPENDING (summary, range, per-consumer, IDLE), XCLAIM (JUSTID, FORCE, IDLE, TIME, RETRYCOUNT), XAUTOCLAIM (COUNT, JUSTID), XINFO (STREAM, STREAM FULL, GROUPS, CONSUMERS)
- **Sets**: SADD, SMEMBERS, SREM, SMISMEMBER, SUNION, SDIFF, SINTER, SUNIONSTORE, SDIFFSTORE, SINTERSTORE
- **Sorted sets**: ZUNIONSTORE / ZINTERSTORE (WEIGHTS, AGGREGATE MIN/MAX), ZRANGESTORE (BYSCORE, REV, LIMIT), ZUNION (WEIGHTS, AGGREGATE MAX), ZINTER (WITHSCORES, WEIGHTS, AGGREGATE), ZDIFF (WITHSCORES), ZDIFFSTORE, ZMSCORE, ZRANDMEMBER (count, negative count, WITHSCORES)
- **Blocking lists / zsets**: BRPOPLPUSH, BZPOPMAX, BZPOPMIN, BLPOP, BRPOP (timeout 0 and 5), BLMOVE (LEFT/RIGHT, timeout 0 and 5). Setup uses LPUSH, RPUSH and ZADD (see caveats).
- **Lists**: LPOS (RANK, COUNT, MAXLEN)
- **Hashes**: HRANDFIELD (count, negative count, WITHVALUES)
- **Strings / keys**: GETDEL, GETEX (EX, PX, EXAT, PXAT, PERSIST), MSETNX, SUBSTR, RENAME, RENAMENX, RANDOMKEY, KEYS, SCAN (MATCH, TYPE, COUNT), SORT (DESC, ALPHA, LIMIT, BY, GET, STORE), BITOP (AND, OR, XOR, NOT)
- **HyperLogLog**: PFMERGE
- **Geo**: GEORADIUS, GEORADIUSBYMEMBER (WITHDIST, WITHCOORD, WITHHASH, COUNT, ASC/DESC, STORE), GEOSEARCH, GEOSEARCHSTORE (FROMMEMBER, FROMLONLAT, BYBOX, BYRADIUS, STOREDIST)
- **Pub/Sub introspection**: PUBSUB CHANNELS (with and without a pattern), PUBSUB NUMSUB, PUBSUB NUMPAT
- **Scripting**: SCRIPT LOAD, EXISTS, FLUSH, KILL
- **Server / connection / admin**: FLUSHALL (sync and ASYNC), SLOWLOG (GET, GET 10, LEN, RESET), CONFIG (GET \*, GET maxmemory, SET maxmemory 2GB, RESETSTAT), CLIENT (LIST, GETNAME, SETNAME, KILL, PAUSE 5000), INFO (all, memory), CLUSTER (INFO, NODES, SLOTS, KEYSLOT), SELECT 0/1, HELLO (2, 3 AUTH, 3 SETNAME), UNWATCH

**How it runs**:
- Connects with `redis-cli -p 1999` (default host 127.0.0.1, no `-c` cluster mode). Commands go through a shell (`shell=True`), so shell quoting, globbing and redirection apply (see caveats).
- For each group it runs:
  `valgrind --leak-check=full --show-leak-kinds=all --log-file=envoy_valgrind_<group>_xmem_read.log ./bazel-bin/source/exe/envoy-static -c envoy.yaml --log-level debug`
  Envoy's stdout and stderr go to `build_output_xread.log`, which is overwritten for each group.
- It waits up to 600 s for the valgrind/Envoy process to appear and up to 600 s for `PING` to return `PONG`. After the commands it sends SIGTERM, waits up to 900 s for the process to exit, then sleeps 10 s before reading the log.
- Each command has a 10 s timeout. Commands whose text contains `block` (case-insensitive) get 7 s, which in practice means only the `XREADGROUP ... BLOCK 5000` call. BLPOP, BRPOP, BZPOP\*, BRPOPLPUSH and BLMOVE don't contain that word, so they keep 10 s. A command that times out is killed and recorded as `Command timed out`. For example, `blmove source destination left right 0` always runs into this.
- Example: `cd <envoy-src-root> && sudo python3 /path/to/non_blocking_commands.py` (it must run as root; see caveats).

**Pass/fail & output**:
- It gives no pass/fail verdict, and the exit code does not reflect leaks.
- `memory_leak_report.txt` lists, for each group, every command with its stdout (or `Success` if stdout was empty) or, if anything was written to stderr, that stderr as the error.
- It also includes the group's leak summary: the `LEAK SUMMARY:` line plus the next 3 lines (definitely, indirectly and possibly lost), taken from the last 15 lines of the valgrind log. If the summary isn't found there, it records `LEAK SUMMARY not found`. That is also what you get when valgrind finds no leaks at all, because valgrind then prints no `LEAK SUMMARY`.
- You have to read the report yourself to judge whether there are leaks.

**Notes / caveats**:
- **You must run it as root.** The code finds the Envoy PID with the regex `\s*root\s+(\d+)\s+.*valgrind.*envoy-static` against `ps -ef | grep valgrind | grep envoy-static` output. If you run it as any other user, it waits the full 600 s and then reports a timeout.
- **The "Envoy started" check can pass too early.** When run as root, the regex can also match the script's own `sh -c "ps -ef | grep valgrind | grep envoy-static"` helper process, because that line contains both words. The `PING` wait is what really waits for startup.
- **Shell globbing and redirection change some commands.** Commands are not quoted for the shell:
  - The bare `*` in the XADD calls, `keys *` and `config get *` expands to the file names in the current directory, which in an Envoy source tree is a long list.
  - In `sort user_ids BY user:*->age` and `sort user_ids GET user:*->name`, the shell treats `>` as a redirect. The command is cut short and its output is written to files named `age` and `name` in the current directory. The report then shows `Success`.
- **Missing commas in five groups.** In `brpoplpush`, `bzpopmax`, `bzpopmin`, `blpop` and `brpop`, the setup lines have no commas between them. Python joins adjacent strings, so the setup commands and the first blocking command are sent as one malformed command. For example, `lpush pending_tasks "task1"lpush notification_queue ...brpoplpush pending_tasks active_tasks 0` becomes a single LPUSH. The intended setup and that first (timeout 0) blocking call never run as separate commands.
- **`iterations = 5` does nothing.** It is passed to `run_test_group` but never used, so each command runs once.
- **Duplicate group names.** `sunionstore`, `smismember` and `xclaim` each appear twice. The later group reuses the same valgrind log file name and overwrites the earlier one.
- **Report crash after a startup failure.** If Envoy fails to start, `PING` times out, or shutdown times out, the group's result has no `results` key. Writing the report then fails with a `KeyError`.
- **Destructive commands.** `FLUSHALL`, `CONFIG SET maxmemory 2GB`, `CONFIG RESETSTAT`, `SLOWLOG RESET`, `SCRIPT FLUSH` and `CLIENT PAUSE 5000` change the backend if the proxy forwards them. Use a disposable cluster.
- **Many commands are expected to fail.** Lots of them do one of the following:
  - target keys or groups that don't exist;
  - use placeholder IDs (`ID1 ID2 ID3`);
  - use invalid syntax, such as `"> >"` as one ID argument or `fromlon/fromlat` in GEOSEARCH\*;
  - use placeholder credentials (`HELLO 3 AUTH admin StrongPassword123`).

  Error replies are expected and are never checked. The test only cares whether the proxy leaks while handling them.

---

### `blocking_commands.sh`

**Purpose**: Bash script that checks for leaks when the proxy handles Pub/Sub and blocking stream reads (plus a few basic commands). It runs four groups, each against a fresh valgrind-wrapped Envoy.

**What it tests**:
- **pubsub**:
  - Starts two background subscribers, `PSUBSCRIBE test_*` and `SUBSCRIBE test_channel`, each killed by `timeout 5s`.
  - Then sends `PUBSUB CHANNELS`, 5 × `PUBLISH test_channel "Message N"`, `PUBSUB NUMSUB test_channel`, `PUBSUB NUMPAT`, `PUBSUB CHANNELS`, `PUNSUBSCRIBE test_*`, `UNSUBSCRIBE test_channel`, and `PUBSUB CHANNELS` again.
- **xread**: XADD ×2 (the second XADD's output is captured as the ID), `XREAD COUNT 2 STREAMS mystream 0-0`, and `XREAD BLOCK 5000 COUNT 1 STREAMS mystream <id>` (wrapped in `timeout 5s`).
- **xreadgroup**:
  - Setup: XADD plus `XGROUP CREATE ... 0-0 MKSTREAM` on `order_stream`, `notification_stream`, `sensor_data`, `event_log1`, `event_log2` and `audit_log`.
  - Then XREADGROUP with COUNT, BLOCK 5000 (wrapped in `timeout 5s`), NOACK, two streams (`event_log1 event_log2 ">" ">"`), and explicit ID `0-0`.
- **other**: SET, GET, HSET, HGET.

**How it runs**:
- Settings are variables at the top of the script and can only be changed by editing it:

  | Variable | Default |
  |---|---|
  | `ENVOY_BINARY` | `./bazel-bin/source/exe/envoy-static` |
  | `ENVOY_CONFIG` | `envoy.yaml` |
  | `REDIS_PORT` | `1999` |
  | `MEMORY_LEAK_REPORT` | `memory_leak_report_blocking_commands.txt` |
  | `CHANNEL` | `test_channel` |
  | `PATTERN` | `test_*` |

- Connects with `redis-cli -c -h 127.0.0.1 -p $REDIS_PORT` (cluster mode on).
- Each normal command is retried up to 3 times, 1 s apart, if `redis-cli` exits non-zero.
- For each group, the valgrind log goes to `envoy_valgrind_<group>_test.log` and Envoy's output goes to `build_output_<group>.log`.
- Startup and shutdown timeouts match the Python scripts: 600 s for start, 600 s for `PING`, 900 s for exit, then a 10 s sleep before the log is parsed. The Envoy process is found with `pgrep -f "valgrind.*envoy-static"`, so root is not required.
- Also needs `timeout` from coreutils, plus `pgrep` and `awk`.
- Example: `cd <envoy-src-root> && bash /path/to/blocking_commands.sh`. The file is not executable, so you have to call it with `bash`.

**Pass/fail & output**:
- It gives no pass/fail verdict. Command output and progress are printed to stdout.
- After each group it appends `Running test group: <group>` and the valgrind block from `LEAK SUMMARY:` through `suppressed:` to `memory_leak_report_blocking_commands.txt`. If valgrind found no leaks at all, it prints no `LEAK SUMMARY`, so only the header line is appended.
- The exit status is that of the final `run_test_group "other"` call. That is normally 0 (from the last `echo`), so it does not reflect leaks. A `return 1` from the earlier `run_test_group` calls is never checked.

**Notes / caveats**:
- **The report file only grows.** It is appended to and never truncated, so results from earlier runs pile up.
- **`REDIS_CLUSTER_NODES` is unused.** It is defined but never referenced. `LOG_FILE` is also overwritten for each group.
- **Unquoted `*` in XADD.** In `XADD mystream * ...` and the other XADD calls, the shell expands `*` to the file names in the current directory, which in an Envoy source tree is a long list. Quote it (`'*'`) if you want auto-generated IDs.
- **Retry messages can corrupt the captured ID.** `execute_redis_command` prints its "Command failed, retrying..." message to stdout, and the stream ID is captured from that same stdout. `$stream_id` is also unquoted in the XREAD BLOCK call.
- **Pub/Sub timing is tight.**
  - Each background subscriber lives 5 s, and the script sleeps 2 s + 2 s + 2 s before publishing. The pattern subscriber will normally have exited before any message is published.
  - `PUNSUBSCRIBE` and `UNSUBSCRIBE` are sent on new connections, not on the subscriber connections.
- **Possible cross-slot errors.** The two-stream XREADGROUP (`event_log1`, `event_log2`) uses keys without hash tags, which may land in different cluster slots.
- **Unknown group name leaks an Envoy process.** For a group name it doesn't recognise, `run_test_group` returns without stopping Envoy. This can't happen with the four hard-coded groups.

---

### `mem_leak_transaction.py`

**Purpose**: Checks the proxy for leaks while it handles `MULTI`/`EXEC` transactions. Each of 13 command groups is wrapped in one transaction and sent 100 times against a fresh valgrind-wrapped Envoy. At the end the script gives a simple pass/fail verdict.

**What it tests** (each group is sent as `MULTI` + commands + `EXEC`; most multi-key groups use hash tags such as `{key}`, `{mylist}` or `{myset}` so the keys share a slot):
- **Strings**: SET, GET, APPEND, STRLEN, TTL, PTTL, SETRANGE, GETRANGE, INCR, INCRBY, INCRBYFLOAT, DECR, DECRBY, SETBIT, GETBIT, BITCOUNT, BITPOS
- **Lists**: LPUSH, RPUSH, LPUSHX, RPUSHX, LLEN, LRANGE, LPOP, RPOP, LINDEX, LREM, LTRIM, SORT ALPHA, RPOPLPUSH
- **Sets**: SADD, SCARD, SMEMBERS, SISMEMBER, SREM, SRANDMEMBER, SPOP, SMOVE, SDIFF, SDIFFSTORE, SINTER, SINTERSTORE, SUNION, SUNIONSTORE
- **Hashes**: HSET, HSETNX, HGET, HMSET, HMGET, HGETALL, HDEL, HEXISTS, HKEYS, HVALS, HLEN, HINCRBY, HINCRBYFLOAT, HSCAN
- **Sorted sets**: ZADD, ZRANGE / ZREVRANGE WITHSCORES, ZRANK, ZREVRANK, ZCOUNT, ZINCRBY, ZREM, ZRANGEBYSCORE, ZREVRANGEBYSCORE, ZREMRANGEBYRANK, ZREMRANGEBYSCORE, ZCARD, ZSCORE, ZUNIONSTORE, ZINTERSTORE, ZSCAN, ZRANGEBYLEX, ZLEXCOUNT, ZREMRANGEBYLEX
- **HyperLogLog**: PFADD, PFCOUNT, PFMERGE
- **Geo**: GEOADD, GEODIST, GEOHASH, GEOPOS, GEORADIUS, GEORADIUSBYMEMBER
- **Streams**: XADD (auto and explicit ID), XLEN, XRANGE, XREVRANGE, XPENDING (before group creation, after it, and after XACK), XGROUP CREATE/DESTROY (DESTROY twice), XREAD, XREADGROUP (`>` and `0`), XACK, XINFO STREAM/GROUPS, XTRIM, XDEL (twice)
- **Server**: PING, ECHO, TIME, CLIENT LIST/SETNAME/GETNAME
- **Keyspace**: TYPE, EXISTS, DEL, UNLINK, EXPIRE, PERSIST, TTL, RENAME
- **Copy**: DEL, MSET, MGET, COPY, COPY ... REPLACE
- **Blocking commands inside MULTI**:
  - Setup: DEL, LPUSH, RPUSH, ZADD.
  - Pops: BLPOP, BRPOP, BRPOPLPUSH, BZPOPMIN, BZPOPMAX, with finite and 0 timeouts, plus wrong-type BLPOP/BRPOP calls on zset keys.
  - Moves: BLMOVE in all four LEFT/RIGHT combinations, with timeout 1000 and 0, plus LRANGE.
- **XREAD / XREADGROUP with BLOCK inside MULTI**:
  - Setup: DEL, then XREADGROUP before the group exists, XGROUP CREATE (twice), and XADD.
  - XREAD with BLOCK 100/0, COUNT 1/-1 and ID `0`.
  - XREADGROUP with COUNT 10, BLOCK 10000/0 and IDs `0` and `>`.

**How it runs**:
- Each transaction is sent as `echo '<MULTI\n...\nEXEC>' | redis-cli -p 1999` (no `-c`), with a 15 s timeout per transaction.
- `iterations = 100` transactions per group. The Envoy command line and startup/shutdown handling match `non_blocking_commands.py`. The valgrind log is `envoy_valgrind_<group>_xmem_read.log`, and Envoy's output goes to `build_output.log`, which is overwritten for each group.
- Example: `cd <envoy-src-root> && sudo python3 /path/to/mem_leak_transaction.py`. There is no shebang, so always call it with `python3`.

**Pass/fail & output**:
- `memory_leak_report_for_transaction.txt` contains, for each group and iteration:
  - the commands with their output lines;
  - a `Transaction Result:` line (the last output line);
  - the group's leak summary (the same 4-line extract as `non_blocking_commands.py`).
- If `redis-cli` writes anything to stderr, or the transaction times out, that iteration is recorded as a single error entry.
- After writing the report, the script greps it for every `definitely lost:` line and prints `Memory Leak Analysis Result:` with one of:
  - `Passed: No memory leaks detected.` if every line contains `0 bytes in 0 blocks`.
  - `Failed: Memory leak is identified...` otherwise.
  - `Failed: No 'definitely lost' information found...` if no such line exists.
- Indirectly and possibly lost bytes are not considered. The exit code is 0 unless the script crashes, so it does not reflect the verdict.
- It also prints the full command and raw output of every transaction (`Debug - ...`), so stdout gets very long.

**Notes / caveats**:
- **You must run it as root.** It uses the same `ps -ef` regex for `root` as `non_blocking_commands.py`, so it times out as any other user. The same early-match issue with its own helper shell applies.
- **Fragile shell quoting.** Many commands contain single quotes (`'Hello'`, `' World'`, `'Palermo'`), which break out of the `echo '...'` wrapper. The shell strips those quotes, so values are effectively sent unquoted, and spaces inside them can be lost (for example, `' World'` becomes `World`). It still runs, but not exactly as written.
- **Per-command labels are approximate.** Output lines are matched to commands by line number. `EXEC` returns multi-line output, so the labels don't line up with the real replies.
- **Groups with no leaks at all can be missed.** When valgrind finds no leaks at all, it prints no `LEAK SUMMARY`, so that group adds no `definitely lost:` line. If no group produces one, the final verdict is `Failed`. Only the last 15 lines of each valgrind log are searched.
- **Report crash after a startup failure.** As in `non_blocking_commands.py`, a startup, `PING` or shutdown timeout makes the result lack `results` and `transaction_results`. Writing the report then fails with a `KeyError`, before any verdict is printed.
- **Error replies are expected and never checked.** Many queued commands deliberately error or do nothing, for example duplicate XGROUP CREATE/DESTROY, XDEL of an already deleted ID, and BLPOP/BRPOP on zset keys.

---

## address-sanitiser-scripts/

These scripts start a locally built `envoy-static` binary, which is expected to be an AddressSanitizer (ASan) build, with an `envoy.yaml` you supply. They then send Redis commands through the proxy with `redis-cli`. They check that Envoy is still running and still answers `PING`: the Python script checks before every command, and the shell script checks after every group. A crash, or a memory error that ASan turns into a crash, therefore shows up as a failure. Neither script reads the Envoy log for ASan reports, so you have to check the log yourself.

### `non_blocking_commands.py`

- **Purpose**: Starts Envoy and sends a long fixed list of Redis commands through the proxy one at a time. Before every command it checks that Envoy is running and that the proxy answers `PING`. This stresses how the `redis_proxy` filter parses and routes many different command shapes.
- **What it tests** (grouped by family below; the script runs them in a different, mixed order):
  - Streams: XADD (MAXLEN ~, NOMKSTREAM, MINID ~, LIMIT), XRANGE (COUNT), XREVRANGE (COUNT), XLEN, XDEL, XTRIM (MAXLEN / MINID, ~, LIMIT), XGROUP (CREATE, CREATECONSUMER, SETID with ENTRIESREAD, DESTROY, DELCONSUMER, MKSTREAM), XREADGROUP (COUNT, BLOCK 5000, NOACK, multiple streams, explicit ID), XPENDING (summary, range, consumer, IDLE), XCLAIM (JUSTID, FORCE, IDLE, RETRYCOUNT, TIME), XAUTOCLAIM (COUNT, JUSTID), XINFO (STREAM, STREAM FULL, GROUPS, CONSUMERS)
  - Sets: SADD, SMEMBERS, SREM, SMISMEMBER, SUNION, SDIFF, SINTER, SUNIONSTORE, SDIFFSTORE, SINTERSTORE
  - Sorted sets: ZUNIONSTORE / ZINTERSTORE (WEIGHTS, AGGREGATE), ZMSCORE, ZRANGESTORE (BYSCORE, REV, LIMIT), ZUNION (WEIGHTS, AGGREGATE), ZDIFF (WITHSCORES), ZDIFFSTORE, ZINTER (WITHSCORES, WEIGHTS, AGGREGATE), ZRANDMEMBER (count, negative count, WITHSCORES)
  - Blocking list / zset commands: BRPOPLPUSH, BZPOPMAX, BZPOPMIN, BLPOP, BRPOP, BLMOVE. Every group except BLMOVE is meant to run setup pushes first (LPUSH, RPUSH, ZADD), but see the missing-commas caveat below.
  - Geo: GEORADIUS, GEORADIUSBYMEMBER (WITHDIST / WITHCOORD / WITHHASH, COUNT, ASC/DESC, STORE), GEOSEARCH, GEOSEARCHSTORE (FROMLONLAT / FROMMEMBER, BYBOX / BYRADIUS, ASC, COUNT, WITHDIST / WITHCOORD / WITHHASH, STOREDIST)
  - HyperLogLog: PFMERGE
  - Hashes: HRANDFIELD (no count, count, negative count, WITHVALUES)
  - Strings / keys: GETDEL, GETEX (no option, EX, PX, EXAT, PXAT, PERSIST), MSETNX, SUBSTR, BITOP (AND/OR/XOR/NOT), RENAME, RENAMENX, SORT (DESC, ALPHA, LIMIT, BY, GET, STORE), KEYS, SCAN (MATCH, TYPE, COUNT), RANDOMKEY
  - Lists: LPOS (RANK, COUNT, MAXLEN)
  - Pub/Sub introspection: PUBSUB CHANNELS (with and without a pattern), NUMSUB, NUMPAT
  - Scripting: SCRIPT LOAD, EXISTS, FLUSH, KILL
  - Server / connection / admin: FLUSHALL (and ASYNC), SLOWLOG (GET, GET 10, LEN, RESET), CONFIG (GET, SET maxmemory, RESETSTAT), CLIENT (LIST, GETNAME, SETNAME, KILL, PAUSE), INFO (and INFO memory), CLUSTER (INFO, NODES, SLOTS, KEYSLOT), SELECT 0/1, HELLO (2, 3 AUTH, 3 SETNAME), UNWATCH
- **How it runs**:
  - The script takes no CLI arguments, environment variables or config file. Everything is hardcoded:
    - The Envoy command is `./bazel-bin/source/exe/envoy-static -c envoy.yaml`, started in the background. Its stdout and stderr go to `envoy_logs.txt`.
    - Proxy address: `redis-cli -p 1999`. With no `-h`, redis-cli uses its default host, 127.0.0.1. Cluster mode (`-c`) is not used.
    - Every command runs as `redis-cli -p 1999 <command>` through `/bin/sh` (`shell=True`).
  - Prerequisites:
    - Python 3.6 or later, standard library only (`subprocess`, `time`, `re`, `sys`).
    - `redis-cli` on `PATH`, plus `ps` and `grep`.
    - An Envoy build at `bazel-bin/source/exe/envoy-static`, relative to the current directory. It should be ASan-instrumented for this suite to be useful.
    - An `envoy.yaml` in the current directory with a `redis_proxy` listener on port 1999 pointing at your Redis cluster.
    - Envoy must show up in `ps -ef` with the user name `root` (see Notes).
  - Example:
    ```bash
    cd /path/to/envoy-source        # contains bazel-bin/ and your envoy.yaml
    python3 /path/to/address-sanitiser-scripts/non_blocking_commands.py
    ```
- **Pass/fail & output**:
  - **Startup:** waits up to 600 s for an `envoy-static` process, then up to 600 s for `PONG`. If either times out, it prints `Error: Timed out ...` and then `Failed to start Envoy or connect to Redis`, and exits with code 1.
  - **Each command:** the full health check runs first, so a dead proxy can take up to 600 s + 600 s to be noticed. Then the command runs.
  - **What counts as a failure:** a failed health check, or anything at all written to redis-cli's **stderr**. On the first failure the script prints the report so far, ending with the failing entry, and exits with code 1.
  - **Report:** a single line with one `<group> - Success` or `<group> - Failed` entry per command (not per group). Entries are joined by a literal `\ ` (backslash and space).
  - **Success:** the report line ends with `Test completed` and the script exits with code 0.
  - **Console noise:** every health check also prints `Debug - PS output: ...` lines.
  - ASan findings go to `envoy_logs.txt`, and you must check them by hand.
- **Notes / caveats**:
  - **`envoy.yaml` is not included.** You must supply it.
  - **Weak liveness check.** `wait_for_envoy` runs `ps -ef | grep 'envoy-static'` and accepts a match only if the regex `root\s+(\d+)\s+.*envoy-static` matches, i.e. the user column reads `root`.
    - If neither Envoy nor the `grep` runs as `root`, the check loops until the 600 s timeout and then fails. This also happens when `ps` shows numeric UIDs.
    - When you run the script as root, the `grep envoy-static` process matches its own pattern and satisfies the regex. The "Envoy is running" check then always passes, even if Envoy is dead. In practice, crashes are caught by the `PING` check.
  - **Error replies don't fail the test.** The redis-cli exit code is never checked. Server error replies, such as unsupported commands, cross-slot errors or bad syntax, count as failures only if your redis-cli version writes them to stderr. Otherwise they are reported as `Success`.
  - **Some commands are invalid as written.** They exercise the proxy's error paths rather than real behaviour. Examples:
    - `xadd audit_log LIMIT 1000 *` (LIMIT without MAXLEN/MINID).
    - `geosearch` / `geosearchstore ... fromlon <x> fromlat <y>` (not a valid option).
    - `xclaim ... ID1 ID2 ID3`.
  - **Missing commas.** In the `brpoplpush`, `bzpopmax`, `bzpopmin`, `blpop` and `brpop` groups, the setup strings and the first blocking command have no commas between them. Python joins them into one string, so each group sends one merged command:
    - For `brpoplpush`, `blpop` and `brpop`, it becomes a single LPUSH or RPUSH with many extra values. The first blocking command (the one with timeout `0`) is never sent.
    - For `bzpopmax` and `bzpopmin`, it becomes a single ZADD with a non-numeric score, which gets an error reply.
    - Only the second blocking command in each group (timeout `5`) is sent on its own.
  - **Shell interpretation.** Commands run through `/bin/sh`:
    - These unquoted `*` arguments can be glob-expanded against files in the current directory: `*` in every XADD (`xadd <stream> * ...`), `config get *`, `keys *`, and the `user:*`, `product:*` and `user:*:notifications` patterns.
    - In `sort user_ids BY user:*->age` and `sort user_ids GET user:*->name`, the shell treats `>` as a redirect. The commands are sent truncated as `... user:*-`, and their output goes to files named `age` and `name` in the current directory.
  - **Blocking commands can hang.** Despite the file name, the script sends blocking commands, and there is no per-command timeout.
    - `blmove source destination left right 0` runs after FLUSHALL, so `source` is empty. If the proxy forwards it, it can block indefinitely.
    - The commands with timeout `5` and `XREADGROUP ... BLOCK 5000` can each block for about 5 s.
  - **Destructive commands.** The script runs FLUSHALL (and ASYNC), SCRIPT FLUSH, SCRIPT KILL, CONFIG SET maxmemory 2GB, CONFIG RESETSTAT, SLOWLOG RESET, CLIENT KILL 127.0.0.1:52500 and CLIENT PAUSE 5000. Use a disposable cluster.
  - **Hardcoded credentials.** `hello 3 AUTH admin StrongPassword123` uses a hardcoded placeholder username and password.
  - **Placeholder values.** Many commands use keys or IDs that don't exist, such as `ID1 ID2 ID3` and fixed stream IDs. The aim is to exercise the proxy, not to check results.
  - **Duplicates and dead code.**
    - The groups `sunionstore`, `smismember` and `xclaim` each appear twice.
    - An `xreadgroup` group is commented out.
    - In `xreadgroup`, `"> >"` is passed as one argument, which is malformed.
  - **Python 3.12+ warning.** `"\ ".join(...)` uses an invalid escape sequence. Python 3.12 and later print a `SyntaxWarning`, but the script still runs.
  - **Envoy keeps running.** The script never stops Envoy, so it is still running in the background afterwards.

### `blocking_commands.sh`

- **Purpose**: Starts Envoy and runs four groups of commands through the proxy, focused on blocking and subscription commands: Pub/Sub, XREAD, XREADGROUP, plus a few basic commands. It checks that Envoy is alive and answering `PING` after each group. At the end it stops Envoy with SIGTERM, so ASan's exit-time output can be written to the log.
- **What it tests**:
  - `pubsub`:
    1. Background `PSUBSCRIBE test_*` and `SUBSCRIBE test_channel`, each run under `timeout 5s`, with 2 s sleeps.
    2. `PUBSUB CHANNELS`, then 5 × `PUBLISH test_channel "Message N"`.
    3. `PUBSUB NUMSUB test_channel`, `PUBSUB NUMPAT`, `PUBSUB CHANNELS`.
    4. `PUNSUBSCRIBE test_*`, `UNSUBSCRIBE test_channel`, then `PUBSUB CHANNELS` again.
  - `xread`: 2 × `XADD mystream * ...`, then `XREAD COUNT 2 STREAMS mystream 0-0`, then `XREAD BLOCK 5000 COUNT 1 STREAMS mystream <id from 2nd XADD>` under `timeout 5s`.
  - `xreadgroup`:
    1. Setup: `XADD` plus `XGROUP CREATE ... 0-0 MKSTREAM` for `order_stream`, `notification_stream`, `sensor_data`, `event_log1`, `event_log2` and `audit_log`.
    2. `XREADGROUP` with COUNT, BLOCK 5000 (under `timeout 5s`), NOACK, two streams with `">" ">"`, and an explicit ID `0-0`.
  - `other`: SET, GET, HSET, HGET.
- **How it runs**:
  - The script takes no CLI arguments or environment variables. To change anything, edit the variables at the top of the script:
    - `ENVOY_BINARY=./bazel-bin/source/exe/envoy-static`
    - `ENVOY_CONFIG=envoy.yaml`
    - `REDIS_PORT=1999`
    - `CHANNEL=test_channel`
    - `PATTERN=test_*`
  - Envoy is started in the background as `$ENVOY_BINARY -c $ENVOY_CONFIG --log-level debug`. Its stdout and stderr go to `envoy_console_log.log`.
  - Every command is sent as `redis-cli -c -h 127.0.0.1 -p $REDIS_PORT ...` (cluster mode on).
  - Prerequisites:
    - bash.
    - `redis-cli`, `pgrep`, `kill`, `date` and `timeout`. `timeout` is from GNU coreutils; on macOS, install coreutils and make `timeout` available on `PATH`.
    - The Envoy binary and an `envoy.yaml` with a `redis_proxy` listener on port 1999, both relative to the current directory.
  - Example:
    ```bash
    cd /path/to/envoy-source        # contains bazel-bin/ and your envoy.yaml
    bash /path/to/address-sanitiser-scripts/blocking_commands.sh
    ```
- **Pass/fail & output**:
  - **Startup:** waits up to 600 s for an `envoy-static` process (via `pgrep -f`), then up to 600 s for `PONG`.
    - If either check fails, it prints `Error: Envoy failed to start` or `Error: Redis did not respond in time` and kills Envoy.
    - It then prints `Error: Unable to connect to Redis` and exits with code 1.
  - **Each command:** `execute_redis_command` makes up to 3 attempts in total, 1 s apart, whenever redis-cli exits non-zero.
    - Each failed attempt prints `Command failed, retrying... (Attempt N)` to stdout.
    - After the third failure it prints `Error: Redis command failed after 3 attempts: <output>` to stderr and returns 1.
  - **After each group:** the Envoy and `PING` check runs again.
    - If the check fails, Envoy is killed and the script prints `Error: Envoy or Redis failed after <group>`.
    - It then prints `Error: Tests for <group> - Failed` (`Error: Tests for other commands - Failed` for the last group).
    - The script carries on with the next group.
  - **Shutdown:**
    1. Sends SIGTERM to `$ENVOY_PID` and waits up to 900 s.
    2. If Envoy hasn't stopped by then, prints `Error: Failed to terminate Envoy` and sends `kill -9`.
    3. Prints `Completed testing for all commands - Success`.
  - **Exit code** is 0 whenever startup succeeded, even if some groups failed. Look for `Error:` lines in the console output, and read `envoy_console_log.log` for ASan reports.
- **Notes / caveats**:
  - **`envoy.yaml` is not included.** You must supply it.
  - **Command failures never fail a group.** `run_test_group` ignores the return value of the group function, so a group is reported as failed only when the post-group health check fails.
    - Inside `pubsub`, `|| return 1` only stops the rest of the pubsub sequence early.
    - Even that triggers only on some failures: a helper function's status comes from its last command, and several helpers end with `sleep`.
  - **Final message is always "Success".** The last line prints `Success` regardless of earlier failures.
  - **Unquoted `*` in XADD.** `execute_redis_command XADD <stream> * ...` passes `*` unquoted, so bash glob-expands it against the current directory. In a non-empty directory, such as the Envoy source tree, XADD receives file names instead of `*` and fails, which also affects the stream and group setup.
  - **Garbage stream ID is possible.** `stream_id` captures all stdout of `execute_redis_command`, including any `Command failed, retrying...` lines. If that XADD fails, the following `XREAD BLOCK` gets a garbage ID.
  - **Pattern subscriber expires early.** The `PSUBSCRIBE` client's `timeout 5s` has already expired (after about 6 s of sleeps) before the first `PUBLISH`, so pattern delivery is not really exercised. The channel subscriber is still alive for roughly the first second of publishing.
  - **Unsubscribe doesn't touch the subscribers.** `PUNSUBSCRIBE` / `UNSUBSCRIBE` are sent on a new connection, so the background subscribers are unaffected. They end only when their `timeout 5s` expires, and their output is mixed into the console output.
  - **Envoy is not restarted after a failed health check.** It is killed, and later groups then run against no proxy, each waiting up to 600 s for Envoy before failing.
  - **PID can be overwritten.** `ENVOY_PID` is first set from `$!` and then replaced by the output of `pgrep -f ".*envoy-static"`. That can return several PIDs, and the final `kill` would then signal every `envoy-static` process on the host.
  - **Unused variables.** `LOG_FILE="envoy_asan_build.log"`, `PSUB_PID` and `SUB_PID` are set but never used.

---

## endurance-test-scripts/

Long-running load and fault-injection scripts. Each one stresses the proxy for a long time (or forever) so you can watch its memory, connection count, error rate and crash behaviour. None of them checks results automatically and none returns a pass/fail exit code. You judge the run from the logs and from the proxy's own metrics.

Common prerequisites:
- `bash`.
- A [`redis-benchmark-go`](https://github.com/redis-performance/redis-benchmark-go) binary in the **current working directory** (`./redis-benchmark-go`) for the benchmark-driven scripts (`endurance_automation.sh`, `endurance_streams.sh`).
- `redis-cli` and `openssl` on the local machine for `endurance_pubsub.sh`.
- `kubectl` for `endurance_client_kill.sh`. That script runs `redis-cli` inside the Redis pods, so it does not need a local copy.
- A password. Every script requires a non-empty password and always sends it with `-a`.

---

### `endurance_automation.sh`

**Purpose**: Starts one `redis-benchmark-go` load generator per line of a commands file (for example `commands.txt`). All generators run against the proxy at the same time. When they finish, the script prints a per-command summary of duration, throughput and error count.

**What it tests**
- Every line of `<commands_file>` as one benchmark command. See [`commands.txt`](#commandstxt) for the default set.
- The proxy under many concurrent mixed-command workloads: one background process per line, started 2 s apart.

**How it runs**
- 7 positional arguments, all required. With any other count it prints usage and exits `1`:
  `<redis_password> <proxy_host> <proxy_port> <requests> <connections> <res_file> <commands_file>`
  - `<requests>` is passed as `-rps` (a rate limit in requests per second, not a total) and `<connections>` as `-c`.
  - Every benchmark also gets `-l` (loop mode) and `--json-out-file`.
- For each command it runs:
  `./redis-benchmark-go -a <pwd> -h <host> -p <port> -rps <requests> -c <connections> -l -cmd "<cmd>" --json-out-file results_endurance/<res_file>_<cmd_with_underscores>.json`
  - Output (stdout and stderr) goes to `results_endurance/<res_file>_<cmd_with_underscores>.log`.
  - Double quotes in the command are escaped with a backslash, and the whole line is run through `eval`.
- Prerequisites: `./redis-benchmark-go` in the current directory, and a `results_endurance/` directory that you create yourself.
- Example:
  ```bash
  mkdir -p results_endurance
  ./endurance_automation.sh "$REDIS_PWD" 127.0.0.1 6379 500 200 result_cx.txt commands.txt
  ```

**Pass/fail & output**
- While starting jobs it prints `Executing benchmark command for: <cmd>` and `Benchmark started for: <cmd> (PID: <pid>)`.
- After `wait` returns, it prints `All benchmarks completed. Processing results...` and then reads each command's log:
  - If the log contains the string `error` (case-sensitive), it prints `<date> : ERROR : Load test execution failed for command: <cmd> - <requests> requests across <connections> connections.`, then `Error message: <first matching line>`.
  - Otherwise it parses the last `Total Duration`, `Total Errors` and `Throughput summary` lines and prints `<date> : INFO : Command: <cmd> - <requests> requests across <connections> connections took <N>s and throughput value is <X> with <E> errors.`
- The exit code does not reflect benchmark failures.

**Notes / caveats**
- **The script does not create `results_endurance/`.** If the directory is missing, every log redirect fails and no benchmark starts.
- **The summary step reads the wrong path.** It reads `${RES_FILE}_<cmd>.log` from the current directory, without the `results_endurance/` prefix used when writing. As written it does not find the logs: `grep` prints "No such file" errors and every line comes out as INFO with empty duration, throughput and error values. To get a summary, copy or symlink the logs into the current directory, or fix the path.
- **The summary step only runs after every benchmark exits, and with `-l` they never exit on their own.** In redis-benchmark-go, `-l` loops forever, so `wait` blocks until you kill the processes yourself, for example with `pkill redis-benchmark-go`.
- **One process runs per command line.** With `commands.txt` that is 94 processes, each holding `<connections>` connections to the proxy. Starting them takes about 3 minutes (94 × 2 s).
- **The summary text says "requests"**, but the value is the `-rps` rate.
- **Commands are run through `eval`, and their text becomes part of the output file names.** Shell metacharacters (`*`, `:`, quotes) end up in the file names, and the log names keep the backslashes added by the escaping step.
- **The `xreadgroup ... ">"` line in `commands.txt` breaks.** In the unquoted `--json-out-file` part of the `eval` string, the `>` is parsed as a shell redirection. That benchmark's output goes to a file named `".json` in the current directory, its `.log` stays empty, and its JSON file name is cut off.
- **The password is passed on the command line** (`-a`), so it shows up in the process list.

---

### `commands.txt`

**Purpose**: The default list of commands for `endurance_automation.sh`, one complete Redis command with arguments per line (94 lines). It is not a script.

**What it tests**
- Strings: SET, GET, SETEX, SETNX, INCR, DECR, INCRBY, DECRBY, STRLEN, APPEND, GETRANGE, SETRANGE
- Hashes: HSET (multi-field), HGET, HMGET, HGETALL, HINCRBY, HSETNX, HEXISTS, HKEYS, HVALS, HLEN, HSTRLEN, HRANDFIELD
- Lists: RPUSH, LRANGE, LPOP, RPOP, LLEN, LINDEX, LREM, LTRIM
- Sets: SADD, SMEMBERS, SISMEMBER, SCARD, SPOP, SRANDMEMBER, SREM, SMISMEMBER
- Sorted sets: ZADD, ZRANGE/ZREVRANGE/ZRANGEBYSCORE/ZREVRANGEBYSCORE (WITHSCORES), ZINCRBY, ZREM, ZRANK, ZREVRANK, ZCARD, ZSCORE, ZCOUNT, ZMSCORE, ZRANDMEMBER, ZPOPMAX, ZPOPMIN
- HyperLogLog: PFADD, PFCOUNT
- Geo: GEOHASH, GEOPOS, GEORADIUS
- Bitmaps: SETBIT, GETBIT, BITCOUNT
- Streams (consumer groups): XREADGROUP, XPENDING, XCLAIM, XAUTOCLAIM
- Pub/Sub: PUBLISH
- Generic keys: EXISTS, DEL, UNLINK, EXPIRE, TTL, PERSIST, TYPE
- Iteration: SCAN (MATCH/COUNT), HSCAN (MATCH), SSCAN, ZSCAN
- Connection, server and cluster: PING, ECHO, TIME, CLIENT GETNAME, CLIENT SETNAME, CLUSTER SLOTS, CLUSTER KEYSLOT, INFO, INFO memory, INFO clients

**Notes / caveats**
- **Some commands target data that nothing in the file creates.**
  - The geo commands use `locations`, but there is no GEOADD, so they return nil or empty replies.
  - The stream commands use the `order_processors` group on `order_stream`, but there is no XADD or XGROUP CREATE, so expect `NOGROUP` errors. XCLAIM also uses a hard-coded entry ID.
  - LRANGE, LPOP, LLEN and LREM use `notifications`, but nothing pushes to it. `TYPE user:1003` targets a key that is never set.
- **All lines run at the same time and in a loop**, so writes and deletes on the same keys race each other (for example `del user:1000` against `set user:1000`, or `unlink user:1001` against the `user:1001` hash commands).
- **Some of the admin and cluster commands may be rejected by the proxy**, depending on which commands your build supports. Examples: CLUSTER SLOTS, CLIENT SETNAME, TIME, INFO.
- **The `">"` argument of the XREADGROUP line breaks `endurance_automation.sh`'s file naming** (see that script's caveats).

---

### `endurance_streams.sh`

**Purpose**: Starts a fixed set of `redis-benchmark-go` loops in the background, one per command. The set covers streams, a few list and bitmap commands, a RENAME and Lua scripting.

**What it tests**
- Streams: XADD (`*` ID), XRANGE, XREVRANGE, XLEN, XDEL, XTRIM MAXLEN, XGROUP SETID
- Lists: LPUSH, LSET, LPOS
- Bitmaps: BITPOS
- Keys: RENAME with brace-tagged keys (`{mykey} {newkey}`)
- Scripting: EVAL (`redis.call('set', KEYS[1], ARGV[1])`), EVALSHA

**How it runs**
- Environment variables:
  - `REDIS_PWD`: required.
  - `PROXY_HOST`: required.
  - `PROXY_PORT`: optional, default `6379`.
- Values fixed in the script: `REQUESTS=2000` (passed as `-rps`) and `CONNECTIONS=200` (passed as `-c`).
- Each command runs as:
  `./redis-benchmark-go -a "$REDIS_PWD" -h "$PROXY_HOST" -p "$PROXY_PORT" -rps 2000 -c 200 -l -cmd "<cmd>" --json-out-file "<cmd_with_underscores>_output.json"`
  It runs in the background, with output in `benchmark_output_<cmd_with_underscores>.log`.
- Prerequisite: `./redis-benchmark-go` in the current directory.
- Example:
  ```bash
  REDIS_PWD=secret PROXY_HOST=127.0.0.1 PROXY_PORT=6379 ./endurance_streams.sh
  ```

**Pass/fail & output**
- There is no result processing. The script prints `Running benchmark for command: <cmd>` for each job, then exits immediately without waiting.
- Check results in the per-command `.log` and `*_output.json` files in the current directory.

**Notes / caveats**
- **The benchmarks keep running after the script exits.** They are started with `-l` and never waited on, so stop them yourself, for example with `pkill redis-benchmark-go`.
- **The EVALSHA SHA (`f77c0e99...`) is not the SHA1 of the script used in the EVAL line**, which is `55b22c0d...`. The `SCRIPT LOAD` line is commented out. EVALSHA therefore returns `NOSCRIPT` unless a script with that SHA is already loaded on the backend.
- **The RENAME keys do not share a hash tag.** `{mykey}` and `{newkey}` hash to different slots, so a Redis Cluster backend can reject the command with `CROSSSLOT`. The key `{mykey}` is also never created (the other commands use `mykey` without braces), so the command otherwise returns `ERR no such key`.
- **`XGROUP SETID` targets the group `mygroup`, which is never created**, so expect errors. `XDEL` uses a hard-coded entry ID, so it deletes nothing.
- **The `output_file` variable is defined but never used.**
- **How the quoted Lua body in the EVAL line is split into arguments is decided by redis-benchmark-go's `-cmd` parsing.** Check that it reaches the proxy as intended.

---

### `endurance_pubsub.sh`

**Purpose**: A long-running pub/sub soak test through the proxy. It opens thousands of channel and pattern subscriptions, publishes to every channel at a capped rate, and mixes in random subscribe, unsubscribe and publish operations. All of this repeats for many iterations.

**What it tests**
- Pub/Sub: SUBSCRIBE, PSUBSCRIBE, PUBLISH, UNSUBSCRIBE, PUNSUBSCRIBE.
- What happens in each iteration:
  1. Opens 7000 `SUBSCRIBE` and 3000 `PSUBSCRIBE` connections, each one a background `redis-cli` process. Channel names are `channel_<16 hex>` and patterns are `pattern_<8 hex>*`.
  2. In the background, publishes to every subscribed channel in turn for 1800 s, sleeping 1 s after every 100 messages.
  3. While publishing runs, performs one random operation every 10 s on a newly generated channel or pattern: SUBSCRIBE, PUBLISH, UNSUBSCRIBE, PSUBSCRIBE or PUNSUBSCRIBE.
  4. Sends UNSUBSCRIBE and PUNSUBSCRIBE for every channel and pattern from that iteration, one `redis-cli` call each. It then pauses 5 s, except after the last iteration.

**How it runs**
- Environment variables:
  - `REDIS_HOST`: required, the proxy host.
  - `REDIS_PORT`: optional, default `6379`.
  - `REDIS_PWD`: required.
- Values fixed in the script:
  - `NUM_CHANNELS=7000`
  - `NUM_PATTERNS=3000`
  - `PUBLISH_DURATION=1800` (seconds)
  - `PUBLISH_IOPS=100` (messages per second)
  - `RANDOM_OPERATIONS_INTERVAL=10` (seconds)
  - `ITERATIONS=2000`
- Prerequisites:
  - `redis-cli` and `openssl` (used for random names).
  - Process and file-descriptor limits high enough for at least 10,000 concurrent `redis-cli` processes (`ulimit -u` / `ulimit -n`).
  - A proxy build that accepts SUBSCRIBE/PSUBSCRIBE. If the proxy rejects them, the subscriber processes simply exit, and only PUBLISH gets exercised.
- Example:
  ```bash
  REDIS_HOST=127.0.0.1 REDIS_PORT=6379 REDIS_PWD=secret ./endurance_pubsub.sh
  ```

**Pass/fail & output**
- There are no assertions. Progress goes to stdout:
  - `Starting iteration i of N...`, `Subscribing to ...`, `Starting to publish messages for 1800 seconds...`, `Performing random operations...`
  - One line per random operation (`Subscribed to ...`, `Published to ...`, `Unsubscribed from ...`, `PSubscribed to ...`, `PUnsubscribed from ...`)
  - `Unsubscribing from channels and patterns...`, `Iteration i of N complete.`, `Pausing before next iteration...`, and finally `All iterations complete.`
- Subscriber output is sent to `/dev/null`, so delivery of messages is never checked. Judge the run by the proxy's stability, memory and connection metrics.

**Notes / caveats**
- **Subscriber connections are never closed, so they pile up.** The unsubscribe step and the random UNSUBSCRIBE/PUNSUBSCRIBE each open a new `redis-cli` connection. Subscriptions belong to the connection that made them, so the original SUBSCRIBE and PSUBSCRIBE processes keep running. Each iteration adds about 10,000 more processes and proxy connections.
- **Random operations act on brand-new names.** They never touch the channels or patterns subscribed in step 1.
- **Pattern subscribers never receive anything.** Patterns are `pattern_*` while publishes go to `channel_*` names, so the pattern side only exercises subscription handling.
- **A full run takes a very long time.** 2000 iterations of about 30 minutes each is roughly 1000 hours, plus the time spent subscribing and unsubscribing. Lower `ITERATIONS` and `PUBLISH_DURATION` for shorter runs.
- **The real publish rate is lower than `PUBLISH_IOPS`.** Every PUBLISH starts a new `redis-cli` process, and the 1800 s limit is only checked after a full pass over all 7000 channels.
- **The terminal fills with password warnings.** PUBLISH calls redirect only stdout, so `redis-cli` prints its `-a` password warning on stderr every time.

---

### `endurance_client_kill.sh`

**Purpose**: Injects faults on a Kubernetes-hosted Redis cluster. On a fixed interval it runs `CLIENT KILL` on every matching backend pod, which forces the proxy to deal with dropped upstream connections. Run it alongside the load scripts above.

**What it tests**
- Server/admin: `CLIENT KILL TYPE normal`, then `CLIENT KILL TYPE pubsub`, on each pod selected by the label. These are sent directly to the backend, not through the proxy.
- Shows how the proxy reconnects and how clients see errors when backend connections drop in the middle of the load.

**How it runs**
- Environment variables:
  - `NAMESPACE`: required, the Kubernetes namespace of the Redis pods.
  - `LABEL_SELECTOR`: optional, default `role=Master`. Label values are case-sensitive.
  - `REDIS_PASSWORD`: required.
- Values fixed in the script: `REDIS_PORT=6379` and `INTERVAL_MINUTES=900`.
- Each cycle:
  1. Lists the pods with `kubectl get pods -n $NAMESPACE -l $LABEL_SELECTOR` (jsonpath output) to get each pod's IP and name.
  2. For each pod, runs `kubectl exec -n $NAMESPACE <pod> -- redis-cli -h <podIP> -p 6379 -a $REDIS_PASSWORD CLIENT KILL TYPE <type>` once for `normal` and once for `pubsub`.
  3. Sleeps `INTERVAL_MINUTES` seconds, then starts the next cycle.
- Prerequisites:
  - `kubectl` with access to the namespace and permission to `exec` into the pods.
  - `redis-cli` available in the pod's default container.
- Example:
  ```bash
  NAMESPACE=redis LABEL_SELECTOR=role=master REDIS_PASSWORD=secret ./endurance_client_kill.sh
  ```

**Pass/fail & output**
- It loops forever; stop it with Ctrl-C. For each cycle it prints:
  - `Starting client kill process at <date>`
  - `Processing pod: <name> (<ip>)`
  - `Killing <type> clients on <ip>`, followed by the number of clients each `CLIENT KILL` removed
  - `Finished client kill process at <date>`
  - `Waiting for 900 minutes before next iteration...`
- There are no assertions and no meaningful exit code. Judge the effect through the proxy and the load scripts running alongside.

**Notes / caveats**
- **The interval is in seconds, not minutes.** `INTERVAL_MINUTES=900` is passed straight to `sleep`, so the wait is 900 s (15 minutes), even though the message says "Waiting for 900 minutes".
- **It kills every normal and pubsub client on each backend**, not only the proxy's connections. Any other client connected to those nodes is dropped too.
- **`kill_redis_clients` relies on a global variable.** It uses `$pod_name` from the calling loop rather than a parameter.
- **If no pods match the selector, the cycle still runs `kubectl exec` with an empty pod name and IP**, which fails.
- **This script only works with Kubernetes-hosted Redis.** With any other setup, run `CLIENT KILL TYPE normal|pubsub` against each backend node yourself.
