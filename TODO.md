# TODO — From "Hello World" to a Bootable OS

Where we are: a kernel that boots via GRUB/QEMU into 64-bit long mode and
prints a string to VGA text memory, then halts forever. Everything below
is what stands between that and something you could reasonably call an
operating system.

This is organized in roughly the order you'd actually want to tackle it —
each phase mostly depends on the ones before it — but OS dev is nonlinear
in practice, so treat this as a map, not a strict sequence. Skipping around
based on what's interesting is fine; just know that some things (like
interrupts) unblock a surprising number of later items.

A rough note on scope: a "real" OS in the Linux/Windows sense is a
multi-decade, thousands-of-person-year undertaking. The goal here is
realistically a **hobby OS that can boot, manage memory, handle input,
run its own simple programs, and read/write a disk** — which is genuinely
achievable and is what most OSDev-community projects mean by "done."

---

## Phase 0 — Harden what already exists

Before building forward, the current boot path has some rough edges worth
cleaning up so they don't bite later.

- [x] Replace the single hardcoded VGA string write with a real
      `terminal_putchar` / `terminal_write` / `terminal_writestring` set of
      functions, including a cursor position and basic scrolling when text
      reaches the bottom of the screen.
- [x] Add a `printf`-style formatted output function (even a minimal one
      supporting `%s %d %x %c`) — you will want this constantly from here on
      for debugging.
- [x] Add serial port (COM1, `0x3F8`) output as a second, more reliable
      debug channel — useful once VGA becomes unreliable (e.g. mid interrupt
      setup) or when running headless.
- [x] Set up a `panic()` function: prints a message, dumps registers if
      possible, and halts — so failures are diagnosable instead of silent
      hangs or triple faults.
- [x] Write actual comments into `boot.S` explaining *why* each page-table /
      long-mode step exists, not just what it does — future you will thank
      present you.
- [x] Decide on and document a consistent kernel coding style now
      (naming, indentation, header layout) before the codebase grows enough
      that changing it later is painful.

---

## Phase 1 — Interrupts and exceptions (the real unblocker)

Right now interrupts are just masked off with `cli` forever. Almost
everything past this point — keyboard input, a timer, preemptive
multitasking, page faults — requires a working interrupt system.

- [ ] Build a proper **GDT** in code (not just the minimal 64-bit one in
      `boot.S`) with kernel code/data segments and (later) user code/data
      segments.
- [ ] Build an **IDT** (Interrupt Descriptor Table) with 256 entries.
- [ ] Write **ISR (Interrupt Service Routine) stubs** for the 32 CPU
      exception vectors (divide-by-zero, page fault, GPF, double fault,
      etc.) in assembly, each pushing state and calling into a shared C
      handler.
- [ ] Write a generic C-level exception handler that at minimum prints
      which exception fired, the error code (where applicable), and the
      faulting instruction pointer, then halts.
- [ ] Set up the **PIC** (8259, or skip straight to **APIC** if you want to
      do it once and do it right) and remap IRQs 0–15 away from the CPU
      exception vector range (0–31) they conflict with by default.
- [ ] Enable interrupts (`sti`) only once the above is actually in place
      and tested with a deliberately triggered exception (e.g. divide by
      zero) to confirm the handler fires correctly instead of triple
      faulting.
- [ ] Handle the **double fault** exception specifically with its own
      dedicated stack (IST mechanism in the TSS) — a double fault while
      already handling a fault with a bad stack is a classic silent
      triple-fault trigger.

---

## Phase 2 — Timer and basic scheduling groundwork

- [ ] Set up the **PIT** (Programmable Interval Timer) on IRQ0, or the
      **APIC timer** if you went that route in Phase 1, and get a periodic
      tick handler running.
- [ ] Maintain a simple tick counter / uptime value, incremented in the
      timer IRQ handler.
- [ ] Implement a basic `sleep()`/busy-wait based on tick count, just to
      prove the timer interrupt is really firing.
- [ ] (Optional but very useful) Get the **RTC** (Real-Time Clock) readable
      for wall-clock date/time, separate from the tick-based uptime.

---

## Phase 3 — Memory management

This is arguably the single biggest phase. Everything from here on assumes
you can dynamically allocate and map memory.

### Physical memory
- [ ] Parse the **multiboot2 memory map** tag (passed in `%ebx` at boot —
      currently ignored entirely) to find out how much RAM actually exists
      and which regions are usable vs. reserved.
- [ ] Implement a **physical frame allocator** — a bitmap or free-list
      tracking which 4KB physical frames are free/used. Start simple
      (bitmap) before anything fancier.
- [ ] Reserve the frames actually used by the kernel image itself, and by
      structures set up during boot (page tables, GDT/IDT, etc.) so the
      allocator doesn't hand them out.

### Virtual memory
- [ ] Move from the boot-time identity-mapped-first-1GB page tables to a
      proper, dynamically managed set of page tables.
- [ ] Implement functions to map/unmap arbitrary virtual → physical
      addresses on demand (`map_page`, `unmap_page`).
- [ ] Set up a **higher-half kernel** — map the kernel to the upper part of
      the virtual address space (e.g. `0xFFFFFFFF80000000`) rather than
      living at 1MB, which is the conventional approach and matters a lot
      once user processes exist and need the lower half of address space
      to themselves.
- [ ] Handle **page faults** properly (Phase 1's exception handler should
      already catch these) — at minimum, distinguish a real bug from
      something recoverable like demand paging (later).

### Kernel heap
- [ ] Implement `kmalloc`/`kfree` — a basic kernel heap allocator on top of
      the virtual memory system. A simple bump allocator or free-list is
      fine to start; don't over-engineer this initially.
- [ ] Once `kmalloc` exists, go back and convert any boot-time fixed-size
      arrays/structures to dynamically sized ones where it makes sense.

---

## Phase 4 — Input

- [ ] Write a **PS/2 keyboard driver** on IRQ1: read scancodes from port
      `0x60`, translate scan set 1 to ASCII (handle shift/caps for a first
      pass, skip exotic keys initially).
- [ ] Add a simple **keyboard input buffer/queue** the rest of the kernel
      can read from.
- [ ] (Optional) PS/2 mouse driver on IRQ12, if you want anything beyond a
      pure text-mode system eventually.

---

## Phase 5 — Moving off VGA text mode (optional but common next step)

- [ ] If you want graphics eventually: parse the multiboot2 **framebuffer**
      tag instead of relying on legacy `0xb8000` VGA text memory, and write
      a basic pixel-plotting + font-rendering text layer on top of it.
- [ ] This is a good point to revisit the `set gfxpayload=text` issue noted
      in the README — once you deliberately want graphics mode, that
      earlier obstacle becomes a feature you actually want to get working
      properly instead of avoiding.

---

## Phase 6 — Getting off the GRUB-provided environment

- [ ] Implement **ACPI table parsing** (starting with just RSDP/RSDT/MADT)
      — needed for proper multi-core (APIC) info, and eventually for
      power management (shutdown/reboot without cheating via keyboard
      controller resets).
- [ ] Implement a clean **shutdown** and **reboot** path using ACPI, rather
      than relying on QEMU-specific exits during development.

---

## Phase 7 — Processes and multitasking

This is where it starts feeling like a real OS rather than a bootloader
demo.

- [ ] Design a **task/process control block** structure — saved registers,
      page table pointer, kernel stack, state (ready/running/blocked).
- [ ] Implement **context switching** in assembly — saving/restoring
      general-purpose registers and switching `%cr3` (page table base) and
      the stack pointer.
- [ ] Hook context switching into the **timer interrupt** for preemptive
      multitasking, with a simple round-robin scheduler to start.
- [ ] Set up **separate kernel stacks per task** (via the TSS) so an
      interrupt during user code lands on a safe, known-good stack.
- [ ] Implement basic **user mode** (ring 3): user code/data segments in
      the GDT, dropping to ring 3 via `iretq`, and a working **syscall**
      mechanism (`syscall`/`sysret` or a software interrupt) to get back to
      ring 0 for privileged operations.
- [ ] Enforce actual **memory protection** between processes — separate
      page tables per process, kernel pages marked supervisor-only.

---

## Phase 8 — A real filesystem and persistent storage

- [ ] Write an **ATA/IDE (PIO mode) disk driver** — simplest storage
      driver to start with; AHCI/SATA is the more "real" long-term target
      but significantly more complex.
- [ ] Implement reading a simple, well-documented filesystem —
      **FAT32** is the traditional first choice since it's simple and you
      can create/inspect test images with standard tools (`mkfs.fat`,
      mounting via loopback, etc.) without writing your own tooling.
- [ ] Implement a **VFS (virtual filesystem) layer** — an abstraction so
      the rest of the kernel doesn't care whether it's talking to FAT32,
      a ramdisk, or (eventually) something custom.
- [ ] Get write support working, not just read — this matters once you
      want persistent state across boots.

---

## Phase 9 — Loading and running actual programs

- [ ] Implement an **ELF loader** — parse a userspace ELF64 binary, map its
      segments into a new process's address space, and jump to its entry
      point in ring 3.
- [ ] Define a minimal **syscall ABI**: at minimum something like
      `write`, `read`, `exit`, `fork`/`exec`-equivalent, `mmap`-equivalent.
      Keep the initial syscall table small and expand as real programs
      demand more.
- [ ] Write a trivial **userspace "libc"** stub — even just enough to wrap
      syscalls in normal-looking C functions — so you can compile simple
      C programs against your OS instead of hand-writing raw syscall
      assembly for every test program.
- [ ] Get a **basic shell** running as a userspace program: read a line
      from keyboard input, parse it, and load/exec a matching program from
      the filesystem.

---

## Phase 10 — The stuff that makes it feel like a "real" system

Roughly in priority order once the above works:

- [ ] **Inter-process communication** — pipes at minimum.
- [ ] **Signals** or some equivalent async-notification mechanism.
- [ ] **Multi-core support** — bring up secondary CPUs via the APIC,
      extend the scheduler to be SMP-aware, add proper locking (spinlocks
      at minimum) anywhere shared kernel state is touched.
- [ ] **Networking** — an Ethernet driver (e.g. for the RTL8139 or a QEMU
      virtio-net device, both well-documented and QEMU-testable) plus a
      minimal TCP/IP stack, or integrate an existing minimal one (lwIP is
      a common hobby-OS choice).
- [ ] **Dynamic linking** (shared libraries) — a substantial jump in
      complexity, optional for a long time.
- [ ] **A package/build system** for userspace programs so the OS can grow
      a small ecosystem of its own tools instead of one-off test binaries.

---

## Ongoing / never really "done"

- [ ] Keep a running **known-issues log** — bare-metal bugs are often
      silent (triple faults, no debugger by default) so tracking "this
      broke, here's what fixed it" as you go is genuinely valuable, the
      same way the README's troubleshooting section already is.
- [ ] Periodically test on **real hardware**, not just QEMU — QEMU is
      forgiving in ways real BIOS/UEFI and real devices are not, and bugs
      that only show up on real hardware are a rite of passage.
- [ ] Consider **UEFI boot** as an alternative/addition to BIOS+GRUB
      eventually — increasingly the more "modern" path, though BIOS/GRUB
      remains the easier on-ramp and is fine to stay on for a long time.
- [ ] Set up **automated testing** where feasible (e.g. scripted QEMU boots
      checking for expected serial output) so regressions get caught
      without manually re-testing every change by hand.

---

## Suggested next concrete step

If picking just one thing to start on right now: **Phase 1, interrupts**.
It's the single biggest unlock — keyboard input, timers, scheduling, and
proper fault handling (instead of mysterious triple-fault reboots) all sit
behind it. Everything in Phase 0 is good hygiene but not strictly
blocking; Phase 1 actually is.
