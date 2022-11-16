#!/usr/bin/guestfish -f
# shellcheck disable=SC1000-SC9999
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Create a disk with boot and root partition, which is updated and then used
# for building software in

! printf "Create build disk %s (%i bytes)...\n" "$BUILD_IMAGE_NAME" "$BUILD_DISK_BYTES"
<! printf "disk-create %s raw %i\n" "$BUILD_IMAGE_NAME" "$BUILD_DISK_BYTES"
<! printf "add-drive %s format:raw\n" "$BUILD_IMAGE_NAME"

launch

! printf "Initialize device /dev/sda...\n"
part-init /dev/sda gpt

# add boot partition (vfat)
! printf "Create boot partition from sector %i to sector %i...\n" "$BUILD_BOOT_PARTITION_SECTOR_START" "$BUILD_BOOT_PARTITION_SECTOR_END"
<! printf "part-add /dev/sda p %i %i\n" "$BUILD_BOOT_PARTITION_SECTOR_START" "$BUILD_BOOT_PARTITION_SECTOR_END"
!printf "Add GUID %s to boot partition...\n" "$BUILD_BOOT_PART_GUID"
<! printf "part-set-gpt-guid /dev/sda 1 '%s'\n" "$BUILD_BOOT_PART_GUID"
! printf "Set GPT partition type BC13C2FF-59E6-4262-A352-B275FD6F7172 for boot partition...\n"
part-set-gpt-type /dev/sda 1 BC13C2FF-59E6-4262-A352-B275FD6F7172
! printf "Set bootable flag for boot partition...\n"
part-set-bootable /dev/sda 1 true
! printf "Format boot partition as vfat...\n"
mkfs vfat /dev/sda1
part-list /dev/sda

# add root partition (ext4)
! printf "Create root partition from sector %i to sector %i...\n" "$BUILD_ROOT_PARTITION_SECTOR_START" "$BUILD_ROOT_PARTITION_SECTOR_END"
<! printf "part-add /dev/sda p %s %s\n" "$BUILD_ROOT_PARTITION_SECTOR_START" "$BUILD_ROOT_PARTITION_SECTOR_END"
! printf "Set GUID %s for root partition...\n" "$BUILD_ROOT_PART_GUID"
<! printf "part-set-gpt-guid /dev/sda 2 %s\n" "$BUILD_ROOT_PART_GUID"
! printf "Set GPT partition type B921B045-1DF0-41C3-AF44-4C6F280D3FAE for root partition...\n"
part-set-gpt-type /dev/sda 2 B921B045-1DF0-41C3-AF44-4C6F280D3FAE
! printf "Format root partition as ext4...\n"
mkfs ext4 /dev/sda2
! printf "Set GUID %s for ext4 root partition...\n" "$BUILD_ROOT_GUID"
<! printf "set-uuid /dev/sda2 %s\n" "$BUILD_ROOT_GUID"
part-list /dev/sda

! printf "Mount root partition...\n"
mount /dev/sda2 /
! printf "Extract rootfs to root partition...\n"
<! printf "tar-in %s / compress:gzip xattrs:true acls:true\n" "${ARCHIVE_NAME}"

! printf "Move /boot directory...\n"
mv /boot /boot.old
mkdir /boot

! printf "Mount boot partition to /boot...\n"
mount /dev/sda1 /boot

! printf "Sync previous /boot contents to boot partition...\n"
rsync /boot.old/ /boot archive:true deletedest:true
rm-rf /boot.old

! printf "Create /boot/startup.nsh to allow booting with UEFI firmware...\n"
<! printf "write /boot/startup.nsh 'Image root=UUID=%s rw initrd=\\initramfs-linux.img'\n" "$BUILD_ROOT_GUID"

! printf "Remove unneeded /etc/fstab...\n"
rm-f /etc/fstab

! printf "Unmount all mounts...\n"
umount-all
