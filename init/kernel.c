// Declare a function pointer to the kernel entry point
typedef void (*kernel_entry_t)(void);

// This is an external function you might jump to later
extern void secure_memory(void);

// Simple delay loop (rough approximation, since we don't have timers)
void delay(volatile unsigned int count) {
    while (count--) {
        __asm__ volatile ("nop"); // prevent optimization
    }
}

// The "stub" main
void kernel(void) {
    // Kernel address
    uintptr_t kernel_addr = 0x200000;
    kernel_entry_t kernel_entry = (kernel_entry_t)kernel_addr;

    // Optional: small delay before jumping
    delay(1000000);

    // Jump to kernel
    kernel_entry();

    // If the kernel returns (usually it won't), jump to external function
    secure_memeory();

    // If all else fails, loop forever
    while (1) {
        __asm__ volatile ("wfi"); // wait for interrupt
    }
}
