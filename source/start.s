.section .text.start
.global _start
.align 4
.arm

@ if the binary is booted from Brahma/CakeHax/k9lh or 2xrsa
@ the entrypoint is <start + 0x0>
@ framebuffers are already set unless 2xrsa
_start:
    mov r0, #0x20000000
    ldr r0, [r0]
    ldr r1, .2xrsa_magic @ "FUCK"
    cmp r0, r1
    beq _set_2xrsa_framebuffers
    b _skip_gw
    nop
    nop
    nop
    nop
    nop @ dummy
    .2xrsa_magic: .word 0x4b435546

@ if the binary is booted from the GW exploit
@ the entrypoint is <start + 0x30>
_start_gw:

    @@wait for the arm11 kernel threads to be ready
    mov r1, #0x10000
    waitLoop9:
        sub r1, #1
        cmp r1, #0
        bgt waitLoop9

    mov r1, #0x10000
    waitLoop92:
        sub r1, #1
        cmp r1, #0
        bgt waitLoop92


    @ copy the payload to the standard entrypoint (0x23F00000)
    adr r0, _start
    add r1, r0, #0x100000
    ldr r2, .entry
    .copy_binary_fcram:
        cmp r0, r1
        ldrlt r3, [r0], #4
        strlt r3, [r2], #4
        blt .copy_binary_fcram

    @ setup framebuffers to look like Brahma/etc

    ldr r0, .gw_fba
    ldr r1, [r0, #0x18]
    and r1, #1
    ldr r1, [r0, r1, lsl #2] @ r1 := top framebuffer loc
    mov r2, r1               @ r2 := top framebuffer loc

    ldr r0, .gw_fbb
    ldr r3, [r0, #0xC]
    and r3, #1
    ldr r3, [r0, r3, lsl #2] @ r3 := bottom framebuffer loc

    ldr r0, .cakehax
    stmia r0, {r1,r2,r3}
    @ framebuffers properly set

    bl ctr_cache_clean_and_flush_all

    ldr r3, .entry
    bx r3

.gw_fba:    .word 0x080FFFC0 @ gw top framebuffer magic
.gw_fbb:    .word 0x080FFFD0 @ ^ bottom

.2xrsa_fba: .word 0x181E6000 @ 2xrsa top framebuffer start
.2xrsa_fbb: .word 0x1848F000 @ ^ bottom

.cakehax:   .word 0x23FFFE00 @ cakehax fb struct location
.entry:     .word 0x23F00000 @ brahma execution base address

_set_2xrsa_framebuffers:
    ldr r0, .cakehax
    ldr r1, .2xrsa_fba
    mov r2, r1
    ldr r3, .2xrsa_fbb
    stmia r0, {r1,r2,r3}
    @ fall through

_skip_gw:
    bl ctr_cache_clean_and_flush_all
    @ Disable caches / mpu
    mrc p15, 0, r4, c1, c0, 0  @ read control register
    bic r4, #(1<<12)           @ - instruction cache disable
    bic r4, #(1<<2)            @ - data cache disable
    bic r4, #(1<<0)            @ - mpu disable
    mcr p15, 0, r4, c1, c0, 0  @ write control register

    @ Clear bss
    ldr r0, =__bss_start
    ldr r1, =__bss_end
    mov r2, #0
    .bss_clr:
        cmp r0, r1
        strlt r2, [r0], #4
        blt .bss_clr

    @ Give read/write access to all the memory regions
    ldr r5, =0x33333333
    mcr p15, 0, r5, c5, c0, 2 @ write data access
    mcr p15, 0, r5, c5, c0, 3 @ write instruction access

    @ Sets MPU permissions and cache settings
    ldr r0, =0xFFFF001F	@ ffff0000 64k  | bootrom (unprotected / protected)
    ldr r1, =0x3000801B	@ 30000000 16k  | dtcm
    ldr r2, =0x01FF801D	@ 01ff8000 32k  | itcm
    ldr r3, =0x08000029	@ 08000000 2M   | arm9 mem (O3DS / N3DS) 
    ldr r4, =0x10000029	@ 10000000 2M   | io mem (ARM9 / first 2MB)
    ldr r5, =0x20000037	@ 20000000 256M | fcram (O3DS / N3DS)
    ldr r6, =0x1FF00027	@ 1FF00000 1M   | dsp / axi wram
    ldr r7, =0x1800002D	@ 18000000 8M   | vram (+ 2MB)
    mov r8, #0x2D
    mcr p15, 0, r0, c6, c0, 0
    mcr p15, 0, r1, c6, c1, 0
    mcr p15, 0, r2, c6, c2, 0
    mcr p15, 0, r3, c6, c3, 0
    mcr p15, 0, r4, c6, c4, 0
    mcr p15, 0, r5, c6, c5, 0
    mcr p15, 0, r6, c6, c6, 0
    mcr p15, 0, r7, c6, c7, 0
    mcr p15, 0, r8, c3, c0, 0	@ Write bufferable 0, 2, 5
    mcr p15, 0, r8, c2, c0, 0	@ Data cacheable 0, 2, 5
    mcr p15, 0, r8, c2, c0, 1	@ Inst cacheable 0, 2, 5

    @ Enable dctm
    ldr r1, =0x3000800A        @ set dtcm
    mcr p15, 0, r1, c9, c1, 0  @ set the dtcm Region Register

    @ Enable caches
    mrc p15, 0, r4, c1, c0, 0  @ read control register
    orr r4, r4, #(1<<18)       @ - itcm enable
    orr r4, r4, #(1<<16)       @ - dtcm enable
    orr r4, r4, #(1<<12)       @ - instruction cache enable
    orr r4, r4, #(1<<2)        @ - data cache enable
    orr r4, r4, #(1<<0)        @ - mpu enable
    mcr p15, 0, r4, c1, c0, 0  @ write control register

    @ Flush caches
    mov r5, #0
    mcr p15, 0, r5, c7, c5, 0  @ flush I-cache
    mcr p15, 0, r5, c7, c6, 0  @ flush D-cache
    mcr p15, 0, r5, c7, c10, 4 @ drain write buffer

    @ Fixes mounting of SDMC
    ldr r0, =0x10000020
    mov r1, #0x340
    str r1, [r0]

    mov sp, #0x27000000

    blx main
    b _start

@ code from https://github.com/gemarcano/libctr9/blob/6a3c0748c3e508e50eedcfa6f639bb29823eda4e/src/ctr_cache.s#L38
ctr_cache_clean_and_flush_all:
    mov r1, #0 @segment

    1:  @outer_loop
        mov r0, #0 @line
        2:  @inner_loop
            orr r2, r1, r0  @make r2 be the resulting combination of
                                  @segment and line

            mcr p15, 0, r2, c7, c14, 2  @Clean and flush the line

            add r0, r0, #0x20  @move line to next line

            @The number of lines depends on the cache size, 0x400 for the
            @3DS data cache since it has 8KB of cache. Refer to the ARM
            @documentation for more details.
            cmp r0, #0x400
            bne 2b  @inner_loop

        add r1, r1, #0x40000000
        cmp r1, #0x0
        bne 1b  @outer_loop

    mov r0, #0
    mcr p15, 0, r0, c7, c5, 0  @Flush instruction cache
    mcr p15, 0, r0, c7, c10, 4  @drain write buffer
    bx lr


.pool
