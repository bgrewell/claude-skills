# DART — reference

Exhaustive companion to `SKILL.md`. Verified against source at commit `be7df6b` (2026-08-09): `internal/config/`, `pkg/nodetypes/`, `pkg/steptypes/`, `pkg/testtypes/`, `internal/eval/`, `pkg/ifaces/`, `docs/cli.md`. DART is pre-1.0; expect churn — re-verify against source rather than trusting this file indefinitely, the same way this revision replaced a stale one.

## CLI

| Short | Long | Default | Meaning |
|---|---|---|---|
| `-c` | `--config` | `config.yaml` | Path to the suite YAML |
| `-v` | `--verbose` | false | Also print every *passing* evaluator check, not just failures |
| `-d` | `--debug` | false | Stream command stdout/stderr live while running |
| `-p` | `--pause-on-error` | false | Interactive pause on setup/test failure (reads stdin — unsuitable for CI) |
| `-s` | `--stop-on-error` | false | Stop the suite on the first **test** failure (does not affect setup-step failures, which always abort) |
| `-setup` | `--setup-only` | false | Run only setup steps; leaves environment up, runs **zero** cleanup |
| `-teardown` | `--teardown-only` | false | Run only teardown (steps, then node, then platform); wins if both `-setup`/`-teardown` given |
| `-i` | `--iterations` | 1 | Run the entire suite N times (must be ≥1); reports get `-1`/`-2`/… suffixes when N>1 |
| `-u` | `--until` | – | Stop after this setup-step name, test name, or 1-based test number |
| `-ub` | `--until-behavior` | `exit` | `exit` (stop, exit 0, skip all teardown) or `pause` (wait on stdin, then continue normally) |
| `-r` | `--report` | – | `format:path[,format:path...]` — `junit:results.xml`, `json:results.json` |
| `-V` | `--version` | false | Print version info and exit (short form is capital `-V`) |
| `-ck` | `--check` | false | Validate config + print the plan; touches no infrastructure |
| `-l` | `--log` | – | Write a color-stripped transcript of the run to this file |
| `-var` | `--vars` | – | Override suite `vars:`: `key=value[,key=value...]` |
| `-o` | `--only` | – | Run only tests carrying a tag: `tag=name[,name...]` |
| `-sk` | `--skip` | – | Exclude tests carrying a tag: `tag=name[,name...]` |

DART takes **no positional arguments** — the suite path always goes after `-c`. `--help` prints `[ARGUMENTS]` in its usage line regardless; that's the underlying usage library, not a real accepted argument. One dash or two is interchangeable for every flag (`-c` / `--c` / `-config` / `--config` all work); boolean flags are set by presence only (`--verbose false` is rejected — use `--verbose=false`).

**Flag validation errors** (checked before config loads, exit 1): `-i 0` → `iterations must be at least 1`; a bad `-ub` value → `until-behavior must be "exit" or "pause"`.

### Exit codes

- **0** — no test failed. Also: a suite with zero tests, `--setup-only`, `--teardown-only`, `--check`, `--version`, `--until` with default `exit` behavior. **Also a malformed/unrecognized flag** (Go's `flag` package routes parse errors through the usage library's `PrintUsage`, which unconditionally calls `os.Exit(0)`) — a green exit code does not prove the suite ran; assert on a produced report file (`test -s results.xml`) in CI instead.
- **1** — one or more test failures, a config load/validation error, a rejected flag value, a `--until` target matching nothing, a tag filter excluding every test, a platform/node/setup-step failure, a teardown failure, or a report write failure.
- **2** — a positional argument was passed.

### What survives an abort

Teardown **steps** run only if the suite reaches the end of its test list. Anything that ends the run early — a failing test under `-s`, a test that *errors* (vs. merely fails an evaluation, aborts with or without `-s`), a broken skip condition, or an unhandled setup/node/platform failure — jumps straight to node teardown then platform teardown (reverse order), skipping user `teardown:` steps. `--setup-only` and `--until` (default `exit`) go further and skip node/platform teardown too, leaving everything up for inspection; `--teardown-only` is what removes it afterward, best-effort (keeps going past individual failures, reports a summary, exits 1 if anything failed). `--pause-on-error` can intervene on setup/node/platform failures (menu: continue/retry/quit) but never on the test phase (which just pauses-and-continues) or teardown (unaffected, never prompts).

### `--until` / `-u`

Target matches, in order: a setup-step `name`, a test `name`, or a 1-based test number (numbering reflects `--only`/`--skip` filtering, but *includes* tests that end up `skip_if`/`skip_unless`-skipped). Validated before any infrastructure is touched — an unknown target aborts immediately, listing every valid target. `-ub pause` prints a prompt, waits on stdin, then resumes normally (including teardown); `-ub exit` (default) stops there with exit 0 **unconditionally** — it does not consult the pass/fail count, so a pipeline needing the real verdict must read the report file, not the exit code, on this path.

### Reports (`-r`/`--report`)

- Formats: `junit` and `json` only; anything else is rejected before the suite runs.
- Both halves of `format:path` are required; paths resolve relative to the **working directory dart was started in** (not the suite file's directory), and the parent directory must already exist (DART does not `mkdir -p` it).
- A report is written on every exit from the test phase onward (failures, `-s` abort, `--until` test-phase stop, teardown failures) — nothing is written if the run aborts *before* the first test (platform/node/setup-step failure, `--until` targeting a setup step, `--setup-only`, `--teardown-only`, `--check`). A write failure on a completed suite is a hard error (exits 1 even if all tests passed); on an aborted run it's a best-effort `Warning:` that doesn't mask the original abort cause.
- `--teardown-only` never writes reports, even if `-r` is passed.

JSON schema:
```json
{
  "suite": "string", "passed": 0, "failed": 0, "skipped": 0, "ran": 0,
  "duration_seconds": 0.0,
  "tests": [{ "name": "string", "node": "string", "status": "pass", "duration_seconds": 0.0, "failures": ["check: detail"], "reason": "string" }]
}
```
`status` ∈ `pass`, `fail` (≥1 check failed/errored), `skip` (skip condition matched, reason recorded), `ran` (executed, no `evaluate:` configured — nothing to pass/fail), `error` (infrastructure error or a broken skip condition). `failed` = `fail` + `error` counts. `failures`/`reason` omitted when empty; `tests` is `null` if nothing ran.

JUnit: one `<testsuite name tests failures errors skipped time>` with one `<testcase name classname time>` per test; `pass`/`ran` both emit a bare `<testcase/>` (indistinguishable in a CI panel); `fail`→`<failure>`, `error`→`<error>`, `skip`→`<skipped message="...">`. XML-illegal control characters are stripped from names/messages first.

## Top-level schema

| Key | Type | Required | Meaning |
|---|---|---|---|
| `suite` | string | yes | Suite name |
| `vars` | map | no | Suite variables, overridable via `--vars key=value`, referenced as `{{var.name}}` |
| `docker` | object | no | Docker platform setup (`networks`, `images`) |
| `lxd` | object | no | LXD/Incus platform setup (`socket`, `project`, `networks`, `profiles`, `images`) |
| `nodes` | list | yes | Node definitions |
| `setup` | list | no | Setup steps |
| `tests` | list | yes | Tests |
| `teardown` | list | no | Teardown steps |

A `node:` field on any step/test is a **NodeReference**: string or list-of-strings (multi-node → expanded to one step/test each, except `consistency` tests — see Tests below).

## Node types (`pkg/nodetypes/`)

Recognized `type:` values: `local`, `ssh`, `docker`, `docker-compose`, `lxd`, `lxd-vm` (`mock` is internal-test-only). Unknown → config error. `lxd-vm` is sugar for `lxd` + `instance_type: virtual-machine`.

### Capability matrix (`pkg/nodetypes/capabilities.go`)

| Capability | `local` | `ssh` | `docker` | `lxd`/`lxd-vm` |
|---|---|---|---|---|
| `reboot` (reboot test/step) | – | ✓ | – | ✓ |
| `snapshot` (snapshot step) | – | – | – | ✓ |
| network inspection | – | – | ✓ | ✓ |

A capability mismatch is a construction-time error naming the supporting types, not a runtime surprise.

### local
At most **one** per suite (a second is a duplicate error).

| `options.` | type | default | meaning |
|---|---|---|---|
| `shell` | string | system | shell for commands |
| `env` | []string | – | `VAR=value` entries |
| `sudo.password` | string | – | sudo password (avoid; prefer env_var) |
| `sudo.env_var` | string | – | name of env var holding the sudo password |
| `sudo.vault_secret` | string | – | parsed but unused (no-op) |

### ssh
| `options.` | type | default | meaning |
|---|---|---|---|
| `host` | string | – (req) | hostname/IP |
| `port` | int | 22 | SSH port |
| `user` | string | – (req) | username |
| `pass` | string | – | password auth |
| `key` | string | – | path to private key |

Host key checking is disabled.

### docker
Created **privileged** by default.

| `options.` | type | meaning |
|---|---|---|
| `image` | string (req) | `image:tag` (can reference one built in `docker.images`) |
| `exec_opts` | object | `{ shell, env, sudo }` used for command execution |
| `networks` | list | `{ name, subnet?, ip? }` per attached network |

Remote Docker via standard env vars (no YAML): `DOCKER_HOST` (`tcp://…`, `ssh://user@host`), `DOCKER_TLS_VERIFY=1`, `DOCKER_CERT_PATH`.

**Warning:** the image's own `CMD`/`ENTRYPOINT` must be a long-lived foreground process — DART attaches no TTY/stdin, so an interactive-shell default image (`ubuntu`, `debian`, `alpine`) exits immediately and node setup polls up to 2 minutes before failing with a "container ... never became ready" error. Give it `command: ["sleep", "infinity"]`, use a real service image, or use an `lxd`/`ssh` node instead.

### docker-compose
| `options.` | type | meaning |
|---|---|---|
| `compose_file` | string (req) | path to compose file |
| `service` | string (req) | service to target for execution |
| `project_name` | string | compose project (defaults to node name) |
| `exec_opts` | object | `{ shell, env, sudo }` |

Multiple nodes sharing `compose_file`+`project_name` share one stack.

### lxd / lxd-vm
| `options.` | type | default | meaning |
|---|---|---|---|
| `image` | string (req) | – | `ubuntu:24.04` or `remote:alias`; auto-translated for Incus |
| `instance_type` | string | `container` | `container` or `virtual-machine` (`lxd-vm` forces the latter) |
| `profiles` | []string | – | LXD profiles to apply |
| `project` | string | `default` | LXD project |
| `exec_opts` | object | – | `{ shell, env, sudo }` |
| `networks` | list | – | `{ name, subnet?, ip? }` |
| `server` | string | `local` | image server name |
| `protocol` | string | `lxd` | `lxd` or `simplestreams` |
| `socket` | string | auto | local Unix socket path |
| `remote_addr` | string | – | `https://host:8443` for a remote server |
| `trust_token` | string | – | one-time token (preferred remote auth) |
| `client_cert` / `client_key` | string | – | cert-based remote auth |
| `server_cert` | string | – | custom CA for the remote |
| `skip_verify` | bool | false | skip TLS verify (discouraged) |

Socket auto-detect priority: `/var/lib/incus/unix.socket` → `/var/snap/lxd/common/lxd/unix.socket` → `/var/lib/lxd/unix.socket`. Incus image translation: `ubuntu:24.04` → `images:ubuntu/24.04`; other remotes left as-is.

### Node facts (any node type)
`facts: { <name>: <command> }` — stdout trimmed → value, referenced via `{{ fact "<nodeName|self>" "<name>" }}` anywhere (option strings, commands — recursively through maps/lists). A non-zero fact command aborts the suite.

## Platform blocks

```yaml
docker:
  networks: [{ name: test-net, subnet: 172.20.0.0/16, gateway: 172.20.0.1 }]
  images: [{ name: myimg, tag: latest, dockerfile: dockerfiles/app.dockerfile }]   # built before the suite

lxd:
  socket: /var/lib/incus/unix.socket
  project: { name: dart-proj, config: { features.images: "true" } }   # deleted on teardown
  networks: [{ name: test-net, type: bridge, subnet: 10.100.0.0/24, gateway: 10.100.0.1 }]
  profiles:
    - name: p
      config: { limits.cpu: "2", limits.memory: "2GB", user.user-data: "#cloud-config\n..." }
      devices: { root: { type: disk, path: /, pool: default, opts: { size: 50GB } } }
```

## Step types (`pkg/steptypes/base.go` — `stepFactories`)

Step shape: `{ name, node, step: { type, options } }`.

| type | option | type | notes |
|---|---|---|---|
| `execute` | `command` | string \| []string | list runs sequentially; **`timeout` (seconds) is honored**, bounds each command |
| `apt` | `packages` | []string (req) | `sudo -n apt-get update` if index >24h stale, then `install -y` |
| `simulated` | `time` | float (req) | sleep seconds |
| | `message` | string | shown as a live status update while sleeping |
| `file_create` (alias `file_write`) | `path` | string (req) | |
| | `contents` | string | file body |
| | `overwrite` | bool (false) | error if exists otherwise |
| | `create_dir` | bool (false) | mkdir -p parent |
| | `mode` | int (0644 on create) | octal |
| `file_delete` | `path` | string (req) | |
| | `ignore_errors` | bool (false) | swallow failure (e.g. already gone) |
| `file_edit` | `path` | string (req) | |
| | `operation` | string (req) | `insert` \| `replace` \| `remove` |
| | `match_type` | string (`plain`) | `plain` \| `regex` \| `line` |
| | `match` | string | required unless `match_type: line` |
| | `line_number` | int | required (≥1) for `match_type: line` |
| | `position` | string (`after`) | `before` \| `after`, insert only |
| | `content` | string | inserted/replacement text |
| | `use_captures` | bool (false) | regex replace with `$1`/`${1}`/`${name}` |
| `file_exists` | `path` | string (req) | step **fails** if missing (contrast the `exists` test, which asserts either way) |
| `file_read` | `path` | string (req) | |
| | `contains` | string | optional substring assertion |
| `file_push` | `source` | string (req) | local path, resolved relative to suite file |
| | `dest` | string (req) | path on the node |
| | `mode`, `overwrite`, `create_dir` | | same semantics as `file_create`; unset mode carries the source file's own permissions |
| `file_fetch` | `source` | string (req) | path on the node |
| | `dest` | string (req) | local path, resolved relative to suite file |
| | `overwrite`, `create_dir` | | |
| `file_template` | `source` | string (req) | local Go-template file, parsed **at config time** (fails fast on a broken template) |
| | `dest`, `mode`, `overwrite`, `create_dir` | | |
| | `values` | map | rendered with `text/template`, `missingkey=error`; a null value is a hard config error, and a literal `<no value>` appearing in the render is also caught and errored |
| `http_request` | `url` | string (req) | |
| | `method` | string (`GET`) | |
| | `headers` | map | |
| | `expected_status` | int (200) | |
| | `expected_body` | string | substring check |
| | `timeout` | float (30) | |
| | `from` | `node`\|`host` (`node`) | node-side uses curl |
| `dns_request` | `hostname` | string (req) | |
| | `expected_ips` | []string | every listed IP must appear in the answer |
| | `timeout` | float (10) | |
| | `from` | `node`\|`host` (`node`) | node resolver/hosts file vs. DART's own |
| `service_check` | `service` | string (req) | fails unless `systemctl is-active` = `active` (fixed; use the `service_status` **test** for other expected states) |
| `reboot` | `mode` | `graceful`\|`force` (`graceful`) | needs `reboot` capability |
| | `ready_command` | string | overrides the node's default readiness check |
| | `timeout` | float (node default if 0) | |
| `wait_for` | `command` | string (req) | polled until exit 0 |
| | `timeout` | float (60) | |
| | `interval` | float (2) | |
| `snapshot` | `name` | string (req) | |
| | `action` | `create`\|`restore`\|`delete` (`create`) | |
| | `stateful` | bool (false) | create/restore only; needs CRIU; must match between create and restore or LXD silently does a disk-only restore |

File-op steps (`file_create`/`file_delete`/`file_edit`/`file_exists`/`file_read`/`file_push`/`file_fetch`/`file_template`) go through the node's shell for every non-`local` node type (`cat`/`test -e`/`rm`/`mkdir -p`/`stat -c %a`/base64-chunked writes — chunk size 32 KiB, comfortably under the ~128 KiB `MAX_ARG_STRLEN` kernel limit for a single argv element) and through the native Go filesystem for `local`. Same option surface either way.

## Test types + evaluators (`pkg/testtypes/`)

Shape: `{ name, node, type, options: { ...type-options..., evaluate: {...} }, setup: [...], teardown: [...], retry: {...}, skip_if: "...", skip_unless: "...", capture: ... }` (`setup`/`teardown` here are plain per-test pre/post command strings, distinct from the suite-level `setup:`/`teardown:` sections).

### Evaluators (`internal/eval`, registry in `evaluate.go`) — usable in every test type's `evaluate:` block

| key | value | meaning |
|---|---|---|
| `exit_code` | int | exact process exit code |
| `exit_code_not` | int | exit code must differ |
| `match` | string | stdout, exact after trailing-whitespace trim |
| `stderr_match` | string | same, against stderr |
| `contains` | string | substring of stdout |
| `not_contains` | string | substring must be absent from stdout |
| `stderr_contains` | string | substring of stderr |
| `regex` | string (pattern) | stdout matches |
| `stderr_regex` | string | stderr matches |
| `empty` | bool | stdout is empty |
| `stderr_empty` | bool | stderr is empty |
| `line_count` | int (or comparator map) | number of lines in stdout |
| `gt`/`lt`/`ge`/`le` | number | numeric comparison against stdout parsed as a number |
| `max_duration` | seconds | wall time of the command |
| `json_path` | `{ path, equals? , ... }` | value at a JSON path in stdout |

Several specified together: **all must pass**.

### execute
`command` (string, required), `timeout` (seconds, default 0 = unbounded).
- `extract: { name: { jsonpath: "$.field" } | { regex: "pattern-with-(capture)" } }` — pulls a named value from stdout.
- An `evaluate:` entry whose name matches an `extract:` name takes a **comparator map** instead of a normal evaluator: `{ gt|gte|lt|lte|ge|le: N }`, `{ eq|ne: value }`, `{ within: N, tolerance_pct: P }` or `{ within: N, tolerance: abs }`. Multiple comparators in one map must all hold.
- `capture: name` (whole trimmed stdout) or `capture: { name: { jsonpath|regex } }` (extracted piece) — makes the value available to *later* tests as `{{capture.name}}` in `command`, `skip_if`, `skip_unless`. A dangling reference (capturing test skipped, filtered out by `--only`/`--skip`, or simply doesn't exist) is a hard error, not a silent empty string.

### exists
`path`/`filename` (required, alias). `evaluate.exists` (bool, default `true`) — runs `test -e`.

### file_content
`filename`/`path` (required, alias). Runs `cat`, applies any evaluator to the content. No `evaluate:` block → asserts readable (exit 0).

### file_hash
`filename`/`path` (required, alias). `evaluate: { md5: <32-hex>, sha1: <40-hex>, sha256: <64-hex> }` — at least one required; only the requested tool(s) run (`md5sum`/`sha1sum`/`sha256sum`), matched case-insensitively.

### http_request
`url` (required), `method` (default `GET`), `headers` (map), `timeout` (seconds, default 30), `from` (`node`\|`host`, default `node`). `evaluate.status_code` (int, default 200 if no evaluate block) maps to the result's exit code; body is the result's stdout, so `contains`/`match`/`regex`/`json_path` etc. all work against it. Node-side (`from: node`) shells out with `curl`.

### ping
`target`/`host` (required, alias), `count` (default 5). `evaluate.packet_loss` (max %, default 0 with no evaluate block), `evaluate.rtt_min` (lower bound ms), `evaluate.rtt_avg`/`rtt_max` (upper bound ms). Parses both iputils and busybox ping output. Requires `ping` on the node.

### port_check
`host` (required), `port` (required, 1–65535), `from` (`node`\|`host`, default `node`), `timeout` (seconds, default 5). `evaluate.status` (`open`\|`closed`, default `open`). Node-side probe tries bash `/dev/tcp` first, falls back to `nc -z` (after verifying the local `nc` build actually accepts `-z`, guarding against `busybox nc` builds that don't), and prints `unsupported` (failing the check) rather than guessing if neither works.

### service_status
`service` (required). `evaluate.status` (string, default `active`) compared against `systemctl is-active` output. Needs systemd on the node.

### reboot
Node must implement the `reboot` capability (`ssh`, `lxd`, `lxd-vm`) or the test fails at construction. `mode` (`graceful`\|`force`, default `graceful` — `force` models a power cut), `ready_command` (override), `timeout` (0 = node default). `evaluate` default: `rebooted` (exit 0); any standard evaluator also applies (e.g. `max_duration` to bound the reboot). **`retry:` is rejected outright** on this type — a failing evaluation must never re-trigger a reboot.

### tls_cert
`host` (required), `port` (default 443), `server_name` (SNI, default = host), `timeout` (seconds, default 10), `from` (`node`\|`host`; parsed via the same helper as `http_request`/`port_check`, which defaults to `node` — **but the type's own doc comment claims the connection is always made from the host running DART**; this looks like a stale comment from before `from:` was added and was not empirically re-verified in this pass — pin `from:` explicitly if the default matters to you). Handshake skips chain verification so expired/misissued certs can still be inspected; `evaluate.chain_valid` asserts validity explicitly.

`evaluate` keys: `min_days_remaining` (number, default 0 with no evaluate block), `dns_names` (list — every name must be covered, including via IP SANs), `issuer_contains`/`subject_contains` (string), `chain_valid` (bool). Others fall through to the standard evaluators against the JSON facts (`subject`, `issuer`, `dns_names`, `ip_addresses`, `not_before`, `not_after`, `days_remaining`, `chain_valid`).

### consistency
**Not expanded per node** — the one test type that spans several nodes in a single test. `command` (required), `nodes` (optional list, must be a non-empty, no-duplicates subset of the test's `node:` list; defaults to the full `node:` list), `timeout` (default 0 = unbounded), needs ≥2 nodes.

`evaluate.all_equal` (bool, default `true` if no evaluate block) — every node's trimmed output must (or must not) match; a node that errored can never count as equal (prevents an outage from reading as "difference confirmed" under `all_equal: false`). `evaluate.matching: { pattern, count }` — exactly `count` (default 1) nodes' output must match the regex; this is the "exactly one leader" / "quorum of N" primitive. Comparison uses a SHA-256 digest of raw output bytes (not the JSON-marshaled string) so binary-different outputs can't collapse into false agreement. A failure names which nodes disagree and with what output.

## Retry (`BaseTest`, any test type except `reboot`)

```yaml
retry: { timeout: 90, interval: 5 }   # interval defaults to 2s if given as 0; interval must be < timeout
```

Reruns produce+evaluate (not the per-test `setup:`/`teardown:` commands, which run once, outside the loop) until every check passes or the timeout elapses. A command timeout inside a retry loop counts as a failed attempt, not a fatal error.

## Skip conditions

`skip_if: "<command>"` — test is skipped if the command exits 0. `skip_unless: "<command>"` — skipped if the command exits non-zero. The condition command itself erroring (not just a nonzero exit — an actual execution error) is a hard suite error, never silently treated as skip or pass. Skipped tests are reported separately (`skip` status) and never affect the process exit code. Non-verbose output shows a bare `skipped` marker; `-v` and both report formats carry the reason.

## `!!load_from` (`internal/config` — a textual preprocessor, not a YAML tag)

`<key>: !!load_from(<dir>)` — before YAML parsing, replaces the line with the concatenated contents of every `.yaml`/`.yml` file under `<configdir>/<dir>` (recursive `filepath.Walk`, lexical path order), indented two spaces under `<key>`.
- Each fragment file must be a top-level YAML **list** matching its target section.
- Order = filename order → `00_`, `01_`, … prefixes to sequence.
- Recursive: every `.yml`/`.yaml` beneath the directory is pulled in, no exceptions.
- Fragment files must not start with a `---` document separator (the splice indents it mid-document and breaks the parse).
- Once a suite uses `!!load_from`, DART stops attaching file/line/snippet locations to config errors for that suite — inlining shifts line numbers away from the files actually on disk.

Conventional layout: `main.yaml` + sibling dirs of numbered fragments — see `~/repos/dart/examples/merged/` for a worked example, or `~/repos/core/tests/` for a real production suite using this pattern (documented in that repo's own `tests/README.md`).

## Real consumer patterns

- **`~/repos/dart/examples/`** — `basic/` (local + simulated + execute, no external deps), `docker/`, `docker-compose-example/`, `ssh/`, `lxd/` (+ `lxd-remote`, `lxd-project`, `lxd-vm`), `incus/`, `multi-node/`, `file-operations/`, `sudo/`, `merged/` (the `!!load_from` worked example). Avoid copying `examples/test_types/*.yaml` uncritically — cross-check any type/option you copy from there against `pkg/testtypes/base.go`'s `testFactories` map, since aspirational examples have outpaced implementation before.
- **`grewelltech/core`** (`~/repos/core/tests/`) — real, working suite (`dart -c tests/integration.yaml`): builds Go binaries from the working tree, deploys into a throwaway `lxd` container, drives a gRPC API, uses the full `!!load_from` split-directory layout with numbered fragments. That repo's own `tests/README.md` is worth reading directly for a complete, current example of suite organization at real-project scale.
- **`pronto-project`** (`~/repos/pronto-project/tests/online.yaml`, `tests/air-gapped.yaml`) — another real, current consumer.

## Source map (for re-verifying/extending this skill)

- `internal/config/config.go` — schema structs, `NodeReference`, `!!load_from`, multi-node expansion, contextual errors, `vars`/`{{var.*}}`.
- `pkg/nodetypes/` — node implementations, `base.go` (dispatch, "one local node" rule), `capabilities.go` (the reboot/snapshot/network-inspection matrix — the ground truth for "is a node type suitable for this suite").
- `pkg/steptypes/` — `base.go` (`stepFactories`, 16 real types) + one file per type.
- `pkg/testtypes/` — `base.go` (`testFactories`, 11 real types, retry/skip/capture machinery in `BaseTest`) + one file per type; `extract.go` (jsonpath/regex extractors + comparators); `capture.go` (capture store + `{{capture.*}}` interpolation); `evaluators.go` (type-specific checks like `existsCheck`/`hashCheck`/`packetLossCheck`/`rttCheck`); `vantage.go` (`from: node|host` parsing shared by http_request/port_check/tls_cert).
- `internal/eval/` — the 18-entry evaluator `registry` in `evaluate.go`, one file per evaluator.
- `internal/facts/facts.go` — fact gathering + `{{ fact ... }}` templating.
- `internal/probe/` — the actual shell commands used for node-side http/tls/dns/port probes (what tool each one needs present on the node).
- `docs/cli.md`, `docs/tests.md`, `docs/steps.md`, `docs/node-types.md`, `docs/evaluation.md` — versioned docs living alongside the code; cross-check against source rather than trusting either alone, same discipline that caught this skill's staleness.
- `cmd/dart/main.go` — CLI flags (`go.uber.org/fx` for wiring).
