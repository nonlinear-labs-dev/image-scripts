#!/usr/bin/guestfish -f
# shellcheck disable=SC1000-SC9999
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Create a data disk for building software in

! printf "Create build data disk %s (%i bytes)...\n" "$BUILD_DATA_IMAGE_NAME" "$BUILD_DATA_DISK_BYTES"
<! printf "disk-create %s raw %i\n" "$BUILD_DATA_IMAGE_NAME" "$BUILD_DATA_DISK_BYTES"
<! printf "add-drive %s format:raw\n" "$BUILD_DATA_IMAGE_NAME"

launch

! printf "Initialize device /dev/sda...\n"
part-init /dev/sda gpt
part-list /dev/sda

! printf "Format build data partition as ext4...\n"
mkfs ext4 /dev/sda

! printf "Mount build data partition...\n"
mount /dev/sda /

! printf "Copy all relevant build files...\n"
<! printf "copy-in %s /\n" "$CUSTOM_BUILD_DIR"

! printf "Create build dir...\n"
mkdir-p /build

! printf "Unmount all mounts...\n"
umount-all
