# Requires the x86_64-elf cross-compiler built earlier to be on your PATH:
#   export PATH="$HOME/opt/cross/bin:$PATH"
# and: apt install qemu-system-x86 grub-pc-bin grub-common xorriso mtools
 
TARGET := x86_64-elf
CC     := $(TARGET)-gcc
 
CFLAGS  := -ffreestanding -fno-stack-protector -fno-pic -m64 \
           -mno-red-zone -mno-mmx -mno-sse -mno-sse2 \
           -Wall -Wextra -O2
LDFLAGS := -ffreestanding -O2 -nostdlib -T linker.ld \
           -Wl,-z,max-page-size=0x1000 -Wl,-z,noseparate-code \
           -no-pie -Wl,--build-id=none
 
all: kernel.elf
 
boot.o: boot.S
	$(CC) $(CFLAGS) -c boot.S -o boot.o
 
kernel.o: kernel.c
	$(CC) $(CFLAGS) -c kernel.c -o kernel.o
 
kernel.elf: boot.o kernel.o linker.ld
	$(CC) $(LDFLAGS) -o kernel.elf boot.o kernel.o -lgcc
 
# Build a bootable ISO with GRUB, which loads the kernel far more robustly
# than QEMU's own minimal -kernel multiboot loader.
kernel.iso: kernel.elf grub.cfg
	rm -rf isodir
	mkdir -p isodir/boot/grub
	cp kernel.elf isodir/boot/kernel.elf
	cp grub.cfg isodir/boot/grub/grub.cfg
	grub-mkrescue -o kernel.iso isodir
 
run: kernel.iso
	qemu-system-x86_64 -cdrom kernel.iso -boot d
 
# Old direct-kernel-load path, kept for reference/debugging only —
# unreliable with some binutils/QEMU combos, prefer `make run`.
run-direct: kernel.elf
	qemu-system-x86_64 -kernel kernel.elf
 
clean:
	rm -f *.o kernel.elf kernel.iso
	rm -rf isodir
 
.PHONY: all run run-direct clean
 
