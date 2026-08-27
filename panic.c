#include "panic.h"
 
#include <stdarg.h>
#include <stdint.h>
 
#include "terminal.h"
#include "kprintf.h"
#include "serial.h"
 
void panic(const char *format, ...) {
    /* Mask interrupts immediately — if we got here because something is
     * already badly wrong, the last thing we want is an interrupt firing
     * mid-panic and making things worse (or masking the real error behind
     * a second fault). */
    __asm__ volatile ("cli");
 
    /* White text on red background: VGA_COLOR_WHITE | (VGA_COLOR_RED << 4).
     * Using the raw enum values here rather than terminal.c's internal
     * vga_entry_color() helper, since that's not (currently) exposed
     * outside terminal.c. */
    terminal_setcolor((uint8_t)(VGA_COLOR_WHITE | (VGA_COLOR_RED << 4)));
 
    terminal_writestring("\n*** KERNEL PANIC ***\n");
    serial_writestring("\n*** KERNEL PANIC ***\n");
 
    va_list args;
    va_start(args, format);
    kvprintf(format, args);
    va_end(args);
 
    terminal_putchar('\n');
    serial_write_char('\n');
 
    for (;;) {
        __asm__ volatile ("cli; hlt");
    }
}
 
