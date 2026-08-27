#include "terminal.h"
 
/* The VGA text-mode buffer lives at this fixed physical address and is a
 * grid of 16-bit entries: low byte = ASCII character, high byte = color
 * attribute (4 bits background, 4 bits foreground). */
static uint16_t *const VGA_MEMORY = (uint16_t *)0xB8000;
 
#define VGA_WIDTH  80
#define VGA_HEIGHT 25
 
static size_t terminal_row;
static size_t terminal_column;
static uint8_t terminal_color;
 
static inline uint8_t vga_entry_color(enum vga_color fg, enum vga_color bg) {
    return (uint8_t)fg | (uint8_t)(bg << 4);
}
 
static inline uint16_t vga_entry(unsigned char c, uint8_t color) {
    return (uint16_t)c | ((uint16_t)color << 8);
}
 
void terminal_initialize(void) {
    terminal_row = 0;
    terminal_column = 0;
    terminal_color = vga_entry_color(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);
 
    for (size_t y = 0; y < VGA_HEIGHT; y++) {
        for (size_t x = 0; x < VGA_WIDTH; x++) {
            const size_t index = y * VGA_WIDTH + x;
            VGA_MEMORY[index] = vga_entry(' ', terminal_color);
        }
    }
}
 
void terminal_setcolor(uint8_t color) {
    terminal_color = color;
}
 
/* Moves every line up by one, dropping the top line, and clears the newly
 * empty bottom line. Called when the cursor would otherwise go past the
 * last row. */
static void terminal_scroll(void) {
    for (size_t y = 1; y < VGA_HEIGHT; y++) {
        for (size_t x = 0; x < VGA_WIDTH; x++) {
            const size_t dst = (y - 1) * VGA_WIDTH + x;
            const size_t src = y * VGA_WIDTH + x;
            VGA_MEMORY[dst] = VGA_MEMORY[src];
        }
    }
 
    const size_t last_row = VGA_HEIGHT - 1;
    for (size_t x = 0; x < VGA_WIDTH; x++) {
        VGA_MEMORY[last_row * VGA_WIDTH + x] = vga_entry(' ', terminal_color);
    }
 
    terminal_row = last_row;
}
 
static void terminal_newline(void) {
    terminal_column = 0;
    if (++terminal_row == VGA_HEIGHT) {
        terminal_scroll();
    }
}
 
void terminal_putchar(char c) {
    if (c == '\n') {
        terminal_newline();
        return;
    }
 
    if (c == '\r') {
        terminal_column = 0;
        return;
    }
 
    const size_t index = terminal_row * VGA_WIDTH + terminal_column;
    VGA_MEMORY[index] = vga_entry((unsigned char)c, terminal_color);
 
    if (++terminal_column == VGA_WIDTH) {
        terminal_newline();
    }
}
 
void terminal_write(const char *data, size_t size) {
    for (size_t i = 0; i < size; i++) {
        terminal_putchar(data[i]);
    }
}
 
void terminal_writestring(const char *data) {
    size_t i = 0;
    while (data[i] != '\0') {
        terminal_putchar(data[i]);
        i++;
    }
}
 
