# claude-skills

Claude Code [Skills](https://docs.claude.com/en/docs/claude-code/skills) for tools and libraries by [@bgrewell](https://github.com/bgrewell). Each skill teaches a Claude Code instance how to use one tool correctly without rediscovering its API.

## Skills

| Skill | Covers |
|---|---|
| [`stencil`](skills/stencil/) | Building Go CLIs with [`github.com/bgrewell/stencil`](https://github.com/bgrewell/stencil) — command/subcommand trees, typed flags, console UI spinners, build-time version injection, and the `stencil` versioning dev-CLI. |
| [`dart`](skills/dart/) | Authoring & running [DART](https://github.com/bgrewell/dart) test suites — YAML nodes (local/ssh/docker/lxd), setup/teardown steps, `execute` tests with `exit_code`/`match`/`contains` assertions, node-facts templating, multi-node expansion, and `!!load_from` layout. |

## Installing

Use the `install.sh` script. By default it **symlinks every skill** into your
personal skills directory (`~/.claude/skills/`), so edits in this repo take
effect immediately:

```bash
./install.sh                 # symlink all skills into ~/.claude/skills
./install.sh stencil         # just one skill
./install.sh --copy          # standalone copy instead of symlinks
./install.sh --list          # list available skills
./install.sh --uninstall     # remove this repo's skills from the target
```

Install into a project instead of your profile with `--target`:

```bash
./install.sh --target /path/to/project/.claude/skills dart
```

Other options: `--force` (overwrite existing), `--dry-run` (preview actions),
`--help` (full usage). Restart Claude Code or start a new session to pick up
changes.

### Manual install

Each `skills/<name>/` directory is self-contained, so you can also symlink or
copy one by hand:

```bash
ln -s "$PWD/skills/stencil" ~/.claude/skills/stencil
```

A skill activates automatically when its `description` matches what you're doing. The layout is also plugin-ready — the whole `skills/` directory can later be wrapped as a Claude Code plugin without moving anything.
