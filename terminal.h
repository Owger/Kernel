#ifndef TERMINAL_H
#define TERMINAL_H
 
#include <stddef.h>
#include <stdint.h>
 
/* Standard VGA text-mode color palette (used as the low/high nibble of an
 * attribute byte — foreground and background). */
enum vga_color {
    VGA_COLOR_BLACK         = 0,
    VGA_COLOR_BLUE          = 1,
    VGA_COLOR_GREEN         = 2,
    VGA_COLOR_CYAN          = 3,
    VGA_COLOR_RED           = 4,
    VGA_COLOR_MAGENTA       = 5,
    VGA_COLOR_BROWN         = 6,
    VGA_COLOR_LIGHT_GREY    = 7,
    VGA_COLOR_DARK_GREY     = 8,
    VGA_COLOR_LIGHT_BLUE    = 9,
    VGA_COLOR_LIGHT_GREEN   = 10,
    VGA_COLOR_LIGHT_CYAN    = 11,
    VGA_COLOR_LIGHT_RED     = 12,
    VGA_COLOR_LIGHT_MAGENTA = 13,
    VGA_COLOR_LIGHT_BROWN   = 14,
    VGA_COLOR_WHITE         = 15,
};
 
/* Must be called once before any other terminal_* function — clears the
 * screen and resets cursor position and color. */
void terminal_initialize(void);
 
/* Change the color used for subsequent writes. Does not affect text
 * already on screen. */
void terminal_setcolor(uint8_t color);
 
/* Write a single character at the current cursor position and advance the
 * cursor, handling newlines, wrapping, and scrolling as needed. */
void terminal_putchar(char c);
 
/* Write `size` bytes starting at `data`. */
void terminal_write(const char *data, size_t size);
 
/* Write a NUL-terminated string. */
void terminal_writestring(const char *data);
 
#endif /* TERMINAL_H */
