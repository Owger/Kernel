/* boot.S — multiboot2 entry point + long mode setup
 *
 * GRUB/QEMU's multiboot loader always drops us in 32-bit protected mode,
 * regardless of the target CPU — there is no way to ask GRUB to hand off
 * directly into 64-bit mode. So every x86_64 bare-metal kernel needs code
 * like this to bridge the gap. This file:
 *
 *   1. Advertises a multiboot2 header so GRUB can load us directly.
 *      (Why multiboot2 and not v1: v1 requires the header within the
 *      first 8KB of the file, which modern linker output can blow past
 *      surprisingly easily due to alignment padding. v2 gives a 32KB
 *      window, which is far more forgiving.)
 *
 *   2. Sanity-checks that multiboot, CPUID, and long mode are available.
 *      (Why: if any of these are missing, continuing would eventually
 *      crash in a confusing way deep in the paging/GDT setup. Failing
 *      loudly and immediately here is much easier to debug.)
 *
 *   3. Builds minimal page tables identity-mapping the first 1GB.
 *      (Why: x86_64 long mode REQUIRES paging to be enabled — there is no
 *      "64-bit mode without paging" option, unlike 32-bit protected mode.
 *      Identity mapping — virtual address == physical address — is the
 *      simplest possible page table setup and is enough to get the
 *      kernel itself running before anything fancier is needed.)
 *
 *   4. Enables PAE + long mode + paging via CR4/EFER/CR0.
 *      (Why this exact order matters: PAE must be on before long mode
 *      can be enabled, and long mode must be enabled in EFER before
 *      paging is turned on in CR0 — the CPU checks this ordering and
 *      will fault if it's wrong.)
 *
 *   5. Loads a 64-bit GDT and far-jumps into 64-bit code.
 *      (Why a far jump specifically: changing CS via a regular jump/call
 *      doesn't reload the CPU's internal notion of code segment
 *      attributes: only a far jump, interrupt return, or task switch
 *      actually flips the CPU into 64-bit instruction decoding.)
 *
 *   6. Calls into kernel_main (compiled C, 64-bit).
 *      (Why cli first: no IDT exists yet at this point. Any interrupt —
 *      most commonly the timer — firing before one exists causes a fault
 *      the CPU also can't handle, cascading into a triple fault and a
 *      full machine reset. This bit us during initial bring-up and looks
 *      exactly like "the kernel worked for a split second, then
 *      rebooted" — see the README's troubleshooting section.)
 */
 
.set MB2_MAGIC,  0xE85250D6   /* multiboot2 magic */
.set MB2_ARCH,   0            /* i386 protected mode */
.set MB2_LENGTH, mb2_header_end - mb2_header_start
.set MB2_CHECKSUM, -(MB2_MAGIC + MB2_ARCH + MB2_LENGTH)
 
.section .multiboot
.align 8
mb2_header_start:
    .long MB2_MAGIC
    .long MB2_ARCH
    .long MB2_LENGTH
    .long MB2_CHECKSUM
 
    /* end tag — required, marks the end of the tag list */
    .align 8
    .short 0
    .short 0
    .long 8
mb2_header_end:
 
.section .bss
.align 16
stack_bottom:
.skip 16384      /* 16 KiB stack */
stack_top:
 
.align 4096
p4_table:
.skip 4096
p3_table:
.skip 4096
p2_table:
.skip 4096
 
.section .text
.code32
.global _start
.type _start, @function
_start:
    mov $stack_top, %esp
 
    call check_multiboot
    call check_cpuid
    call check_long_mode
 
    call set_up_page_tables
    call enable_paging
 
    lgdt gdt64_pointer
    ljmp $gdt64_code_offset, $long_mode_start
 
    hlt
 
/* eax holds the multiboot2 magic value on entry; confirm it's what we expect */
check_multiboot:
    cmp $0x36D76289, %eax
    jne .no_multiboot
    ret
.no_multiboot:
    mov $'0', %al
    jmp error
 
/* flip the CPUID-support bit in EFLAGS; if it doesn't stick, no CPUID */
check_cpuid:
    pushfl
    pop %eax
    mov %eax, %ecx
    xor $(1<<21), %eax
    push %eax
    popfl
    pushfl
    pop %eax
    push %ecx
    popfl
    cmp %ecx, %eax
    je .no_cpuid
    ret
.no_cpuid:
    mov $'1', %al
    jmp error
 
check_long_mode:
    mov $0x80000000, %eax
    cpuid
    cmp $0x80000001, %eax
    jb .no_long_mode
 
    mov $0x80000001, %eax
    cpuid
    test $(1<<29), %edx
    jz .no_long_mode
    ret
.no_long_mode:
    mov $'2', %al
    jmp error
 
/* identity-map the first 1GB using 2MB pages: P4 -> P3 -> P2(huge pages) */
set_up_page_tables:
    mov $p3_table, %eax
    or $0b11, %eax
    mov %eax, (p4_table)
 
    mov $p2_table, %eax
    or $0b11, %eax
    mov %eax, (p3_table)
 
    xor %ecx, %ecx
.map_p2_table:
    mov $0x200000, %eax
    mul %ecx
    or $0b10000011, %eax   /* present, writable, huge page */
    mov %eax, p2_table(,%ecx,8)
 
    inc %ecx
    cmp $512, %ecx
    jne .map_p2_table
 
    ret
 
enable_paging:
    mov $p4_table, %eax
    mov %eax, %cr3
 
    mov %cr4, %eax
    or $(1<<5), %eax        /* PAE */
    mov %eax, %cr4
 
    mov $0xC0000080, %ecx   /* EFER MSR */
    rdmsr
    or $(1<<8), %eax        /* long mode enable */
    wrmsr
 
    mov %cr0, %eax
    or $(1<<31), %eax       /* paging enable */
    mov %eax, %cr0
 
    ret
 
/* prints "ERR: <code>" in white-on-red to VGA text memory, then halts */
error:
    movl $0x4f524f45, (0xb8000)
    movl $0x4f3a4f52, (0xb8004)
    movl $0x4f204f20, (0xb8008)
    movb %al, (0xb800a)
    hlt
 
.section .rodata
.align 8
gdt64:
    .quad 0                                    /* null descriptor */
gdt64_code:
    .quad (1<<43) | (1<<44) | (1<<47) | (1<<53) /* 64-bit code segment */
gdt64_pointer:
    .word . - gdt64 - 1
    .quad gdt64
 
.set gdt64_code_offset, gdt64_code - gdt64
 
.section .text
.code64
long_mode_start:
    cli                      /* mask interrupts — no IDT exists yet;
                                 without this, the first timer interrupt
                                 triple-faults and reboots the machine */
 
    mov $0, %ax
    mov %ax, %ss
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs
 
    call kernel_main
 
    hlt
.hang:
    jmp .hang
 
