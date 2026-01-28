section_luckfox() {
	return 0
}

create_image_rootfs() {
	local _script=$(readlink -f "$scriptdir/genrootfs.sh")
	local output_file="$(readlink -f ${OUTDIR:-.})/$output_filename"

	fakeroot "$_script" -k "$APKROOT"/etc/apk/keys \
		-r "$APKROOT"/etc/apk/repositories \
		-o "$output_file" \
		-a $ARCH \
		-l "$apkovl" \
		$rootfs_apks
}

profile_luckfox() {
	title="Base root filesystem"
	desc="Minimal root filesystem.
		For use in Luckfox devices."
	image_ext=tar.gz
	output_format=rootfs
	arch="armv7"
	rootfs_apks=" \
		alpine-base \
		busybox \
		dhcpcd \
		doas \
		openssl
		tzdata \
		agetty"
	apkovl=luckfox
}
