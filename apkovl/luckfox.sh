#!/bin/sh

HOSTNAME="luckfox"
TTY_PORT="ttyFIQ0"

rc_add() {
	mkdir -p ./etc/runlevels/"$2"
	ln -sf /etc/init.d/"$1" ./etc/runlevels/"$2"/"$1"
}

echo "$HOSTNAME" > ./etc/hostname

echo "# /etc/inittab
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
${TTY_PORT}::respawn:/sbin/agetty --autologin root ${TTY_PORT} vt100
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown" > ./etc/inittab

rc_add devfs boot
rc_add procfs boot
rc_add sysfs boot
rc_add localmount default
rc_add ubi-mount default
rc_add networking default
rc_add local default