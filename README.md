# x86_64 Bare-Metal Kernel — "Hello World"

A minimal x86_64 kernel that boots via GRUB/QEMU and prints a message to the
screen. This is the "Bare Bones" starting point for OS dev — no libc, no
host OS, just your code talking directly to hardware.

Built from an ARM64 Linux host using a custom cross-compiler.

---

## 1. What's in this folder

| File | Purpose |
|---|---|
| `boot.S` | Entry point. Handles the 32-bit → 64-bit transition (multiboot2 header, CPU checks, page tables, long mode setup), then jumps into C code. |
| `kernel.c` | The actual kernel. Currently just writes text to the VGA buffer. |
| `linker.ld` | Tells the linker where in memory to load everything (starting at 1MB). |
| `grub.cfg` | Tells GRUB how to find and boot `kernel.elf`. |
| `Makefile` | Builds everything and boots it in QEMU. |
| `build-x86_64-elf-toolchain.sh` | One-time script to build the cross-compiler itself (see Section 2). |

---

## 2. One-time setup: build the cross-compiler

You need a compiler that targets **x86_64-elf** (bare metal, no OS) — your
system's normal `gcc` targets your host OS and won't work for this.

```bash
chmod +x build-x86_64-elf-toolchain.sh
./build-x86_64-elf-toolchain.sh
```

This downloads and builds `binutils` + `gcc` from source. **Takes 20–60+
minutes** depending on your machine. It installs to `~/opt/cross`.

**Then add it to your PATH permanently.** Figure out which shell you're
running first (`echo $SHELL`) — Kali defaults to **zsh**, not bash:

```bash
# for zsh (Kali default):
echo 'export PATH="$HOME/opt/cross/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# for bash:
echo 'export PATH="$HOME/opt/cross/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

Verify it worked:
```bash
which x86_64-elf-gcc
# should print: /home/<you>/opt/cross/bin/x86_64-elf-gcc
```

If a *new* terminal ever says `x86_64-elf-gcc: command not found`, it means
the PATH line didn't make it into your shell's rc file, or you're in a
non-interactive shell that doesn't source it. Re-run the `echo`/`source`
commands above.

### If the build gets killed (`Killed signal terminated program cc1plus`)

This is an out-of-memory kill, not a code error — GCC's build is
memory-hungry. Fixes, in order of preference:
- Edit the script and lower `JOBS` (e.g. `JOBS=1`), then re-run `make -j1
  all-gcc` from `~/src/cross-toolchain/build/gcc`.
- Add swap space if your machine has under ~2GB RAM.
- Build on a beefier machine and copy `~/opt/cross` over.

---

## 3. Build and run the kernel

Also needs GRUB's ISO tools (one-time):
```bash
sudo apt install qemu-system-x86 grub-pc-bin grub-common xorriso mtools
```

Then, every time you want to build and boot:
```bash
make run
```

This compiles `boot.S` + `kernel.c` → `kernel.elf`, packages it into a
bootable ISO with GRUB (`kernel.iso`), and launches it in QEMU. You should
see:

```
Hello, x86_64 kernel world!
```

on an otherwise blank screen.

Other useful targets:
```bash
make clean     # wipe all build artifacts (kernel.elf, kernel.iso, isodir/, *.o)
make kernel.elf  # just build, don't run
```

**Always do a clean rebuild if something seems stale:**
```bash
rm -f kernel.elf kernel.iso boot.o kernel.o
rm -rf isodir
make run
```

---

## 4. If it doesn't boot — troubleshooting

We hit every one of these getting this working the first time. Check them
in this order.

### "No rule to make target 'boot.S'"
You're not in the right folder, or a file didn't save correctly. Run `ls`
— you should see all 5 source files (`boot.S`, `kernel.c`, `linker.ld`,
`grub.cfg`, `Makefile`) together in one folder.

### "x86_64-elf-gcc: No such file or directory"
PATH isn't set in this shell session. See Section 2 above — check
`echo $SHELL` and make sure the export line is in the *matching* rc file
(`~/.zshrc` vs `~/.bashrc`), then `source` it.

### QEMU: "Error loading uncompressed kernel without PVH ELF Note"
This means the multiboot magic number wasn't found. We eventually solved
this two ways at once — both already in this repo, don't undo them:
1. **Use `multiboot2`, not multiboot1.** v1 requires the header within the
   first 8192 bytes of the file, which modern linkers make surprisingly
   easy to blow past with alignment padding. v2 gives a 32KB window instead.
2. **Boot via a GRUB ISO (`-cdrom`), not QEMU's raw `-kernel` flag.** GRUB
   is a far more mature multiboot implementation than QEMU's minimal
   built-in loader.

If you ever need to debug this again:
```bash
readelf -S kernel.elf | grep -A1 boot   # check the .boot section's file offset
```

### Boots, prints "Hello world", then seems to reboot/loop
This is almost always a **triple fault** — the CPU hit an interrupt (like
the timer) with no IDT (interrupt table) set up, faulted, couldn't handle
*that* fault either, and reset. `boot.S` already has a `cli` instruction
right at the start of 64-bit mode to mask interrupts and prevent this.
Don't remove it until we actually build an IDT.

### Stuck forever at "Booting 'My x86_64 Kernel'"
Two very different possible causes — check which one you're hitting:

1. **Stale QEMU process.** By far the most common culprit for us. If
   you've run `make run` multiple times, old QEMU windows/processes can
   pile up in the background and you end up staring at leftover output
   from a previous run. `pkill qemu-system-x86_64` **does not work** —
   the process name gets truncated and the pattern won't match. Use:
   ```bash
   pkill -f qemu-system-x86_64
   ps aux | grep qemu   # confirm it's actually empty now
   ```
   Then run `make run` exactly once and watch that single fresh window.

2. **Genuinely hung in BIOS**, not your kernel at all. Check with `top` —
   if `qemu-system-x86_64` is near 0% CPU, it might be stuck probing a
   boot device (e.g. the floppy controller) before it even reaches GRUB.
   Our `Makefile`'s `run` target already passes `-boot d` to force booting
   straight from the CD-ROM and skip that probe. If you still get stuck,
   debug with:
   ```bash
   qemu-system-x86_64 -cdrom kernel.iso -boot d -no-reboot -no-shutdown \
       -d int,cpu_reset -D qemu.log
   ```
   then `tail -50 qemu.log` — real-mode register state (`CS=f000`,
   `EFER=0`) means it's still in BIOS; 64-bit state with our GDT loaded
   means it's actually in the kernel.

### Screen shows a graphics glitch / VGA writes not visible
Some GRUB builds switch to a graphics framebuffer instead of legacy VGA
text mode, in which case writes to `0xb8000` (what our `kernel.c` uses)
go nowhere visible. We tried `set gfxpayload=text` in `grub.cfg` for this
— but on our setup it caused GRUB to hang instead, so it's currently
**not** in `grub.cfg`. Only re-add it if you hit this specific symptom,
and be ready to remove it again if GRUB hangs.

### Running inside nested virtualization (VirtualBox + QEMU, etc.)
If your ARM64 host runs Kali inside VirtualBox, and QEMU runs *inside*
that guest, you're doing two layers of emulation. This can be slow, and
in our case caused a BIOS floppy-probe routine to hang instead of failing
fast (fixed by `-boot d`, see above). If something seems inexplicably
broken, consider whether it's an artifact of this stacked setup before
assuming it's a bug in the kernel code itself.

---

## 5. How the boot process actually works

Worth understanding before extending this:

1. **GRUB loads `kernel.elf`** and jumps to `_start` in `boot.S`. The CPU
   is in **32-bit protected mode** at this point — always, regardless of
   your target architecture. GRUB never sets up 64-bit mode for you.
2. `boot.S` checks that we were really loaded by a multiboot bootloader,
   that CPUID is available, and that the CPU actually supports long mode
   (64-bit).
3. It builds minimal page tables that identity-map the first 1GB of memory
   (required — you can't enable 64-bit mode without paging enabled).
4. It enables PAE, sets the long-mode bit in the EFER MSR, enables paging,
   then loads a 64-bit GDT and far-jumps into 64-bit code.
5. `long_mode_start` sets up segment registers, masks interrupts (`cli`),
   and calls `kernel_main` in `kernel.c` — now running compiled C code.
6. `kernel_main` writes directly to VGA text memory at `0xb8000` (no
   drivers, no `printf`, just raw memory writes) and halts forever.

---

## 6. Natural next steps

Roughly in order of how OS dev tutorials usually build this up:
- **Print more robustly**: wrap the VGA write in a proper `terminal_write`
  function with scrolling, instead of hardcoding one string at offset 0.
- **Set up a GDT/IDT properly** and handle exceptions instead of just
  masking interrupts forever.
- **Enable the PIC/APIC and handle the timer interrupt** — needed for
  anything scheduling-related.
- **Add a keyboard driver** (IRQ1) for basic input.
- **Physical memory management** — track which of that 1GB you've
  identity-mapped is actually free to allocate.

Happy to help build out any of these next.
