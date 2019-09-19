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
 
#if [[ ! -d imx-atf ]]; then git clone https://source.codeaurora.org/external/imx/imx-atf/ -b imx_4.14.78_1.0.0_ga; fi
#if [[ ! -d uboot-imx ]]; then git clone https://source.codeaurora.org/external/imx/uboot-imx/ -b imx_v2018.03_4.14.78_1.0.0_ga; fi
#if [[ ! -d linux-imx ]]; then git clone https://source.codeaurora.org/external/imx/linux-imx/ -b imx_4.14.78_1.0.0_ga; fi
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

if [[ ! -d $ROOTDIR/build/GTISDK-Linux_aarch64_${GTI_REL} ]]; then
	cd $ROOTDIR/build
	if [ ! -f $ROOTDIR/GTI/GTISDK-Linux_aarch64_${GTI_REL}.tgz ]; then
		echo "Place GTI Linux aarch64 version ${GTI_REL} SDK at GTI directory"
		exit
	fi
	tar zxf $ROOTDIR/GTI/GTISDK-Linux_aarch64_${GTI_REL}.tgz
fi
if [[ ! -d $ROOTDIR/build/GTISDK-Linux_x86_64_${GTI_REL} ]]; then
	cd $ROOTDIR/build
	if [ ! -f $ROOTDIR/GTI/GTISDK-Linux_x86_64_${GTI_REL}.tgz ]; then
		echo "Place GTI Linux x86_64 version ${GTI_REL} SDK at GTI directory"
		exit
	fi
	tar zxf $ROOTDIR/GTI/GTISDK-Linux_x86_64_${GTI_REL}.tgz
fi

# Build buildroot
cd $ROOTDIR/build/buildroot
cp $ROOTDIR/configs/buildroot_defconfig .config
make

export CROSS_COMPILE=$ROOTDIR/build/buildroot/output/host/bin/aarch64-linux-


# Build GTI PCIe drivers
cd $ROOTDIR/build/GTISDK-Linux_x86_64_${GTI_REL}/Drivers/Linux/pcie_drv
KERNELDIR=$ROOTDIR/build/linux-imx make

# Build GTI liteDemo
cd $ROOTDIR/build/GTISDK-Linux_aarch64_${GTI_REL}/Apps/liteDemo
export GTI_CC=$ROOTDIR/build/buildroot/output/host/bin/aarch64-linux-g++
export CPU_ARCH=aarch64
make

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
dd if=/dev/zero of=tmp/part1.fat32 bs=1M count=48
mkdosfs tmp/part1.fat32
mcopy -i tmp/part1.fat32 $ROOTDIR/build/linux-imx/arch/arm64/boot/Image ::/Image
mcopy -s -i tmp/part1.fat32 $ROOTDIR/build/linux-imx/arch/arm64/boot/dts/freescale/*imx8mm*.dtb ::/
mcopy -i tmp/part1.fat32 $ROOTDIR/build/GTISDK-Linux_aarch64_${GTI_REL}/Apps/liteDemo/liteDemo ::/
mcopy -i tmp/part1.fat32 $ROOTDIR/build/GTISDK-Linux_x86_64_${GTI_REL}/Drivers/Linux/pcie_drv/gti_pcie_drv.ko ::/
mcopy -i tmp/part1.fat32 $ROOTDIR/build/GTISDK-Linux_aarch64_${GTI_REL}/Apps/Models/2803/gti_resnet18_2803.model ::/
mcopy -i tmp/part1.fat32 $ROOTDIR/build/GTISDK-Linux_aarch64_${GTI_REL}/Apps/Data/Image_lite/swimming_c40.jpg ::/
mcopy -i tmp/part1.fat32 $ROOTDIR/build/GTISDK-Linux_aarch64_${GTI_REL}/Lib/Linux/aarch64/libftd3xx.so ::/

dd if=/dev/zero of=microsd.img bs=1M count=121
dd if=$ROOTDIR/build/imx-mkimage/iMX8M/flash.bin of=microsd.img bs=1K seek=33 conv=notrunc
parted --script microsd.img mklabel msdos mkpart primary 2MiB 50MiB mkpart primary 50MiB 120MiB
dd if=tmp/part1.fat32 of=microsd.img bs=1M seek=2 conv=notrunc
dd if=$ROOTDIR/build/buildroot/output/images/rootfs.ext2 of=microsd.img bs=1M seek=50 conv=notrunc
echo -e "\n\n*** Image is ready - images/microsd.img"
