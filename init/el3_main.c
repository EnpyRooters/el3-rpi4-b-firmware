// main.c - EL3 Secure Monitor Dispatcher (for Pi 4 firmware)

#include <stdint.h>

/* ------------------------- Minimal UART (optional debug) ------------------------- */
#define UART0_BASE 0xFE201000UL
#define UART0_DR   ((volatile uint32_t *)(UART0_BASE + 0x00))
#define UART0_FR   ((volatile uint32_t *)(UART0_BASE + 0x18))

static inline void uart_putc(char c) {
    while (*UART0_FR & (1 << 5)) {}
    *UART0_DR = c;
}

static void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

static void uart_init(void) {
    uart_puts("EL3 UART initialized.\n");
}

/* ------------------------- External SMC handler ------------------------- */
/* This is defined outside of the firmware. It will receive all arguments
   from the SMC call and return results to be written back to the calling EL. */
extern void smc_handler(
    uint64_t arg0, uint64_t arg1, uint64_t arg2, uint64_t arg3,
    uint64_t arg4, uint64_t arg5, uint64_t arg6, uint64_t arg7,
    uint64_t *ret0, uint64_t *ret1, uint64_t *ret2, uint64_t *ret3
);

/* ------------------------- EL3 main entry ------------------------- */
/* Called from head.S when an SMC instruction occurs */
void el3_main(void) {
    uart_init();
    uart_puts("EL3 Secure Monitor Call Received.\n");

    /* Read SMC arguments from x0-x7 */
    uint64_t x[8];
    __asm__ volatile(
        "mov %[x0], x0\n"
        "mov %[x1], x1\n"
        "mov %[x2], x2\n"
        "mov %[x3], x3\n"
        "mov %[x4], x4\n"
        "mov %[x5], x5\n"
        "mov %[x6], x6\n"
        "mov %[x7], x7\n"
        : [x0]"=r"(x[0]), [x1]"=r"(x[1]), [x2]"=r"(x[2]), [x3]"=r"(x[3]),
          [x4]"=r"(x[4]), [x5]"=r"(x[5]), [x6]"=r"(x[6]), [x7]"=r"(x[7])
    );

    /* Prepare return values */
    uint64_t r[4] = {0, 0, 0, 0};

    /* Call external handler */
    smc_handler(x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7],
                         &r[0], &r[1], &r[2], &r[3]);

    /* Write results back to x0-x3 so the caller sees them */
    __asm__ volatile(
        "mov x0, %[r0]\n"
        "mov x1, %[r1]\n"
        "mov x2, %[r2]\n"
        "mov x3, %[r3]\n"
        :
        : [r0]"r"(r[0]), [r1]"r"(r[1]), [r2]"r"(r[2]), [r3]"r"(r[3])
    );

    /* Return immediately to the lower EL (head.S will handle eret) */
}