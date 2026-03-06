#!/bin/sh
set -e

PACKAGER_PRIVKEY="${PACKAGER_PRIVKEY:-$HOME/.abuild/abuild.rsa}"
REPODEST="${REPODEST:-./output}"
PACKAGES_DIR="${PACKAGES_DIR:-./packages}"
BRANCH="${BRANCH:-mesh}"

if [ ! -f "${PACKAGER_PRIVKEY}" ]; then
    abuild-keygen -a -n
fi

export PACKAGER_PRIVKEY
export REPODEST

for pubkey in "$HOME/.abuild/"*.rsa.pub; do
    if [ -f "$pubkey" ]; then
        sudo cp "$pubkey" /etc/apk/keys/
    fi
done

for pkgdir in "$PACKAGES_DIR"/mesh/*/; do
    echo "Building: $pkgname"
    cd "$pkgdir"

    abuild -r
done
