#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Requirements:
# - curl
# - gpg
# - guestfs-tools
# - openssl
# - qemu-system-aarch64

set -eu

readonly archive_name=ArchLinuxARM-rpi-aarch64-latest.tar.gz
readonly combined_image_name=initial_install.img
readonly boot_image_name=esp.vfat.img
readonly build_image_name=build.img
readonly build_data_image_name=build_data.img
readonly root_image_name=root.ext4.img
readonly signing_key=68B3537F39A313B3E574D06777193F152BDBE6A6
readonly pki_key_name=nonlinear-labs.key.pem
readonly pki_cert_name=nonlinear-labs.cert.pem
readonly pki_cert_subj="/O=Nonlinear-Labs/CN=nonlinear-labs-device"
readonly rauc_bundle_dir=rauc_bundle

readonly BUILD_DISK_START_SECTOR=512
readonly COMBINED_DISK_START_SECTOR=8192
readonly PARTITION_GAP_SECTOR=1
readonly DISK_ADDITIONAL_SECTOR=512
readonly SECTOR_SIZE=512
readonly MEBIBYTE_TO_BYTE=1048576
readonly MEBIBYTE_BOOT_PART_SINGLE=256
readonly MEBIBYTE_BOOT_PART_COMBINED=512
readonly MEBIBYTE_BUILD_DATA=4096
readonly MEBIBYTE_ROOT_PART_SINGLE=2560

src_dir="$(dirname "${0}")"
export CUSTOM_BUILD_DIR="$src_dir/../custom_build"
working_dir="$(mktemp -dt create_image.XXXXXXXXXX)"
boot_part_guid="$(uuidgen)"
root_a_guid="$(uuidgen)"
root_a_part_guid="$(uuidgen)"
root_b_part_guid="$(uuidgen)"

build_boot_partition_sector_start=$BUILD_DISK_START_SECTOR
# NOTE: we substract a sector, as it will be added by fdisk automatically...
build_boot_partition_sector_end=$((
  build_boot_partition_sector_start + ((MEBIBYTE_BOOT_PART_SINGLE * MEBIBYTE_TO_BYTE) / SECTOR_SIZE) - 1
))
build_root_partition_sector_start=$(( build_boot_partition_sector_end + PARTITION_GAP_SECTOR ))
# NOTE: we substract a sector, as it will be added by fdisk automatically...
build_root_partition_sector_end=$((
  build_root_partition_sector_start + (((MEBIBYTE_ROOT_PART_SINGLE * MEBIBYTE_TO_BYTE)) / SECTOR_SIZE) - 1
))

combined_boot_partition_sector_start=$COMBINED_DISK_START_SECTOR
combined_boot_partition_sector_end=$((
  combined_boot_partition_sector_start + PARTITION_GAP_SECTOR + ((MEBIBYTE_BOOT_PART_COMBINED * MEBIBYTE_TO_BYTE) / SECTOR_SIZE)
))
root_a_partition_sector_start=$(( combined_boot_partition_sector_end + PARTITION_GAP_SECTOR ))
root_a_partition_sector_end=$((
  root_a_partition_sector_start + ((MEBIBYTE_ROOT_PART_SINGLE * MEBIBYTE_TO_BYTE) / SECTOR_SIZE)
))
root_b_partition_sector_start=$(( root_a_partition_sector_end + PARTITION_GAP_SECTOR ))
root_b_partition_sector_end=$((
  root_b_partition_sector_start + ((MEBIBYTE_ROOT_PART_SINGLE * MEBIBYTE_TO_BYTE) / SECTOR_SIZE)
))

login_timeout="${QEMU_LOGIN_TIMEOUT:-60}"
fifo_guest_in="${working_dir}/guest.in"
fifo_guest_out="${working_dir}/guest.out"

export HOST_ROOTFS_DIR="$src_dir/../rootfs/"
export PKI_CERT_NAME="$pki_cert_name"
export PKI_CERT_PATH="$pki_cert_name"
export ARCHIVE_NAME="$archive_name"

# exports for build image (boot + root)
export BUILD_IMAGE_NAME="$build_image_name"
export BUILD_BOOT_PARTITION_SECTOR_START="$build_boot_partition_sector_start"
export BUILD_BOOT_PARTITION_SECTOR_END="$build_boot_partition_sector_end"
export BUILD_BOOT_PART_GUID="$boot_part_guid"
export BUILD_ROOT_PARTITION_SECTOR_START="$build_root_partition_sector_start"
export BUILD_ROOT_PARTITION_SECTOR_END="$build_root_partition_sector_end"
export BUILD_ROOT_GUID="$root_a_guid"
export BUILD_ROOT_PART_GUID="$root_a_part_guid"
export BUILD_DISK_BYTES="$(((build_root_partition_sector_end + DISK_ADDITIONAL_SECTOR) * SECTOR_SIZE))"

# exports for build data image
export BUILD_DATA_IMAGE_NAME="$build_data_image_name"
export BUILD_DATA_DISK_BYTES="$(( MEBIBYTE_BUILD_DATA * MEBIBYTE_TO_BYTE ))"

# exports for single root image
export ROOT_IMAGE_NAME="$root_image_name"
export SINGLE_ROOT_GUID="$root_a_guid"
export SINGLE_ROOT_PART_GUID="$root_a_part_guid"
export ROOT_DISK_BYTES="$(((MEBIBYTE_ROOT_PART_SINGLE * MEBIBYTE_TO_BYTE) + 512))"

# exports for single boot image
export BOOT_IMAGE_NAME="$boot_image_name"
export BOOT_PART_GUID="$boot_part_guid"
export BOOT_DISK_BYTES="$((MEBIBYTE_BOOT_PART_SINGLE * MEBIBYTE_TO_BYTE))"

# exports for combined disk image
export COMBINED_IMAGE_NAME="$combined_image_name"
export COMBINED_BOOT_PARTITION_SECTOR_START="$combined_boot_partition_sector_start"
export COMBINED_BOOT_PARTITION_SECTOR_END="$combined_boot_partition_sector_end"
export ROOT_A_PART_GUID="$root_a_part_guid"
export ROOT_A_PARTITION_SECTOR_START="$root_a_partition_sector_start"
export ROOT_A_PARTITION_SECTOR_END="$root_a_partition_sector_end"
export ROOT_B_PART_GUID="$root_b_part_guid"
export ROOT_B_PARTITION_SECTOR_START="$root_b_partition_sector_start"
export ROOT_B_PARTITION_SECTOR_END="$root_b_partition_sector_end"
export COMBINED_DISK_BYTES="$(((512 + root_b_partition_sector_end) * SECTOR_SIZE))"
export BOOT_DISK_A_START_BYTES=0
export BOOT_DISK_B_START_BYTES="$((
  (((MEBIBYTE_BOOT_PART_SINGLE * MEBIBYTE_TO_BYTE) / SECTOR_SIZE) + PARTITION_GAP_SECTOR) * SECTOR_SIZE
))"

if [[ -n "${DEBUG:-}" ]]; then
  export LIBGUESTFS_DEBUG=1
fi

cleanup_working_dir() {
  printf "Cleaning up working dir %s...\n" "$working_dir"

  if mount | grep "${working_dir}" > /dev/null; then
    guestunmount "${working_dir}"
  fi

  if [[ -d "${working_dir}" ]]; then
    rm -rf -- "${working_dir}"
  fi
}

download_archive() {
  if [[ ! -f "$archive_name" ]]; then
    printf "Downloading %s...\n" "$archive_name"
    curl -Ls -o "$archive_name" "http://os.archlinuxarm.org/os/$archive_name"
  else
    printf "Skipping the download of %s as it is already there...\n" "$archive_name"
  fi
  if [[ ! -f "${archive_name}.sig" ]]; then
    printf "Downloading %s...\n" "${archive_name}.sig"
    curl -Ls -o "${archive_name}.sig" "http://os.archlinuxarm.org/os/${archive_name}.sig"
  else
    printf "Skipping the download of %s as it is already there...\n" "${archive_name}.sig"
  fi

  if ! gpg --list-keys "$signing_key" &> /dev/null; then
    printf "Receiving PGP signing key %s...\n" "$signing_key"
    gpg --recv-keys "$signing_key"
  fi

  printf "Validating %s with PGP signing key %s...\n" "$archive_name" "$signing_key"
  gpg --verify "${archive_name}.sig" &> /dev/null
}

create_build_disk() {
  printf "Create a disk image for updating a root disk and building software...\n"

  if [[ ! -f "${build_image_name}" ]]; then
    "$src_dir/build_disk.sh"
    run_qemu "${build_image_name}"
    provision_vm
  else
    printf "Skip creation of %s...\n" "${build_image_name}"
  fi
}

create_boot_image() {
  if [[ ! -f "${boot_image_name}" ]]; then
    printf "Create a boot disk image...\n"
    "$src_dir/boot_disk.sh"
  else
    printf "Skip creation of %s...\n" "${boot_image_name}"
  fi
}

create_root_image() {
  if [[ ! -f "${root_image_name}" ]]; then
    printf "Create a root disk image...\n"
    "$src_dir/root_disk.sh"
  else
    printf "Skip creation of %s...\n" "${root_image_name}"
  fi
}

create_combined_image() {
  if [[ ! -f "${combined_image_name}" ]]; then
    printf "Create a root disk image...\n"
    "$src_dir/combined_disk.sh"
  else
    printf "Skip creation of %s...\n" "${combined_image_name}"
  fi
}

run_qemu() {
  local image_name="$1"
  local build_disk="${2:-}"

  local qemu_options=(
    -machine "type=virt,accel=kvm:tcg"
    -smp 8
    -m 8192
    -cpu cortex-a72
    -drive "if=pflash,media=disk,format=raw,cache=writethrough,file=${working_dir}/flash0.img"
    -drive "if=pflash,media=disk,format=raw,cache=writethrough,file=${working_dir}/flash1.img"
    -drive "if=none,file=${image_name},format=raw,id=hd0"
    -device "virtio-scsi-pci,id=scsi0"
    -device "scsi-hd,bus=scsi0.0,drive=hd0,bootindex=1"
    -device "VGA,id=vga1"
    -device "secondary-vga,id=vga2"
    -nic "user,model=virtio-net-pci,hostfwd=tcp::60022-:22"
    -monitor none
    -nographic
    -serial "pipe:${working_dir}/guest"
  )

  if [[ -n "${build_disk}" ]]; then
    qemu_options+=(
      -drive "if=none,file=${build_disk},format=raw,id=hd1"
      -device "virtio-scsi-pci,id=scsi1"
      -device "scsi-hd,bus=scsi1.0,drive=hd1,bootindex=2"
    )
  fi

  printf "Preparing UEFI firmware...\n"
  truncate -s 64M "${working_dir}/flash0.img"
  truncate -s 64M "${working_dir}/flash1.img"
  dd if=/usr/share/edk2-armvirt/aarch64/QEMU_CODE.fd of="${working_dir}/flash0.img" conv=notrunc

  printf "Creating named pipes to communicate with QEMU...\n"
  mkfifo "${fifo_guest_out}" "${fifo_guest_in}"

  printf "Starting QEMU virtual machine...\n"
  {
    qemu-system-aarch64 "${qemu_options[@]}" || kill "${$}" ;
  } &

  # send the output from QEMU to fd3 and fd10 (the latter is used for the expect function)
  exec 3>&1 10< <(tee /dev/fd/3 < "${fifo_guest_out}")
}

expect() {
  local length="${#1}"
  local i=0
  local timeout="${2:-30}"
  # We can't use ex: grep as we could end blocking forever, if the string isn't followed by a newline
  while true; do
    # read should never exit with a non-zero exit code,
    # but it can happen if the fd is EOF or it times out
    IFS= read -r -u 10 -n 1 -t "${timeout}" c
    if [[ "${1:${i}:1}" = "${c}" ]]; then
      i="$((i + 1))"
      if [[ "${length}" -eq "${i}" ]]; then
        printf "The timeout of %s has been reached, aborting...\n" "$timeout"
        break
      fi
    else
      i=0
    fi
  done
  printf "Expected exit...\n"
}

# Send string to qemu
send() {
  echo -en "${1}" > "${fifo_guest_in}"
}

provision_vm() {
  expect "alarm login:" "${login_timeout}"
  send "root\n"
  expect "Password: "
  send "root\n"
  expect "[root@alarm ~]# "
  send "trap \"systemctl poweroff -i\" ERR\n"
  expect "[root@alarm ~]# "
  send "mount /dev/sda1 /boot\n"
  expect "[root@alarm ~]# "
  # TODO: adapt to slower machines
  send "pacman-key --init\n"
  expect "[root@alarm ~]# "
  send "pacman-key --populate archlinuxarm\n"
  expect "[root@alarm ~]# "
  send "pacman -Syu --needed --noconfirm casync git openssl-1.1 pacman-contrib rauc uboot-tools\n"
  expect "[root@alarm ~]# " 600
  send "paccache -rk0\n"
  expect "[root@alarm ~]# "
  send "systemctl enable auditd rauc\n"
  expect "[root@alarm ~]# "
  send "systemctl poweroff -i\n"
  wait
  rm -fv -- "${fifo_guest_in}"
  rm -fv -- "${fifo_guest_out}"
}

create_pki() {
  local openssl_options=(
    req -x509
    -newkey rsa:4096
    -nodes
    -keyout "${pki_key_name}"
    -out "${pki_cert_name}"
    -subj "${pki_cert_subj}"
  )

  if [[ ! -f "${pki_key_name}" || ! -f "${pki_cert_name}" ]]; then
    printf "Create Personal Key Infrastructure (PKI)...\n"
    openssl "${openssl_options[@]}"
  else
    printf "Skip creation of Personal Key Infrastructure (PKI) as it is already there...\n"
  fi
}

create_build_data_image() {
  printf "Create a build data disk image...\n"

  if [[ ! -f "${build_data_image_name}" ]]; then
    "$src_dir/build_data_disk.sh"
  else
    printf "Skip creation of %s...\n" "${build_data_image_name}"
  fi
}

build_custom_projects() {
  printf "Build custom projects...\n"

  run_qemu "${build_image_name}" "${build_data_image_name}"

  expect "alarm login:" "${login_timeout}"
  send "root\n"
  expect "Password: "
  send "root\n"
  expect "[root@alarm ~]# "
  send "trap \"systemctl poweroff -i\" ERR\n"
  expect "[root@alarm ~]# "
  send "mount /dev/sda1 /boot\n"
  expect "[root@alarm ~]# "
  send "mount /dev/sdb /mnt\n"
  expect "[root@alarm ~]# "
  send "/mnt/custom_build/build.sh\n"
  expect "[root@alarm ~]# " 1800
  send "systemctl poweroff -i\n"
  wait
  rm -fv -- "${fifo_guest_in}"
  rm -fv -- "${fifo_guest_out}"
}

create_update_bundle() {
  local rauc_bundle_version
  rauc_bundle_version="$(date +%Y.%m.%d)"
  local rauc_bundle_name="nonlinear-labs-update-$rauc_bundle_version.raucb"

  local rauc_bundle_options=(
    --cert="$pki_cert_name"
    --key="$pki_key_name"
    "$rauc_bundle_dir"
    "$rauc_bundle_name"
  )

  if [[ ! -f "$rauc_bundle_name" ]]; then
    printf "Create a RAUC update bundle...\n"
    mkdir -vp -- "$rauc_bundle_dir"
    printf "Copy images to bundle dir %s...\n" "$rauc_bundle_dir"
    cp -v -- "$boot_image_name" "$root_image_name" "$rauc_bundle_dir"
    printf "Write RAUC manifest...\n"
    {
      printf "[update]\n"
      printf "compatible=nonlinear-labs\n"
      printf "version=%s\n" "$rauc_bundle_version"
      printf "\n"
      printf "[bundle]\n"
      printf "format=verity\n"
      printf "\n"
      printf "[image.rootfs]\n"
      printf "filename=%s\n" "$root_image_name"
      printf "\n"
      printf "[image.esp]\n"
      printf "filename=%s\n" "$boot_image_name"
    } > "$rauc_bundle_dir/manifest.raucm"
    printf "Create update bundle...\n"
    rauc bundle "${rauc_bundle_options[@]}"
    rm -frv -- "$rauc_bundle_dir"
  else
    printf "Skipping RAUC bundle creation...\n"
  fi
}

trap cleanup_working_dir EXIT

download_archive
create_pki
create_build_disk
create_build_data_image
build_custom_projects
create_root_image
create_boot_image
create_combined_image
create_update_bundle
