#!/usr/bin/env bash
#
# install.sh — install the skills in this repo into a Claude Code skills directory.
#
# By default, skills are symlinked into your personal skills directory
# (~/.claude/skills) so edits in this repo take effect immediately. Use --copy
# for a standalone copy, or --target to install into a project's .claude/skills.
#
# Usage:
#   ./install.sh [options] [skill...]
#
# Options:
#   -c, --copy            Copy skills instead of symlinking them.
#   -f, --force           Overwrite existing skills at the target.
#   -t, --target DIR      Install into DIR instead of ~/.claude/skills.
#   -u, --uninstall       Remove the named skills (or all) from the target.
#   -l, --list            List the skills available in this repo and exit.
#   -n, --dry-run         Print actions without making any changes.
#   -h, --help            Show this help and exit.
#
# Arguments:
#   skill...   One or more skill names to act on. If omitted, all skills in
#              this repo are used.
#
# Examples:
#   ./install.sh                 # symlink every skill into ~/.claude/skills
#   ./install.sh --copy stencil  # copy just the stencil skill
#   ./install.sh --uninstall     # remove all of this repo's skills
#   ./install.sh -t ./.claude/skills dart   # install dart into a project

set -euo pipefail

# Resolve the directory this script lives in, following symlinks.
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
REPO_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
SKILLS_DIR="$REPO_DIR/skills"

# Defaults.
TARGET="${HOME}/.claude/skills"
MODE="symlink"   # symlink | copy
FORCE=0
UNINSTALL=0
LIST=0
DRY_RUN=0

# Colors (disabled when not writing to a terminal).
if [ -t 1 ]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  BOLD=""; RED=""; GREEN=""; YELLOW=""; RESET=""
fi

info()  { printf '%s\n' "$*"; }
warn()  { printf '%s%s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
err()   { printf '%s%s%s\n' "$RED" "$*" "$RESET" >&2; }
ok()    { printf '%s%s%s\n' "$GREEN" "$*" "$RESET"; }

usage() {
  sed -n '2,/^set -euo/p' "$SOURCE" | sed '$d' | sed 's/^# \{0,1\}//'
}

# Print the names of all skills found in the repo (a skill is a directory
# containing a SKILL.md file).
available_skills() {
  local d
  for d in "$SKILLS_DIR"/*/; do
    [ -f "${d}SKILL.md" ] || continue
    basename "$d"
  done
}

# --- Parse arguments ---------------------------------------------------------
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -c|--copy)      MODE="copy"; shift ;;
    -f|--force)     FORCE=1; shift ;;
    -u|--uninstall) UNINSTALL=1; shift ;;
    -l|--list)      LIST=1; shift ;;
    -n|--dry-run)   DRY_RUN=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    -t|--target)
      [ $# -ge 2 ] || { err "Option $1 requires an argument."; exit 2; }
      TARGET="$2"; shift 2 ;;
    --target=*)     TARGET="${1#*=}"; shift ;;
    --)             shift; while [ $# -gt 0 ]; do ARGS+=("$1"); shift; done ;;
    -*)             err "Unknown option: $1"; usage >&2; exit 2 ;;
    *)              ARGS+=("$1"); shift ;;
  esac
done

# --- Collect the set of skills to act on ------------------------------------
mapfile -t ALL_SKILLS < <(available_skills)
if [ "${#ALL_SKILLS[@]}" -eq 0 ]; then
  err "No skills found in $SKILLS_DIR"
  exit 1
fi

if [ "$LIST" -eq 1 ]; then
  info "${BOLD}Available skills:${RESET}"
  for s in "${ALL_SKILLS[@]}"; do info "  $s"; done
  exit 0
fi

if [ "${#ARGS[@]}" -gt 0 ]; then
  SELECTED=("${ARGS[@]}")
  # Validate each requested skill exists.
  for s in "${SELECTED[@]}"; do
    found=0
    for a in "${ALL_SKILLS[@]}"; do [ "$a" = "$s" ] && found=1 && break; done
    if [ "$found" -eq 0 ]; then
      err "Unknown skill: $s"
      info "Available: ${ALL_SKILLS[*]}"
      exit 1
    fi
  done
else
  SELECTED=("${ALL_SKILLS[@]}")
fi

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    info "  ${BOLD}[dry-run]${RESET} $*"
  else
    "$@"
  fi
}

# --- Uninstall ---------------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
  info "${BOLD}Uninstalling from $TARGET${RESET}"
  for s in "${SELECTED[@]}"; do
    dest="$TARGET/$s"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      run rm -rf "$dest"
      ok "  removed $s"
    else
      warn "  $s not installed, skipping"
    fi
  done
  exit 0
fi

# --- Install -----------------------------------------------------------------
info "${BOLD}Installing into $TARGET${RESET} (mode: $MODE)"
run mkdir -p "$TARGET"

for s in "${SELECTED[@]}"; do
  src="$SKILLS_DIR/$s"
  dest="$TARGET/$s"

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$FORCE" -eq 1 ]; then
      run rm -rf "$dest"
    else
      warn "  $s already exists at target (use --force to overwrite), skipping"
      continue
    fi
  fi

  case "$MODE" in
    symlink) run ln -s "$src" "$dest" ;;
    copy)    run cp -R "$src" "$dest" ;;
  esac
  ok "  installed $s"
done

info ""
info "Done. Restart Claude Code or start a new session to pick up changes."
