# Run ./setup.sh once to install everything this needs.
#
# Toolchain selection, in order of preference:
#   1. x86_64-elf-gcc        the purpose-built bare-metal cross compiler
#                            (./setup.sh --toolchain=source, or the older
#                            ./x86_64-elf script). Needs ~/opt/cross/bin on PATH.
#   2. x86_64-linux-gnu-gcc  Debian's cross compiler, from the
#                            gcc-x86-64-linux-gnu package. This is what
#                            ./setup.sh installs by default on an arm64 host.
#   3. plain gcc             only when building on an x86_64 machine.
#
# Every flag below already makes the compiler forget it has a host OS, so a
# linux-gnu targeted compiler produces the same freestanding kernel as an
# elf targeted one. Override the choice with e.g. `make CROSS=x86_64-elf-`.

CROSS ?= $(shell \
    if command -v x86_64-elf-gcc       >/dev/null 2>&1; then echo x86_64-elf-;       \
    elif command -v x86_64-linux-gnu-gcc >/dev/null 2>&1; then echo x86_64-linux-gnu-; \
    elif [ "`uname -m`" = "x86_64" ];    then echo "";                                \
    else echo NO-X86_64-TOOLCHAIN-FOUND; fi)

ifeq ($(CROSS),NO-X86_64-TOOLCHAIN-FOUND)
$(error No x86_64 compiler found. Run ./setup.sh, or put ~/opt/cross/bin on your PATH)
endif

CC := $(CROSS)gcc

# -fcf-protection=none: Debian's x86_64 gcc defaults to emitting CET/endbr64
# instrumentation, which is pointless in a kernel that has no CET setup.
CFLAGS  := -ffreestanding -fno-stack-protector -fno-pic -m64 \
           -mno-red-zone -mno-mmx -mno-sse -mno-sse2 \
           -fcf-protection=none \
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

# Boot in a QEMU window. Needs a display, so not usable over plain SSH.
run: kernel.iso
	qemu-system-x86_64 -cdrom kernel.iso -boot d

# Boot headless, with the emulated COM1 serial port wired to this terminal.
# This is the one to use on a remote VM. Quit QEMU with Ctrl-A then X.
# On a non-x86 host this runs under TCG emulation, so give it a few seconds.
run-serial: kernel.iso
	qemu-system-x86_64 -cdrom kernel.iso -boot d \
	    -display none -serial mon:stdio -no-reboot

# Old direct-kernel-load path, kept for reference/debugging only —
# unreliable with some binutils/QEMU combos, prefer `make run`.
run-direct: kernel.elf
	qemu-system-x86_64 -kernel kernel.elf

clean:
	rm -f *.o kernel.elf kernel.iso
	rm -rf isodir

.PHONY: all run run-serial run-direct clean
