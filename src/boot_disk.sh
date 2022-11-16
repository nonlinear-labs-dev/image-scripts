#!/usr/bin/guestfish -f
# shellcheck disable=SC1000-SC9999
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Create a boot image by copying the boot partition from the build image

! printf "Create single boot disk %s (%i bytes)...\n" "$BOOT_IMAGE_NAME" "$BOOT_DISK_BYTES"
<! printf "disk-create %s raw %i\n" "$BOOT_IMAGE_NAME" "$BOOT_DISK_BYTES"
<! printf "add-drive %s format:raw\n" "$BOOT_IMAGE_NAME"

! printf "Add build disk %s...\n" "$BUILD_IMAGE_NAME"
<! printf "add-drive %s format:raw\n" "$BUILD_IMAGE_NAME"

launch

! printf "Initialize device /dev/sda...\n"
part-init /dev/sda gpt
part-list /dev/sda

# write boot to blockdevice directly
! printf "Copy boot partition from build disk and write directly to block device...\n"
<! printf "copy-device-to-device /dev/sdb1 /dev/sda\n"

! printf "Mount boot partition to /...\n"
mount /dev/sda /

! printf "Remove unneeded startup.nsh...\n"
rm-f /startup.nsh

! printf "Unmount all mounts...\n"
umount-all
