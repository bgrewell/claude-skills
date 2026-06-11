---
name: dart
description: >-
  Author and run DART (Dynamic Assessment & Regression Toolkit) test suites —
  a YAML-driven distributed-systems test runner by bgrewell. Write a suite of
  nodes (local/ssh/docker/docker-compose/lxd) plus setup steps, execute tests
  with exit_code/match/contains assertions, and teardown, then run the `dart`
  CLI. Use when creating or editing DART YAML test files (top-level `suite:`,
  `nodes:`, `setup:`, `tests:`, `teardown:`, with `evaluate:` blocks), when
  working in a project's `tests/` directory of such YAML (e.g. aether-ops,
  aether-ops-bootstrap, pronto-project), or when running/debugging the `dart`
  command. Covers node options, the real step/test/assertion set, node facts
  templating, multi-node expansion, and `!!load_from` directory layout.
---

# DART

DART is a **YAML-driven test runner** for distributed-systems / integration testing. You describe a suite — target **nodes**, **setup** steps, **tests** with pass/fail assertions, and **teardown** — in a YAML file and run the `dart` CLI. DART provisions the nodes (containers/VMs/SSH), runs everything in order, prints color-coded results, and exits non-zero if any test fails (so it drops into CI).

You **author YAML and run a binary** — you do not import a Go library. (DART is written in Go, but consumers never `import` it.)

> ⚠️ **Read the "What actually works" box below before writing.** DART's README, Writerside docs, and `examples/test_types/` advertise many node/step/test types and assertions that are **not implemented** and will error at runtime. This skill documents only what the current code actually runs. `REFERENCE.md` has the exhaustive tables and the full not-implemented list.

## What actually works (current code)

| Category | Implemented (use these) | NOT implemented (will error / be ignored) |
|---|---|---|
| **Test types** | `execute` only | `ping`, `http_request`, `port_check`, `file_content`, `exists`, `service_status`, `file_hash`, `resource` → all return *"Test type not implemented"*. `examples/test_types/*.yaml` for these are aspirational — don't copy them. |
| **Assertions** (`evaluate:`) | `exit_code`, `match`, `contains` | `regex`, `not_contains`, `status_code`, `packet_loss`, `rtt_*`, etc. — none exist |
| **Step types** (setup/teardown) | `execute`, `apt`, `simulated`, `file_create`, `file_delete`, `file_edit` | `http_request`, `dns_request`, `service_check`, `file_read`, `file_exists` steps → *"unknown step type"* |
| **Node types** | `local`, `ssh`, `docker`, `docker-compose`, `lxd`, `lxd-vm` | — |

Other footguns: `execute` step ignores a `timeout:` option (wrap the command itself, e.g. `timeout 120 ...`); `simulated` only reads `time` (`message:` is ignored); sudo `vault_secret:` is parsed but a no-op; **only one `local` node is allowed per suite**.

## Install & run

```bash
# Install a release
curl -sSL https://raw.githubusercontent.com/bgrewell/dart/main/install.sh | bash   # -> /usr/local/bin/dart
# or build from source
git clone https://github.com/bgrewell/dart.git && cd dart && make build            # -> bin/dart
```

If a source build fails with *"requires go >= 1.26.x"* (a bleeding-edge LXD dependency outruns the local toolchain), build with `GOTOOLCHAIN=auto go build -o bin/dart ./cmd/dart`.

```bash
dart -c suite.yaml              # run a suite
dart -c suite.yaml -v           # verbose
dart -c suite.yaml -d           # stream command output live (debug)
dart -c suite.yaml -s           # stop on first test failure
dart -c suite.yaml --setup-only # run only setup (leave env up for inspection)
dart -c suite.yaml --teardown-only
dart -c suite.yaml -i 5         # run the whole suite 5 times
```

Exit code is **0** only if every test passed; non-zero otherwise. Full flag table in `REFERENCE.md`.

## Suite file structure

```yaml
suite: My Suite          # required: name
docker: { ... }          # optional: Docker platform setup (networks, images) — see REFERENCE
lxd:    { ... }          # optional: LXD/Incus platform setup (socket, project, networks, profiles)
nodes:  [ ... ]          # required: where tests run
setup:    [ ... ]        # optional: steps run before tests (sequential)
tests:    [ ... ]        # required: the actual tests
teardown: [ ... ]        # optional: steps run after tests (always, even on failure)
```

**Execution order:** platform setup → node setup (create containers/VMs/SSH) → **gather facts** → `setup` steps in order → `tests` in order → `teardown` steps in order → node teardown → platform teardown. A failing **setup** step aborts the suite (teardown still runs); test failures are recorded and, unless `-s`, the suite continues.

## Nodes

Each node has a `name`, a `type`, and type-specific `options`. Steps and tests reference a node by `name`.

```yaml
nodes:
  # Local machine (AT MOST ONE per suite)
  - name: local
    type: local
    options:
      shell: /bin/bash
      env: ["FOO=bar"]            # optional
      sudo: { env_var: SUDO_PASS } # optional: password OR env_var (env_var preferred)

  # Remote over SSH
  - name: server
    type: ssh
    options:
      host: 10.0.0.5
      port: 22                    # default 22
      user: ubuntu
      key: ~/.ssh/id_rsa          # key and/or pass

  # Docker container (privileged by default)
  - name: web
    type: docker
    options:
      image: ubuntu:24.04
      exec_opts: { shell: /bin/bash }
      networks:
        - { name: test-net, ip: 172.20.0.10 }

  # LXD/Incus container or VM (lxd-vm == lxd with instance_type: virtual-machine)
  - name: box
    type: lxd
    options:
      image: ubuntu:24.04         # auto-translated to images:ubuntu/24.04 on Incus
      instance_type: container    # or virtual-machine
      profiles: [default]
```

Multiple `docker`/`lxd`/`ssh` nodes are fine; remote LXD (trust token or certs), Docker/LXD platform blocks, networks, and projects are all in `REFERENCE.md`. DART auto-detects LXD vs Incus and translates image names.

## Steps (setup / teardown)

A step is `{ name, node, step: { type, options } }`. Steps succeed if they complete without error (no assertions). The six real types:

```yaml
setup:
  - name: install deps                 # apt: install packages (auto apt-get update if stale)
    node: box
    step:
      type: apt
      options: { packages: [nginx, jq] }

  - name: run commands                 # execute: a command string, or a list run in order
    node: box
    step:
      type: execute
      options:
        command: |
          mkdir -p /tmp/data
          echo ready > /tmp/data/state

  - name: wait a bit                   # simulated: sleep N seconds (only `time` is read)
    node: box
    step:
      type: simulated
      options: { time: 5 }

  - name: write a file                 # file_create / file_edit / file_delete
    node: local
    step:
      type: file_create
      options:
        path: /tmp/app.conf
        contents: "version=1.0.0\n"
        create_dir: true               # mkdir -p parent
        overwrite: true                # else error if exists
        # mode: 0644
```

`file_edit` does `insert`/`replace`/`remove` with `match_type: plain|regex|line` (and `use_captures` for regex `$1`/`$2`); `file_delete` takes `path` + `ignore_errors`. Full option tables in `REFERENCE.md`.

## Tests

Only the `execute` test type exists: run a command on a node, assert on its result.

```yaml
tests:
  - name: service responds
    node: box                    # single node, or [a, b, c] to fan out (see Multi-node)
    type: execute
    options:
      command: "curl -s localhost:8080/health"
      evaluate:
        exit_code: 0             # exact exit code
        contains: "ok"          # substring of stdout
        # match: "ok"           # EXACT stdout (trailing whitespace trimmed) — not a substring
    setup: ["systemctl start app"]    # optional per-test commands (plain strings) before
    teardown: ["systemctl stop app"]  # optional per-test commands after
```

`evaluate` keys are **only** `exit_code`, `match`, `contains`. Specify several and **all** must pass. Use `contains` for substrings; `match` is a full-string comparison (it just trims trailing whitespace). On failure DART prints the assertion, `Expected:`, and `Actual:`.

## Node facts (templating)

Each node can declare **facts** — commands whose trimmed stdout becomes a named value gathered before steps/tests run. Reference them in any option string or command via Go-template syntax `{{ fact "<node>" "<name>" }}`, where `<node>` is a node name or `"self"`.

```yaml
nodes:
  - name: a
    type: local
    options: { shell: /bin/bash }
    facts:
      me:   "whoami"
      host: "hostname"
tests:
  - name: uses facts
    node: a
    type: execute
    options:
      command: 'echo "ran as {{ fact "self" "me" }} on {{ fact "a" "host" }}"'
      evaluate: { contains: "ran as" }
```

A fact command that exits non-zero aborts the suite. Facts work in step options, test options, and per-test setup/teardown command strings.

## Multi-node expansion

Give a step or test a **list** of nodes and DART expands it into one independent step/test per node:

```yaml
tests:
  - name: airgap enforced
    node: [mgmt, core, gnb]      # → three numbered tests
    type: execute
    options:
      command: "! ping -c1 -W3 1.1.1.1 && echo airgap"
      evaluate: { exit_code: 0, contains: airgap }
```

## Organizing on disk: `!!load_from`

A suite can be one file, or split a section across a directory with the `!!load_from(<dir>)` directive. It **recursively** reads every `.yaml`/`.yml` under `<dir>` (relative to the config file), in **lexical filename order**, and splices them in — which is why list fragments are named `00_`, `01_`, … to control order:

```yaml
# suite/main.yaml
suite: Big Suite
nodes:    !!load_from(nodes)
setup:    !!load_from(setup)
tests:    !!load_from(tests)
teardown: !!load_from(teardown)
```

```
suite/
├── main.yaml
├── nodes/    nodes.yaml
├── setup/    00_build.yaml  01_configure.yaml
├── tests/    01_smoke.yaml  02_api.yaml
└── teardown/ 01_cleanup.yaml
```

Each fragment file is a YAML **list** (`- name: ...`) matching the section it feeds. YAML anchors/aliases (e.g. a shared `&cloud-init` block reused across LXD profiles) are commonly used in large suites.

## Gotchas (verified)

1. **Only `execute` tests and 6 step types exist** — see the table at top. Anything else errors; don't trust `examples/test_types/` or the docs' fuller lists.
2. **Assertions are only `exit_code`/`match`/`contains`.** No regex/negation. `match` is exact (trailing-trimmed), `contains` is substring.
3. **`execute` step ignores `timeout:`** — put `timeout N ...` inside the command. **`simulated` ignores `message:`** — only `time` (integer seconds) is read.
4. **At most one `local` node** per suite (a second errors as a duplicate).
5. **`load_from` is a recursive, lexically-ordered textual concat** — name fragments `00_`,`01_` for order; one stray `.yml` in the tree gets included.
6. Sudo via `password:` or `env_var:` works; **`vault_secret:` is a no-op.**
7. Source build may need `GOTOOLCHAIN=auto` (bleeding-edge LXD dep).
8. DART surfaces config errors with file + line + a source snippet — read them; they point at the offending node/step.

For exhaustive node/step option tables, the Docker/LXD platform blocks, remote-LXD auth, the complete CLI flag list, on-disk conventions, and real consumer examples, see `REFERENCE.md`.
