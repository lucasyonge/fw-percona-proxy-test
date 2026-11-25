# Test scripts reference

This page describes every script in the repository: what it tests, how to run it, and how it reports pass/fail. For setup and an overview, see the [README](README.md).

| Script | Type | Summary |
| --- | --- | --- |
| [`envoy_commands_sanity.sh`](#envoy_commands_sanitysh) | Functional | Positive checks for set, sorted-set, list/blocking, script, cluster, string, stream, hash and misc commands, run from a k8s pod via the proxy |
| [`envoy_commands_sanity_valkey8.sh`](#envoy_commands_sanity_valkey8sh) | Functional | Valkey 8 variant of the sanity suite |
| [`pubsub_commands.sh`](#pubsub_commandssh) / [`_valkey8`](#pubsub_commands_valkey8sh) | Functional | SUBSCRIBE / PSUBSCRIBE / PUBLISH / PUBSUB introspection through the proxy |
| [`transaction_commands.sh`](#transaction_commandssh) / [`_valkey8`](#transaction_commands_valkey8sh) | Functional | Commands wrapped in MULTI/EXEC through the proxy |
| [`negative_testing_envoy_commands.sh`](#negative_testing_envoy_commandssh) / [`_valkey8`](#negative_testing_envoy_commands_valkey8sh) | Negative | Unsupported/invalid commands and auth errors must return the expected error |
| [`valgrind-memory-leak-scripts/*`](#valgrind-memory-leak-scripts) | Memory | Workloads against Envoy running under Valgrind |
| [`address-sanitiser-scripts/*`](#address-sanitiser-scripts) | Memory | Workloads against an ASan-instrumented Envoy build |
| [`k8s/deploy-valkey-cluster.sh`](#deploy-a-valkey-cluster-on-kubernetes) | Setup | Installs the Valkey Operator and deploys the benchmark cluster |
| [`endurance-test-scripts/*`](#endurance-test-scripts) | Endurance | Long-running benchmark, pub/sub churn, streams and periodic client kills |

## envoy_commands_sanity/ — command sanity suites

### `envoy_commands_sanity.sh`

- **Purpose**: An end-to-end positive check of Redis commands sent through the Envoy `redis_proxy` filter to a Redis Cluster backend. Each command is run with `redis-cli -c` against the proxy and the reply is compared with a known expected value.

- **What it tests** (in run order; each "Test case NN" banner is printed before its block). Later blocks reuse keys created by earlier ones (for example, BZPOPMIN/BZPOPMAX pop from the sorted set built in 02), so run the whole script rather than single functions:
  - **01 Sets**: SADD, DEL, SMEMBERS, SUNION, SUNIONSTORE, SINTER, SINTERSTORE, SDIFF, SDIFFSTORE, SISMEMBER, SMISMEMBER. All keys share the `{set}` hash tag.
  - **02 Sorted sets**: ZADD, DEL, ZRANGE ... WITHSCORES, ZUNION, ZUNIONSTORE, ZINTER, ZINTERSTORE, ZDIFF, ZDIFFSTORE, ZRANDMEMBER (with and without count), ZRANGESTORE, ZMSCORE.
  - **03 Lists / blocking**:
    - Basic list commands: DEL, LPUSH, RPUSH, LRANGE, BLPOP, BRPOP. BLPOP/BRPOP first pop from a non-empty list with timeout `0`, then run with a 5 s timeout on an empty list, which must return `nil`.
    - Blocking pops and moves: BZPOPMIN, BZPOPMAX (timeout 3), BRPOPLPUSH, BLMOVE with all four LEFT/RIGHT combinations.
    - SORT ... ALPHA (ascending and DESC).
    - LPOS: plain, with RANK, with COUNT, and with COUNT + RANK.
    - Wait-forever check: BLPOP, BRPOP, BZPOPMIN, BZPOPMAX, BLMOVE and BRPOPLPUSH are each run with timeout `0` on an empty key. They must still be blocked when a local `timeout --kill-after=1s 10s` kills them (exit code 124 or 137). A matching "timeout 5 must not wait forever" variant is commented out.
  - **04 Script / client / select**:
    - SELECT 0 must return OK. SELECT 1 must fail with `SELECT is not allowed in cluster mode`.
    - CLIENT SETNAME with no argument must not return OK.
    - SCRIPT LOAD must return 40-character SHAs, followed by EVALSHA (ARGV[1], then KEYS[1]), SCRIPT EXISTS before and after, and SCRIPT FLUSH SYNC. If SHA generation fails, the EVALSHA checks are skipped.
  - **05 Cluster**:
    - CLUSTER KEYSLOT: `{test}1` and `{test}2` must both map to slot 6918.
    - CLUSTER SLOTS: the slot ranges must add up to 16384 and the highest slot must be 16383.
  - **06 Strings**: SET, SUBSTR, GETRANGE (with negative and positive ranges), DEL, RENAMENX, MGET.
  - **07 Streams**:
    - Basic stream commands: XADD, XRANGE, XTRIM MAXLEN, XDEL, XINFO STREAM (length must be 2, last-entry must match the newest ID).
    - Consumer groups: XGROUP CREATE, CREATECONSUMER (a duplicate must not return 1), DELCONSUMER, SETID and DESTROY (a second destroy must not return 1), XINFO GROUPS, XINFO CONSUMERS, XREADGROUP (`>` read twice; the second read must be empty).
    - Blocking read: DEL, XADD, XLEN, XRANGE ... COUNT 1 as pre-checks, then XREAD BLOCK 5 (milliseconds) from ID `0`, which must succeed, then XREAD BLOCK 0 on `$`, which must block until the local 10 s timeout kills it.
  - **08 Default / connection**:
    - PING must return PONG.
    - TIME is read, then the script sleeps 2 s; the local clock minus the server time must be between 2 and 4 s.
    - QUIT and EXIT must both reply `OK`.
  - **09 Hashes**: DEL, HSET (return counts 2 and then 1), HMSET, HRANDFIELD (single, with count, and WITHVALUES).
  - **11 Other**:
    - FLUSHALL SYNC, with XADD and SCAN 0 checked before and after (key present, then gone).
    - GETEX ... EX 10 (the key must be gone after a 10 s sleep), GETDEL, MSETNX (all keys new vs. some keys already set), EXISTS (multi-key count), DEL (multi-key count).
    - MSET, then COPY with and without REPLACE.
    - SCAN positive cases (after another FLUSHALL SYNC and 20 SETs): TYPE, COUNT and MATCH in different argument orders. Each must return 5 or fewer matching keys.
    - SCAN negative cases: cursors `-1`, `a`, `1.5` and an oversized number must return `ERR invalid cursor`. An unknown TYPE and a MATCH with no hits must return an empty result.
  - **Present but disabled** (commented out in the script):
    - Test case 10 Bitwise (BITOP AND/OR/XOR/NOT).
    - `slowlog_command` (SLOWLOG GET/RESET/LEN, plus a slow Lua script loaded with SCRIPT LOAD/EVALSHA to generate entries).
    - `info_and_config_commands` (INFO, which expects `maxmemory_policy:noeviction`; INFO replication; CONFIG RESETSTAT/GET/SET maxmemory).
    - `xrange_xrevrange` (XADD, XRANGE, XREVRANGE) and `xclaim_xack_xautoclaim` (XREADGROUP, XACK only; despite the name, there is no XCLAIM or XAUTOCLAIM call).

- **How it runs**:
  - The script runs no Redis client locally. It drives `redis-cli` inside a Kubernetes pod through `kubectl exec -it <POD_NAME> -n <TENANT_NAME> -- redis-cli -c -h <PROXY_HOST> -p <PROXY_PORT> -a <REDIS_PWD> ...`.
  - Configuration is read only from `./test_params_envoy.cfg` in the current working directory. The script exits with code 1 if that file is missing, and also exits with an error if `POD_NAME` is empty or unset (`${POD_NAME:?...}`). There are no CLI arguments. The config file is sourced, so its values override any same-named environment variables.
  - `PROXY_HOST` is not a config value. The script derives it from the external-dns hostname annotation on the proxy Service: `kubectl describe service ${PROXY_SERVICE} --namespace ${TENANT_NAME} | grep external-dns | grep hostname | awk '{print $NF}'`.
  - Prerequisites:
    - `bash`, plus standard `awk`, `sed`, `grep`/`egrep`, `date`.
    - `kubectl` with access to the namespace.
    - A pod in that namespace whose image includes `redis-cli`.
    - GNU `timeout` (coreutils) on the machine running the script; it must support `--kill-after`.
    - An interactive terminal: the checks rely on the TTY-formatted `redis-cli` output (see Notes).
    - The proxy reachable from that pod, in front of a Redis Cluster.
  - Example:

    ```bash
    cd envoy_commands_sanity
    # fill in test_params_envoy.cfg first
    ./envoy_commands_sanity.sh 2>&1 | tee sanity.log
    ```

- **Pass/fail & output**:
  - Each check prints a timestamped `PASSED`, `FAILED`, `INFO` or `ERROR` line to stdout. The CLUSTER SLOTS check also prints `DEBUG` lines, and many steps print the raw command output (set, list and zset contents).
  - The first fatal failure ends the run with `exit 1`. Most fatal failures print the elapsed time first; the setup failures in 01–03 (creating the sample sets, sorted sets and lists) exit without it.
  - A full run ends with `FLUSHALL SYNC` and `Total script execution time is (HH:MM:SS) - ...` and exits 0.
  - There are no pass/fail counters and no summary table.
  - Some failures only print `FAILED`/`ERROR` and do not stop the run: SORT DESC, CLIENT SETNAME, SHA generation, SCRIPT EXISTS (before and after flush), the stream deletion after the XREAD test, MSETNX on new keys, the SCAN positive cases, and INFO replication (disabled block).
  - A temporary file `./test_block_cmd.log` is created during the BLPOP/BRPOP timeout test and deleted when that test passes. It is left behind if the test fails.

- **Notes / caveats**:
  - **Destructive**: the script runs `FLUSHALL SYNC` at the start, three times during Test case 11, and at the end. Use a throwaway cluster.
  - **Needs a TTY**: commands run through `kubectl exec -it`, and many checks grep for `redis-cli`'s human-readable formatting (`(integer)`, `(nil)`, `(empty array)`, quoted strings). Running without a terminal on stdin (for example from cron or CI) changes the output and causes false failures. `grep -v option` is used everywhere to drop the `redis-cli` "-a password" warning, which the TTY merges into stdout.
  - If the proxy Service has no external-dns hostname annotation, `PROXY_HOST` ends up empty and every command fails. In that case, edit the `PROXY_HOST=` line to point at your proxy address.
  - `REDIS_PWD` is passed with `-a` and is effectively required. With an empty password, `-a` swallows the next argument, so no-auth setups need a script edit.
  - Some expectations are hard-coded to specific server and proxy behaviour:
    - The exact SELECT error text.
    - QUIT and EXIT both returning `OK`.
    - CLUSTER SLOTS output parsed by taking the last field of every line that does not contain `6379`. This assumes the backend nodes listen on 6379 and depends on the exact reply shape the proxy returns.
    - TIME compared with the local clock, so clock skew causes a failure.
  - Several checks are loose:
    - XADD and XTRIM only match `.*sensor.*`.
    - The XDEL check passes an empty pattern, so it always passes and does not verify deletion. The XINFO STREAM check that follows expects a length of 2, which assumes the earlier entry is still present.
    - The ID check in `validate_blocking_command` is an unquoted `grep 17*`, which matches any output containing a `1`.
    - The MSETNX "some keys already set" check tests the exit status of a `... | wc -l` assignment, so it always passes.
  - In `info_and_config_commands` (disabled), `${INFO}` is printed but never defined.
  - After the ZDIFFSTORE check passes, the script displays `{zset}.zinter` instead of `{zset}.zdiff`, and its failure message says `zinterstore`. This is cosmetic.
  - The run includes a 2 s sleep for TIME, a 10 s sleep for GETEX, two 5 s BLPOP/BRPOP timeouts and seven 10 s `timeout` waits for blocking commands, on top of one `kubectl exec` per command, so expect it to take a few minutes.

### `envoy_commands_sanity_valkey8.sh`

- **Purpose**: The same suite as `envoy_commands_sanity.sh`, adapted for a Valkey 8 backend. It adds a block of Valkey 8 features and breaking-change checks, and relaxes two SCAN expectations.

- **What it tests (differences from the base script)**:
  - **New Test case 12 "Valkey 8 New Features"** (`valkey8_new_features`), run after Test case 11 and before the final `FLUSHALL SYNC`:
    - **SET ... IFEQ**:
      - An initial `SET k v1` must return OK.
      - `SET k v2 IFEQ v1` must return OK.
      - `SET k v3 IFEQ v1` must return `nil`.
      - The value must still be `v2` afterwards.
    - **Nested transactions**: each case is sent as a heredoc into one `redis-cli` session (`kubectl exec -i`, no TTY). Lines containing `Defaulted container`, `option` or `Warning` are filtered out.
      - `MULTI; MULTI; DISCARD` must return `MULTI calls can not be nested`.
      - `MULTI; WATCH k; DISCARD` must return `ERR Command not allowed inside a transaction`.
    - **SCAN 0 TYPE faketype** must return `ERR unknown type name`.
    - **BITPOS / BITCOUNT argument errors** (on a deleted key):
      - `BITPOS k 0 0 1 hello` must return `ERR syntax error`.
      - `BITCOUNT k 0 asd` and `BITCOUNT nokey invalid1 invalid2` must return `ERR value is not an integer or out of range`. The second case checks that arguments are validated before the key's existence.
    - **BGSAVE CANCEL**, **CLIENT KILL MAXAGE 3600**: informational only; these never fail the run.
    - **CLIENT LIST SKIPME YES** and **CLIENT LIST MAXAGE 60**: each fails only if the command produces no output.
    - All Test case 12 checks except BGSAVE CANCEL and CLIENT KILL MAXAGE are fatal (`exit 1`).
  - **SCAN changes in `copy_and_scan_commands`**:
    - The positive cases now require more than 0 matching keys, instead of 5 or fewer, because COUNT is only a hint. They are still non-fatal.
    - The negative case with an unknown TYPE now accepts either an empty result or `ERR unknown type name`.
  - Everything else is the same as the base script: connection, config file, the other test cases, the disabled blocks and the output format.

- **How it runs**: Same as the base script: same `./test_params_envoy.cfg`, same prerequisites (including the TTY). The backend must be a Valkey version that supports the commands and options used. The file is not marked executable, so run it with bash:

  ```bash
  bash envoy_commands_sanity_valkey8.sh 2>&1 | tee sanity_valkey8.log
  ```

- **Pass/fail & output**: Same as the base script: the run stops with `exit 1` at the first fatal failure, and a full run ends with `FLUSHALL SYNC` and the total execution time.

- **Notes / caveats**:
  - The BGSAVE CANCEL "pass" depends only on the exit status of `grep -v option`, so it passes whenever any output comes back. It does not show that the command is supported.
  - The CLIENT LIST SKIPME/MAXAGE checks also pass on any output, including an error reply, so they do not show that the filters are supported either.
  - CLIENT KILL MAXAGE 3600 really disconnects clients connected for more than an hour on whichever node or proxy handles it. Avoid running it next to long-lived clients.
  - The nested MULTI/WATCH checks open their own `kubectl exec` session. They expect transactions to be handled within a single connection through the proxy.
  - SET ... IFEQ is not available in every Valkey 8 release (it was added in 8.1). On a server without it, Test case 12 fails at its first check.

### `test_params_envoy.cfg`

- **Purpose**: A shell fragment that both sanity scripts `source` from the current directory. It ships with placeholder values that you replace with your own.

- **Contents** (all required; there are no defaults in the scripts, and only `POD_NAME` is explicitly checked):

  | Variable | Meaning |
  | --- | --- |
  | `TENANT_NAME` | Kubernetes namespace that holds the test pod and the proxy Service |
  | `POD_NAME` | Pod used to run `redis-cli` against the proxy (`kubectl exec`) |
  | `PROXY_SERVICE` | Kubernetes Service in front of the Envoy proxy; its external-dns hostname annotation becomes `PROXY_HOST` |
  | `PROXY_PORT` | Port the proxy listens on |
  | `REDIS_PWD` | Password passed to `redis-cli -a` |

- **Notes / caveats**:
  - The file is sourced as bash, so keep the `KEY="value"` syntax. `PROXY_PORT` is unquoted in the template.
  - It holds a plaintext password. Don't commit real values.

---

## envoy_commands_sanity/ — pub/sub, transaction and negative tests

All six scripts are standalone Bash scripts that run `redis-cli` from the local machine straight against the proxy endpoint. They do **not** read `test_params_envoy.cfg` and do not use `kubectl`. They all share the same connection settings:

| Env var | Default | Notes |
| --- | --- | --- |
| `REDIS_HOST` | none (required) | Proxy host. The script aborts if it is unset or empty. |
| `REDIS_PORT` | `6379` | Proxy port. |
| `REDIS_PASSWORD` | none (required) | Password passed to `redis-cli -a`. The script aborts if it is unset or empty. |

The expected results assume a **Redis Cluster / Valkey cluster backend behind the Envoy `redis_proxy` filter**. They use `{hash-tag}` keys, and they expect `CROSSSLOT` errors, Envoy's `invalid request` / `unsupported command` replies and the proxy's "`'X' command is not supported within transaction`" rejections.

---

### `pubsub_commands.sh`

**Purpose**: A functional check of pub/sub through the proxy. It runs background subscribers, publishes messages and checks the `PUBSUB` introspection counters.

**What it tests** (channel `test_channel_100`):

- Introspection: `PUBSUB NUMSUB` (expects 0, 0 again after the first subscriber is killed, then 1 while a subscriber is active), `PUBSUB NUMPAT` (expects 0, 0, then 1 while a pattern subscriber is active), `PUBSUB CHANNELS` (the channel must be listed while a subscriber is active).
- Publish: `PUBLISH` with no subscribers (expects `0`) and with one subscriber (expects `1`).
- Subscribe: `SUBSCRIBE` (subscribe confirmation `subscribe / <channel> / 1`, then receipt of `message / <channel> / Hello`), `PSUBSCRIBE test_channel_100*` (confirmation `psubscribe / <pattern> / 1`).
- Unsubscribe: `UNSUBSCRIBE` outside subscribe mode (expects zero output lines matching the channel, `unsubscribe` or `0`). A second check is labelled "PUNSUBSCRIBE".

**How it runs**:

- Prerequisites: `bash`, `redis-cli`, and standard `ps`/`awk`/`sed`/`grep`/`egrep`/`xargs`/`tail`/`tr`. Subscribers run as background `redis-cli` processes on the same host. Each subscriber step waits 5 s (`sleep 5`) and then stops the subscribers with `kill -9` (`kill_clients`, also run once at startup).
- Writes subscriber output to `./subscriber_output.log` in the current directory and deletes it at the end.
- Example:

  ```bash
  REDIS_HOST=127.0.0.1 REDIS_PORT=6379 REDIS_PASSWORD=secret ./pubsub_commands.sh
  ```

**Pass/fail & output**:

- Each check prints a timestamped `PASSED : ✅ ...` or `FAILED : ❌ ...` line with the expected and actual values. The numsub/numpat checks print `INFO : ... validation succeeded` or `FAILED : ... validation failed`.
- There are no counters, no summary and no failure exit code: the script always ends normally. Search the output for `FAILED` to find problems.

**Notes / caveats**:

- `kill_clients` kills **every** local process whose `ps -aef` line contains "subscribe" (case-insensitive) and `$REDIS_HOST`. It is not limited to processes this script started.
- The check labelled "PUNSUBSCRIBE" actually sends `unsubscribe test_channel_100`. `PUNSUBSCRIBE` is never sent.
- All three log-based checks (both SUBSCRIBE checks and the PSUBSCRIBE check) read the log only *after* `kill -9`. Subscriber output goes through a pipe (`redis-cli | grep -v option > file`), so it may not have been flushed yet when `tail` runs, which can make these checks flaky. The `_valkey8` variant addresses this.
- If `PUBSUB NUMSUB`/`NUMPAT` returns nothing or a non-numeric reply, the unquoted `[ ... -eq ... ]` test prints a shell error (e.g. `unary operator expected` / `integer expression expected`) and then falls into the FAILED branch.

---

### `pubsub_commands_valkey8.sh`

**Purpose**: The same pub/sub flow, adapted for Valkey 8 backends, plus several Valkey 8 `CLIENT` command checks.

**Differences from `pubsub_commands.sh`**:

- The channel is `{channel}test_pubsub` (hash-tagged) instead of `test_channel_100`.
- `redis-cli` is called with `--no-auth-warning`. stderr is merged into stdout (`2>&1`) and `Warning:` lines are filtered out, so error replies now appear in the results.
- Background subscribers run through `stdbuf -oL -eL redis-cli ...` (line-buffered output, not piped through `grep`). Each subscriber log is deleted before the step and read **before** the subscribers are killed (first 3 non-empty lines for subscribe/psubscribe confirmations, last 3 non-empty lines for the message). There is an extra `sleep 1` after `PUBLISH`.
- `PUBLISH` replies are parsed by stripping every non-digit character.
- **ACL pre-check**: after the initial `kill_clients`, the script sends `PUBLISH <channel> test`. If the reply contains `NOPERM`, it prints a WARNING block, skips all pub/sub tests, runs only the Valkey 8 tests below and exits with `0`.
- Additional Valkey 8 tests, run at the end (or alone in the NOPERM case):
  - `UNSUBSCRIBE <channel>_test` and `PUNSUBSCRIBE <channel>_test*` outside subscribe mode. `PUNSUBSCRIBE` is really sent here.
  - `CLIENT LIST SKIPME YES`, `CLIENT LIST SKIPME NO`.
  - `CLIENT KILL MAXAGE 3600`. This test never reports a failure: the "else" branch only logs INFO.
  - `CLIENT LIST MAXAGE 60`. Also logs how many `age=` lines came back.
- Example: `REDIS_HOST=... REDIS_PASSWORD=... bash pubsub_commands_valkey8.sh`. The file is not marked executable.

**Notes / caveats**:

- Requires `stdbuf` (GNU coreutils). It is not available by default on macOS, where coreutils provides it as `gstdbuf`. Without it, the subscriber logs only contain a "command not found" error and the subscribe checks fail.
- The Valkey 8 checks decide pass/fail from `$?` of `result=$(redis_cmd ...)`. That is the exit status of the trailing `grep -v "Warning:"`, so any non-empty reply passes, **including error replies**; only an empty reply fails.
- The "PUNSUBSCRIBE" step in the main flow still sends `unsubscribe`, as in the base script. The same `kill_clients` caveat also applies.

---

### `transaction_commands.sh`

**Purpose**: Wraps each of 274 commands in its own `MULTI` / `<command>` / `EXEC` block sent through the proxy. It compares each `EXEC` result with a hard-coded expected value to check how the proxy handles transactions.

**What it tests** (one transaction per entry, in a fixed order; the cases build on each other's state):

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
- Connection/server: PING, ECHO, TIME, CLIENT LIST/GETNAME/SETNAME. CONFIG GET, SLOWLOG GET and INFO are expected to be rejected inside a transaction.
- Keyspace: TYPE, EXISTS, DEL, UNLINK, EXPIRE, PERSIST, TTL, MOVE, RENAME, RENAMENX, SORT … ALPHA. RANDOMKEY, SCAN and KEYS are expected to be rejected inside a transaction.
- Pub/sub: PUBLISH, PUBSUB CHANNELS, UNSUBSCRIBE and PUNSUBSCRIBE are all expected to be rejected inside a transaction. SUBSCRIBE and PSUBSCRIBE are commented out.
- Database: SELECT 1 (expects `DB index is out of range`), SELECT 0 (expects `OK`). FLUSHDB, FLUSHALL, DBSIZE and SWAPDB are expected to be rejected inside a transaction.
- Cluster/modules: CLUSTER INFO/NODES/SLOTS (expected to be rejected), MODULE LIST (expects `(nil)`), MODULE LOAD/UNLOAD (expect an empty result).
- Blocking commands: BLPOP, BRPOP, BRPOPLPUSH, BZPOPMIN, BZPOPMAX and BLMOVE (all four LEFT/RIGHT combinations), with non-zero and zero timeouts, checked with LRANGE.
- XREAD/XREADGROUP argument permutations: 19 XREAD and 23 XREADGROUP orderings of `BLOCK`/`COUNT`/`STREAMS`/`GROUP`/consumer (the XREAD cases include `COUNT 0` and `COUNT -1`). Depending on the ordering, the expected result is a valid read, an empty result, `ERR syntax error`, `CROSSSLOT` + `EXECABORT`, or the "Unbalanced XREAD list of streams" error.
- COPY: `COPY {key}1 {key}2` without `REPLACE` (expects `0`) and with `REPLACE` (expects `1`), verified with MGET.

**How it runs**:

- Prerequisites: `bash`, `redis-cli`, `awk`/`sed`/`egrep`/`cut`/`tr`. No cluster mode (`-c`) is used: everything goes through the proxy.
- At startup the script runs `FLUSHALL` and `SCRIPT LOAD` of a small SET/GET Lua script. **It wipes the target database.**
- Each case is fed to `redis-cli` on stdin as a heredoc (`MULTI`, the command, `EXEC`). Multi-line replies (after dropping lines containing `QUEUED`/`OK`) are flattened into one string with literal `\n` separators; single-line replies drop the first two lines (the `MULTI` `OK` and `QUEUED`). Per-command parsing rules exist for XRANGE/XREAD/XREVRANGE/XINFO, ZRANGE/HGETALL/MGET/GEOPOS, SMEMBERS/SRANDMEMBER/SPOP (each line cut to 6 chars so member order does not matter), TIME, XREADGROUP, XADD, PING, TTL and PTTL.
- Example:

  ```bash
  REDIS_HOST=127.0.0.1 REDIS_PORT=6379 REDIS_PASSWORD=secret ./transaction_commands.sh
  ```

**Pass/fail & output**:

- For each case it prints `Executing: <cmd>`, the raw `=======RESULT`, then `PASSED : ✅`, `FAILED : ❌` (with expected and actual values) or `FATAL : ❌` (if the output contains `WRONGTYPE`, `NOSCRIPT`, `NOTBUF` or `SYNTAXERR`). FATAL also counts as an error.
- TTL/PTTL pass when the value is ≤ 10 or ≤ 10000 respectively.
- At the end it prints a summary with the total number of commands and the number of commands with errors.
- **Exit code**: `0` if `error_count ≤ 11`, followed by a final `FLUSHALL`. Otherwise it prints `ERROR : n/total commands failed ...` and exits with `1` (no final `FLUSHALL`, so test data is left behind).

**Notes / caveats**:

- The `commands` and `expected_results` arrays are matched **by position**. Both have 274 entries, so adding or removing an entry in only one array shifts every later expectation.
- In `execute_redis_command`, the line `2>/dev/null | grep -v option` comes *after* the heredoc terminator. It therefore runs as a separate, empty command, and the intended stderr suppression and filtering never apply to `redis-cli` (the `-a` password warning is printed to the terminal for every case).
- The FATAL check runs before the comparison, so the unknown-SHA `EVALSHA` case (whose expected value itself contains `NOSCRIPT`) always counts as an error.
- XADD results are validated twice: once against `<ms>-<expected>`, then again against the bare expected value. The second comparison cannot match, so each of the 4 XADD cases adds one error.
- The TIME check counts reply lines that start with `172` (an epoch-seconds prefix) and compares the count with an empty string, so this check cannot pass as written.
- In the TTL/PTTL check, an empty result also evaluates as ≤ 10 inside `[[ ]]` and passes.
- The tolerance of 11 errors suggests some expected mismatches are already accepted. Many expected strings are tied to one particular proxy and server version (error wording, `XINFO` field lists, the GEOPOS precision).

---

### `transaction_commands_valkey8.sh`

**Purpose**: The same MULTI/EXEC sweep, with expectations updated for Valkey 8 backends, plus a few standalone Valkey 8 transaction checks.

**Differences from `transaction_commands.sh`**:

- Before the main loop (after the startup FLUSHALL/SCRIPT LOAD), three extra checks run. They print PASSED/FAILED/INFO lines but **do not count toward `error_count` or the exit code**:
  - Nested `MULTI` must fail with `MULTI calls can not be nested`. `WATCH` inside `MULTI` must fail with `ERR Command not allowed inside a transaction`.
  - `DEL {trans}version`, then `SET {trans}version v1`, `SET … v2 IFEQ v1` and `GET` inside one transaction. The result must contain `v2`.
  - `BITCOUNT {trans}nonexistent 0 invalid` (expects `ERR value is not an integer or out of range`) and `BITPOS {trans}nonexistent 0 0 1 hello` (expects `ERR syntax error`). When these do not match, the script only logs INFO, never FAILED.
- Changes to the main list (273 entries):
  - The first `CLIENT GETNAME` is removed, and `CLIENT GETNAME` after `SETNAME` now expects an empty result instead of `myclient`.
  - `XINFO STREAM` expects the extra fields `max-deleted-entry-id`, `entries-added` and `recorded-first-entry-id`. `XINFO GROUPS` expects the extra fields `entries-read` and `lag`.
  - Nested `WATCH` expects `ERR Command not allowed inside a transaction` + `EXECABORT`. `UNWATCH` expects "`'UNWATCH' command is not supported within transaction`".
  - `SELECT 1` and `SELECT 0` both expect "`'SELECT' command is not supported within transaction`". `DBSIZE` and `SWAPDB` now expect an empty result.
  - `MODULE LIST` expects an empty result instead of `(nil)`.
  - The unbalanced XREADGROUP case expects the Valkey wording `ERR Unbalanced 'xreadgroup' list of streams: for each stream key an ID or '>' must be specified.`
- The pass threshold (`error_count ≤ 11`), the parsing and the FLUSHALL behaviour are unchanged. The file is not marked executable, so run it with `bash transaction_commands_valkey8.sh`.

**Notes / caveats**:

- The heredoc stderr/filter issue, the NOSCRIPT-always-FATAL case, the double XADD validation and the TIME check from the base script are all inherited. The extra checks use the same heredoc pattern; in the SET IFEQ check, the trailing `| tail -3` is on the same disconnected line, so it has no effect either.
- The nested-MULTI and WATCH-inside-MULTI checks use the non-hash-tagged key `key1`; if the proxy queues the `SET`, it is actually written.

---

### `negative_testing_envoy_commands.sh`

**Purpose**: Sends malformed or wrong-type commands through the proxy and checks that the proxy or the backend returns the expected errors. It also checks that commands sent without arguments are rejected.

**What it tests**:

- **Authentication** (results are only printed, not counted): `PING` without a password (expects `NOAUTH`), with a wrong password (expects `invalid password`), and with the correct password (expects `PONG`).
- **Test case 01, wrong type / bad arguments** (counted; the setup steps such as `flushall`, `LPUSH`, `SET` and `del` are counted as tests too). The script creates a list `{negative_list}1` and a string `{negative_string}1`, then sends:
  - Strings: APPEND, BITCOUNT, BITOP and STRLEN on a list (expect `WRONGTYPE`); DECR and INCR on a non-integer; SETBIT and GETBIT with offset -1; SETRANGE with a negative offset; GET on a missing key; GETRANGE with an inverted range.
  - Lists: BLPOP with a negative timeout; LINDEX, LINSERT, LPOP, LPUSH, LRANGE, LSET and LTRIM on a string; RPOPLPUSH with a non-list source and/or destination.
  - Sets: SADD, SCARD, SDIFF, SINTER, SISMEMBER, SMEMBERS, SMOVE, SPOP, SRANDMEMBER and SREM on a list.
  - Hashes: HDEL, HEXISTS, HGET, HGETALL, HINCRBY, HKEYS, HLEN, HMGET, HMSET and HSETNX on a list.
  - Sorted sets: ZADD, ZCARD, ZCOUNT, ZINCRBY, ZRANGE, ZRANK, ZREM, ZREVRANGE, ZSCORE and ZUNIONSTORE on a list.
  - HyperLogLog: PFADD, PFCOUNT and PFMERGE on a list.
  - Geo: GEOADD, GEODIST, GEOHASH, GEOPOS, GEORADIUS and GEORADIUSBYMEMBER on a list.
  - Pub/sub: PUBLISH with a missing argument (expects a wrong-number-of-arguments error); PUBSUB with an invalid subcommand (expects `ERR Unknown subcommand or wrong number of arguments`).
  - Transactions: EXEC without MULTI; DISCARD without MULTI; "WATCH inside MULTI".
  - Connection: AUTH with a wrong password (expects `ERR invalid password`); ECHO without a message; SELECT 99 (expects `ERR SELECT is not allowed in cluster mode`); CLIENT SETNAME `''` (expects `OK`).
  - Server: INFO with an invalid section (expects `ERR Invalid section`); BGSAVE and SLAVEOF (expect `unsupported command`).
  - Scripting: EVAL with a syntax error; EVALSHA with an unknown SHA (expects `NOSCRIPT`); SCRIPT LOAD of an empty script; SCRIPT KILL when no script is running (expects `NOTBUSY`).
  - Keys: DEL, EXPIRE, RENAME, TYPE and DUMP on a missing key.
  - Streams: XADD, XLEN, XRANGE, XREAD, XREVRANGE, XDEL, XTRIM, XGROUP CREATE and XREADGROUP on a list.
- **Test case 02, no arguments**: 176 commands are each sent with no arguments, and each reply must contain `invalid request` (Envoy's response to bad arity). The list covers string, hash, list, set, sorted-set, HyperLogLog, connection (AUTH, ECHO, PING, SELECT), server (BGREWRITEAOF, BGSAVE, DBSIZE, FLUSHALL, FLUSHDB, INFO, LASTSAVE, SAVE, TIME), scripting (EVAL, EVALSHA), geo, stream and generic key commands (DEL … SCAN, including MIGRATE, MOVE, OBJECT, RESTORE, SORT and WAIT).

**How it runs**:

- Prerequisites: `bash` and `redis-cli`.
- The script runs `FLUSHALL SYNC` at the start and at the end (and `flushall` again as the first counted case). **It wipes the target database.**
- Before every no-argument command it checks `PING`, retrying every 5 s for as long as the proxy is unreachable (there is no timeout). There is a `sleep 5` between case 01 and case 02.
- Example:

  ```bash
  REDIS_HOST=127.0.0.1 REDIS_PORT=6379 REDIS_PASSWORD=secret \
  PROXY_HOST=127.0.0.1 PROXY_PORT=6379 ./negative_testing_envoy_commands.sh
  ```

  `PROXY_HOST` and `PROXY_PORT` are needed for the authentication tests; see the caveats.

**Pass/fail & output**:

- A case passes when the reply *contains* the expected substring. Case 01 prints `PASS: <name>` or `FAIL: <name> - Expected '...', but got '...'`, followed by a summary of total, passed and failed tests. Case 02 prints `PASSED : ✅` or `FAILED : ⚠️` per command, then an overall PASSED/FAILED line.
- **Exit code**: `1` if case 01 has **more than 5** failures; in that case case 02 never runs. Also `1` if case 02 has **more than 6** failures. Otherwise the exit code is that of the final `FLUSHALL SYNC ... | grep -wq OK`, i.e. `0` only if that final flush replies `OK`.

**Notes / caveats**:

- The authentication tests use `$PROXY_HOST` and `$PROXY_PORT`, which this script never defines. Export them yourself, or these three checks run against an empty host and port.
- Cases whose expected value is `""` (GET on a missing key, GETRANGE with an inverted range, DUMP on a missing key) always pass, because an empty substring matches any reply.
- Commands are passed unquoted (`$command`), so embedded quotes reach the server literally and `\n` is not a newline. As a result:
  - "WATCH inside MULTI" sends one malformed command rather than a MULTI block.
  - `EVAL "return {KEYS[1]" ...` and `SCRIPT LOAD ""` do not send the arguments they appear to send.
  - `"PUBLISH "" ..."` ends up as `PUBLISH {negative_list}1`.
- Case 02 really executes commands that are valid without arguments, such as `FLUSHALL`, `FLUSHDB`, `SAVE`, `BGREWRITEAOF`, `BGSAVE`, `PING`, `TIME`, `DBSIZE`, `INFO`, `LASTSAVE` and `RANDOMKEY`, if the proxy forwards them. Any of them that does not reply `invalid request` counts as a failure against the threshold of 6.
- `start_time` is computed but never used.

---

### `negative_testing_envoy_commands_valkey8.sh`

**Purpose**: The same negative suite with expectations relaxed or updated for Valkey 8 backends, plus extra SCAN, BITCOUNT/BITPOS and transaction checks.

**Differences from `negative_testing_envoy_commands.sh`**:

- The authentication tests use `REDIS_HOST`/`REDIS_PORT`, which fixes the undefined `PROXY_*` variables. A wrong password also passes if the reply contains `NOAUTH`.
- Pub/sub: `PUBLISH \"\" {negative_list}1` now expects `NOPERM`, which assumes an ACL that blocks pub/sub. `PUBSUB INVALID_SUBCOMMAND` expects `ERR unknown subcommand`.
- Transactions: the broken "WATCH inside MULTI" one-liner is replaced by two real heredoc transactions that are counted. Nested `MULTI` expects `MULTI calls can not be nested`; `WATCH` inside `MULTI` expects `ERR Command not allowed inside a transaction`.
- `ECHO` with no argument and `BGSAVE` both expect `invalid request`.
- Scripting expectations are reduced to prefixes: `ERR`, `NOSCRIPT`, `ERR`, `NOTBUSY`.
- New counted sections (run after the stream tests):
  - SCAN: `SCAN 0 TYPE faketype` (expects `ERR unknown type name`), `SCAN -1` and `SCAN abc` (expect `ERR invalid cursor`).
  - BITCOUNT/BITPOS: `BITCOUNT {nonexistent}key 0 invalid` and `BITCOUNT {no}key invalid1 invalid2` (expect `ERR value is not an integer or out of range`), `BITPOS {nonexistent}key 0 0 1 hello` (expects `ERR syntax error`).
- Case 02 (no arguments; same 176-command list):
  - A reply passes if it matches `invalid request`, `wrong number of arguments`, `ERR` or `syntax error`.
  - PING, FLUSHALL, FLUSHDB, TIME, RANDOMKEY and DBSIZE are reported as `SKIPPED` (the skip list also names MULTI, EXEC, DISCARD and UNWATCH, which are not in the command list). The skip is decided only *after* the command has already been sent.
- Thresholds (≤ 5 and ≤ 6 failures), exit codes and the FLUSHALL behaviour are unchanged. The file is not marked executable, so run it with `bash negative_testing_envoy_commands_valkey8.sh`.

**Notes / caveats**:

- The `NOPERM` expectation for PUBLISH only holds on a deployment whose ACL denies pub/sub. Because of the unquoted expansion, the channel sent is literally `""`; without such an ACL the reply is an integer and the test fails.
- The case 02 pattern `ERR` accepts almost any error reply, so this case is much weaker than in the base script.
- `SELECT 99` still expects the cluster-mode error.
- The unquoted-`$command` quoting caveat and the always-passing empty expectations from the base script still apply to the `run_negative_test` cases. The new heredoc transaction checks have the same disconnected `2>/dev/null | grep -v option` line as the transaction scripts, and they write the non-hash-tagged key `key1` if the `SET` is queued.
- FLUSHALL and FLUSHDB are still executed during case 02 even though they are reported as SKIPPED.

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
  | --- | --- |
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
  - **Report:** a single line with one `<group> - Success` or `<group> - Failed` entry per command (not per group). Entries are joined by a literal `\` (backslash and space).
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

## Deploy a Valkey Cluster on Kubernetes

Run the deployment from the repository root with Helm and `kubectl` installed. Set your current Kubernetes context and namespace to the test environment first.

```bash
(cd k8s && ./deploy-valkey-cluster.sh)
kubectl get pods -n valkey-operator-system
kubectl get valkeycluster benchmark-cluster
kubectl get valkeynodes -o wide
```

The script installs the Valkey Operator in `valkey-operator-system` and applies the `benchmark-cluster` resource in your current namespace. Run it from `k8s/` because it uses a relative path to the manifest. The manifest requests three shards with zero replicas per shard. Check that the operator is running and the Valkey nodes are ready before starting a workload. [Deployment script](k8s/deploy-valkey-cluster.sh) · [Cluster manifest](k8s/cr/valkey-cluster.yaml)

The deployment provides the Valkey backend. Configure your proxy to use that backend before running the benchmark or pub/sub scripts. Run the client-kill script from a shell with `kubectl` access to the backend namespace.

## endurance-test-scripts/

Long-running load and fault-injection scripts. Each one stresses the proxy for a long time (or forever) so you can watch its memory, connection count, error rate and crash behaviour. None of them checks results automatically and none returns a pass/fail exit code. You judge the run from the logs and from the proxy's own metrics.

### `endurance_automation.sh`

Runs one `valkey-benchmark` process per command. It reads arguments from a commands file, skips blank lines and full-line comments, and preserves quoted arguments without shell expansion. Install `valkey-cli` and `valkey-benchmark` where the script runs.

```bash
./endurance_automation.sh '' 127.0.0.1 7777 500 200 result_cx commands.txt
```

The seven positional arguments are the password, proxy host, proxy port, per-command request rate, connections per command, result prefix, and commands file. Pass an empty password to skip authentication. Set `BENCHMARK_REQUESTS` to override the benchmark client's default total requests per command, and `BENCHMARK_START_DELAY` to override the two-second delay between starts.

At startup, the script uses an unauthenticated `valkey-cli` connection to check for `order_stream`. If the stream is absent, it creates the `order_processors` group at `$`. If the stream already exists but lacks the group, create it before running the bundled workload.

```bash
valkey-cli -h 127.0.0.1 -p 7777 XGROUP CREATE order_stream order_processors '$' MKSTREAM
```

Each benchmark writes CSV output and diagnostics to `results_endurance/<result_prefix>_<line_number>.log`. The script waits for the jobs, reports throughput and p50 latency, and exits with status 1 if a benchmark fails. [Script](endurance-test-scripts/endurance_automation.sh)

### `commands.txt`

The bundled workload contains 94 commands for `endurance_automation.sh`. It covers strings, hashes, lists, sets, sorted sets, HyperLogLog, geo, bitmaps, streams, pub/sub, key management, scanning, and server and cluster commands. [Workload](endurance-test-scripts/commands.txt)

Benchmarks run concurrently, so operations on shared keys can overlap. Geo queries use `locations` without populating it. Stream commands use `order_processors` on `order_stream`, and `XCLAIM` uses a fixed entry ID. Server and cluster commands require support in the proxy build under test.

### `endurance_streams.sh`

Runs 14 benchmarks covering streams, lists, bitmaps, and Lua scripting. Setup uses `valkey-cli` to load the Lua script for `EVALSHA`, create or reuse the `mygroup` consumer group, and add an entry whose ID is passed to `XDEL`. The workloads use `valkey-benchmark`.

```bash
PROXY_HOST=127.0.0.1 PROXY_PORT=7777 VALKEY_PWD='' KEY_PREFIX=streams-test: \
  ./endurance_streams.sh
```

- `PROXY_HOST` is required. `PROXY_PORT` defaults to `7777`. Set `VALKEY_PWD` for an authenticated endpoint.
- `REQUESTS` sets the per-benchmark rate in requests per second and defaults to `2000`. `CONNECTIONS` defaults to `200` per benchmark.
- `KEY_PREFIX` is optional and is prepended to `mylist`, `mykey`, and `mystream`.

Jobs start two seconds apart and the script waits for them. It overwrites `endurance_streams_result.csv` alongside the script and appends the last output line from each benchmark. Setup failures cause a nonzero exit. Inspect stderr and the CSV for individual benchmark failures because the parent script does not collect those exit statuses. [Script](endurance-test-scripts/endurance_streams.sh)

### `endurance_pubsub.sh`

Runs a pub/sub soak test with `valkey-cli` and OpenSSL. Each iteration opens channel and pattern subscriptions, publishes to the generated channels, and runs random subscribe, unsubscribe, and publish operations while publishing is active.

```bash
VALKEY_HOST=127.0.0.1 VALKEY_PORT=7777 VALKEY_PWD='' \
  NUM_CHANNELS=10 NUM_PATTERNS=5 PUBLISH_DURATION=10 ITERATIONS=1 \
  ./endurance_pubsub.sh
```

| Variable | Default |
| --- | --- |
| `VALKEY_HOST` | Required |
| `VALKEY_PORT` | `6379` |
| `VALKEY_PWD` | Empty for an unauthenticated proxy |
| `NUM_CHANNELS` | `7000` |
| `NUM_PATTERNS` | `3000` |
| `PUBLISH_DURATION` | `1800` seconds per iteration |
| `PUBLISH_IOPS` | `100` messages per one-second pause |
| `RANDOM_OPERATIONS_INTERVAL` | `10` seconds |
| `ITERATIONS` | `2000` |

The script reports progress and discards subscriber output. Watch proxy metrics for the effect of the load. Unsubscribe commands use fresh connections, so the original subscriber processes can persist across iterations. The generated `pattern_*` subscriptions do not match the `channel_*` destinations. Default settings require process and file-descriptor limits that can support at least 10,000 concurrent subscribers per iteration. [Script](endurance-test-scripts/endurance_pubsub.sh)

### `endurance_client_kill.sh`

Injects backend connection failures while another workload runs through the proxy. It requires `kubectl` access to list `ValkeyNode` resources and exec into the selected pods. Each cycle reads `.status.podIP` and `.status.podName` from nodes whose `.status.role` is `primary`. In each pod's `server` container, it runs `valkey-cli` against that pod's IP on port `6379` and issues `CLIENT KILL TYPE normal` and `CLIENT KILL TYPE pubsub`.

```bash
NAMESPACE=default VALKEY_PASSWORD='' ./endurance_client_kill.sh
```

Set `NAMESPACE` to the namespace where you deployed the cluster. `VALKEY_PASSWORD` defaults to empty and is passed to the backend client with `--user default`. The script selects nodes by their reported role. It prints the selected pods and kill results, then sleeps for 900 seconds (15 minutes) and repeats until stopped. The kill commands affect all clients of the selected types on those nodes. [Script](endurance-test-scripts/endurance_client_kill.sh)
