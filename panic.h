#ifndef PANIC_H
#define PANIC_H
 
/* Prints a "KERNEL PANIC" message (printf-style, same specifiers as
 * kprintf) in a distinct color, mirrors it to serial, disables
 * interrupts, and halts forever. Call this anywhere a failure is
 * unrecoverable and continuing would just corrupt state further or hang
 * mysteriously instead of failing loudly.
 *
 * Marked noreturn so the compiler knows code after panic() is
 * unreachable (helps catch bugs and silences some warnings). */
void panic(const char *format, ...) __attribute__((noreturn));
 
#endif /* PANIC_H */
