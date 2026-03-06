#!/bin/sh
set -e

REPODEST="${REPODEST:-./output}"
PACKAGES_DIR="${PACKAGES_DIR:-./packages}"
BRANCH="${BRANCH:-mesh}"

export REPODEST

for pubkey in "$HOME/.abuild/"*.rsa.pub; do
    if [ -f "$pubkey" ]; then
        sudo cp "$pubkey" /etc/apk/keys/
    fi
done

packages_dir="$(realpath "$PACKAGES_DIR")"
for pkgdir in "$packages_dir"/mesh/*/; do
    pkgname="$(basename "$pkgdir")"
    echo "Building: $pkgname"
    cd "$pkgdir"

    abuild -r
done
