#!/usr/bin/env bash
# build-alpenglow.sh — build agave for the Alpenglow test cluster from source
# and point active_release at it.
#
# Usage: build-alpenglow.sh [ref]
#   ref   agave tag or branch — defaults to the cluster's current ref below.
#         The cluster moves on restarts; override when it does.
set -euo pipefail

DEFAULT_REF="v4.2.0-beta.0"   # last verified: 2026-08
TAG="${1:-$DEFAULT_REF}"
echo "Building anza-xyz/agave at ref: $TAG"

echo "Check if required packages are installed."
packages=("libssl-dev" "libudev-dev" "pkg-config" "zlib1g-dev" "llvm" "clang" "cmake" "make" "libprotobuf-dev" "protobuf-compiler")
missing_packages=()
for package in "${packages[@]}"; do
  if dpkg -s "$package" >/dev/null 2>&1; then
    echo "$package is installed."
  else
    missing_packages+=("$package")
  fi
done
[ "${#missing_packages[@]}" -ne 0 ] && {
  echo ERROR: following packages are missing "${missing_packages[@]}"
  echo hint: sudo apt install -y "${missing_packages[@]}"
  exit 1
}

if ! command -v cargo &> /dev/null; then
  curl https://sh.rustup.rs -sSf | sh
fi

# shellcheck disable=SC1091
source "$HOME/.cargo/env"

rustup component add rustfmt
rustup update

rm -rf "$HOME"/agave
git clone https://github.com/anza-xyz/agave.git "$HOME"/agave --recurse-submodules

cd "$HOME"/agave || exit

git checkout "$TAG"
git submodule update --init --recursive

CI_COMMIT=$(git rev-parse HEAD) scripts/cargo-install-all.sh --validator-only "$HOME"/.local/share/solana/install/releases/"$TAG"

rm -rf "$HOME"/.local/share/solana/install/active_release
ln -sf "$HOME"/.local/share/solana/install/releases/"$TAG" "$HOME"/.local/share/solana/install/active_release

if [ ! -x "$HOME/.local/share/solana/install/releases/$TAG/bin/solana" ]; then
  echo "NOTE: the --validator-only build has no solana CLI tools."
  echo "      Run ~/build-solana-cli.sh to build and install them alongside the validator."
fi

rm -rf "$HOME"/agave
