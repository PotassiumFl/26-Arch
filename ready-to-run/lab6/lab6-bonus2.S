# Lab 6 Bonus2: M-mode timer interrupt demo

.section .text
.globl _start

.set TIMER_DELTA, 1000
.set TICK_TARGET, 8

_start:
    jal     ra, init_uart
    la      t0, timer_handler
    csrw    mtvec, t0
    li      s2, 0
    li      s3, TICK_TARGET
    li      s4, 0
    li      a0, TIMER_DELTA
    jal     ra, set_timer
    jal     ra, print_banner
    li      t0, 0x80
    csrs    mie, t0
bonus_loop:
    blez    s3, bonus_done
    csrsi   mstatus, 8
int_gate:
    csrci   mstatus, 8
    j       bonus_loop
bonus_done:
    jal     ra, print_done
    li      a0, 0
    .word   0x0005006b
bonus_spin:
    j       bonus_spin

init_uart:
    lui     a5, 0x40600
    li      a4, 3
    sb      a4, 12(a5)
    ret

putchar:
    beq     a0, zero, putchar_done
    li      a5, 10
    bne     a0, a5, putchar_write
    lui     a4, 0x40600
    li      a5, 13
    sb      a5, 4(a4)
    li      a5, 10
    sb      a5, 4(a4)
    ret
putchar_write:
    lui     a4, 0x40600
    sb      a0, 4(a4)
putchar_done:
    ret

putstr:
    lbu     a1, 0(a0)
    beqz    a1, putstr_done
putstr_loop:
    lbu     a1, 0(a0)
    beqz    a1, putstr_done
    mv      t0, a0
    mv      a0, a1
    jal     ra, putchar
    mv      a0, t0
    addi    a0, a0, 1
    j       putstr_loop
putstr_done:
    ret

putdec_u:
    mv      t3, a0
    li      t0, 10
    bltu    a0, t0, putdec_emit
    divu    a0, a0, t0
    mv      t4, a0
    mv      a0, t4
    jal     ra, putdec_u
    mv      a0, t3
    remu    a0, a0, t0
putdec_emit:
    addi    a0, a0, 48
    j       putchar

clear_timer:
    lui     a5, 0x38004
    li      a4, -1
    sd      a4, 0(a5)
clear_timer_wait:
    csrr    a5, mip
    andi    a5, a5, 128
    bnez    a5, clear_timer_wait
    ret

set_timer:
    add     s4, s4, a0
    lui     a5, 0x38004
    sd      s4, 0(a5)
    ret

print_banner:
    mv      s1, ra
    li      a0, 76
    jal     ra, putchar
    li      a0, 97
    jal     ra, putchar
    li      a0, 98
    jal     ra, putchar
    li      a0, 54
    jal     ra, putchar
    li      a0, 32
    jal     ra, putchar
    li      a0, 66
    jal     ra, putchar
    li      a0, 111
    jal     ra, putchar
    li      a0, 110
    jal     ra, putchar
    li      a0, 117
    jal     ra, putchar
    li      a0, 115
    jal     ra, putchar
    li      a0, 50
    jal     ra, putchar
    li      a0, 58
    jal     ra, putchar
    li      a0, 32
    jal     ra, putchar
    li      a0, 116
    jal     ra, putchar
    li      a0, 105
    jal     ra, putchar
    li      a0, 109
    jal     ra, putchar
    li      a0, 101
    jal     ra, putchar
    li      a0, 114
    jal     ra, putchar
    li      a0, 32
    jal     ra, putchar
    li      a0, 105
    jal     ra, putchar
    li      a0, 110
    jal     ra, putchar
    li      a0, 116
    jal     ra, putchar
    li      a0, 101
    jal     ra, putchar
    li      a0, 114
    jal     ra, putchar
    li      a0, 114
    jal     ra, putchar
    li      a0, 117
    jal     ra, putchar
    li      a0, 112
    jal     ra, putchar
    li      a0, 116
    jal     ra, putchar
    li      a0, 32
    jal     ra, putchar
    li      a0, 100
    jal     ra, putchar
    li      a0, 101
    jal     ra, putchar
    li      a0, 109
    jal     ra, putchar
    li      a0, 111
    jal     ra, putchar
    li      a0, 10
    jal     ra, putchar
    mv      ra, s1
    ret

print_tick:
    mv      s1, ra
    li      a0, 84
    jal     ra, putchar
    li      a0, 105
    jal     ra, putchar
    li      a0, 109
    jal     ra, putchar
    li      a0, 101
    jal     ra, putchar
    li      a0, 114
    jal     ra, putchar
    li      a0, 32
    jal     ra, putchar
    li      a0, 116
    jal     ra, putchar
    li      a0, 105
    jal     ra, putchar
    li      a0, 99
    jal     ra, putchar
    li      a0, 107
    jal     ra, putchar
    li      a0, 32
    jal     ra, putchar
    li      a0, 35
    jal     ra, putchar
    addi    a0, s2, 48
    jal     ra, putchar
    li      a0, 10
    jal     ra, putchar
    mv      ra, s1
    ret

print_done:
    mv      s1, ra
    li      a0, 66
    jal     ra, putchar
    li      a0, 111
    jal     ra, putchar
    li      a0, 110
    jal     ra, putchar
    li      a0, 117
    jal     ra, putchar
    li      a0, 115
    jal     ra, putchar
    li      a0, 50
    jal     ra, putchar
    li      a0, 32
    jal     ra, putchar
    li      a0, 116
    jal     ra, putchar
    li      a0, 105
    jal     ra, putchar
    li      a0, 109
    jal     ra, putchar
    li      a0, 101
    jal     ra, putchar
    li      a0, 114
    jal     ra, putchar
    li      a0, 32
    jal     ra, putchar
    li      a0, 116
    jal     ra, putchar
    li      a0, 101
    jal     ra, putchar
    li      a0, 115
    jal     ra, putchar
    li      a0, 116
    jal     ra, putchar
    li      a0, 32
    jal     ra, putchar
    li      a0, 102
    jal     ra, putchar
    li      a0, 105
    jal     ra, putchar
    li      a0, 110
    jal     ra, putchar
    li      a0, 105
    jal     ra, putchar
    li      a0, 115
    jal     ra, putchar
    li      a0, 104
    jal     ra, putchar
    li      a0, 101
    jal     ra, putchar
    li      a0, 100
    jal     ra, putchar
    li      a0, 46
    jal     ra, putchar
    li      a0, 10
    jal     ra, putchar
    mv      ra, s1
    ret

timer_handler:
    csrr    t0, mepc
    la      t1, int_gate
    bne     t0, t1, handler_fail
    addi    s2, s2, 1
    jal     ra, print_tick
    addi    s3, s3, -1
    jal     ra, clear_timer
    li      a0, TIMER_DELTA
    jal     ra, set_timer
    mret

handler_fail:
    li      a0, 70
    jal     ra, putchar
    li      a0, 65
    jal     ra, putchar
    li      a0, 73
    jal     ra, putchar
    li      a0, 76
    jal     ra, putchar
    li      a0, 10
    jal     ra, putchar
    .word   0x0005006b
    j       handler_fail
