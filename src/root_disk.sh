#!/usr/bin/guestfish -f
# shellcheck disable=SC1000-SC9999
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Create a root image by copying the root partition from the build image

! printf "Create single root disk %s (%i bytes)...\n" "$ROOT_IMAGE_NAME" "$ROOT_DISK_BYTES"
<! printf "disk-create %s raw %i\n" "$ROOT_IMAGE_NAME" "$ROOT_DISK_BYTES"
<! printf "add-drive %s format:raw\n" "$ROOT_IMAGE_NAME"

! printf "Add build disk %s...\n" "$BUILD_IMAGE_NAME"
<! printf "add-drive %s format:raw\n" "$BUILD_IMAGE_NAME"

launch

! printf "Initialize device /dev/sda...\n"
part-init /dev/sda gpt
part-list /dev/sda

# write root to blockdevice directly
! printf "Copy root image from build disk and write directly to block device...\n"
<! printf "copy-device-to-device /dev/sdb2 /dev/sda\n"

! printf "Mount root image...\n"
mount /dev/sda /

! printf "Add RAUC configuration...\n"
mkdir-p /etc/rauc/
<! printf "upload %s/etc/rauc/system.conf /etc/rauc/system.conf\n" "$HOST_ROOTFS_DIR"
! printf "Install RAUC PKI cert...\n"
<! printf "upload %s /etc/rauc/%s\n" "$PKI_CERT_PATH" "$PKI_CERT_NAME"

! printf "Add configuration for fw_setenv/ fw_printenv...\n"
<! printf "upload %s/etc/fw_env.config /etc/fw_env.config\n" "$HOST_ROOTFS_DIR"

! printf "Add systemd units...\n"
mkdir-p /etc/systemd/system/app.target.wants/
mkdir-p /etc/systemd/system/multi-user.target.wants/
<! printf "upload %s/etc/systemd/system/app.target /etc/systemd/system/app.target\n" "$HOST_ROOTFS_DIR"
<! printf "upload %s/etc/systemd/system/app.service /etc/systemd/system/app.service\n" "$HOST_ROOTFS_DIR"
<! printf "upload %s/etc/systemd/system/rauc-mark-good.service /etc/systemd/system/rauc-mark-good.service\n" "$HOST_ROOTFS_DIR"
ln-s /etc/systemd/system/app.service /etc/systemd/system/app.target.wants/app.service
ln-s /etc/systemd/system/rauc-mark-good.service /etc/systemd/system/multi-user.target.wants/rauc-mark-good.service

! printf "Unmount all mounts...\n"
umount-all
