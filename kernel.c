#include <stdint.h>
#include "terminal.h"
#include "kprintf.h"
#include "serial.h"
#include "panic.h"
 
void kernel_main(void) {
    terminal_initialize();
 
    if (serial_initialize() != 0) {
        /* Not fatal — just means COM1 isn't available in this
         * environment. kprintf's serial writes will silently go nowhere,
         * but VGA output still works fine. */
        terminal_writestring("Warning: serial port COM1 not detected.\n");
    }
 
    terminal_writestring("Hello, x86_64 kernel world!\n");
 
    kprintf("kprintf is working: %d, %u, 0x%x, %c, %s\n",
            -42, 42u, 0xDEADBEEF, '!', "nice");
    kprintf("pointer example: %p\n", (void *)kernel_main);
 
    /* Example of how panic() gets used once something is actually wrong —
     * left commented out so normal boot doesn't halt here:
     *
     *   panic("unexpected condition: value was %d", some_value);
     */
 
    for (;;) {
        __asm__ volatile ("cli; hlt");
    }
}
 
