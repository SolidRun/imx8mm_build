#!/bin/bash
set -e

### General setup
NXP_REL=rel_imx_4.14.78_1.0.0_ga
UBOOT_NXP_REL=imx_v2018.03_4.14.78_1.0.0_ga
BUILDROOT_VERSION=2019.02
GTI_REL=v4.5.0.3
###

export ARCH=arm64
ROOTDIR=`pwd`

COMPONENTS="imx-atf uboot-imx linux-imx imx-mkimage"
mkdir -p build
for i in $COMPONENTS; do
	if [[ ! -d $ROOTDIR/build/$i ]]; then
		cd $ROOTDIR/build/
		git clone https://source.codeaurora.org/external/imx/$i
		cd $i
		if [ "x$i" == "xuboot-imx" ]; then
			git checkout remotes/origin/$UBOOT_NXP_REL
			git pull origin $UBOOT_NXP_REL
		elif [ "x$i" == "xlinux-imx" ]; then
			git checkout -b $NXP_REL
			git pull origin $NXP_REL
		elif [ "x$i" == "ximx-mkimage" ]; then
			git checkout -b $NXP_REL
			git pull origin $NXP_REL
		elif [ "x$i" == "ximx-atf" ]; then
			git checkout $NXP_REL
			git pull origin $NXP_REL
		else
			git checkout -b $NXP_REL
			git pull origin $NXP_REL
		fi
		if [[ -d $ROOTDIR/patches/$i/ ]]; then
			git am $ROOTDIR/patches/$i/*.patch
		fi
	fi
done
 
if [[ ! -d $ROOTDIR/build/imx-mkimage ]]; then cd $ROOTDIR/build; git clone https://source.codeaurora.org/external/imx/imx-mkimage.git -b rel_imx_4.14.78_1.0.0_ga; fi
if [[ ! -d $ROOTDIR/build/firmware ]]; then
	cd $ROOTDIR/build/
	mkdir -p firmware
	cd firmware
	wget http://www.freescale.com/lgfiles/NMG/MAD/YOCTO/firmware-imx-8.0.bin
	bash firmware-imx-8.0.bin --auto-accept
	cp -v $(find . | awk '/train|hdmi_imx8|dp_imx8/' ORS=" ") ${ROOTDIR}/build/imx-mkimage/iMX8M/
fi

if [[ ! -d $ROOTDIR/build/buildroot ]]; then
	cd $ROOTDIR/build
	git clone https://github.com/buildroot/buildroot -b $BUILDROOT_VERSION
fi

# Build buildroot
cd $ROOTDIR/build/buildroot
cp $ROOTDIR/configs/buildroot_defconfig .config
make

export CROSS_COMPILE=$ROOTDIR/build/buildroot/output/host/bin/aarch64-linux-

# Build ATF
cd $ROOTDIR/build/imx-atf
make -j32 PLAT=imx8mm bl31
cp build/imx8mm/release/bl31.bin $ROOTDIR/build/imx-mkimage/iMX8M/

# Build u-boot
cd $ROOTDIR/build/uboot-imx/
make imx8mm_solidrun_defconfig
make -j 32
set +e
cp -v $(find . | awk '/u-boot-spl.bin$|u-boot.bin$|u-boot-nodtb.bin$|.*\.dtb$|mkimage$/' ORS=" ") ${ROOTDIR}/build/imx-mkimage/iMX8M/
set -e

# Build linux
cd $ROOTDIR/build/linux-imx
make defconfig
./scripts/kconfig/merge_config.sh .config $ROOTDIR/configs/kernel.extra
make -j32 Image dtbs

# Bring bootlader all together
unset ARCH CROSS_COMPILE
cd $ROOTDIR/build/imx-mkimage/iMX8M
sed "s/\(^dtbs = \).*/\1fsl-imx8mm-solidrun.dtb/;s/\(mkimage\)_uboot/\1/" soc.mak > Makefile
make clean
make flash_evk SOC=iMX8MM

# Create disk images
mkdir -p $ROOTDIR/images/tmp/
cd $ROOTDIR/images
dd if=/dev/zero of=tmp/part1.fat32 bs=1M count=58
mkdosfs tmp/part1.fat32

echo "label linux" > $ROOTDIR/images/extlinux.conf
echo "        linux ../Image" >> $ROOTDIR/images/extlinux.conf
echo "        fdt ../fsl-imx8mm-solidrun.dtb" >> $ROOTDIR/images/extlinux.conf
echo "        append root=/dev/mmcblk1p2 rootwait" >> $ROOTDIR/images/extlinux.conf
mmd -i tmp/part1.fat32 ::/extlinux
mcopy -i tmp/part1.fat32 $ROOTDIR/images/extlinux.conf ::/extlinux/extlinux.conf
mcopy -i tmp/part1.fat32 $ROOTDIR/build/linux-imx/arch/arm64/boot/Image ::/Image
mcopy -s -i tmp/part1.fat32 $ROOTDIR/build/linux-imx/arch/arm64/boot/dts/freescale/*imx8mm*.dtb ::/
dd if=/dev/zero of=microsd.img bs=1M count=121
dd if=$ROOTDIR/build/imx-mkimage/iMX8M/flash.bin of=microsd.img bs=1K seek=33 conv=notrunc
parted --script microsd.img mklabel msdos mkpart primary 2MiB 60MiB mkpart primary 60MiB 120MiB
dd if=tmp/part1.fat32 of=microsd.img bs=1M seek=2 conv=notrunc
dd if=$ROOTDIR/build/buildroot/output/images/rootfs.ext2 of=microsd.img bs=1M seek=60 conv=notrunc
echo -e "\n\n*** Image is ready - images/microsd.img"
