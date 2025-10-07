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
.extern el3_main        /* C function: void el3_main(void) */

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
.align 0x1000
tee_l1_table:
    .rept L1_ENTRIES
    .quad 0
    .endr

/* ---------------------- VECTOR TABLE ------------------------ */
.align 11
vector_table:
    b sync_handler
    b irq_handler
    b fiq_handler
    b serror_handler

sync_handler:
    /* Determine cause; if SMC, forward to el3_main, otherwise handle/print/hang */
    mrs x0, esr_el3                 /* ESR_EL3 holds exception syndrome */
    ubfx x1, x0, #26, #6            /* Extract EC (Exception Class) */
    /* EC value for SMC instruction is 0x17 (32 decimal).  Compare and branch. */
    cmp x1, #0x17
    beq handle_smc_sync

    /* Not an SMC: save context and hang (or extend handlers). */
    /* For now, hang to simplify. */
    b hang

handle_smc_sync:
    /* On SMC sync exceptions, ELR_EL3 contains return address; x0..x7 hold params in AArch64 calling convention */
    /* Call into C-level el3_main. The C code should extract SMC args by reading registers or memory as needed. */
    /* Preserve caller-saved registers as needed (we'll call a normal branch-and-link to el3_main). */
    bl el3_main
    /* After el3_main returns, return from exception */
    eret

irq_handler:
    /* IRQ for EL3: for now, consume / hang. Extend to handle timers/interrupts */
    b hang

fiq_handler:
    b hang

serror_handler:
    b hang

/* -------------- START / PRIMARY INITIALIZATION --------------- */
_start:
    /* Mask all exceptions while we init */
    msr daifset, #0xf

    /* Setup stack pointer for EL3 */
    ldr x0, =stack_top
    mov sp, x0
    /* Align SP to 16 bytes for AArch64 ABI */
    and sp, sp, #0xFFFFFFFFFFFFFFF0

    /* Set Exception Vector Base Register for EL3 */
    ldr x0, =vector_table
    msr vbar_el3, x0
    isb

    /* Enable FP/SIMD access for EL1/EL0 when el1 is entered (optional but useful for C) */
    mrs x0, cpacr_el1
    orr x0, x0, #(0b11 << 20)    /* enable FP/SIMD for EL0/EL1 */
    msr cpacr_el1, x0
    isb

    /* Configure MAIR_EL3 - memory attribute encodings:
     * MAIR[0] = Normal memory, Outer/Inner WB WA (value 0xff)
     * MAIR[1] = Device-nGnRE memory (0x00 is usually used, but keep explicitly 0x04)
     * NOTE: Tune attributes to your system; below is a common basic assignment
     */
    mov x0, #(0xff)              /* Attr0 (byte 0) = 0xff (normal WB/WA) */
    orr x0, x0, #(0x04 << 8)     /* Attr1 (byte 1) = 0x04 (device) */
    orr x0, x0, #(0x00 << 16)    /* Attr2 (unused) */
    orr x0, x0, #(0x00 << 24)    /* Attr3 (unused) */
    msr mair_el3, x0
    isb

    /* Set TCR_EL3 for 4KB granule, TTBR0 size covering 48-bit VA (simple config).
     * We'll select settings to allow 48-bit input address space and 4KB granule.
     * TCR value composition is platform-specific; below is a conservative choice:
     *  - T0SZ = 16 (48-bit VA) => value 16 in bits [5:0]
     *  - TG0 = 0b00 (4KB)
     *  - SH0 = 0b11 (Inner Shareable)
     *  - ORGN0 & IRGN0 = 0b01/0b01 (Normal WB WA)
     * NOTE: If you need different cacheability, tune ORGN/IRGN.
     */
    mov x0, #(16)                /* T0SZ = 16 (48-bit VA space) */
    /* Build TCR with fields:
     *   T0SZ [5:0] = 16
     *   TG0  [15:14] = 0b00 (4KB)
     *   SH0  [13:12] = 0b11 (Inner)
     *   ORGN0[11:10] = 0b01
     *   IRGN0[9:8] = 0b01
     */
    lsl x1, x0, #0               /* x1 = T0SZ */
    orr x1, x1, #(0b00 << 14)    /* TG0 = 4KB */
    orr x1, x1, #(0b11 << 12)    /* SH0 = Inner */
    orr x1, x1, #(0b01 << 10)    /* ORGN0 = WBWA */
    orr x1, x1, #(0b01 << 8)     /* IRGN0 = WBWA */
    msr tcr_el3, x1
    isb

    /* Set TTBR0_EL3 to our tee_l1_table */
    ldr x0, =tee_l1_table
    msr ttbr0_el3, x0
    isb

    /* Initialize simple page tables for secure world: 1GB blocks for 0..4GB */
    bl init_page_tables

    /* Setup secure timer (clear value, disable for now) */
    mov x0, #0
    msr cntv_tval_el0, x0
    msr cntv_ctl_el0, x0
    isb

    /* Enable I & D caches in SCTLR_EL3 (we'll set M bit later after page tables are in place) */
    mrs x0, sctlr_el3
    /* Set C (bit 2) and I (bit 12) to enable caches later with MMU enabled */
    orr x0, x0, #(1 << 2)        /* C */
    orr x0, x0, #(1 << 12)       /* I */
    msr sctlr_el3, x0
    isb

    /* Finally enable MMU (set M bit) - after TTBR/MAIR/TCR prepared and page tables created */
    mrs x0, sctlr_el3
    orr x0, x0, #(1 << 0)        /* M = 1, enable MMU and caches as configured */
    msr sctlr_el3, x0
    isb

    /* Unmask exceptions if you want (we keep them masked until el3_main configures) */
    /* msr daifclr, #0xf */

    /* From here EL3 environment is ready. We don't immediately jump to non-secure,
     * instead hand over SMC handling to el3_main when SMCs occur.
     *
     * If desired to immediately jump to BL33 (non-secure kernel), set ELR_EL3, SPSR_EL3
     * and eret here. But in this stub we prefer to run as BL31: waiting for SMCs/handlers.
     */

    /* Wait forever here — SMCs will cause exceptions and sync_handler will call el3_main.
     * If you prefer to call el3_main now, just bl el3_main
     */
    b hang

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
    str x4, [x0, x3, lsl #3]     /* entry offset = index*8 */

    /* advance phys base by 1GB and index */
    add x2, x2, #GB
    add x3, x3, #1
    /* loop 4 times (4GB / 1GB) */
    cmp x3, #4
    blt 1b

    ret

/* -------------------- HANG / UTIL ------------------------------ */
hang:
    wfe
    b hang

/* End of file */