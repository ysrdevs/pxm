#!/bin/sh
# pxm installer. One line, on any supported Linux:
#
#   curl -fsSL https://raw.githubusercontent.com/ysrdevs/pxm/main/install.sh | sh
#
# On Omarchy it adds the pxm plugin (bar icon + window) and runs `pxm setup`.
# Elsewhere it puts the pxm command in ~/.local/lib/pxm and runs `pxm setup`.
# Run the same line again later to update.
set -eu

REPO="${PXM_REPO:-https://github.com/ysrdevs/pxm}"
BRANCH="${PXM_BRANCH:-main}"

say() { printf '%s\n' "$*"; }
fail() { printf 'pxm install: %s\n' "$*" >&2; exit 1; }

# `curl | sh` leaves the script on stdin, so setup's questions must read from the terminal instead.
run_setup() {
  bin="$1"; shift
  if ( : </dev/tty ) 2>/dev/null; then
    exec "$bin" setup "$@" </dev/tty
  fi
  exec "$bin" setup "$@"
}

if command -v omarchy >/dev/null 2>&1 && [ -d "$HOME/.config/omarchy" ]; then
  plugin="$HOME/.config/omarchy/plugins/pxm"
  if [ -d "$plugin" ]; then
    say "pxm is already an Omarchy plugin here; updating it."
    omarchy plugin update pxm --yes || true
  else
    say "Omarchy found: adding the pxm plugin (bar icon and window)."
    omarchy plugin add "$REPO" --enable
  fi
  run_setup "$plugin/bin/pxm" "$@"
fi

command -v python3 >/dev/null 2>&1 || fail "python3 is needed first (sudo apt install python3 / sudo dnf install python3)"
command -v git >/dev/null 2>&1 || fail "git is needed first (sudo apt install git / sudo dnf install git)"

app="$HOME/.local/lib/pxm"
if [ -d "$app/.git" ]; then
  say "Updating pxm in $app"
  git -C "$app" pull -q --ff-only
else
  say "Downloading pxm to $app"
  mkdir -p "$(dirname "$app")"
  git clone -q --depth 1 -b "$BRANCH" "$REPO" "$app"
fi
run_setup "$app/bin/pxm" "$@"
