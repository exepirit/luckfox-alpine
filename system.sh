#!/bin/bash -e

ROOTFS_FILENAME=
DEVICE_NAME=
while getopts ":f:d:" opt; do
  case ${opt} in
    f) ROOTFS_FILENAME="${OPTARG}" ;;
    d) DEVICE_NAME="${OPTARG}" ;;
    ?)
      echo "Invalid option: -${OPTARG}."
      exit 1
      ;;
  esac
done
set -- "${script_args[@]}" # Reset positional arguments before call `source`

ROOTFS_NAME="$(basename "$ROOTFS_FILENAME")"
echo "$ROOTFS_FILENAME => $ROOTFS_NAME"
echo sdk/sysdrv/custom_rootfs/"$ROOTFS_NAME"

[ -e sdk/sysdrv/custom_rootfs ] && rm -rf sdk/sysdrv/custom_rootfs
mkdir -p sdk/sysdrv/custom_rootfs
cp "$ROOTFS_FILENAME" sdk/sysdrv/custom_rootfs/"$ROOTFS_NAME"

# env_install_toolchain.sh need this file. don't ask why
touch $HOME/.bash_profile

pushd sdk

pushd tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/
source env_install_toolchain.sh
popd

[ -f ".BoardConfig.mk" ] && rm ".BoardConfig.mk"

case $DEVICE_NAME in
  pico-mini-sd) DEVICE="1"; MEDIA="0" ;;
  pico-mini-flash) DEVICE="1"; MEDIA="1" ;;
  *)
    echo "Invalid device: ${DEVICE_NAME}."
    exit 1
    ;;
esac
printf "$DEVICE\n$MEDIA\n0\n" | ./build.sh lunch
echo "export RK_CUSTOM_ROOTFS=../sysdrv/custom_rootfs/$ROOTFS_NAME" >> .BoardConfig.mk
echo "export RK_BOOTARGS_CMA_SIZE=\"1M\"" >> .BoardConfig.mk

./build.sh uboot
./build.sh kernel
./build.sh driver
./build.sh en
./build.sh firmware
./build.sh save

popd

mkdir -p output
cp sdk/output/image/update.img "output/$DEVICE_NAME-sysupgrade.img"
