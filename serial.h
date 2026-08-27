#ifndef SERIAL_H
#define SERIAL_H
 
#include <stddef.h>
 
/* Initializes the COM1 serial port (0x3F8) for 38400 baud, 8N1 — the
 * classic OSDev-tutorial configuration. Call once, before any
 * serial_write* function.
 *
 * Returns 0 on success, non-zero if the port fails the loopback
 * self-test (this can genuinely happen — not every machine/VM has a
 * working serial port, so don't treat failure here as fatal). */
int serial_initialize(void);
 
void serial_write_char(char c);
void serial_write(const char *data, size_t size);
void serial_writestring(const char *data);
 
#endif /* SERIAL_H */
