#!/usr/bin/env zsh

# Step 0: Prepare ISO staging
mkdir -p iso/{boot,live,EFI,isolinux}

# Step 1: Compress rootfs to squashfs
mksquashfs rootfs/ iso/live/rootfs.squashfs -comp xz -e boot

# Step 2: Copy kernel & initrd
cp rootfs/boot/vmlinuz iso/boot/vmlinuz
cp rootfs/boot/initrd.img iso/boot/initrd.img

# Step 3: Create GRUB config
# iso/boot/grub/grub.cfg
cat > iso/boot/grub/grub.cfg <<EOF
set default=0
set timeout=5

menuentry "Murex Live" {
    linux /boot/vmlinuz boot=live
    initrd /boot/initrd.img
}
menuentry "Install Murex" {
    linux /boot/vmlinuz boot=installer
    initrd /boot/initrd.img
}
EOF

# Step 4: Build ISO
grub-mkrescue -o murex.iso iso/
