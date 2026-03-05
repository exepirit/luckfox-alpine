#!/bin/sh
set -e

PACKAGER_PRIVKEY="${PACKAGER_PRIVKEY:-/output/abuild.rsa}"
REPODEST="${REPODEST:-/output}"
PACKAGES_DIR="${PACKAGES_DIR:-/packages}"

if [ ! -f "$PACKAGER_PRIVKEY" ]; then
    abuild-keygen -a -n
    cp "$HOME/.abuild/"*.rsa.pub "$PACKAGER_PRIVKEY.pub"
    cp "$HOME/.abuild/"*.rsa "$PACKAGER_PRIVKEY"
fi

chmod 600 "$PACKAGER_PRIVKEY"
chmod 644 "$PACKAGER_PRIVKEY.pub"

export PACKAGER_PRIVKEY
export REPODEST

for pubkey in "$HOME/.abuild/"*.rsa.pub; do
    if [ -f "$pubkey" ]; then
        sudo cp "$pubkey" /etc/apk/keys/
    fi
done

for pkgdir in "$PACKAGES_DIR"/mesh/*/; do
    pkgname=$(basename "$pkgdir")
    echo "Building: $pkgname"
    
    mkdir -p "/tmp/build/$pkgname"
    cp -r "$pkgdir"/* "/tmp/build/$pkgname/"
    cd "/tmp/build/$pkgname"
    
    abuild -r
done