# DART — reference

Exhaustive companion to `SKILL.md`. Schema is verified against source (`internal/config/`, `pkg/nodetypes/`, `pkg/steptypes/`, `pkg/testtypes/`, `internal/eval/`, `internal/facts/`) and by running the `dart` binary. DART is pre-1.0; expect churn.

## CLI

| Short | Long | Default | Meaning |
|---|---|---|---|
| `-c` | `--config` | `config.yaml` | Path to the suite YAML |
| `-v` | `--verbose` | false | Verbose logging |
| `-d` | `--debug` | false | Stream command stdout/stderr live while running |
| `-p` | `--pause-on-error` | false | Pause for inspection on error |
| `-s` | `--stop-on-error` | false | Stop the suite on the first test failure |
| `-setup` | `--setup-only` | false | Run only setup steps (leave environment up) |
| `-teardown` | `--teardown-only` | false | Run only teardown steps |
| `-i` | `--iterations` | 1 | Run the entire suite N times |

**Exit code:** `0` iff all tests passed; non-zero on any test failure or error. Output phases: `[+] Running test setup`, `[+] Gathering node facts`, `[+] Running tests`, `[+] Running test teardown`, `[+] Results` (Pass/Fail counts). Failed tests print the assertion with `Expected:` / `Actual:`.

## Top-level schema (`internal/config/config.go`)

| Key | Type | Required | Meaning |
|---|---|---|---|
| `suite` | string | yes | Suite name |
| `docker` | object | no | Docker platform setup (`networks`, `images`) |
| `lxd` | object | no | LXD/Incus platform setup (`socket`, `project`, `networks`, `profiles`, `images`) |
| `nodes` | list | yes | Node definitions |
| `setup` | list | no | Setup steps |
| `tests` | list | yes | Tests |
| `teardown` | list | no | Teardown steps |

A `node:` field on any step/test is a **NodeReference**: either a string (one node) or a list of strings (multi-node → expanded to one step/test each).

## Node types (`pkg/nodetypes/`)

Recognized `type:` values: `local`, `ssh`, `docker`, `docker-compose`, `lxd`, `lxd-vm`. (`mock` exists for internal tests only.) Unknown → config error. **`lxd-vm`** is sugar for `lxd` with `instance_type: virtual-machine`.

### local
At most **one** per suite (a second is a duplicate error, `base.go:40`).

| `options.` | type | default | meaning |
|---|---|---|---|
| `shell` | string | system | shell for commands |
| `env` | []string | – | `VAR=value` entries |
| `sudo.password` | string | – | sudo password (avoid; prefer env_var) |
| `sudo.env_var` | string | – | name of env var holding the sudo password |
| `sudo.vault_secret` | string | – | **parsed but unused (no-op)** |

### ssh
| `options.` | type | default | meaning |
|---|---|---|---|
| `host` | string | – (req) | hostname/IP |
| `port` | int | 22 | SSH port |
| `user` | string | – (req) | username |
| `pass` | string | – | password auth |
| `key` | string | – | path to private key |

Host key checking is disabled (insecure-ignore).

### docker
Created **privileged** by default.

| `options.` | type | meaning |
|---|---|---|
| `image` | string (req) | image:tag (can be one built in `docker.images`) |
| `exec_opts` | object | `{ shell, env, sudo }` used for command execution |
| `networks` | list | `{ name, subnet?, ip? }` per attached network |

Remote Docker uses standard env vars (no YAML): `DOCKER_HOST` (`tcp://…`, `ssh://user@host`), `DOCKER_TLS_VERIFY=1`, `DOCKER_CERT_PATH`.

### docker-compose
| `options.` | type | meaning |
|---|---|---|
| `compose_file` | string (req) | path to compose file |
| `service` | string (req) | service to target for execution |
| `project_name` | string | compose project (defaults to node name) |
| `exec_opts` | object | `{ shell, env, sudo }` |

Multiple nodes sharing the same `compose_file`+`project_name` share one stack.

### lxd / lxd-vm
| `options.` | type | default | meaning |
|---|---|---|---|
| `image` | string (req) | – | `ubuntu:24.04` or `remote:alias`; auto-translated for Incus |
| `instance_type` | string | `container` | `container` or `virtual-machine` (`lxd-vm` forces the latter) |
| `profiles` | []string | – | LXD profiles to apply |
| `project` | string | `default` | LXD project (or the one from `lxd.project`) |
| `exec_opts` | object | – | `{ shell, env, sudo }` |
| `networks` | list | – | `{ name, subnet?, ip? }` (IPv4/IPv6 auto-detected) |
| `server` | string | `local` | image server name |
| `protocol` | string | `lxd` | `lxd` or `simplestreams` |
| `socket` | string | auto | local Unix socket path (Incus/LXD auto-detected if unset) |
| `remote_addr` | string | – | `https://host:8443` for a remote server |
| `trust_token` | string | – | one-time token from `lxc config trust add` (preferred remote auth) |
| `client_cert` / `client_key` | string | – | cert-based remote auth |
| `server_cert` | string | – | custom CA for the remote |
| `skip_verify` | bool | false | skip TLS verify (discouraged) |

**Incus/LXD auto-detect** socket priority: `/var/lib/incus/unix.socket` → `/var/snap/lxd/common/lxd/unix.socket` → `/var/lib/lxd/unix.socket`. On Incus, `ubuntu:24.04` → `images:ubuntu/24.04`; `images:debian/12` is left as-is.

### Node facts (any node type)
`facts: { <name>: <command> }` — each command runs on the node, stdout trimmed → fact value. Reference with `{{ fact "<nodeName|self>" "<name>" }}` in any option string / command (recursively through maps and lists). A non-zero fact command aborts the suite. (`internal/facts/facts.go`)

## Platform blocks

### `docker:`
```yaml
docker:
  networks:
    - { name: test-net, subnet: 172.20.0.0/16, gateway: 172.20.0.1 }
  images:
    - { name: myimg, tag: latest, dockerfile: dockerfiles/app.dockerfile }  # built before the suite
```

### `lxd:`
```yaml
lxd:
  socket: /var/lib/incus/unix.socket        # optional explicit socket
  project:
    name: dart-proj
    description: ...
    config: { features.images: "true" }     # default profile is auto-copied; project deleted on teardown
  networks:
    - { name: test-net, type: bridge, subnet: 10.100.0.0/24, gateway: 10.100.0.1 }
  profiles:
    - name: p
      description: ...
      config: { limits.cpu: "2", limits.memory: "2GB", user.user-data: "#cloud-config\n..." }
      devices: { root: { type: disk, path: /, pool: default, opts: { size: 50GB } } }
  images: [ ... ]
```

## Step types (`pkg/steptypes/base.go` — `CreateSteps`)

Step shape: `{ name, node, step: { type, options } }`. Real types: `execute`, `apt`, `simulated`, `file_create`, `file_delete`, `file_edit`. Anything else → *"unknown step type"*.

| type | option | type | notes |
|---|---|---|---|
| `execute` | `command` | string \| []string | a list runs sequentially. **No `timeout` option** — bake it into the command. |
| `apt` | `packages` | []string | runs `sudo -n`; auto `apt-get update` if cache > 24h old |
| `simulated` | `time` | int | sleep seconds. **Only `time` is read** (`message:` ignored) |
| `file_create` | `path` | string (req) | target path |
| | `contents` | string | file body |
| | `overwrite` | bool (false) | else error if file exists |
| | `create_dir` | bool (false) | mkdir -p parent |
| | `mode` | int (0644) | octal permissions |
| `file_delete` | `path` | string (req) | |
| | `ignore_errors` | bool (false) | don't fail if missing |
| `file_edit` | `path` | string (req) | |
| | `operation` | string (req) | `insert` \| `replace` \| `remove` |
| | `match_type` | string (`plain`) | `plain` \| `regex` \| `line` |
| | `match` | string | text/regex (for plain/regex) |
| | `line_number` | int | 1-based (for `match_type: line`) |
| | `position` | string (`after`) | `before` \| `after` (for insert) |
| | `content` | string | inserted/replacement text |
| | `use_captures` | bool (false) | regex replace with `$1`,`$2`,`${name}` |

## Test type + assertions

Only `execute` (`pkg/testtypes/base.go`). Shape:

```yaml
- name: <string>
  node: <name | [names]>
  type: execute
  options:
    command: <string>
    evaluate: { exit_code: <int>, match: <string>, contains: <string> }
  setup:    [<command>, ...]   # optional per-test pre-commands (plain strings)
  teardown: [<command>, ...]   # optional per-test post-commands
```

`evaluate` keys (`internal/eval/`), all optional, **all specified must pass**:
- `exit_code` (int; accepts int/float) — exact process exit code.
- `match` (string) — stdout compared exactly after trimming trailing `\n\r `/spaces.
- `contains` (string) — substring of stdout.

**Not implemented** test types (error *"Test type not implemented"*): `exists`, `file_content`, `file_hash`, `http_request`, `ping`, `port_check`, `resource`, `service_status`. The matching `examples/test_types/*.yaml` files are aspirational.

## `!!load_from` (config.go `processLoadFromDirectives`)

`<key>: !!load_from(<dir>)` is a **preprocessor** that, before YAML parsing, replaces the line with the contents of every `.yaml`/`.yml` file found by a recursive `filepath.Walk` of `<configdir>/<dir>`, concatenated in lexical path order and indented two spaces under `<key>`. Therefore:
- Each fragment file must be a YAML **list** matching the target section (`nodes`/`setup`/`tests`/`teardown`).
- Order = filename order → prefix fragments `00_`, `01_`, … to sequence them.
- It is a recursive directory walk — every `.yml`/`.yaml` beneath the dir is pulled in.

Conventional layout: a `main.yaml` with `!!load_from(nodes|setup|tests|teardown)` and sibling dirs of numbered fragment files.

## Real consumer patterns

Verified, idiomatic usage seen in real suites:

- **aether-ops / aether-ops-bootstrap multi-node** — `lxd-vm` nodes with per-node `profiles`, profile `config.user.user-data` cloud-init (often a shared YAML `&cloud-init` anchor reused with `*cloud-init`), `!!load_from` directory layout, cloud-init wait loops (`for i in $(seq 1 300); do [ -f /tmp/cloud-init.complete ] && exit 0; sleep 1; done; exit 1`), API checks via `curl -sf ... | jq -e ...`, and airgap checks fanned out with `node: [a,b,c]` + `contains`.
- **dart/examples** — `basic` (local + simulated + execute), `docker/`, `ssh/`, `lxd/` (+ `lxd-remote`, `lxd-project`, `lxd-vm`), `incus/`, `multi-node/`, `file-operations/`, `sudo/`. Use these for working node/step syntax. **Avoid `examples/test_types/`** (advertises unimplemented test types).

## Source map (for verifying/extending)

- `internal/config/config.go` — schema structs, `NodeReference`, `!!load_from`, multi-node expansion, contextual errors.
- `pkg/nodetypes/` — node implementations + `CreateNodesWithWrappers` (type dispatch, "one local node" rule).
- `pkg/steptypes/` — step implementations + `CreateSteps` (the 6 wired step types).
- `pkg/testtypes/` — `CreateTests` (only `execute` wired) + `execute.go` (evaluate parsing).
- `internal/eval/` — `exit_code`/`match`/`contains` evaluators.
- `internal/facts/facts.go` — fact gathering + `{{ fact ... }}` templating.
- `cmd/dart/main.go` — CLI flags (uses `go.uber.org/fx` for wiring).
