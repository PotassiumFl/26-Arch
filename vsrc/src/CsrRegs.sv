`ifndef __CSR_REGS_SV
`define __CSR_REGS_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "include/csr.sv"
`endif

module CsrRegs import common::*; import csr_pkg::*; (
    input  logic   clk,
    input  logic   reset,
    input  u12     read_addr,
    output u64     read_data,
    input  logic   write_en,
    input  u12     write_addr,
    input  u64     write_data,
    input  logic   trap_en,
    input  logic   trap_to_s,
    input  u64     trap_epc,
    input  u64     trap_cause,
    input  u64     trap_tval,
    input  priv_mode_t trap_prev_priv,
    input  logic   mret_en,
    input  logic   sret_en,
    input  logic   hw_swint,
    input  logic   hw_trint,
    input  logic   hw_exint,
    output u64     dbg_mhartid,
    output u64     dbg_mcycle,
    output u64     dbg_mstatus,
    output u64     dbg_mepc,
    output u64     dbg_mtvec,
    output u64     dbg_mcause,
    output u64     dbg_mtval,
    output u64     dbg_mip,
    output u64     dbg_mie,
    output u64     dbg_mscratch,
    output u64     dbg_satp,
    output u64     dbg_mideleg,
    output u64     dbg_medeleg,

    output u64     dbg_sepc,
    output u64     dbg_stval,
    output u64     dbg_stvec,
    output u64     dbg_scause,
    output u64     dbg_sscratch
);

    u64 mcycle_r;

    assign dbg_mhartid = 64'd0;

    u64 mstatus_r, mie_r, mtvec_r, mscratch_r, mepc_r, mcause_r, mtval_r, mip_r,
        satp_r, medeleg_r, mideleg_r;
    u64 pmpaddr0_r, pmpcfg0_r;
    u64 stvec_r, sscratch_r, sepc_r, scause_r, stval_r, sie_r, sip_r;

    assign dbg_mcycle   = mcycle_r;
    assign dbg_mstatus  = mstatus_r;
    assign dbg_mepc     = mepc_r;
    assign dbg_mtvec    = mtvec_r;
    assign dbg_mcause   = mcause_r;
    assign dbg_mtval    = mtval_r;
    assign dbg_mip      = mip_r |
        ({63'b0, hw_swint} << 3) |
        ({63'b0, hw_trint} << 7) |
        ({63'b0, hw_exint} << 11);
    assign dbg_mie      = mie_r;
    assign dbg_mscratch = mscratch_r;
    assign dbg_satp     = satp_r;
    assign dbg_mideleg  = mideleg_r;
    assign dbg_medeleg  = medeleg_r;
    assign dbg_sepc     = sepc_r;
    assign dbg_stval    = stval_r;
    assign dbg_stvec    = stvec_r;
    assign dbg_scause   = scause_r;
    assign dbg_sscratch = sscratch_r;

    always_comb begin
        read_data = 64'b0;
        unique case (read_addr)
            CSR_MHARTID:  read_data = 64'b0;
            CSR_MSTATUS:  read_data = mstatus_r;
            CSR_MIE:      read_data = mie_r;
            CSR_MTVEC:    read_data = mtvec_r;
            CSR_MSCRATCH: read_data = mscratch_r;
            CSR_MEPC:     read_data = mepc_r;
            CSR_MCAUSE:   read_data = mcause_r;
            CSR_MTVAL:    read_data = mtval_r;
            CSR_MIP:      read_data = dbg_mip;
            CSR_SATP:     read_data = satp_r;
            CSR_MEDELEG:  read_data = medeleg_r;
            CSR_MIDELEG:  read_data = mideleg_r;
            CSR_MCYCLE:   read_data = mcycle_r;
            CSR_PMPADDR0: read_data = pmpaddr0_r;
            CSR_PMPCFG0:  read_data = pmpcfg0_r;
            CSR_SSTATUS:  read_data = mstatus_r & SSTATUS_MASK;
            CSR_STVEC:    read_data = stvec_r;
            CSR_SSCRATCH: read_data = sscratch_r;
            CSR_SEPC:     read_data = sepc_r;
            CSR_SCAUSE:   read_data = scause_r;
            CSR_STVAL:    read_data = stval_r;
            CSR_SIE:      read_data = sie_r;
            CSR_SIP:      read_data = sip_r;
            default:      read_data = 64'b0;
        endcase
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            mcycle_r    <= '0;
            mstatus_r   <= '0;
            mie_r       <= '0;
            mtvec_r     <= '0;
            mscratch_r  <= '0;
            mepc_r      <= '0;
            mcause_r    <= '0;
            mtval_r     <= '0;
            mip_r       <= '0;
            satp_r      <= '0;
            medeleg_r   <= '0;
            mideleg_r   <= '0;
            pmpaddr0_r  <= '0;
            pmpcfg0_r   <= '0;
            stvec_r     <= '0;
            sscratch_r  <= '0;
            sepc_r      <= '0;
            scause_r    <= '0;
            stval_r     <= '0;
            sie_r       <= '0;
            sip_r       <= '0;
        end
        else begin
            if (write_en && write_addr == CSR_MCYCLE)
                mcycle_r <= write_data;
            else
                mcycle_r <= mcycle_r + 64'd1;

            if (trap_en) begin
                if (trap_to_s) begin
                    sepc_r       <= trap_epc;
                    scause_r     <= trap_cause;
                    stval_r      <= trap_tval;
                    mstatus_r[5] <= mstatus_r[1];      // SPIE <= SIE
                    mstatus_r[1] <= 1'b0;              // SIE <= 0
                    mstatus_r[8] <= (trap_prev_priv == PRIV_S); // SPP
                end else begin
                    mepc_r           <= trap_epc;
                    mcause_r         <= trap_cause;
                    mtval_r          <= trap_tval;
                    mstatus_r[7]     <= mstatus_r[3];      // MPIE <= MIE
                    mstatus_r[3]     <= 1'b0;              // MIE <= 0
                    mstatus_r[12:11] <= trap_prev_priv;
                end
            end
            else if (mret_en) begin
                mstatus_r[3]    <= mstatus_r[7];      // MIE <= MPIE
                mstatus_r[7]    <= 1'b1;              // MPIE <= 1
                mstatus_r[12:11]<= PRIV_U;
                if (mstatus_r[12:11] != PRIV_M)
                    mstatus_r[17] <= 1'b0;            // MPRV <= 0 when returning below M
            end
            else if (sret_en) begin
                mstatus_r[1] <= mstatus_r[5];         // SIE <= SPIE
                mstatus_r[5] <= 1'b1;                 // SPIE <= 1
                mstatus_r[8] <= 1'b0;                 // SPP <= U
                mstatus_r[17] <= 1'b0;                // y != M => clear MPRV
            end
            else if (write_en && write_addr != CSR_MCYCLE) begin
                unique case (write_addr)
                    CSR_MSTATUS:
                        mstatus_r <= (~MSTATUS_MASK & mstatus_r) |
                            (write_data & MSTATUS_MASK);
                    CSR_SSTATUS:
                        mstatus_r <= (~SSTATUS_MASK & mstatus_r) |
                            (write_data & SSTATUS_MASK);
                    CSR_MIE: mie_r <= write_data;
                    CSR_SIE:
                        sie_r <= (~SIE_MASK & sie_r) | (write_data & SIE_MASK);
                    CSR_MTVEC:
                        mtvec_r <= (~MTVEC_MASK & mtvec_r) |
                            (write_data & MTVEC_MASK);
                    CSR_STVEC:
                        stvec_r <= (~STVEC_MASK & stvec_r) |
                            (write_data & STVEC_MASK);
                    CSR_MSCRATCH: mscratch_r <= write_data;
                    CSR_SSCRATCH: sscratch_r <= write_data;
                    CSR_MEPC: mepc_r <= write_data;
                    CSR_SEPC: sepc_r <= write_data;
                    CSR_MCAUSE: mcause_r <= write_data;
                    CSR_SCAUSE: scause_r <= write_data;
                    CSR_MTVAL: mtval_r <= write_data;
                    CSR_STVAL: stval_r <= write_data;
                    CSR_MIP:
                        mip_r <= (~MIP_MASK & mip_r) | (write_data & MIP_MASK);
                    CSR_SIP:
                        sip_r <= (~SIP_MASK & sip_r) | (write_data & SIP_MASK);
                    CSR_SATP: satp_r <= write_data;
                    CSR_MEDELEG:
                        medeleg_r <= (~MEDELEG_MASK & medeleg_r) |
                            (write_data & MEDELEG_MASK);
                    CSR_MIDELEG:
                        mideleg_r <= (~MIDELEG_MASK & mideleg_r) |
                            (write_data & MIDELEG_MASK);
                    CSR_PMPADDR0: pmpaddr0_r <= write_data;
                    CSR_PMPCFG0:  pmpcfg0_r <= write_data;
                    default: ;
                endcase
            end
        end
    end

endmodule

`endif
