#!/bin/sh -e

# Copyright (C) 2026 Alpine Linux developers
# Some changes made for overlay scripts handling

cleanup() {
	rm -rf "$tmp"
}

tmp="$(mktemp -d)"
trap cleanup EXIT
chmod 0755 "$tmp"

arch="$(apk --print-arch)"
repositories_file=/etc/apk/repositories
keys_dir=/etc/apk/keys
apkovl=

while getopts "a:r:k:o:l:" opt; do
	case $opt in
	a) arch="$OPTARG";;
	r) repositories_file="$OPTARG";;
	k) keys_dir="$OPTARG";;
	o) outfile="$OPTARG";;
	l) apkovl="$OPTARG";;
	esac
done
shift $(( $OPTIND - 1))

cat "$repositories_file"

if [ -z "$outfile" ]; then
	outfile=rootfs-$arch.tar.gz
fi

if [ "$BOOTSTRAP_USR_MERGED" = "1" ]; then
	mkdir -p "$tmp"/usr/lib "$tmp"/usr/bin "$tmp"/usr/sbin
	ln -s usr/bin usr/sbin usr/lib "$tmp"/
fi
${APK:-apk} add --keys-dir "$keys_dir" --no-cache \
	--repositories-file "$repositories_file" \
	--no-script --root "$tmp" --initdb --arch "$arch" \
	"$@"

rm -f "$tmp"/var/log/apk.log

for link in $("$tmp"/bin/busybox --list-full); do
	[ -e "$tmp"/$link ] || [ -L "$tmp/$link" ] || ln -s /bin/busybox "$tmp"/$link
done

if [ -n "$apkovl" ]; then
	_script=
	for _script in "$PWD/apkovl/$apkovl.sh"; do
		if [ -f "$_script" ]; then
			break
		fi
	done
	[ -n "$_script" ] || die "could not find $apkovl"
	(cd "$tmp"; "$_script" "$tmp")
fi

# disable password login but allow login with ssh keys for root
sed -i -e 's/^root::/root:*:/' "$tmp"/etc/shadow
# Set shadow group manually since we use --no-script above
# Use gid since we use --numeric-owner below
chgrp 42 "$tmp"/etc/shadow

branch=edge
VERSION_ID=$(awk -F= '$1=="VERSION_ID" {print $2}'  "$tmp"/etc/os-release)
case $VERSION_ID in
*_alpha*|*_beta*) branch=edge;;
*.*.*) branch=v${VERSION_ID%.*};;
esac

cat > "$tmp"/etc/apk/repositories <<EOF
https://dl-cdn.alpinelinux.org/alpine/$branch/main
https://dl-cdn.alpinelinux.org/alpine/$branch/community
EOF

tar --numeric-owner --exclude='dev/*' -c -C "$tmp" . | gzip -9n > "$outfile"
