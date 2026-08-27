#ifndef KPRINTF_H
#define KPRINTF_H
 
#include <stdarg.h>
 
/* Minimal, freestanding printf for kernel debugging output.
 *
 * Named kprintf (not printf) deliberately: this is NOT a general-purpose
 * libc printf, and keeping the name distinct avoids confusion or symbol
 * clashes if/when a real libc gets built for userspace later.
 *
 * Output goes to both the VGA terminal and the COM1 serial port, so it
 * stays visible even if the display is unreliable (e.g. mid interrupt
 * setup) or you're running headless.
 *
 * Supported specifiers: %d %u %x %X %c %s %p %%
 * NOT supported (yet): width/precision (%5d, %.2f), %f (no float support
 * in a freestanding kernel without extra work), %ld/%lld (assumes int is
 * good enough for now — revisit if 64-bit values need printing directly).
 */
int kprintf(const char *format, ...);
 
/* va_list-taking core, exposed so other functions (e.g. panic()) that
 * receive their own varargs can forward them here without duplicating
 * the formatting logic. */
int kvprintf(const char *format, va_list args);
 
#endif /* KPRINTF_H */
