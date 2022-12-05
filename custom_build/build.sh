#!/usr/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build customized pieces of software and install them

set -eu

src_dir="$(dirname "${0}")"

readonly projects=(
  uboot-raspberrypi400
)

exists() {
  [[ -f $1 ]];
}

build_project() {
  printf "Build custom project %s...\n" "$1"
  cd "$1"
  runuser --whitelist-environment='PWD' -u alarm -- extra-aarch64-build -r /mnt/build/
}

install_project() {
  printf "Install custom project %s...\n" "$1"
  cd "$1"
  yes | pacman -U -- *.zst
}

prepare() {
  printf "Prepare system for building software using an unprivileged user...\n"
  pacman -Syu --needed --noconfirm git devtools-alarm sudo
  echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/alarm
  gpasswd -a alarm wheel
  sed 's/Mcd/Mc/' -i /usr/bin/mkarchroot
}

cleanup() {
  printf "Remove packages used for building...\n"
  pacman -Rns --noconfirm git devtools-alarm
  paccache -rk0
  printf "Remove user configuration for unprivileged user...\n"
  gpasswd -d alarm wheel
  rm -fv -- /etc/sudoers.d/alarm
}

trap cleanup EXIT

prepare

for project in "${projects[@]}"; do
  project_dir="$src_dir/$project"

  if ! exists "$project_dir/"*.zst; then
    build_project "$project_dir"
  else
    printf "Skipping build for %s...\n" "$project_dir"
  fi

  if exists "$project_dir/"*.zst; then
    install_project "$project_dir"
  fi
done
