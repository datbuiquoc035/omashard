#!/usr/bin/env bash
# omarchy:summary=Install the OmaShard plugin locally from this checkout
# omarchy:group=plugin
# omarchy:args=[options]

# Local installer for the qdot.omashard Omarchy plugin.
#
# Copies this checkout into ~/.config/omarchy/plugins/qdot.omashard/, then
# validates, discovers and enables it as a bar widget — the same flow as
# `omarchy plugin add` uses for git plugins, but from the local filesystem.
#
# Usage:
#   scripts/install.sh                 # install and enable next to the clock
#   scripts/install.sh --section left  # place the widget in the left section
#   scripts/install.sh --no-enable     # copy the plugin but leave it disabled
#   scripts/install.sh --force         # replace an existing install
#   scripts/install.sh --remove        # uninstall (alias: --rollback)

set -euo pipefail

PLUGIN_ID="qdot.omashard"
PLUGINS_DIR="${HOME}/.config/omarchy/plugins"
TARGET="$PLUGINS_DIR/$PLUGIN_ID"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

ACTION="install"
FORCE=0
NO_ENABLE=0
SECTION="right"

fail() {
  echo "install.sh: $*" >&2
  exit 1
}

usage() {
  cat <<USAGE
Usage: scripts/install.sh [options]

Local installer for the $PLUGIN_ID Omarchy plugin.

Options:
  --section <left|center|right>  Bar section to place the widget in (default: right)
  --no-enable                    Copy the plugin but do not enable it
  --force                        Replace an existing install instead of failing
  --remove, --rollback           Uninstall the plugin from this machine
  -h, --help                     Show this help
USAGE
}

parse_options() {
  while (( $# > 0 )); do
    case "$1" in
      --section)
        SECTION="${2:-}"
        [[ -n $SECTION ]] || fail "--section requires left, center or right"
        [[ $SECTION =~ ^(left|center|right)$ ]] || fail "section must be left, center, or right"
        shift 2
        ;;
      --no-enable)
        NO_ENABLE=1
        shift
        ;;
      --force)
        FORCE=1
        shift
        ;;
      --remove | --rollback)
        ACTION="remove"
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        fail "unknown option: $1 (try --help)"
        ;;
    esac
  done
}

require_omarchy() {
  command -v omarchy-shell >/dev/null 2>&1 ||
    fail "omarchy-shell not found — this script installs an Omarchy plugin"
}

remove_plugin() {
  [[ -e $TARGET || -L $TARGET ]] || { echo "OmaShard is not installed."; exit 0; }
  rm -rf "$TARGET"
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  echo "Removed OmaShard from $TARGET"
}

stage_and_validate() {
  local stage="$1"
  mkdir -p "$PLUGINS_DIR"
  cp -a "$REPO_DIR/." "$stage/"
  rm -rf "$stage/.git" "$stage/__pycache__"
  find "$stage" -name '*.pyc' -delete

  if command -v omarchy-plugin-validate >/dev/null 2>&1; then
    omarchy-plugin-validate "$stage" || fail "plugin folder failed validation"
  elif ! jq -e . "$stage/manifest.json" >/dev/null 2>&1; then
    fail "manifest.json is not valid JSON and omarchy-plugin-validate is unavailable"
  fi
}

enable_plugin() {
  local discovered=0
  for (( attempt = 0; attempt < 40; attempt++ )); do
    if omarchy-plugin-list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" '
        any(.[]; .id == $id)' >/dev/null; then
      discovered=1
      break
    fi
    sleep 0.05
  done
  (( discovered )) || fail "installed plugin '$PLUGIN_ID' was not discovered; enable it with: omarchy plugin enable $PLUGIN_ID"
  omarchy-plugin-enable "$PLUGIN_ID" --section "$SECTION"
}

install_plugin() {
  [[ -e $TARGET || -L $TARGET ]] && {
    if (( FORCE )); then
      echo "Replacing existing install at $TARGET"
      rm -rf "$TARGET"
    else
      fail "OmaShard is already installed at $TARGET (use --force to reinstall)"
    fi
  }

  local stage
  stage="$(mktemp -d "$PLUGINS_DIR/.install.$PLUGIN_ID.XXXXXX")"
  local committed=0
  cleanup() {
    [[ -d ${stage:-} ]] && rm -rf "$stage"
    (( committed )) || rm -rf "$TARGET"
  }
  trap cleanup EXIT

  stage_and_validate "$stage"
  mv "$stage" "$TARGET"
  stage=""
  committed=1
  echo "Installed $PLUGIN_ID into $TARGET"

  omarchy-shell shell rescanPlugins >/dev/null || true

  if (( NO_ENABLE )); then
    echo "Enable it later with: omarchy plugin enable $PLUGIN_ID --section $SECTION"
  else
    enable_plugin
  fi
}

parse_options "$@"
require_omarchy

if [[ $ACTION == "remove" ]]; then
  remove_plugin
else
  install_plugin
fi