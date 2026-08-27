#include "kprintf.h"
 
#include <stddef.h>
#include <stdint.h>
 
#include "terminal.h"
#include "serial.h"
 
/* Every character kprintf emits goes through here, so it reaches both the
 * screen and serial in one place instead of every call site remembering
 * to write to both. */
static void emit_char(char c) {
    terminal_putchar(c);
    serial_write_char(c);
}
 
static void emit_string(const char *s) {
    while (*s != '\0') {
        emit_char(*s++);
    }
}
 
/* Converts an unsigned integer to a string in the given base and emits
 * it. `uppercase` controls A-F vs a-f for hex. Returns the number of
 * characters written. */
static int print_unsigned(uintmax_t value, unsigned base, int uppercase) {
    /* 64-bit value in base 2 needs at most 64 digits — 32 is plenty for
     * every base we actually support (2 isn't exposed, but leave headroom). */
    char buf[32];
    int i = 0;
 
    const char *digits = uppercase ? "0123456789ABCDEF" : "0123456789abcdef";
 
    if (value == 0) {
        buf[i++] = '0';
    } else {
        while (value > 0) {
            buf[i++] = digits[value % base];
            value /= base;
        }
    }
 
    int written = i;
    /* buf was filled least-significant-digit-first; emit in reverse. */
    while (i > 0) {
        emit_char(buf[--i]);
    }
    return written;
}
 
static int print_signed(intmax_t value) {
    if (value < 0) {
        emit_char('-');
        /* Careful with INTMAX_MIN: -value would overflow. Cast through
         * unsigned to handle it correctly. */
        uintmax_t magnitude = (uintmax_t)(-(value + 1)) + 1;
        return 1 + print_unsigned(magnitude, 10, 0);
    }
    return print_unsigned((uintmax_t)value, 10, 0);
}
 
int kvprintf(const char *format, va_list args) {
    int written = 0;
 
    for (size_t i = 0; format[i] != '\0'; i++) {
        if (format[i] != '%') {
            emit_char(format[i]);
            written++;
            continue;
        }
 
        /* format[i] == '%' — look at the next character to decide what to do. */
        i++;
        switch (format[i]) {
            case 'd':
            case 'i': {
                int value = va_arg(args, int);
                written += print_signed(value);
                break;
            }
            case 'u': {
                unsigned int value = va_arg(args, unsigned int);
                written += print_unsigned(value, 10, 0);
                break;
            }
            case 'x': {
                unsigned int value = va_arg(args, unsigned int);
                written += print_unsigned(value, 16, 0);
                break;
            }
            case 'X': {
                unsigned int value = va_arg(args, unsigned int);
                written += print_unsigned(value, 16, 1);
                break;
            }
            case 'p': {
                void *ptr = va_arg(args, void *);
                emit_string("0x");
                written += 2 + print_unsigned((uintmax_t)(uintptr_t)ptr, 16, 0);
                break;
            }
            case 'c': {
                /* char is promoted to int when passed through varargs */
                char c = (char)va_arg(args, int);
                emit_char(c);
                written++;
                break;
            }
            case 's': {
                const char *s = va_arg(args, const char *);
                if (s == NULL) {
                    s = "(null)";
                }
                while (*s != '\0') {
                    emit_char(*s++);
                    written++;
                }
                break;
            }
            case '%': {
                emit_char('%');
                written++;
                break;
            }
            case '\0': {
                /* Trailing lone '%' at end of string — nothing sensible to
                 * do; back up so the outer loop's i++ doesn't skip past
                 * the NUL terminator. */
                i--;
                break;
            }
            default: {
                /* Unknown specifier — print it literally so mistakes are
                 * visible instead of silently swallowed. */
                emit_char('%');
                emit_char(format[i]);
                written += 2;
                break;
            }
        }
    }
 
    return written;
}
 
int kprintf(const char *format, ...) {
    va_list args;
    va_start(args, format);
    int written = kvprintf(format, args);
    va_end(args);
    return written;
}
 
