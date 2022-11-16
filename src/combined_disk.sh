#!/usr/bin/guestfish -f
# shellcheck disable=SC1000-SC9999
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Create a combined image by copying the single boot and root images to their respective A/B partitions

! printf "Create combined system image %s of size %s bytes...\n" "$COMBINED_IMAGE_NAME" "$COMBINED_DISK_BYTES"
<! printf "disk-create %s raw %s\n" "$COMBINED_IMAGE_NAME" "$COMBINED_DISK_BYTES"
<! printf "add-drive %s format:raw\n" "$COMBINED_IMAGE_NAME"

! printf "Add boot disk %s...\n" "$BOOT_IMAGE_NAME"
<! printf "add-drive %s format:raw\n" "$BOOT_IMAGE_NAME"

! printf "Add root disk %s...\n" "$ROOT_IMAGE_NAME"
<! printf "add-drive %s format:raw\n" "$ROOT_IMAGE_NAME"

launch

! printf "Initialize main device...\n"
part-init /dev/sda gpt
part-list /dev/sda

# add combined boot partition
!printf "Create combined boot partition from sector %i to sector %i...\n" "$COMBINED_BOOT_PARTITION_SECTOR_START" "$COMBINED_BOOT_PARTITION_SECTOR_END"
<! printf "part-add /dev/sda p %i %i\n" "$COMBINED_BOOT_PARTITION_SECTOR_START" "$COMBINED_BOOT_PARTITION_SECTOR_END"
!printf "Set GPT partition type BC13C2FF-59E6-4262-A352-B275FD6F7172 for combined boot partition...\n"
part-set-gpt-type /dev/sda 1 BC13C2FF-59E6-4262-A352-B275FD6F7172
!printf "Set bootable flag for combined boot partition...\n"
part-set-bootable /dev/sda 1 true

# add root partition (A)
!printf "Create root A partition from sector %i to sector %i...\n" "$ROOT_A_PARTITION_SECTOR_START" "$ROOT_A_PARTITION_SECTOR_END"
<! printf "part-add /dev/sda p %s %s\n" "$ROOT_A_PARTITION_SECTOR_START" "$ROOT_A_PARTITION_SECTOR_END"
!printf "Add GUID %s to partition...\n" "$ROOT_A_PART_GUID"
<! printf "part-set-gpt-guid /dev/sda 2 %s\n" "$ROOT_A_PART_GUID"
!printf "Set GPT partition type B921B045-1DF0-41C3-AF44-4C6F280D3FAE for root partition (A)...\n"
part-set-gpt-type /dev/sda 2 B921B045-1DF0-41C3-AF44-4C6F280D3FAE

# add root partition (B)
!printf "Create root B partition from sector %i to sector %i...\n" "$ROOT_B_PARTITION_SECTOR_START" "$ROOT_B_PARTITION_SECTOR_END"
<! printf "part-add /dev/sda p %s %s\n" "$ROOT_B_PARTITION_SECTOR_START" "$ROOT_B_PARTITION_SECTOR_END"
!printf "Add GUID %s to partition...\n" "${ROOT_B_PART_GUID}"
<! printf "part-set-gpt-guid /dev/sda 3 %s\n" "$ROOT_B_PART_GUID"
!printf "Set GPT partition type B921B045-1DF0-41C3-AF44-4C6F280D3FAE for root partition (B)...\n"
part-set-gpt-type /dev/sda 3 B921B045-1DF0-41C3-AF44-4C6F280D3FAE

# copy partitions
! printf "Copy single boot image to A slot in combined boot partition with %i bytes offset...\n" "$BOOT_DISK_A_START_BYTES"
<! printf "copy-device-to-device /dev/sdb /dev/sda1 destoffset:%i\n" "$BOOT_DISK_A_START_BYTES"

! printf "Copy single boot image to B slot in combined boot partition with %i bytes offset...\n" "$BOOT_DISK_B_START_BYTES"
<! printf "copy-device-to-device /dev/sdb /dev/sda1 destoffset:%i\n" "$BOOT_DISK_B_START_BYTES"

! printf "Copy root image to A slot partition...\n"
<! printf "copy-device-to-device /dev/sdc /dev/sda2\n"
! printf "Copy root image to B slot partition...\n"
<! printf "copy-device-to-device /dev/sdc /dev/sda3\n"
