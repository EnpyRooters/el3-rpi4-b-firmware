#include <stdint.h>

/* ------------------- Platform-specific constants ------------------- */

/* UART MMIO for logging (replace with your platform's UART base) */
#define UART0_BASE 0xFE201000UL
#define UART_DR    (UART0_BASE + 0x00)

/* Secure memory region from head.s */
#define TEE_BASE    0x000000000ULL
#define TEE_SIZE    0x100000000ULL  /* 4 GB */

/* Non-secure region */
#define NS_BASE     0x100000000ULL
#define NS_SIZE     0x100000000ULL  /* 4 GB */

/* Peripheral region */
#define PERIPH_BASE 0x0FE000000ULL
#define PERIPH_SIZE 0x02000000ULL   /* 32 MB */

/* Deny code for SMCs */
#define SMC_DENIED 0xFFFFFFFFFFFFFFFFULL

/* ------------------- Basic MMIO helpers ------------------- */
static inline void mmio_write32(uintptr_t addr, uint32_t val) {
    *((volatile uint32_t*)addr) = val;
}

static inline uint32_t mmio_read32(uintptr_t addr) {
    return *((volatile uint32_t*)addr);
}

/* ------------------- UART logging ------------------- */
static void uart_putc(char c) {
    mmio_write32(UART_DR, (uint32_t)c);
}

static void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

static void uart_hex32(uint32_t val) {
    const char *hex = "0123456789ABCDEF";
    for (int i = 7; i >= 0; --i) {
        uart_putc(hex[(val >> (i*4)) & 0xF]);
    }
}

/* ------------------- ESR/SMC helpers ------------------- */
static inline uint64_t read_esr_el3(void) {
    uint64_t val;
    asm volatile("mrs %0, esr_el3" : "=r"(val));
    return val;
}

static inline void write_x0(uint64_t val) {
    asm volatile("mov x0, %0" :: "r"(val) : "x0");
}

/* ------------------- Policy enforcement functions ------------------- */

/* Deny any SMC (secure monitor call) */
void deny_smc_if_detected(void) {
    uint64_t esr = read_esr_el3();
    uint32_t ec = (esr >> 26) & 0x3F; /* Exception Class */

    if (ec == 0x16) { /* 0x16 = SMC instruction */
        uart_puts("[EL3] SMC detected -> DENIED\n");
        write_x0(SMC_DENIED);
    }
}

/* ------------------- Secure memory access helpers ------------------- */

/* Check if an address is inside the secure TEE region */
static inline int is_secure_addr(uint64_t addr, uint64_t size) {
    if (addr >= TEE_BASE && (addr + size) <= (TEE_BASE + TEE_SIZE)) {
        return 1;
    }
    return 0;
}

/* Safe read from secure memory (EL3 only) */
uint32_t secure_read32(uint64_t addr) {
    if (!is_secure_addr(addr, 4)) {
        uart_puts("[EL3] Attempted read outside TEE region -> DENIED\n");
        return 0; /* Return 0 for denied read */
    }
    return *((volatile uint32_t*)addr);
}

/* Safe write to secure memory (EL3 only) */
void secure_write32(uint64_t addr, uint32_t val) {
    if (!is_secure_addr(addr, 4)) {
        uart_puts("[EL3] Attempted write outside TEE region -> DENIED\n");
        return;
    }
    *((volatile uint32_t*)addr) = val;
}

/* ------------------- Peripheral access helpers ------------------- */

/* Placeholder: mediate access to GPIO/UART/peripherals */
void secure_periph_write(uint64_t addr, uint32_t val) {
    if (addr < PERIPH_BASE || addr >= (PERIPH_BASE + PERIPH_SIZE)) {
        uart_puts("[EL3] Peripheral write out of range -> DENIED\n");
        return;
    }
    mmio_write32(addr, val);
}

uint32_t secure_periph_read(uint64_t addr) {
    if (addr < PERIPH_BASE || addr >= (PERIPH_BASE + PERIPH_SIZE)) {
        uart_puts("[EL3] Peripheral read out of range -> DENIED\n");
        return 0;
    }
    return mmio_read32(addr);
}

/* ------------------- Initialization ------------------- */

/* Freestanding init function called after head.s setup */
void el3_security_init(void) {
    uart_puts("[EL3] Security module initialized\n");
    uart_puts("[EL3] Ready to deny SMCs and protect secure memory\n");
}

/* ------------------- Example usage ------------------- */
void example_smc_entry(void) {
    /* Call this at any synchronous exception trap in EL3 */
    deny_smc_if_detected();
}

/* Optional: test secure memory access */
void secure_memory(void) {
    uart_puts("[EL3] Testing secure memory\n");
    secure_write32(TEE_BASE + 0x100, 0xdeadbeef);
    uint32_t val = secure_read32(TEE_BASE + 0x100);
    uart_puts("[EL3] Read value: 0x");
    uart_hex32(val);
    uart_puts("\n");
}