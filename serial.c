#include "serial.h"
 
#include <stdint.h>
 
/* Standard I/O port base for COM1. COM2-4 exist at other well-known ports
 * (0x2F8, 0x3E8, 0x2E8) if you ever need more than one. */
#define COM1_PORT 0x3F8
 
/* Offsets from the port base — this is the classic 8250/16550 UART
 * register layout. */
#define REG_DATA        0 /* read: RX buffer, write: TX buffer (when DLAB=0) */
#define REG_INT_ENABLE  1
#define REG_FIFO_CTRL   2
#define REG_LINE_CTRL   3
#define REG_MODEM_CTRL  4
#define REG_LINE_STATUS 5
 
static inline void outb(uint16_t port, uint8_t value) {
    __asm__ volatile ("outb %0, %1" : : "a"(value), "Nd"(port));
}
 
static inline uint8_t inb(uint16_t port) {
    uint8_t value;
    __asm__ volatile ("inb %1, %0" : "=a"(value) : "Nd"(port));
    return value;
}
 
int serial_initialize(void) {
    outb(COM1_PORT + REG_INT_ENABLE, 0x00); /* disable all interrupts — we poll instead */
    outb(COM1_PORT + REG_LINE_CTRL, 0x80);  /* enable DLAB to set the baud rate divisor */
    outb(COM1_PORT + REG_DATA, 0x03);       /* divisor low byte:  3 -> 38400 baud */
    outb(COM1_PORT + REG_INT_ENABLE, 0x00); /* divisor high byte: 0 */
    outb(COM1_PORT + REG_LINE_CTRL, 0x03);  /* 8 bits, no parity, one stop bit; also clears DLAB */
    outb(COM1_PORT + REG_FIFO_CTRL, 0xC7);  /* enable FIFO, clear it, 14-byte trigger threshold */
    outb(COM1_PORT + REG_MODEM_CTRL, 0x1E); /* set loopback mode for the self-test below */
 
    /* Self-test: send a known byte in loopback mode and check we read the
     * same byte back. Confirms the UART is actually present and working
     * before we trust it for real output. */
    outb(COM1_PORT + REG_DATA, 0xAE);
    if (inb(COM1_PORT + REG_DATA) != 0xAE) {
        return 1; /* faulty (or just doesn't exist in this environment) */
    }
 
    /* Leave loopback mode, switch to normal operation. */
    outb(COM1_PORT + REG_MODEM_CTRL, 0x0F);
    return 0;
}
 
static int transmit_ready(void) {
    /* Bit 5 of the line status register: transmitter holding register
     * empty, i.e. safe to write the next byte. */
    return inb(COM1_PORT + REG_LINE_STATUS) & 0x20;
}
 
void serial_write_char(char c) {
    while (!transmit_ready()) {
        /* busy-wait — fine for a polling-only debug channel this early;
         * revisit if this ever needs to not block */
    }
    outb(COM1_PORT + REG_DATA, (uint8_t)c);
}
 
void serial_write(const char *data, size_t size) {
    for (size_t i = 0; i < size; i++) {
        serial_write_char(data[i]);
    }
}
 
void serial_writestring(const char *data) {
    size_t i = 0;
    while (data[i] != '\0') {
        serial_write_char(data[i]);
        i++;
    }
}
 
