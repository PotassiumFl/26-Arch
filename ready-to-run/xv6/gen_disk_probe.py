#!/usr/bin/env python3
"""Assemble disk_probe.bin: verify MMIO disk magic + sector 0 data."""

import struct
from pathlib import Path

EXPECT_OFF = 0x80

def enc_u(op, rd, imm20):
    return (imm20 & 0xfffff) << 12 | rd << 7 | op

def enc_i(op, rd, rs1, imm12):
    imm12 &= 0xfff
    return imm12 << 20 | rs1 << 15 | (op & 0x7000) | rd << 7 | (op & 0x7f)

def enc_b(op, rs1, rs2, imm13):
    imm13 &= 0x1fff
    funct3 = (op >> 12) & 0x7
    b12 = (imm13 >> 12) & 1
    b10_5 = (imm13 >> 5) & 0x3f
    b4_1 = (imm13 >> 1) & 0xf
    b11 = (imm13 >> 11) & 1
    return b12 << 31 | b10_5 << 25 | rs2 << 20 | rs1 << 15 | funct3 << 12 | b4_1 << 8 | b11 << 7 | (op & 0x7f)

def add(rd, rs1, rs2):
    return rs2 << 20 | rs1 << 15 | rd << 7 | 0x33

def bne(rs1, rs2, off):
    return enc_b(0x63 | (0x1 << 12), rs1, rs2, off)

def enc_j(op, rd, imm21):
    imm21 &= 0x1fffff
    return ((imm21 >> 20) & 1) << 31 | ((imm21 >> 1) & 0x3ff) << 21 | ((imm21 >> 11) & 1) << 20 | ((imm21 >> 12) & 0xff) << 12 | rd << 7 | (op & 0x7f)

def auipc(rd, imm20):
    return (imm20 & 0xfffff) << 12 | rd << 7 | 0x17

def load_magic_const(insns):
    insns += [
        enc_u(0x37, 28, 0x44495),
        enc_i(0x13, 28, 28, 0x34b),
        (16 << 20) | (28 << 15) | (0x1 << 12) | (28 << 7) | 0x13,  # slli t3, t3, 16
        enc_u(0x37, 29, 0x1),
        enc_i(0x13, 29, 29, 0x234),
        add(28, 28, 29),
    ]

def main():
    insns = []
    insns += [enc_u(0x37, 2, 0x80000), enc_i(0x13, 2, 2, 0x100)]
    insns += [enc_u(0x37, 5, 0x40000), 0x0202b023]
    insns += [enc_u(0x37, 6, 0x40000), enc_i(0x13, 6, 6, 0x210)]
    insns += [enc_i(0x03 | 0x3000, 7, 6, 0)]
    insns += [enc_i(0x13, 0, 0, 0) for _ in range(4)]
    load_magic_const(insns)
    bne1 = len(insns)
    insns.append(0)
    insns += [enc_u(0x37, 6, 0x40000), enc_i(0x13, 6, 6, 8)]
    insns += [enc_i(0x03 | 0x3000, 7, 6, 0)]
    auipc_idx = len(insns)
    insns += [auipc(28, 0)]
    insns += [enc_i(0x13, 28, 28, EXPECT_OFF - auipc_idx * 4)]
    insns += [enc_i(0x03 | 0x3000, 29, 28, 0)]
    insns += [enc_i(0x13, 0, 0, 0) for _ in range(4)]
    bne2 = len(insns)
    insns.append(0)
    insns += [enc_i(0x13, 10, 0, 0), 0x0005006b]
    fail = len(insns)
    insns.append(enc_j(0x6f, 0, 0))
    insns[bne1] = bne(7, 28, (fail - bne1) * 4)
    insns[bne2] = bne(7, 29, (fail - bne2) * 4)

    code = b''.join(struct.pack('<I', x) for x in insns)
    pad = b'\x00' * (EXPECT_OFF - len(code))
    expected = struct.pack('<Q', struct.unpack('<Q', b'DISKTEST')[0])
    out = Path(__file__).with_name('disk_probe.bin')
    out.write_bytes(code + pad + expected)
    Path(__file__).with_name('disk_probe.img').write_bytes(b'DISKTEST' + b'\x00' * (512 - 8))
    print(f'Wrote {out} ({len(code + pad + expected)} bytes)')

if __name__ == '__main__':
    main()
