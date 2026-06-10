# Stencil — API reference

Exhaustive companion to `SKILL.md`. Symbols are in package `stencil` unless noted as `pkg/ui`.

> Stencil is early and its public API is **not yet frozen** — names and signatures can still change between commits (the repo has no version tags). Verify against the installed source if something here doesn't match.

## `App` and options

```go
func NewApp(opts ...Option) *App
func (a *App) Execute(argv []string) int   // returns the process exit code
```

`App` fields: `Name string`, `Description string`, `Version VersionInfo`, `Color ColorMode`, `IO Stdio`, `UI ui.UI`, `Root *Command`.

`NewApp` defaults: `Name = base(os.Args[0])`, `Color = ColorAuto`, `IO = {os.Stdin, os.Stdout, os.Stderr}`. After applying options: if `Root == nil` it auto-creates a root named after the app (with empty flag sets); if `UI == nil` it creates `ui.NewConsoleUI(IO.Out)`.

| Option | Effect |
|---|---|
| `WithName(string)` | App name (help/version, default root name) |
| `WithDescription(string)` | One-line description in help |
| `WithVersionInfo(VersionInfo)` | Populates `--version` and help header |
| `WithColorMode(ColorMode)` | `ColorAuto` (default), `ColorOn`, `ColorOff` |
| `WithIO(in io.Reader, out, err io.Writer)` | Override the three streams |
| `WithUI(ui.UI)` | Inject a custom UI implementation |
| `WithRootCommand(*Command)` | Supply your own root command tree |

```go
type VersionInfo struct{ Version, BuildDate, CommitHash, Branch string }
type Stdio struct{ In io.Reader; Out, Err io.Writer }
type ColorMode int // ColorAuto=0, ColorOn, ColorOff
```

**Color resolution** (`shouldColor`): `NO_COLOR` env set (non-empty) → always off. Else `ColorOn`→on, `ColorOff`→off, `ColorAuto`→on only if `IO.Out` is a character device (TTY).

## `Command`

```go
type RunFunc func(ctx *Context) error

type Command struct {
	Name       string
	Summary    string   // one-liner in parent's command list + own help header
	Long       string   // longer description block in help
	Aliases    []string // alternative names matched during path resolution
	Hidden     bool     // hide from help listings
	Deprecated string   // marks "(deprecated)" in help

	Run               RunFunc // leaf action
	PreRun            RunFunc // leaf, before Run
	PostRun           RunFunc // leaf, after Run
	PersistentPreRun  RunFunc // every command on path, root→leaf
	PersistentPostRun RunFunc // every command on path, leaf→root

	PersistentFlags *FlagSet // inherited by this command + all descendants
	Flags           *FlagSet // local to this command only

	Args ArgSpec // positional-arg constraints

	Sub []*Command // child commands
}

type ArgSpec struct {
	Min, Max int               // Max == 0 means unlimited
	Names    []string          // labels for help
	Validate func([]string) error
}
```

**Hook order** (path = root→leaf commands matched): all `PersistentPreRun` root→leaf, then leaf `PreRun`, `Run`, `PostRun`, then all `PersistentPostRun` leaf→root. First hook to return an error stops execution and yields exit code 1.

## Flags

```go
func NewFlagSet() *FlagSet
func (fs *FlagSet) Bool(name, short, usage string, def bool) *Flag
func (fs *FlagSet) String(name, short, usage, def string) *Flag
func (fs *FlagSet) Int(name, short, usage string, def int) *Flag
func (fs *FlagSet) Duration(name, short, usage string, def time.Duration) *Flag
func (fs *FlagSet) StringSlice(name, short, usage string, def []string) *Flag
func (fs *FlagSet) IntSlice(name, short, usage string, def []int) *Flag
```

Each returns the `*Flag` for further configuration. `add` **panics** on: empty long `Name`, duplicate long name, or duplicate short.

```go
type Flag struct {
	Type     FlagType         // set by the adder
	Name     string           // long --name
	Short    string           // short -n ("" = none)
	Usage    string
	Default  any
	Env      string           // env-var fallback name
	Required bool
	Enum     []string         // allowed values (string flags)
	Validate func(any) error  // custom per-flag validation
	Hidden   bool             // omit from help
}

type FlagType int // FlagBool, FlagString, FlagInt, FlagDuration, FlagStringSlice, FlagIntSlice
```

### Reading resolved values — `Context` / `ResolvedFlags`

```go
type Context struct {
	App   *App
	Path  []*Command // root→leaf
	Args  []string   // positionals
	Flags *ResolvedFlags
}

func (rf *ResolvedFlags) Bool(name string) bool
func (rf *ResolvedFlags) String(name string) string
func (rf *ResolvedFlags) Int(name string) int
func (rf *ResolvedFlags) Duration(name string) time.Duration
func (rf *ResolvedFlags) StringSlice(name string) []string
func (rf *ResolvedFlags) IntSlice(name string) []int
func (rf *ResolvedFlags) Get(name string) (any, bool)
```

All typed accessors return the **zero value** for an unknown name or a value of the wrong type — never panic, never error. `Get` is the only one that tells you whether the key existed.

### Parsing rules (`parser.go`)

- **Path resolution** is greedy by leading non-`-` tokens, matching `Name` or any `Aliases`. Stops at the first token starting with `-` or `--`, or the first non-matching word.
- **Long flags**: `--flag` (bool→true), `--flag=value`, `--flag value`. `--no-flag` sets a bool to false.
- **Short flags**: `-f`, `-f=value`, `-f value`. **Bundled short bools**: `-abc` sets three bool flags. A non-bool short in a bundle is an error.
- `--` switches the rest of the line to positionals.
- **Value precedence**: default → env (if `Env` set and var non-empty) → command-line value.
- **Casting / validation** at parse time: bool accepts `true/1/yes/on` and `false/0/no/off` (case-insensitive); `Enum` membership and `Validate` are enforced for the relevant types; bad values produce a usage error (exit 2).
- **Required** flags are checked **only on the leaf command's local `Flags`** (a value must be present and non-empty).

### Exit codes (`errors.go`)

```go
const (
	ExitOK           = 0
	ExitRuntime      = 1   // a Run/hook returned an error
	ExitUsage        = 2   // unknown flag, bad arg count, missing required, etc.
	ExitNoChange     = 10  // reserved for app logic
	ExitVerifyFailed = 20  // reserved for app logic
	ExitNetworkError = 30  // reserved for app logic
)
```

`Execute` itself only ever returns `0`, `1`, or `2`. The `10/20/30` constants are conventions for app code — if you want them, branch in `main` and call `os.Exit` yourself (a `Run` error always maps to `1`). Error types `UsageError` and `ExecError` exist internally; `Run` should just return a normal `error`.

### Built-in commands / flags

- `--version` / `-V`: prints `name version` plus a `commit/built/branch` line; exit 0.
- `-h` / `--help` anywhere: contextual help for the resolved command path; exit 0.
- `help [cmd ...]`: same help, as a subcommand.
- A command whose `Run == nil` but has `Sub` prints help and exits 2.

### Help output shape (`help.go`)

Sections, in order: header (`path: summary`), `Long` if set; on the root only a `Version:` block and `Description:`; then `Usage:`, `Flags:` (merged persistent+local, short shown as `-x, --name`, with `(default: …)` or `(one of: a,b; default: …)` for enums), an `Environment Variables:` section listing flags that have `Env` set, `Commands:` (sorted, hidden omitted, `(deprecated)` marked), and `Arguments:` (from `ArgSpec.Names`).

## `pkg/ui` — console UI

```go
import "github.com/bgrewell/stencil/pkg/ui"

type UI interface {
	Info(format string, args ...any)
	Warn(format string, args ...any)
	Error(format string, args ...any)
	Task(format string, args ...any) (Spinner, error)
}

type Spinner interface {
	Update(format string, args ...any)
	Complete() // settles to "done"  (green)
	Stop()     // settles to "stopped"
	Fail()     // settles to "error" (red)
	Raw() *yacspin.Spinner
}

func NewConsoleUI(out io.Writer, opts ...Option) UI
func WithSpinnerStyle(index int) Option // yacspin.CharSets index (default 14)
```

- `Info`/`Warn`/`Error` each render one settled line (`done`/`warn`/`error` stop words; warn yellow, error red). `Task` returns a live spinner you drive with `Update`, then settle with exactly one of `Complete`/`Stop`/`Fail`.
- Lines are padded with `.` leaders to ~70 columns, then the stop word. Built on `github.com/theckman/yacspin`; `Raw()` exposes it for advanced tweaks.
- Inject `ui.UI` into your own packages so library code can emit progress without importing the whole app.

## The `stencil` developer CLI (versioning + git hook)

Built from `./cmd` (package `main`). It is **developer tooling for an app that uses stencil**, not something the app imports. It stores a semantic version as plain-text files under `.stencil/` (`version_major`, `version_minor`, `version_patch`) so build tooling can read components directly for ldflags.

Build it from the stencil repo with **`make build`**, which produces a binary named **`stencil`**.

Global flag: `-C, --dir <path>` (project root, default `.`).

| Command | Does |
|---|---|
| `stencil version init` | Create `.stencil/` seeded at `0.0.0` (idempotent) |
| `stencil version show` | Print the current version to stdout |
| `stencil version bump [--major\|--minor\|--patch]` | Increment (patch by default); major resets minor+patch, minor resets patch |
| `stencil hook install` | Install a git **pre-commit** hook that auto-bumps the patch version each commit (also runs `version init`) |
| `stencil hook uninstall` | Remove the stencil-managed git hook |

Typical loop: `stencil version init` once, then `stencil hook install` so every commit bumps patch automatically; your Makefile reads `stencil version show` (or the `.stencil/version_*` files) into `$(VERSION)` and injects it via `-ldflags '-X main.appVersion=…'` (see `SKILL.md` → "Version info & build-time injection").

## Example consumers (real usage to copy from)

- **`testbox`** `cmd/cli/main.go` — root + subcommands, persistent enum flag, `ArgSpec`, ldflags version vars passed to `VersionInfo`. Pure new-API reference.
- **`sshwiz`** `cmd/cli/main.go` — large command tree, `Required` flags, `Duration` flag, nested `service` subcommands.
- **`smart-gateway`** `builder/` — older codebase that imports **`pkg/ui` standalone** (`NewDownloader(..., ui.UI)`) and drives `Task`/`Info`/`Error` from a library package. NOTE: its `main.go` predates the current API and uses the removed `NewStencil` form — use it only as a `pkg/ui` example, not for the command framework.
