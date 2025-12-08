#!/bin/bash

ROOTFS_NAME="rootfs-alpine.tar.gz"
DEVICE_NAME="pico-mini-b"

while getopts ":f:d:" opt; do
  case ${opt} in
    f) ROOTFS_NAME="${OPTARG}" ;;
    d) DEVICE_NAME="${OPTARG}" ;;
    ?)
      echo "Invalid option: -${OPTARG}."
      exit 1
      ;;
  esac
done

rm -rf sdk/sysdrv/custom_rootfs/
mkdir -p sdk/sysdrv/custom_rootfs/
cp "$ROOTFS_NAME" sdk/sysdrv/custom_rootfs/

pushd sdk || exit

pushd tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/ || exit
source env_install_toolchain.sh
popd || exit

rm -rf .BoardConfig.mk
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

# build sysdrv - rootfs
./build.sh uboot
./build.sh kernel
./build.sh driver
./build.sh en

#./build.sh app
# package firmware
./build.sh firmware
./build.sh save

popd || exit

mkdir -p output
cp sdk/output/image/update.img "output/$DEVICE_NAME-sysupgrade.img"
