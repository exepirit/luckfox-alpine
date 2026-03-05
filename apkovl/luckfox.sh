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
${TTY_PORT}::respawn:/sbin/agetty ${TTY_PORT} vt100
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown" > ./etc/inittab

rc_add devfs boot
rc_add procfs boot
rc_add sysfs boot
rc_add localmount default
rc_add ubi-mount default
rc_add networking default
rc_add local default

# Set root password to 'luckfox'
HASH='$6$arxWOZydYqBTHdmJ$0ZUC3US0SfG3i2oMc9FKr3/FBXFBhCZ0t/bcaN3V8BR6oWDkaGb69etwPBReSE2a8O3WJWL8801dw/HtKPhK20'
sed -i "s|^root:.*|root:${HASH}:0:0:99999:7:::|" ./etc/shadow