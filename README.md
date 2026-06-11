# claude-skills

Claude Code [Skills](https://docs.claude.com/en/docs/claude-code/skills) for tools and libraries by [@bgrewell](https://github.com/bgrewell). Each skill teaches a Claude Code instance how to use one tool correctly without rediscovering its API.

## Skills

| Skill | Covers |
|---|---|
| [`stencil`](skills/stencil/) | Building Go CLIs with [`github.com/bgrewell/stencil`](https://github.com/bgrewell/stencil) — command/subcommand trees, typed flags, console UI spinners, build-time version injection, and the `stencil` versioning dev-CLI. |
| [`dart`](skills/dart/) | Authoring & running [DART](https://github.com/bgrewell/dart) test suites — YAML nodes (local/ssh/docker/lxd), setup/teardown steps, `execute` tests with `exit_code`/`match`/`contains` assertions, node-facts templating, multi-node expansion, and `!!load_from` layout. |
| [`usage`](skills/usage/) | Go CLI flag parsing & grouped help output with [`github.com/bgrewell/usage`](https://github.com/bgrewell/usage) — typed options, option groups, positional args, app/version metadata, and colored auto-generated usage text (a thin wrapper over stdlib `flag`). |

## Installing a skill

Each `skills/<name>/` directory is self-contained. Use any one of:

- **Personal (all projects):** copy or symlink it into `~/.claude/skills/`
  ```bash
  ln -s "$PWD/skills/stencil" ~/.claude/skills/stencil
  ```
- **Project-local:** copy or symlink it into a project's `.claude/skills/`
  ```bash
  ln -s "$PWD/skills/stencil" /path/to/project/.claude/skills/stencil
  ```

A skill activates automatically when its `description` matches what you're doing. The layout is also plugin-ready — the whole `skills/` directory can later be wrapped as a Claude Code plugin without moving anything.
