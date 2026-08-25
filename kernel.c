#include <stdint.h>
 
void kernel_main(void) {
    volatile uint16_t *vga = (uint16_t *)0xb8000;
    const char *str = "Hello, x86_64 kernel world!";
    uint8_t color = 0x0F; /* white on black */
 
    for (int i = 0; str[i] != '\0'; i++) {
        vga[i] = (uint16_t)str[i] | ((uint16_t)color << 8);
    }
 
    for (;;) {
        __asm__ volatile ("cli; hlt");
    }
}
 
