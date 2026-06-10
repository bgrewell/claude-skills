---
name: stencil
description: >-
  Build Go command-line apps with the github.com/bgrewell/stencil library —
  command/subcommand trees, typed flags (string/bool/int/duration/slices) with
  enum/required/env support, positional-arg specs, run hooks, built-in
  --help/--version, and a console UI of leveled messages plus dotted-leader
  spinner tasks. Use whenever writing or modifying a Go CLI that imports
  github.com/bgrewell/stencil or github.com/bgrewell/stencil/pkg/ui (e.g.
  sshwiz, testbox, smart-gateway), or when asked to add commands, flags, or
  spinner output to such an app.
---

# Stencil

Stencil is a small Go library for building command-line apps. It has two parts you import:

- **`github.com/bgrewell/stencil`** — the command framework: an `App` wrapping a tree of `Command`s, typed flags, positional args, run hooks, and built-in `--help`/`--version`.
- **`github.com/bgrewell/stencil/pkg/ui`** — a console UI: leveled messages (`Info`/`Warn`/`Error`) and dotted-leader **spinner tasks**. Reachable as `app.UI`, or importable standalone.

There is also a separate `stencil` **developer CLI** (built from `./cmd`) that manages a project's semantic version and a git pre-commit hook. It is *not* imported — it's a tool the app developer runs. See `REFERENCE.md`.

> **Read `REFERENCE.md`** for the exhaustive API (every option, flag type, `Context`/`ResolvedFlags` accessor, parser rule, exit code) and the dev-CLI versioning workflow. This file is enough to write a correct app.

## Install

```bash
go get github.com/bgrewell/stencil@latest
```

Module path `github.com/bgrewell/stencil` (UI subpackage `.../pkg/ui`); requires Go ≥ 1.22. The repo currently has **no version tags**, so `@latest` resolves to `main` (the correct, current API). Pin a commit (`@<sha>`) only if you need reproducibility.

> ⚠️ **The repo README is stale.** It still describes an old "golang-repo-template" and an old ldflags target (`-X github.com/bgrewell/stencil.appVersion=…`). That package var no longer exists. Follow this skill, not the README. Version now flows through `VersionInfo` (see below).

## Anatomy of a stencil app

Build a root `Command`, hang subcommands off `root.Sub`, wrap it in an `App`, and `Execute`. This is the canonical shape (from `testbox`/`sshwiz`):

```go
package main

import (
	"os"

	"github.com/bgrewell/stencil"
)

// Populated at build time via -ldflags (see "Version info" below).
var (
	appVersion    = "dev"
	appBuildDate  = ""
	appCommitHash = ""
	appBranch     = ""
)

func main() {
	root := &stencil.Command{
		Name:            "myapp",
		Summary:         "Short one-liner shown in help.",
		PersistentFlags: stencil.NewFlagSet(), // inherited by ALL descendants
		Flags:           stencil.NewFlagSet(), // local to root only
	}
	// Global flag available to every subcommand:
	root.PersistentFlags.String("log-level", "l", "Log level", "info").Enum = []string{"info", "debug", "trace"}
	root.PersistentFlags.Bool("quiet", "q", "Quiet output", false)

	build := &stencil.Command{
		Name:    "build",
		Summary: "Build the thing.",
		Flags:   stencil.NewFlagSet(),
		Run: func(ctx *stencil.Context) error {
			// read flags + globals here
			force := ctx.Flags.Bool("force")
			level := ctx.Flags.String("log-level") // inherited persistent flag
			_ = force
			_ = level
			return nil // return an error to exit non-zero (code 1)
		},
	}
	build.Flags.Bool("force", "f", "Overwrite existing output", false)

	root.Sub = []*stencil.Command{build}

	app := stencil.NewApp(
		stencil.WithName("myapp"),
		stencil.WithDescription("What myapp does."),
		stencil.WithVersionInfo(stencil.VersionInfo{
			Version: appVersion, BuildDate: appBuildDate,
			CommitHash: appCommitHash, Branch: appBranch,
		}),
		stencil.WithRootCommand(root),
	)

	os.Exit(app.Execute(os.Args[1:])) // Execute returns an exit code int
}
```

Run it: `myapp build --force`, `myapp --quiet build`, `myapp build -f`, `myapp --help`, `myapp build -h`, `myapp --version`.

## Commands & subcommands

A `Command` is a struct (you set fields directly; there's no constructor). Nest with `Sub`:

```go
service := &stencil.Command{Name: "service", Summary: "Manage the daemon."}
service.Sub = []*stencil.Command{
	{Name: "start", Run: func(ctx *stencil.Context) error { /* ... */ return nil }},
	{Name: "stop",  Run: func(ctx *stencil.Context) error { /* ... */ return nil }},
}
```

Useful `Command` fields: `Name`, `Summary`, `Long`, `Aliases []string`, `Hidden bool`, `Deprecated string`, `Run`, the hooks (below), `PersistentFlags`, `Flags`, `Args` (positionals), `Sub`. Full table in `REFERENCE.md`.

- **A command with `Sub` but no `Run` prints help and exits with code 2 (usage).** That's the right pattern for grouping commands like `service`.
- **Persistent vs local flags:** `PersistentFlags` are inherited by the command and all its descendants; `Flags` are local to that one command. Put global flags (log level, config path) on the **root's** `PersistentFlags`.

## Flags

Flags live on a `*FlagSet`. **You must create it with `stencil.NewFlagSet()` before adding flags** — a hand-built `Command` has nil flag sets otherwise, and you can't add to nil. (`NewApp` only auto-creates the *default* root when you don't pass `WithRootCommand`.)

Each adder takes `(name, short, usage, default)` and **returns the `*Flag`** so you can configure it:

```go
fs := stencil.NewFlagSet()
fs.String("source", "s", "Index URL", "")             // --source / -s
fs.Bool("write", "w", "Write to disk", false)          // --write  / -w
fs.Int("limit", "", "Max items", 50)                   // --limit  (no short)
fs.Duration("interval", "i", "Update interval", 4*time.Hour)
fs.StringSlice("tags", "t", "Comma-separated tags", nil)
fs.IntSlice("ports", "p", "Comma-separated ports", nil)

// Configure via the returned *Flag:
fs.String("log-level", "l", "Log level", "info").Enum = []string{"info", "debug", "trace"}
fs.String("to", "t", "Snapshot ID", "").Required = true            // leaf-local only (see gotchas)
fs.String("token", "", "API token", "").Env = "MYAPP_TOKEN"        // env fallback
```

Short `""` means "no short flag." **`add` panics** on a duplicate long name, a duplicate short, or an empty long name — these are programmer errors caught at startup.

`*Flag` config fields: `.Enum []string` (allowed string values), `.Required bool`, `.Env string` (env-var fallback), `.Validate func(any) error` (custom per-flag validation), `.Hidden bool` (omit from help).

### Reading values in `Run`

Inside `Run`, read everything off `ctx`:

```go
Run: func(ctx *stencil.Context) error {
	src   := ctx.Flags.String("source")
	write := ctx.Flags.Bool("write")
	n     := ctx.Flags.Int("limit")
	d     := ctx.Flags.Duration("interval")
	tags  := ctx.Flags.StringSlice("tags")
	pos   := ctx.Args            // []string of positional args
	ui    := ctx.App.UI          // the console UI
	_ = src; _ = write; _ = n; _ = d; _ = tags; _ = pos; _ = ui
	return nil
}
```

Accessor per type: `.Bool/.String/.Int/.Duration/.StringSlice/.IntSlice(name)`, plus `.Get(name) (any, bool)`. **Unknown names return the zero value silently** (no error) — so a typo'd flag name reads as `""`/`0`/`false`. Persistent flags from ancestors are readable here too.

## Positional arguments

Constrain positionals with `Args` (`ArgSpec`):

```go
install := &stencil.Command{
	Name: "install",
	Args: stencil.ArgSpec{Min: 1, Max: 1, Names: []string{"target"}},
	Run: func(ctx *stencil.Context) error {
		target := ctx.Args[0]
		_ = target
		return nil
	},
}
```

`Min`/`Max` (`Max: 0` = unlimited), `Names` (labels for help text), optional `Validate func([]string) error`. Out-of-range counts produce a usage error (exit 2) before `Run`.

## Run hooks & lifecycle

Hooks run around `Run`, all with the same `func(ctx *Context) error` signature. Order:

1. `PersistentPreRun` — every command on the path, **root → leaf**
2. `PreRun` — leaf only
3. `Run` — leaf only
4. `PostRun` — leaf only
5. `PersistentPostRun` — every command on the path, **leaf → root**

Any hook returning an error prints `err.Error()` to stderr and stops with exit code **1** (runtime). Use `PersistentPreRun` on the root for cross-cutting setup (logging, config load) that every subcommand needs.

## Console UI: messages & spinners

Get the UI from `app.UI` (type `ui.UI`). It renders dotted-leader lines that settle to a stop word (`done`/`stopped`/`warn`/`error`):

```go
ui := app.UI

ui.Info("Starting %s", app.Name)      // …………… (settles immediately)
ui.Warn("disk almost full")           // …………… warn   (yellow)
ui.Error("could not reach host: %v", err) // …… error  (red)

sp, err := ui.Task("Downloading assets")  // start a spinner
if err != nil { /* rare */ }
for got := 0; got <= 100; got++ {
	sp.Update("Downloading | %d%%", got)  // change the line (format + args)
}
sp.Complete()                              // … done   (green)  ✅ success
// sp.Stop()  → … stopped   (neutral / cancelled)
// sp.Fail()  → … error     (red / failed)
// sp.Raw()   → underlying *yacspin.Spinner for advanced control
```

Real output looks like:

```
Starting myapp........................................................ done
Downloading | Progress 100.0%......................................... done
This is a warning message............................................. warn
```

`Info`/`Warn`/`Error` and `Task` all take `(format string, args ...any)` like `fmt.Printf`. **Always finish a `Task` with exactly one of `Complete()` / `Stop()` / `Fail()`** so the line settles.

**Pass the UI into your packages** so library code can report progress — `smart-gateway` does this by accepting a `ui.UI`:

```go
import sui "github.com/bgrewell/stencil/pkg/ui"
func NewDownloader(url string, ui sui.UI) *Downloader { /* store ui, call ui.Task/Info */ }
```

Standalone (no `App`): `ui := ui.NewConsoleUI(os.Stdout, ui.WithSpinnerStyle(14))`.

## Version info & build-time injection

`VersionInfo{Version, BuildDate, CommitHash, Branch}` populates `myapp --version` and the help header. The **app owns the ldflags vars** (in its own `main` package — *not* in the stencil package) and passes them through:

```makefile
LDFLAGS := -X 'main.appVersion=$(VERSION)' \
           -X 'main.appBuildDate=$(BUILD_DATE)' \
           -X 'main.appCommitHash=$(COMMIT_HASH)' \
           -X 'main.appBranch=$(BRANCH)'
build:
	go build -ldflags="$(LDFLAGS)" -o myapp ./cmd/cli
```

Then `WithVersionInfo(stencil.VersionInfo{Version: appVersion, ...})` as in the skeleton above. The `stencil` dev CLI can generate `$(VERSION)` from `.stencil/` files and auto-bump it on commit — see `REFERENCE.md`.

## Built-in behavior (free, no wiring)

- `--version` / `-V` → prints version block, exit 0.
- `-h` / `--help` (anywhere on the line) → prints contextual help for the resolved command, exit 0.
- `app help [cmd ...]` → help for that command path.
- Bool flags: `--flag` = true, `--no-flag` = false, `--flag=false` also works. Short bools bundle: `-abc`.
- `--` ends flag parsing; everything after is positional.
- **Color** is auto: on only when stdout is a TTY and `NO_COLOR` is unset. `WithColorMode(stencil.ColorOn|ColorOff|ColorAuto)` overrides; `NO_COLOR` always wins. Piped/CI output is automatically plain.

## Gotchas (read before writing code)

1. **Ignore the repo README** — stale template + dead ldflags target. Version goes through `VersionInfo`, ldflags target your own `main.*` vars.
2. **Initialize flag sets**: `PersistentFlags`/`Flags` on a hand-built `Command` must be set to `stencil.NewFlagSet()` before adding flags, or you'll add to nil.
3. **`Required` is enforced for the LEAF command's local `Flags` only** — not for persistent flags and not for parent commands.
4. **A `Command` with `Sub` but no `Run` prints help and exits 2.** Give group commands no `Run` on purpose, or a `Run` if they should do something.
5. **`ctx.Flags.X("typo")` returns the zero value silently** — no error on unknown/misspelled flag names. Match names exactly.
6. **`FlagSet` adders panic on duplicate or empty names** — a startup crash, by design.
7. **Exit codes**: `Execute` returns `0` (ok), `2` (usage error: unknown flag, bad arg count, missing required), or `1` (a `Run`/hook returned an error). The constants `ExitNoChange`(10)/`ExitVerifyFailed`(20)/`ExitNetworkError`(30) are reserved for app logic but `Execute` never emits them itself — call `os.Exit` directly if you need them.
8. **Finish every `Task` spinner** with `Complete()`/`Stop()`/`Fail()`.

For anything not covered here — full field/method tables, parser precedence (default < env < CLI), help/version output format, and the `stencil` versioning dev-CLI — see `REFERENCE.md`.
