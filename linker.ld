ENTRY(_start)

SECTIONS
{
    /* Load address of firmware in memory */
    . = 0x88000;

    .init_main_functions :
    {
        __functions_start = .;
        KEEP(*(.init_main_functions))
        __functions_end = .;
    }

    /* --- Main code section --- */
    .text : {
        *(.text*)
    }

    .data : {
        *(.data)
    }

    /* --- EL3 Vector table --- */
    .vectors :
    {
        KEEP(*(.vectors))
    }

    /* --- Read-only data --- */
    .rodata ALIGN(8) :
    {
        *(.rodata.*)
        *(.rodata)
    }

    /* --- BSS --- */
    .bss : {
        __bss_start = .;
        *(.bss*)
        __bss_end = .;
    }

    /* --- Stack allocation --- */
    . = ALIGN(16);
    stack_start = .;
    . = . + 32768;       /* 32 KB stack */
    stack_end = .;        /* Top of stack */
}
