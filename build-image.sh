#!/bin/sh

# Exit if any error occurs
set -e

PrintMessage()
{
	printf "\033[33m--> $1\033[0m\n"
}

BUILDROOT_VERSION=2021.02.7

# Check arguments
if [ $# -ne 3 ]
then
	echo "Usage : $0 buildroot_defconfig_name libc_name output_directory"
	echo "  buildroot_defconfig_name : see all available defconfigs here https://git.busybox.net/buildroot/tree/configs?h=${BUILDROOT_VERSION}"
	echo "  libc_name : must be \"glibc\", \"uclibc\" or \"musl\""
	echo "  output_directory : will contain the build directory and the final compressed artifacts"
	exit 1
fi
DEFCONFIG_NAME="$1"
LIBC_NAME="$2"
OUTPUT_DIRECTORY="$3"

# Create the build directory name
BUILD_DIRECTORY_NAME="buildroot-${DEFCONFIG_NAME}-${LIBC_NAME}"
BUILD_DIRECTORY_PATH=$(realpath "${OUTPUT_DIRECTORY}")/"${BUILD_DIRECTORY_NAME}"

PrintMessage "Removing previous build artifacts..."
rm -rf "${BUILD_DIRECTORY_PATH}"

PrintMessage "Downloading Buildroot sources..."
git clone --depth=1 --branch="${BUILDROOT_VERSION}" https://github.com/buildroot/buildroot "${BUILD_DIRECTORY_PATH}"

PrintMessage "Modifying the radvd Buildroot package to use upstream sources..."
RADVD_PACKAGE_PATH="${BUILD_DIRECTORY_PATH}/package/radvd"
# Do not check for package hash, so there is no need to compute it
rm "${RADVD_PACKAGE_PATH}/radvd.hash"
# Get the package sources from the head of the master branch
# Get package sources from head of master branch
LAST_COMMIT_HASH=$(curl -s -H "Accept: application/vnd.github.VERSION.sha" "https://api.github.com/repos/radvd-project/radvd/commits/master")
sed -i "/RADVD_VERSION =/c\\RADVD_VERSION = ${LAST_COMMIT_HASH}" "${RADVD_PACKAGE_PATH}/radvd.mk"
sed -i '/RADVD_SITE =/c\\RADVD_SITE = https://github.com/radvd-project/radvd' "${RADVD_PACKAGE_PATH}/radvd.mk"
sed -i '9iRADVD_SITE_METHOD = git' "${RADVD_PACKAGE_PATH}/radvd.mk"
# Autotools "configure" script is missing, tell Buildroot to generate it before building
sed -i '18iRADVD_AUTORECONF = YES' "${RADVD_PACKAGE_PATH}/radvd.mk"
# Newer versions of radvd require the BSD string functions (using "select BR2_PACKAGE_LIBBSD" breaks the Buildroot configuration, so use "depends on" and manually select the BSD library in the defconfig)
sed -i '4idepends on BR2_PACKAGE_LIBBSD' "${RADVD_PACKAGE_PATH}/Config.in"

PrintMessage "Enabling radvd build in Buildroot configuration..."
echo "BR2_PACKAGE_RADVD=y" >> "${BUILD_DIRECTORY_PATH}/configs/${DEFCONFIG_NAME}"
echo "BR2_PACKAGE_LIBBSD=y" >> "${BUILD_DIRECTORY_PATH}/configs/${DEFCONFIG_NAME}"

PrintMessage "Selecting the ${LIBC_NAME} C library..."
case $LIBC_NAME in
	"glibc")
		echo "BR2_TOOLCHAIN_BUILDROOT_GLIBC=y" >> "${BUILD_DIRECTORY_PATH}/configs/${DEFCONFIG_NAME}"
		;;
	"uclibc")
		echo "BR2_TOOLCHAIN_BUILDROOT_UCLIBC=y" >> "${BUILD_DIRECTORY_PATH}/configs/${DEFCONFIG_NAME}"
		;;
	"musl")
		echo "BR2_TOOLCHAIN_BUILDROOT_MUSL=y" >> "${BUILD_DIRECTORY_PATH}/configs/${DEFCONFIG_NAME}"
		;;
	*)
		echo "Unknown C library, please specify \"glibc\", \"uclibc\" or \"musl\"."
		exit 1
		;;
esac

PrintMessage "Generating the Buildroot configuration..."
cd "${BUILD_DIRECTORY_PATH}"
make "${DEFCONFIG_NAME}"

PrintMessage "Building the Buildroot image..."
make
