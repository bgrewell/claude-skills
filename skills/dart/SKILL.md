---
name: dart
description: >-
  Author and run DART (Dynamic Assessment & Regression Toolkit) test suites —
  a YAML-driven distributed-systems/integration test runner by bgrewell. Write
  a suite of nodes (local/ssh/docker/docker-compose/lxd/lxd-vm) plus setup
  steps, tests (execute, http_request, port_check, service_status, tls_cert,
  file_content, file_hash, exists, ping, reboot, consistency) with a rich
  evaluate/extract/capture/retry system, and teardown, then run the `dart`
  CLI. Use when creating or editing DART YAML test files (top-level `suite:`,
  `nodes:`, `setup:`, `tests:`, `teardown:`, with `evaluate:` blocks), when
  working in a project's `tests/` directory of such YAML (e.g. bgrewell/dart
  itself, grewelltech/core, pronto-project), or when running/debugging the
  `dart` command. Covers node/step/test/evaluator option tables, node facts
  templating, multi-node expansion, `!!load_from` directory layout, and which
  node types support which capabilities (reboot, snapshot).
---

# DART

DART is a **YAML-driven test runner** for distributed-systems / integration testing. You describe a suite — target **nodes**, **setup** steps, **tests** with pass/fail assertions, and **teardown** — in a YAML file and run the `dart` CLI. DART provisions the nodes (containers/VMs/SSH), runs everything in order, prints color-coded results, and exits non-zero if any test fails (so it drops into CI).

You **author YAML and run a binary** — you do not import a Go library. (DART is written in Go, but consumers never `import` it.)

> **This skill was rewritten 2026-08-21, source-verified against commit `be7df6b` (2026-08-09).** A prior version of this skill (written ~2026-06-30) claimed most test types "error at runtime as not implemented" — that was true of an earlier DART, but the tool has evolved substantially since. If DART moves further ahead of this skill, re-verify against `pkg/testtypes/`, `pkg/steptypes/`, `pkg/nodetypes/`, and `internal/eval/` rather than trusting either this file or the README blindly — that discipline caught the last drift and will catch the next one.

## Current capability surface (verified against source)

| Category | Values |
|---|---|
| **Test types** (`pkg/testtypes/`, all wired in `testFactories`) | `execute`, `exists`, `file_content`, `file_hash`, `http_request`, `ping`, `port_check`, `service_status`, `reboot`, `tls_cert`, `consistency` |
| **Evaluators** (`internal/eval`, all wired in `registry`) | `exit_code`, `exit_code_not`, `match`, `stderr_match`, `contains`, `not_contains`, `stderr_contains`, `regex`, `stderr_regex`, `empty`, `stderr_empty`, `line_count`, `gt`, `lt`, `ge`, `le`, `max_duration`, `json_path` |
| **Step types** (`pkg/steptypes/`, all wired in `stepFactories`) | `execute`, `apt`, `simulated`, `file_create` (alias `file_write`), `file_delete`, `file_edit`, `file_exists`, `file_read`, `file_push`, `file_fetch`, `file_template`, `http_request`, `dns_request`, `service_check`, `reboot`, `wait_for`, `snapshot` |
| **Node types** (`pkg/nodetypes/`) | `local`, `ssh`, `docker`, `docker-compose`, `lxd`, `lxd-vm` (`mock` exists for internal tests only) |

Every test/step type parses its own option set and rejects unknown keys with a source-located config error — `--check` catches this without touching infrastructure.

### Node capability matrix — this is the real "is it node-agnostic" answer

Most test/step types run through one shared interface (`ifaces.Node.Execute(command)`), so switching a node's `type:` (e.g. `lxd` → `docker`) is usually a same-suite, no-other-changes swap — confirmed in source (`commandTest`, `execFileOps` in `pkg/steptypes/fileops.go` both dispatch through the generic interface, no per-node-type branching in test/step logic). **But two capabilities are hard, construction-time gates, not just environment quirks** (`pkg/nodetypes/capabilities.go`):

| Capability | Supported node types | Used by |
|---|---|---|
| `reboot` | `ssh`, `lxd`, `lxd-vm` — **not** `docker`, `local` | `reboot` test type, `reboot` step |
| `snapshot` | `lxd`, `lxd-vm` only — **not even `ssh`** | `snapshot` step |
| network inspection | `docker`, `lxd`, `lxd-vm` — not `ssh`, `local` | node-side network facts |

A suite using `type: reboot` or `type: snapshot` on a `docker` node fails at construction with `node "..." does not support reboot (supported: lxd, lxd-vm, ssh)` (or the snapshot equivalent) — before anything runs.

On top of that hard gate, a handful of types have **real environment prerequisites** that exist regardless of node type, because they shell out on the node:
- `service_status` (test) / `service_check` (step) run `systemctl is-active` — needs systemd. LXD/Incus containers and VMs and SSH hosts have it; **plain `docker` nodes generally don't** (standard base images ship no `systemctl`, and DART doesn't boot the container under an init system).
- `http_request`/`port_check`/`tls_cert` (tests) and `http_request`/`dns_request` (steps), when run with the default `from: node` vantage, shell out on the node and need `curl` (http), `openssl` (tls_cert probe), and one of `getent`/`dig`/`host`/`nslookup` (dns) respectively — a minimal image without them fails loudly rather than passing or silently no-op'ing. Use `from: host` to ask the same question from the machine running DART instead, which sidesteps this entirely.
- `ping` needs the `ping` binary on the node.

So: **porting a suite from `lxd` to `docker` nodes is usually just changing the node's `type:`/`image:`**, unless it uses `reboot`/`snapshot` (hard no on docker) or `service_status`/`service_check` (works if the docker image happens to run systemd, which is unusual — most don't).

## Install & run

```bash
# Install a release (verifies against the release checksums.txt)
curl -fsSL https://raw.githubusercontent.com/bgrewell/dart/main/install.sh | bash   # -> /usr/local/bin/dart
# or build from source
git clone https://github.com/bgrewell/dart.git && cd dart && make build            # -> bin/dart (GOOS=linux always)
# or, any platform Go supports:
go install github.com/bgrewell/dart/cmd/dart@latest
```

Requires Go 1.26.5+ for `go install`/build-from-source (released binaries and the install script need no Go toolchain). `DART_INSTALL_DIR` and `DART_VERSION` env vars control the install script's destination and pinned version.

```bash
dart -c suite.yaml              # run a suite (config defaults to config.yaml)
dart -c suite.yaml -v           # verbose (every passing check too, not just failures)
dart -c suite.yaml -d           # stream command output live (debug)
dart -c suite.yaml -s           # stop on first test failure
dart -c suite.yaml --setup-only # run only setup, leave env up for inspection (no cleanup at all)
dart -c suite.yaml --teardown-only
dart -c suite.yaml -i 5         # run the whole suite 5 times
dart -c suite.yaml --check      # validate + print the plan, touch no infrastructure
dart -c suite.yaml -r junit:results.xml,json:results.json
dart -c suite.yaml -u "install locker" -ub pause   # stop after a named step/test, wait for enter
dart -c suite.yaml -o tag=smoke                    # only tests tagged smoke
dart -c suite.yaml --vars target=prod.internal     # override suite `vars:`
```

Exit code is **0** only if every test passed (and 0 for `--check`/`--setup-only`/`--teardown-only`/`--version`/`--until` with default behavior too); **1** on any test failure or error; **2** on a stray positional argument. Full flag table, exit-code nuances, and report schemas are in `REFERENCE.md`.

**Warning (verified, still true, easy to trip on):** a malformed flag or an unknown flag exits **0** — Go's `flag` package routes parse errors through the usage library's `PrintUsage`, which calls `os.Exit(0)`. A green exit code alone does not prove the suite ran; assert on a produced report file in CI (`test -s results.xml`).

## Suite file structure

```yaml
suite: My Suite          # required: name
vars: { target: staging.internal }   # optional: overridable via --vars key=value
docker: { ... }          # optional: Docker platform setup (networks, images)
lxd:    { ... }          # optional: LXD/Incus platform setup (socket, project, networks, profiles)
nodes:  [ ... ]          # required: where tests run
setup:    [ ... ]        # optional: steps run before tests (sequential)
tests:    [ ... ]        # required: the actual tests
teardown: [ ... ]        # optional: steps run after tests (only if the test phase is reached)
```

**Execution order:** platform setup → node setup (create containers/VMs/SSH) → gather node facts → `setup` steps in order → `tests` in order → `teardown` steps in order → node teardown → platform teardown. A failing **setup** step aborts the suite and jumps straight to node/platform teardown (user `teardown:` steps do **not** run on that path) unless `-p`/`--pause-on-error` intervenes. Full abort-path matrix in `REFERENCE.md`.

A `node:` field on any step/test is a **NodeReference**: a string (one node) or a list of strings (multi-node → one step/test per node, expanded before construction) — except `consistency` tests, which are not expanded and instead run once across the whole list (see Multi-node below).

## Nodes

Each node has a `name`, a `type`, and type-specific `options`. Steps and tests reference a node by `name`.

```yaml
nodes:
  - name: local              # AT MOST ONE per suite
    type: local
    options: { shell: /bin/bash, env: ["FOO=bar"] }

  - name: server
    type: ssh
    options: { host: 10.0.0.5, port: 22, user: ubuntu, key: ~/.ssh/id_rsa }

  - name: web
    type: docker              # privileged by default
    options:
      image: ubuntu:24.04
      exec_opts: { shell: /bin/bash }
      networks: [{ name: test-net, ip: 172.20.0.10 }]

  - name: box
    type: lxd                 # lxd-vm == lxd with instance_type: virtual-machine
    options: { image: ubuntu:24.04, instance_type: container, profiles: [default] }
```

DART auto-detects LXD vs Incus (socket priority: `/var/lib/incus/unix.socket` → `/var/snap/lxd/common/lxd/unix.socket` → `/var/lib/lxd/unix.socket`) and translates image names (`ubuntu:24.04` → `images:ubuntu/24.04` on Incus). Remote LXD auth (trust token or certs), remote Docker (`DOCKER_HOST` env vars), Docker/LXD platform blocks, and the full node option tables are in `REFERENCE.md`.

Every local path a suite writes (file-step sources/dests, `compose_file`, LXD certs, `!!load_from` dirs, ...) resolves the same way: absolute as-is, `~` as the invoking user's home, anything else relative to the directory holding the suite file — so a suite behaves identically run from anywhere.

## Tests

All 11 test types share `{ name, node, type, options: { ... evaluate: {...} } }`. Every type has sane defaults for its `evaluate` block when one isn't given (see table). Full per-type option tables are in `REFERENCE.md`; the shape:

```yaml
tests:
  - name: service responds
    node: box                       # single node, or [a,b,c] to fan out
    type: execute
    options:
      command: "curl -s localhost:8080/health"
      evaluate: { exit_code: 0, contains: "ok" }
```

| Type | Core options | Default `evaluate` if none given |
|---|---|---|
| `execute` | `command`, `timeout`, `extract`, `capture` | (none — evaluate block required to assert anything) |
| `exists` | `path`/`filename` | `exists: true` |
| `file_content` | `filename`/`path` | `readable` (exit 0 of `cat`) |
| `file_hash` | `filename`/`path`; `evaluate.{md5,sha1,sha256}` required | n/a — at least one digest required |
| `http_request` | `url`, `method`, `headers`, `timeout`, `from` | `status_code: 200` |
| `ping` | `target`/`host`, `count` | `packet_loss: 0` |
| `port_check` | `host`, `port`, `from`, `timeout` | `status: open` |
| `service_status` | `service` (needs systemd) | `status: active` |
| `reboot` | `mode` (graceful\|force), `ready_command`, `timeout` — node must support `reboot` capability; **retry is rejected outright** | `rebooted` (exit 0) |
| `tls_cert` | `host`, `port` (443), `server_name`, `timeout`, `from` | `min_days_remaining: 0` |
| `consistency` | `command`, optional `nodes:` subset (≥2 of the test's `node:` list), `timeout` — **not** expanded per node | `all_equal: true` |

`from: node\|host` (default `node`) appears on `http_request`, `port_check`, `tls_cert` tests — it picks the vantage point the check probes from. `node` shells out on the target (answers "can *this* node reach X"); `host` asks the machine running DART instead.

> **Known doc/code wrinkle (2026-08-21, worth re-checking if you rely on it):** `TLSCertTest`'s own Go doc comment says the connection is "made from the host running DART, not from the test's node" — unconditionally. But the code reads a `from` option via the same `parseVantage` helper used by `http_request`/`port_check`, which defaults to `node`. The comment reads as stale, predating the `from:` option being added to `tls_cert` — but this wasn't empirically run to confirm. If a `tls_cert` test's default vantage matters to you, pin `from:` explicitly rather than relying on the default either way.

### Retry, skip, capture/extract (new since the last skill revision)

```yaml
tests:
  - name: cluster elects a leader
    node: [db-1, db-2, db-3]
    type: consistency
    retry: { timeout: 90, interval: 5 }     # rerun until pass or timeout; interval must be < timeout
    options:
      command: cluster-role
      evaluate: { matching: { pattern: "^leader$", count: 1 } }

  - name: only run if feature flag is on
    node: box
    type: execute
    skip_if: "test -f /etc/feature-disabled"     # skip when this command exits 0
    # skip_unless: "..."                          # skip when this command exits non-zero
    options: { command: "true", evaluate: { exit_code: 0 } }

  - name: get the deployed version
    node: box
    type: execute
    options:
      command: "myapp --version"
      capture: version                     # whole trimmed stdout, referenced later as {{capture.version}}
      # capture: { name: { jsonpath: "$.field" } }   # or extract a piece

  - name: use it later
    node: box
    type: execute
    options:
      command: "echo deployed {{capture.version}}"
      evaluate: { contains: "deployed" }

  - name: throughput has not regressed
    node: box
    type: execute
    options:
      command: "loom run --json"
      extract: { throughput: { jsonpath: "$.summary.throughput_mbps" } }
      evaluate: { throughput: { within: 12476, tolerance_pct: 5 } }   # or gte/lte/gt/lt/eq/ne
```

A `skip_if`/`skip_unless` condition command that itself errors is a hard error, not a skip (a broken condition must never silently pass as green). A `{{capture.name}}` reference to a name no earlier (unskipped, unfiltered) test captured is a hard error too. `extract`/`capture` are parsed only by the `execute` test type.

## Steps (setup / teardown)

A step is `{ name, node, step: { type, options } }`. 16 real types (up from the 6 an older version of this skill listed):

```yaml
setup:
  - { name: install deps, node: box, step: { type: apt, options: { packages: [nginx, jq] } } }
  - { name: run a command, node: box, step: { type: execute, options: { command: "mkdir -p /tmp/x", timeout: 30 } } }
  - { name: wait for readiness, node: app, step: { type: wait_for, options: { command: "curl -sf localhost:8080/health", timeout: 60, interval: 2 } } }
  - { name: push a fixture, node: app, step: { type: file_push, options: { source: fixtures/app.conf, dest: /etc/app.conf, create_dir: true } } }
  - { name: render a template, node: app, step: { type: file_template, options: { source: app.conf.tmpl, dest: /etc/app.conf, values: { port: 8080 } } } }
  - { name: snapshot clean state, node: vm, step: { type: snapshot, options: { name: clean } } }   # lxd/lxd-vm only
```

| type | key options | notes |
|---|---|---|
| `execute` | `command` (string or list), `timeout` | **timeout is respected** (bounds each command) — an earlier skill claimed it was ignored; that's no longer true |
| `apt` | `packages` (list) | `sudo -n apt-get update` (if index >24h stale) then `install -y` |
| `simulated` | `time` (required, fractional seconds), `message` | **message is shown as a live progress update while sleeping** — an earlier skill claimed it was ignored; it's read now |
| `file_create` (alias `file_write`) | `path`, `contents`, `overwrite`, `create_dir`, `mode` | |
| `file_delete` | `path`, `ignore_errors` | |
| `file_edit` | `path`, `operation` (insert\|replace\|remove), `match_type` (plain\|regex\|line), `match`, `line_number`, `position`, `content`, `use_captures` | regex replace supports `$1`/`${name}` |
| `file_exists` | `path` | fails the step if missing (contrast with the `exists` **test** type, which asserts either way) |
| `file_read` | `path`, `contains` | |
| `file_push` | `source` (local, resolved from suite dir), `dest`, `mode`, `overwrite`, `create_dir` | source read on the machine running DART |
| `file_fetch` | `source` (on node), `dest` (local), `overwrite`, `create_dir` | pulls a file off the node |
| `file_template` | `source` (local Go-template file), `dest`, `values` (map), `mode`, `overwrite`, `create_dir` | parsed at config time; a null `values` entry or unresolved `{{.field}}` is a hard error, not `<no value>` in the output |
| `http_request` | `url`, `method`, `headers`, `expected_status`, `expected_body`, `timeout`, `from` | step version of the test type — fails the step, no `evaluate:` block |
| `dns_request` | `hostname`, `expected_ips`, `timeout`, `from` | |
| `service_check` | `service` | fails unless `systemctl is-active` says `active` (fixed expectation — contrast with the `service_status` **test**, which lets you assert other states) |
| `reboot` | `mode`, `ready_command`, `timeout` | needs `reboot` capability (ssh/lxd/lxd-vm) |
| `wait_for` | `command`, `timeout` (60), `interval` (2) | polls until exit 0 |
| `snapshot` | `name`, `action` (create\|restore\|delete), `stateful` | needs `snapshot` capability (**lxd/lxd-vm only**, not even ssh); a stateful snapshot must be restored with `stateful: true` too or LXD silently does a disk-only restore |

File-op steps operate through the node's shell (base64-chunked writes, capped per-chunk to stay under the kernel's `MAX_ARG_STRLEN`) for every non-`local` node type, and through the native filesystem for `local` — same option surface either way.

## Node facts (templating)

Unchanged in shape from before: each node can declare `facts: { name: command }`, gathered once before setup/tests run (stdout trimmed → value), referenced anywhere via `{{ fact "<nodeName|self>" "<name>" }}`. A non-zero fact command aborts the suite.

## Multi-node expansion

```yaml
tests:
  - name: airgap enforced
    node: [mgmt, core, gnb]      # → three independent tests, one per node
    type: execute
    options: { command: "! ping -c1 -W3 1.1.1.1 && echo airgap", evaluate: { exit_code: 0, contains: airgap } }
```

`consistency` is the one exception: its `node:` list is **not** expanded into independent tests — it runs the command on every listed node and compares results in a single test (`nodes:` can optionally narrow which subset of the `node:` list to compare).

## Organizing on disk: `!!load_from`

```yaml
suite: Big Suite
nodes:    !!load_from(nodes)
setup:    !!load_from(setup)
tests:    !!load_from(tests)
teardown: !!load_from(teardown)
```

A **preprocessor** directive (before YAML parsing, not a real YAML tag): recursively concatenates every `.yaml`/`.yml` under `<dir>` (relative to the suite file) in lexical filename order, spliced in as the section's list — hence `00_`, `01_`, … prefixes to control order. Fragment files must be top-level YAML lists and must **not** start with a `---` document separator (breaks the splice — the resulting error points at the main file, not the fragment, since `!!load_from` suites stop getting source locations entirely). `grewelltech/core`'s `tests/` (see `~/repos/core/tests/README.md`) is a real, working example of this layout in production use.

## Gotchas (verified against source, 2026-08-21)

1. **All 11 test types and 16 step types are real** — don't trust an older revision of this skill (or, going the other direction, don't trust `examples/test_types/` blindly either — cross-check against `pkg/testtypes/base.go`'s `testFactories` map if in doubt).
2. **`execute` step *does* respect `timeout:`** now. **`simulated` *does* use `message:`** (as a live progress line). Both were "ignored" in an older DART; re-verify before trusting any "X is ignored" claim in old notes.
3. **`reboot` and `snapshot` are hard node-capability gates**, not soft warnings — a suite using either on an unsupported node type fails at construction, before any infrastructure is touched. See the capability matrix above.
4. **`service_status`/`service_check` need systemd** — plain `docker` nodes generally don't have it (no init system, standard images ship no `systemctl`).
5. **Only `execute` tests support `extract:`/`capture:`.** A `{{capture.name}}` reference to a name nothing captured (wrong order, or the capturing test got skipped/tag-filtered out) is a hard error.
6. **`retry:` is rejected on `reboot` tests** — a failing evaluation would otherwise power-cycle the target repeatedly.
7. **`!!load_from` is a recursive, lexically-ordered textual concat** — one stray `.yml` anywhere in the tree gets included; fragment files can't start with `---`.
8. **At most one `local` node per suite** (a second is a construction-time duplicate error).
9. **A malformed/unknown CLI flag exits 0**, not a nonzero error code — don't trust exit code alone to mean "the suite ran"; assert on a produced report file in CI.
10. DART surfaces config errors with file + line + a source snippet (unless `!!load_from` is in play) — read them, they point at the exact offending key.

For exhaustive option tables (every node/step/test type, every evaluator, the full CLI flag reference, report JSON/JUnit schemas, and the source map used to verify this skill), see `REFERENCE.md`.
