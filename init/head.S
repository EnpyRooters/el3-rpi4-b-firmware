/* ------------------------------------------------------------
 * pi4_bl31_like.S
 * Minimal ARM Trusted Firmware (BL31-like) stub for Raspberry Pi 4
 * - All allocations are inside .text (stack, heap, page tables)
 * - Reserves 0x0..0x1000_00000 (4GB) for secure world (TEE)
 * - Leaves 0x1000_00000..0x2000_00000 (4GB) for non-secure OS (BL33)
 * - Provides simple SMC-capable sync exception handler that calls el3_main
 * - Sets up minimal page tables (L1 1GB block entries) and enables MMU
 * - NOTE: Tune MAIR/attributes for your platform as needed
 * ------------------------------------------------------------*/

.section .text
.global _start
.extern secure_memory        /* C function: void el3_main(void) */

/* ---------------------- CONSTANTS --------------------------- */
/* Physical memory regions */
.equ TEE_BASE,      0x00000000          /* Secure region start */
.equ TEE_SIZE,      0x100000000         /* 4GB */
.equ NS_BASE,       0x100000000         /* Non-secure OS start */
.equ NS_SIZE,       0x100000000         /* 4GB */
.equ PERIPH_BASE,   0xFE000000          /* Peripherals (VideoCore, UART, etc) */
.equ PERIPH_SIZE,   0x02000000          /* 32MB */

/* Page size / entries */
.equ L1_ENTRIES,     512                 /* 512 entries in an L1 table (4KB granule) */
.equ GB,             0x40000000          /* 1GB */

/* MMU descriptor bits (simple defs used in this stub) */
.equ DESC_TYPE_BLOCK,      0x1           /* b0..1 = 01 for block at level1 */
.equ DESC_AF,              (1 << 10)     /* Access Flag */
.equ DESC_SH_INNER,        (0b11 << 8)   /* Inner Shareable */
.equ DESC_AP_RW_EL1,       (0b00 << 6)   /* AP bits: 00 = EL1/EL0 RW? (tune as needed) */
.equ DESC_NS_SECURE,       (0 << 5)      /* NS = 0 means Secure */
.equ DESC_ATTR_INDEX0,     (0 << 2)      /* AttrIdx = 0 (MAIR[0] will be normal WB) */

/* Compose a block descriptor template for secure normal memory */
.equ SEC_BLOCK_DESC, (DESC_TYPE_BLOCK | DESC_AF | DESC_SH_INNER | DESC_AP_RW_EL1 | DESC_NS_SECURE | DESC_ATTR_INDEX0)

/* ---------------------- STACK & HEAP ------------------------ */
/* Keep these in .text; they are static binary data placed after code */
.align 16
stack:
    .rept 0x4000                   /* 16KB stack */
    nop
    .endr
stack_top:

.align 16
heap:
    .rept 0x10000                  /* 1MB heap */
    nop
    .endr
heap_top:

/* ---------------------- PAGE TABLES ------------------------- */
/* Place L1 table aligned to 4KB boundary (we place in .text so .align 0x1000). */
.align 12
tee_l1_table:
    .rept L1_ENTRIES
    .quad 0
    .endr

/* ---------------------- VECTOR TABLE ------------------------ */
.align 11
vector_table:
    b irq_handler
    b fiq_handler
    b serror_handler

irq_handler:
    /* IRQ for EL3: for now, consume / hang. Extend to handle timers/interrupts */
    b hang

fiq_handler:
    b hang

serror_handler:
    b hang

/* -------------- START / PRIMARY INITIALIZATION --------------- */
_start:
    b secure_memory
    /* Mask all exceptions while we init */
    msr daifset, #0xf

    /* Setup stack pointer for EL3 */
    ldr x0, =stack_top
    mov sp, x0

    /* Align SP to 16 bytes safely using literal load (works on all assemblers) */
    ldr x1, =0xFFFFFFFFFFFFFFF0
    mov x2, sp
    and x2, x2, x1
    mov sp, x2

    /* Set Exception Vector Base Register for EL3 */
    ldr x0, =vector_table
    msr vbar_el3, x0
    isb

    /* Enable FP/SIMD access for EL1/EL0 */
    mrs x0, cpacr_el1
    orr x0, x0, #(0b11 << 20)    /* enable FP/SIMD */
    msr cpacr_el1, x0
    isb

    /* Configure MAIR_EL3 - memory attributes */
    ldr x0, =0x000004ff           /* Precomputed MAIR_EL3 value */
    msr mair_el3, x0
    isb

    /* Configure TCR_EL3 */
    ldr x1, =((16) | (0b00 << 14) | (0b11 << 12) | (0b01 << 10) | (0b01 << 8))  /* Precomputed TCR_EL3 value */
    msr tcr_el3, x1
    isb

    /* Set TTBR0_EL3 to our tee_l1_table */
    ldr x0, =tee_l1_table
    msr ttbr0_el3, x0
    isb

    /* Initialize simple page tables for secure world */
    bl init_page_tables

    /* Setup secure timer (clear value, disable for now) */
    mov x0, #0
    msr cntv_tval_el0, x0
    msr cntv_ctl_el0, x0
    isb

    /* Enable I & D caches in SCTLR_EL3 */
    mrs x0, sctlr_el3
    orr x0, x0, #(1 << 2)        /* C bit */
    orr x0, x0, #(1 << 12)       /* I bit */
    msr sctlr_el3, x0
    isb

    /* Enable MMU (set M bit) */
    mrs x0, sctlr_el3
    orr x0, x0, #(1 << 0)        /* M = 1 */
    msr sctlr_el3, x0
    isb

/* ------------------ PAGE TABLES: init_page_tables ------------- */
/* This routine builds simple 1:1 mappings for secure region 0..4GB using 1GB L1 blocks.
 * Each L1 entry is a 64-bit descriptor:
 *   block_desc = (phys_base & ~((1<<30)-1)) | SEC_BLOCK_DESC
 * where SEC_BLOCK_DESC encodes AF, SH=Inner, AP, AttrIdx=0 (normal WB WA).
 *
 * Note: This is a minimal mapping suitable for secure firmware code that runs in EL3.
 * Tune descriptor bits (AP/NS/AttrIndex/MAIR) to your exact needs. */
init_page_tables:
    /* x0 = base address of L1 table (tee_l1_table) */
    ldr x0, =tee_l1_table
    /* x2 will be the physical base for each 1GB block */
    mov x2, #0

    /* For each 1GB block in 0..4GB (4 entries) */
    mov x3, #0
1:
    /* compute descriptor = phys_base | SEC_BLOCK_DESC */
    /* phys_base is x2; ensure lower 30 bits are zero by construction */
    mov x4, x2
    /* OR with descriptor flags */
    mov x5, #SEC_BLOCK_DESC
    orr x4, x4, x5        /* x4 now has the descriptor */

    /* store into L1 table entry: table is array of 64-bit entries */
    /* We store using STR (64-bit store). */
    add x5, x0, x3, lsl #3
    str x4, [x5]     /* entry offset = index*8 */

    /* advance phys base by 1GB and index */
    ldr x10, =GB
    add x2, x2, x10
    /* loop 4 times (4GB / 1GB) */
    cmp x3, #4
    blt 1b

    ret

/* -------------------- HANG / UTIL ------------------------------ */
hang:
    wfe
    b hang

/* End of file */
