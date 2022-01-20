#!/bin/bash

echo 
echo "##########################################"
echo "### OPENSHIFT/RHCOS VERSION/URL CHECK  ###"
echo "##########################################"
echo

# OCP4 INSTALL AND CLIENT FILES

if [ "$OCP_VERSION" == "latest" -o "$OCP_VERSION" == "stable" ]; then
    urldir="$OCP_VERSION"
else
    test "$(echo $OCP_VERSION | cut -d '.' -f1)" = "4" || err "Invalid OpenShift version $OCP_VERSION"
    OCP_VER=$(echo "$OCP_VERSION" | cut -d '.' -f1-2)
    OCP_MINOR=$(echo "$OCP_VERSION" | cut -d '.' -f3-)
    test -z "$OCP_MINOR" && OCP_MINOR="stable"
    if [ "$OCP_MINOR" == "latest" -o "$OCP_MINOR" == "stable" ]
    then
        urldir="${OCP_MINOR}-${OCP_VER}"
    else
        urldir="${OCP_VER}.${OCP_MINOR}"
    fi
fi
echo -n "====> Looking up OCP4 client for release $urldir: "
CLIENT=$(curl -N --fail -qs "${OCP_MIRROR}/${urldir}/" | grep  -m1 "client-linux" | sed 's/.*href="\(openshift-.*\)">.*/\1/')
    test -n "$CLIENT" || err "No client found in ${OCP_MIRROR}/${urldir}/"; ok "$CLIENT"
CLIENT_URL="${OCP_MIRROR}/${urldir}/${CLIENT}"
echo -n "====> Checking if Client URL is downloadable: "; download check "$CLIENT" "$CLIENT_URL";

echo -n "====> Looking up OCP4 installer for release $urldir: "
INSTALLER=$(curl -N --fail -qs "${OCP_MIRROR}/${urldir}/" | grep  -m1 "install-linux" | sed 's/.*href="\(openshift-.*\)">.*/\1/')
    test -n "$INSTALLER" || err "No installer found in ${OCP_MIRROR}/${urldir}/"; ok "$INSTALLER"
INSTALLER_URL="${OCP_MIRROR}/${urldir}/${INSTALLER}"
echo -n "====> Checking if Installer URL is downloadable: ";  download check "$INSTALLER" "$INSTALLER_URL";

OCP_NORMALIZED_VER=$(echo "${INSTALLER}" | sed 's/.*-\(4\..*\)\.tar.*/\1/' )

# RHCOS KERNEL, INITRAMFS AND IMAGE FILES

if [ -z "$RHCOS_VERSION" ]; then
    RHCOS_VER=$(echo "${OCP_NORMALIZED_VER}" | cut -d '.' -f1-2 )
    RHCOS_MINOR="latest"
else
    RHCOS_VER=$(echo "$RHCOS_VERSION" | cut -d '.' -f1-2)
    RHCOS_MINOR=$(echo "$RHCOS_VERSION" | cut -d '.' -f3)
    test -z "$RHCOS_MINOR" && RHCOS_MINOR="latest"
fi

if [ "$RHCOS_MINOR" == "latest" ]
then
    urldir="$RHCOS_MINOR"
else
    urldir="${RHCOS_VER}.${RHCOS_MINOR}"
fi

echo -n "====> Looking up RHCOS kernel for release $RHCOS_VER/$urldir: "
KERNEL=$(curl -N --fail -qs "${RHCOS_MIRROR}/${RHCOS_VER}/${urldir}/" | grep -m1 "installer-kernel\|live-kernel" | sed 's/.*href="\(rhcos-.*\)">.*/\1/')
    test -n "$KERNEL" || err "No kernel found in ${RHCOS_MIRROR}/${RHCOS_VER}/${urldir}/"; ok "$KERNEL"
KERNEL_URL="${RHCOS_MIRROR}/${RHCOS_VER}/${urldir}/${KERNEL}"
echo -n "====> Checking if Kernel URL is downloadable: "; download check "$KERNEL" "$KERNEL_URL";

echo -n "====> Looking up RHCOS initramfs for release $RHCOS_VER/$urldir: "
INITRAMFS=$(curl -N --fail -qs ${RHCOS_MIRROR}/${RHCOS_VER}/${urldir}/ | grep -m1 "installer-initramfs\|live-initramfs" | sed 's/.*href="\(rhcos-.*\)">.*/\1/')
    test -n "$INITRAMFS" || err "No initramfs found in ${RHCOS_MIRROR}/${RHCOS_VER}/${urldir}/"; ok "$INITRAMFS"
INITRAMFS_URL="$RHCOS_MIRROR/${RHCOS_VER}/${urldir}/${INITRAMFS}"
echo -n "====> Checking if Initramfs URL is downloadable: "; download check "$INITRAMFS" "$INITRAMFS_URL";

# Handling case of rhcos "live" (rhcos >= 4.6)
if [[ "$KERNEL" =~ "live" && "$INITRAMFS" =~ "live" ]]; then
    RHCOS_LIVE="yes"
elif [[ "$KERNEL" =~ "installer" && "$INITRAMFS" =~ "installer" ]]; then
    RHCOS_LIVE=""
else
    err "Sorry, unhandled situation. Exiting"
fi

echo -n "====> Looking up RHCOS image for release $RHCOS_VER/$urldir: "
if [ -n "$RHCOS_LIVE" ]; then
    IMAGE=$(curl -N --fail -qs ${RHCOS_MIRROR}/${RHCOS_VER}/${urldir}/ | grep -m1 "live-rootfs" | sed 's/.*href="\(rhcos-.*.img\)".*/\1/')
else
    IMAGE=$(curl -N --fail -qs ${RHCOS_MIRROR}/${RHCOS_VER}/${urldir}/ | grep -m1 "metal" | sed 's/.*href="\(rhcos-.*.raw.gz\)".*/\1/')
fi
test -n "$IMAGE" || err "No image found in ${RHCOS_MIRROR}/${RHCOS_VER}/${urldir}/"; ok "$IMAGE"
IMAGE_URL="$RHCOS_MIRROR/${RHCOS_VER}/${urldir}/${IMAGE}"
echo -n "====> Checking if Image URL is downloadable: "; download check "$IMAGE" "$IMAGE_URL";

RHCOS_NORMALIZED_VER=$(echo "${IMAGE}" | sed 's/.*-\(4\..*\)-x86.*/\1/')

# CENTOS CLOUD IMAGE
LB_IMG="${LB_IMG_URL##*/}"
echo -n "====> Checking if Centos cloud image URL is downloadable: "; download check "$LB_IMG" "$LB_IMG_URL";


echo
echo
echo "      Red Hat OpenShift Version = $OCP_NORMALIZED_VER"
echo
echo "        Red Hat CoreOS Version = $RHCOS_NORMALIZED_VER"

check_if_we_can_continue

