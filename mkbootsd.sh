#!/bin/bash

TOPDIR=$PWD

KERNEL_CONFIG=kernel-config

A1X_SCRIPT=script.bin-720p50

ROOTFS=http://releases.linaro.org/13.05/ubuntu/raring-images/nano/linaro-raring-nano-20130526-380.tar.gz

CROSS_COMPILE=arm-linux-gnueabihf-

DEVICE=

error() {
    echo "Error $@"
    exit 1
}

check_compiler() {
    local COMPILER=`which ${CROSS_COMPILE}gcc`
    if [ "$COMPILER" = "" ]; then
	echo "Crosscompiler missed, install it:"
	echo
	echo "sudo apt-get install gcc-arm-linux-gnueabihf"
	echo
	echo "or setup crossprefix with --toolchain, for example for"
	echo "CodeSourcery ARM toolchain:"
	echo
	echo "--toolchain arm-none-linux-gnueabi-"
	echo
	echo "More about cross-compilation tools:"
	echo "https://wiki.linaro.org/Platform/DevPlatform/CrossCompile/CrossbuildingQuickStart"
	exit 1
    fi
}

check_mkimage() {
    local MKIMAGE=`which mkimage`
    if [ "$MKIMAGE" = "" ]; then
	echo "U-Boot mkimage utility missed, install it:"
	echo
	echo "sudo apt-get install u-boot-tools"
	echo
	exit 1
    fi
}

clean_dir() {
    echo "Cleaning..."
    echo
    echo "Removing rootfs files, root access required."
    echo
    sudo rm -rf kernel-out binary
    cd linux-sunxi
    make CROSS_COMPILE=$CROSS_COMPILE ARCH=arm distclean || error
    cd ..
#    cd ../u-boot-sunxi
#    make distclean CROSS_COMPILE=$CROSS_COMPILE || error
    exit 0
}

show_help() {
    echo "Usage:"
    echo "./mkbootsd.sh --device <SD card device>"
    echo "             [--kernel-config <kernel config>             |"
    echo "              --script <a1x config script>                |"
    echo "              --rootfs <packed linaro rootfs file or url> |"
    echo "              --toolchain <arm toolchain prefix>          |"
    echo "              --clean                                     |"
    echo "              --dist                                      |"
    echo "              --help]"
    echo
    echo "Required mkimage u-boot utility and arm crosscompiler. Ubuntu"
    echo "packages u-boot-tools, gcc-arm-linux-gnueabihf."
    echo
    echo "More about cross-compilation tools:"
    echo "https://wiki.linaro.org/Platform/DevPlatform/CrossCompile/CrossbuildingQuickStart"
    exit 0
}

make_dist() {
    mkdir -p a1x-mkbootsd
    cp mkbootsd.sh    a1x-mkbootsd/
    cp kernel-config* a1x-mkbootsd/
    cp script.bin*    a1x-mkbootsd/
    cp -R precompiled a1x-mkbootsd/
    tar zcf a1x-mkbootsd-`date +%Y%m%d%H%M%S`.tar.gz a1x-mkbootsd
    rm -rf a1x-mkbootsd
    exit 0
}

while [[ "$1" =~ (^-.*) ]]; do
    case "$1" in
    --device|-d)
	shift
	DEVICE=$1
	;;
    --kernel-config|-k)
	shift
	KERNEL_CONFIG=$1
	;;
    --script|-s)
	shift
	A1X_SCRIPT=$1
	;;
    --rootfs|-r)
	shift
	ROOTFS=$1
	;;
    --toolchain|-t)
	shift
	CROSS_COMPILE=$1
	;;
    --clean|-c)
	clean_dir
	;;
    --dist|-b)
	make_dist
	;;
    --help|-h)
	show_help
	;;
    *)
	error "Unknown option $1"
	;;
    esac
    shift
done

check_compiler
check_mkimage

if [[ "$DEVICE" =~ (^\/dev)  ]]; then
    if [ -e "$DEVICE" ]; then
	if [[ "$DEVICE" =~ (.*[0-9]) ]]; then
	    error "Device required, not partition."
	else
	    REMOVABLE=`cat /sys/block/${DEVICE/*\/}/removable`
	    if [ "$REMOVABLE" != "1" ]; then
		error "$DEVICE is not removable."
	    else

		echo
		echo "Preparing bootable device, root access required!"
		echo

		for f in "${DEVICE}"*; do
		    if [ "$f" = "$DEVICE" ]; then
			continue
		    fi
		    cat /proc/mounts | grep -q "$f" && sudo umount -l "$f"
		    sudo parted -s $DEVICE rm ${f/$DEVICE} || error "Create partition."
		done
		DISK_SIZE=`sudo parted ${DEVICE} unit s print | grep ${DEVICE}: | cut -f2 -d':'`
		sudo parted -s $DEVICE mklabel msdos
		sudo parted -s $DEVICE mkpart primary 2048s 34815s
		sudo parted -s $DEVICE mkpart primary 34816s "$((${DISK_SIZE/s} - 1))s"
		sudo mkfs.vfat ${DEVICE}1
		sudo mkfs.ext4 ${DEVICE}2
		sudo parted -s $DEVICE print
	    fi
	fi
    else
	error "Device $DEV is not found."
    fi
else
    error "Device name must start with /dev prefix."
fi

echo
echo "Compiling A1X kernel and modules"
echo

if test -d linux-sunxi; then
    cd linux-sunxi
    git pull
else
    git clone https://github.com/linux-sunxi/linux-sunxi.git || error
    cd linux-sunxi
fi

cp ../$KERNEL_CONFIG .config

make CROSS_COMPILE=$CROSS_COMPILE ARCH=arm oldconfig || error
make CROSS_COMPILE=$CROSS_COMPILE ARCH=arm -j4 uImage || error
make CROSS_COMPILE=$CROSS_COMPILE ARCH=arm -j4 modules || error
make CROSS_COMPILE=$CROSS_COMPILE ARCH=arm INSTALL_MOD_PATH=${TOPDIR}/kernel-out modules_install || error

cd ..

#echo
#echo "Compiling u-boot and spl"
#echo

#if test -d u-boot-sunxi; then
#    cd u-boot-sunxi
#    git pull
#else
#    git clone https://github.com/linux-sunxi/u-boot-sunxi.git || error
#    cd u-boot-sunxi
#fi

#make mk802 CROSS_COMPILE=$CROSS_COMPILE || error

#cd ..

if [ -f "$ROOTFS" ]; then
    ROOTFS_FILE="$ROOTFS"
else
    ROOTFS_FILE=${ROOTFS/*\/}
    if [ ! -f $ROOTFS_FILE ]; then
	echo "Downloading $ROOTFS"
	wget "$ROOTFS" || error
    fi
fi

echo
echo "Installing u-boot and spl, root access required!"
echo

#sudo dd if=u-boot-sunxi/spl/sunxi-spl.bin of=$DEVICE bs=1024 seek=8  || error
#sudo dd if=u-boot-sunxi/u-boot.bin        of=$DEVICE bs=1024 seek=32 || error

sudo dd if=precompiled/sunxi-spl.bin of=$DEVICE bs=1024 seek=8  || error
sudo dd if=precompiled/u-boot.bin    of=$DEVICE bs=1024 seek=32 || error

echo
echo "Installing kernel and scripts, root access required!"
echo

MNT_DIR=`echo /tmp/mnt.$$`

mkdir -p $MNT_DIR || error

sudo mount ${DEVICE}1 $MNT_DIR || error
sudo cp -f "$A1X_SCRIPT" ${MNT_DIR}/script.bin || error
sudo cp -f "$A1X_SCRIPT" ${MNT_DIR}/evb.bin || error
sudo cp -f linux-sunxi/arch/arm/boot/uImage ${MNT_DIR}/ || error
sudo umount ${DEVICE}1 || error

echo
echo "Unpacking rootfs, root access required!"
echo

case $ROOTFS_FILE in
*.tar.gz|*.tgz)
    sudo tar zxf $ROOTFS_FILE || error
    ;;
*.tar.bz2|*.tbz)
    sudo tar jxf $ROOTFS_FILE || error
    ;;
*)
    error "Can not unpack rootfs."
    ;;
esac

echo
echo "Installing rootfs and modules, root access required!"
echo

sudo mount ${DEVICE}2 $MNT_DIR || error
sudo cp -ax binary/. ${MNT_DIR}/ || error
sudo cp -R kernel-out/. ${MNT_DIR}/ || error
sudo cp -R /lib/firmware/rtlwifi ${MNT_DIR}/lib/firmware/ || error
sudo umount ${DEVICE}2 || error

echo "Done"
