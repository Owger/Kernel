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

kernel.o: kernel.c terminal.h kprintf.h serial.h panic.h
	$(CC) $(CFLAGS) -c kernel.c -o kernel.o

terminal.o: terminal.c terminal.h
	$(CC) $(CFLAGS) -c terminal.c -o terminal.o

serial.o: serial.c serial.h
	$(CC) $(CFLAGS) -c serial.c -o serial.o

kprintf.o: kprintf.c kprintf.h terminal.h serial.h
	$(CC) $(CFLAGS) -c kprintf.c -o kprintf.o

panic.o: panic.c panic.h terminal.h kprintf.h serial.h
	$(CC) $(CFLAGS) -c panic.c -o panic.o

kernel.elf: boot.o kernel.o terminal.o serial.o kprintf.o panic.o linker.ld
	$(CC) $(LDFLAGS) -o kernel.elf boot.o kernel.o terminal.o serial.o kprintf.o panic.o -lgcc

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
