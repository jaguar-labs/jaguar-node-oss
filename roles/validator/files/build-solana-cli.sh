#!/usr/bin/env bash
# build-solana-cli.sh — build the vanilla agave CLI tools (solana, solana-keygen)
# from source and expose them through active_release/bin.
#
# Companion to build-jito.sh: the jito --validator-only build ships no CLI
# tools, and agave 4.1+ has no prebuilt release with the validator either.
# This script never touches validator binaries or the active_release symlink.
#
# Usage: build-solana-cli.sh [version]
#   version   e.g. 4.2.0-beta.2 — defaults to the active_release validator's
#             version when omitted.
set -euo pipefail

INSTALL_ROOT="$HOME/.local/share/solana/install"
ACTIVE_BIN="$INSTALL_ROOT/active_release/bin"
RELEASES_DIR="$INSTALL_ROOT/releases"

VERSION="${1:-}"
if [ -z "$VERSION" ] && [ -x "$ACTIVE_BIN/agave-validator" ]; then
  VERSION="$("$ACTIVE_BIN/agave-validator" --version | awk '{print $2}')"
fi
if [ -z "$VERSION" ]; then
  echo "usage: $0 <version>    e.g. $0 4.2.0-beta.2" >&2
  echo "(could not derive a version from $ACTIVE_BIN/agave-validator)" >&2
  exit 1
fi

CLI_RELEASE="$RELEASES_DIR/$VERSION/solana-release"

if [ -x "$CLI_RELEASE/bin/solana" ]; then
  echo "CLI release $VERSION already built at $CLI_RELEASE"
else
  if ! command -v cargo >/dev/null 2>&1 && [ ! -f "$HOME/.cargo/env" ]; then
    curl https://sh.rustup.rs -sSf | sh -s -- -y
  fi
  # shellcheck disable=SC1091
  source "$HOME/.cargo/env"
  BUILD_DIR="$HOME/build/agave-cli"
  if [ ! -d "$BUILD_DIR/.git" ] || ! git -C "$BUILD_DIR" describe --tags --exact-match 2>/dev/null | grep -qx "v$VERSION"; then
    rm -rf "$BUILD_DIR"
    git clone --depth 1 --branch "v$VERSION" https://github.com/anza-xyz/agave.git "$BUILD_DIR"
  fi
  echo "Building agave CLI $VERSION from source (this can take a while)..."
  (cd "$BUILD_DIR" && ./scripts/cargo-install-all.sh --no-build-validator-bins "$CLI_RELEASE")
fi

# expose the tools the repo's scripts and monitoring need; no-clobber so
# anything the active (validator) release already provides always wins
for tool in solana solana-keygen; do
  if [ ! -e "$ACTIVE_BIN/$tool" ]; then
    cp -n "$CLI_RELEASE/bin/$tool" "$ACTIVE_BIN"/
    echo "installed $tool $VERSION into active_release/bin"
  fi
done

echo "Done: $("$ACTIVE_BIN/solana" --version)"
