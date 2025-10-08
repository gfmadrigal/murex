#!/user/bin/env bash
# murex-installer.sh - Full skeleton for Murex Linux ncurses installer
# Terminal-first, minimal, modular

set -euo pipefail

# Check for required commands
for cmd in dialog parted mkfs.ext4 mkfs.fat mount umount grub-install cp chroot useradd passwd blkid; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "[ERROR] Missing required command: $cmd"; exit 1; }
done

# Variables
TARGET_DISK=""
TARGET_PART_ROOT=""
TARGET_PART_BOOT=""
BOOT_MODE=""
HOSTNAME="murex"
USERNAME="murex"
PASSWORD=""

# Functions
show_message() {
    dialog --title "Murex Installer" --msgbox "$1" 10 50
}

choose_disk() {
    DISKS=$(lsblk -dno NAME,SIZE | grep -v "loop\|sr0")
    OPTIONS=()
    while read -r line; do
        NAME=$(echo "$line" | awk '{print $1}')
        SIZE=$(echo "$line" | awk '{print $2}')
        OPTIONS+=("/dev/$NAME" "$SIZE" "off")
    done <<< "$DISKS"

    TARGET_DISK=$(dialog --radiolist "Select target disk for Murex installation:" 15 60 6 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)
}

select_boot_mode() {
    BOOT_MODE=$(dialog --radiolist "Select boot mode:" 10 50 2 \
        "UEFI" "" on \
        "BIOS" "" off \
        3>&1 1>&2 2>&3)
}

set_hostname() {
    HOSTNAME=$(dialog --inputbox "Enter hostname:" 10 50 "$HOSTNAME" 3>&1 1>&2 2>&3)
}

set_user() {
    USERNAME=$(dialog --inputbox "Enter username:" 10 50 "$USERNAME" 3>&1 1>&2 2>&3)
    PASSWORD=$(dialog --passwordbox "Enter password:" 10 50 3>&1 1>&2 2>&3)
}

confirm_install() {
    dialog --yesno "Ready to install Murex on $TARGET_DISK?\nRoot: $TARGET_PART_ROOT\nBoot: $TARGET_PART_BOOT\nUser: $USERNAME\nHostname: $HOSTNAME" 15 60
}

partition_disk() {
    dialog --infobox "Wiping $TARGET_DISK and creating new partitions..." 5 50
    sleep 1

    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        parted -s "$TARGET_DISK" mklabel gpt
        parted -s "$TARGET_DISK" mkpart ESP fat32 1MiB 513MiB
        parted -s "$TARGET_DISK" set 1 boot on
        parted -s "$TARGET_DISK" mkpart primary ext4 513MiB 100%
        TARGET_PART_BOOT="${TARGET_DISK}1"
        TARGET_PART_ROOT="${TARGET_DISK}2"
    else
        parted -s "$TARGET_DISK" mklabel msdos
        parted -s "$TARGET_DISK" mkpart primary ext4 1MiB 100%
        TARGET_PART_ROOT="${TARGET_DISK}1"
        TARGET_PART_BOOT="${TARGET_PART_ROOT}"
    fi

    dialog --msgbox "Partitioning complete:\nRoot: $TARGET_PART_ROOT\nBoot: $TARGET_PART_BOOT" 10 50
}

format_partitions() {
    dialog --infobox "Formatting partitions..." 5 50
    sleep 1

    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        mkfs.fat -F32 "$TARGET_PART_BOOT"
        mkfs.ext4 -F "$TARGET_PART_ROOT"
    else
        mkfs.ext4 -F "$TARGET_PART_ROOT"
    fi

    dialog --msgbox "Formatting complete." 10 50
}

mount_partitions() {
    dialog --infobox "Mounting partitions..." 5 50
    sleep 1

    mkdir -p /mnt/install
    mount "$TARGET_PART_ROOT" /mnt/install
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        mkdir -p /mnt/install/boot/efi
        mount "$TARGET_PART_BOOT" /mnt/install/boot/efi
    fi

    dialog --msgbox "Mounting complete." 10 50
}

copy_rootfs() {
    dialog --infobox "Copying Murex root filesystem..." 5 50
    sleep 1

    # Assuming live environment rootfs is available at /live/rootfs
    cp -a /live/rootfs/* /mnt/install/

    dialog --msgbox "Root filesystem copied." 10 50
}

install_bootloader() {
    dialog --infobox "Installing GRUB bootloader..." 5 50
    sleep 1

    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        grub-install --target=x86_64-efi \
                     --efi-directory=/mnt/install/boot/efi \
                     --boot-directory=/mnt/install/boot \
                     --removable \
                     --recheck
    else
        grub-install --target=i386-pc --boot-directory=/mnt/install/boot "$TARGET_DISK"
    fi

    ROOT_UUID=$(blkid -s UUID -o value "$TARGET_PART_ROOT")
    cat > /mnt/install/boot/grub/grub.cfg <<EOF
set default=0
set timeout=5

menuentry "Murex Linux" {
    linux /boot/vmlinuz root=UUID=$ROOT_UUID rw quiet
    initrd /boot/initrd.img
}
EOF

    dialog --msgbox "GRUB installation complete." 10 50
}

create_user() {
    dialog --infobox "Creating user account..." 5 50
    sleep 1

    chroot /mnt/install /usr/sbin/useradd -m -G wheel "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chroot /mnt/install /usr/sbin/chpasswd

    dialog --msgbox "User $USERNAME created." 10 50
}

finish_install() {
    dialog --msgbox "Installation complete!\nYou can now reboot into Murex." 10 50
}

# Main installer flow
main() {
    show_message "Welcome to the Murex Linux Installer!"
    choose_disk
    select_boot_mode
    set_hostname
    set_user
    partition_disk
    format_partitions
    mount_partitions
    confirm_install && copy_rootfs
    install_bootloader
    create_user
    finish_install
}

main "$@"