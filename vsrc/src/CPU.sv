`ifndef __TOP_SV
`define __TOP_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "include/csr.sv"
`include "src/CsrRegs.sv"
`include "src/Fetch.sv"
`include "src/MulDivUnit.sv"
`include "src/ALU.sv"
`include "src/Decoder.sv"
`include "src/Forward.sv"
`include "src/Hazard.sv"
`include "src/Mem.sv"
`include "src/RegFile.sv"
`include "src/Wb.sv"
`endif



module CPU import common::*; import csr_pkg::*; (
    input  logic        clk,reset,
    input  ibus_resp_t  iresp,
    output ibus_req_t   ireq,
    input  dbus_resp_t  fetch_dresp,
    output dbus_req_t   fetch_dreq,
    input  dbus_resp_t  dresp,
    output dbus_req_t   dreq,
    input  logic        mmu_fault_valid,
    input  u64          mmu_fault_vaddr,
    input  u64          mmu_fault_cause,
    input  logic        trint,
    input  logic        swint,
    input  logic        exint,
    output priv_mode_t  priv_mode_c,
    output logic        valid_c,
	output u64          pc_c,
	output u32          instr_c,
	output logic        w_en_c,
	output u8           wd_c,
	output i64          wdata_c,
	output i64          reg_c [0:31],
	output u64          mem_addr_c,
	output mem_op_t     mem_op_c,
	output u64          mhartid_c,
	output u64          mcycle_c,
	output u64          mstatus_c,
	output u64          mepc_c,
	output u64          mtvec_c,
	output u64          mcause_c,
	output u64          mtval_c,
	output u64          mip_c,
	output u64          mie_c,
	output u64          mscratch_c,
	output u64          satp_c,
	output u64          pmpaddr0_c,
	output u64          pmpcfg0_c,
	output u64          mideleg_c,
	output u64          medeleg_c,
	output u64          sepc_c,
	output u64          stval_c,
	output u64          stvec_c,
	output u64          scause_c,
	output u64          sscratch_c,
	output logic        custom_trap_commit,
	output logic        pipeline_flush_o
);

    /**
     * pipeline register
     */
    IF_ID_t  if_id;
    ID_EX_t  id_ex;
    EX_MEM_t ex_mem;
    MEM_WB_t mem_wb;

    /**
     * regfile i/o
     */
    RegFile_read_t  RegFile_read;
    RegFile_write_t RegFile_write;

    i64 rs1_data;
    i64 rs2_data;

    /**
     * Hazard ctrl
     */
    logic    hazard_stall;
    logic    stall_ex;
    logic    mem_busy;
    logic    atomic_busy;
    logic    mem_inst_done;
    logic    muldiv_busy;
    logic    wb_fire;
    MEM_WB_t wb_next;

    logic ex_mem_mem_op;
    logic ex_mem_system_op;
    logic ex_mem_system_stall;
    logic stall_fetch;

    logic    redirect_valid_alu;
    addr_t   redirect_pc_alu;
    addr_t   redirect_pc;
    logic    redirect_take_branch;
    logic    csr_commit_flush;

    logic    csr_write_pulse;
    u64      csr_write_value;
    u12      csr_write_addr_pulse;

    u64      csr_read_rdata_wire;
    priv_mode_t priv_mode;
    logic    ecall_commit;
    logic    trap_event;
    logic    pipeline_flush;
    logic    trap_suppress;
    logic    mret_sret_flush;
    logic    mret_commit;
    logic    sret_commit;
    logic    trap_to_s;
    logic    trap_en_csr;
    u64      trap_epc_csr;
    u64      trap_cause_csr;
    u64      trap_tval_csr;
    priv_mode_t trap_prev_priv_csr;
    u64      trap_vector_csr;
    u64      mtvec_eff;
    u64      stvec_eff;
    logic [5:0] trap_code_idx;
    logic    trap_is_interrupt;
    logic    mtvec_csr_in_flight;

    logic redirect_valid_fetch;
    addr_t   fetch_pc;

    logic trap_id_illegal;
    logic alu_trap_valid;
    u64    alu_trap_cause;
    u64    alu_trap_tval;
    u64    alu_trap_epc;
    logic mem_trap_valid;
    u64    mem_trap_cause;
    u64    mem_trap_tval;
    u64    mem_trap_epc;
    logic mmu_fault_effective;

    logic trint_prev;
    logic swint_prev;
    logic exint_prev;
    logic trint_new;
    logic swint_new;
    logic exint_new;
    logic interrupt_trap;
    u64    interrupt_cause;
    u64    interrupt_epc;
    logic  interrupt_epc_latched_valid;
    u64    interrupt_epc_latched;
    logic int_global_en;
    logic int_recheck_csr;
    logic swint_take;
    logic trint_take;
    logic exint_take;

    assign priv_mode_c = priv_mode;
    assign ireq = '0;
    assign ex_mem_mem_op = ex_mem.valid && ex_mem.mem_op != MEM_NONE;
    assign ex_mem_system_op = ex_mem.valid && (ex_mem.system_op != SYS_NONE);
    assign ex_mem_system_stall = ex_mem.valid && (ex_mem.system_op == SYS_ECALL);
    assign stall_fetch =
        hazard_stall | ex_mem_mem_op | ex_mem_system_stall | muldiv_busy;
    assign stall_ex =
        hazard_stall | (ex_mem_mem_op && !mem_inst_done) | ex_mem_system_stall;
    assign redirect_take_branch = redirect_valid_alu & ~stall_ex;
    assign csr_commit_flush     = wb_fire & wb_next.valid & wb_next.is_csr;
    assign ecall_commit         = wb_fire & wb_next.valid && (wb_next.system_op == SYS_ECALL);
    logic mret_in_ex;
    logic mret_in_wb;
    logic sret_in_ex;
    logic sret_in_wb;

    assign mret_in_ex = ex_mem.valid && (ex_mem.decoder_ctrl.instr == 32'h30200073);
    assign mret_in_wb = mem_wb.valid && (mem_wb.decoder_ctrl.instr == 32'h30200073);
    assign sret_in_ex = ex_mem.valid && (ex_mem.decoder_ctrl.instr == 32'h10200073);
    assign sret_in_wb = mem_wb.valid && (mem_wb.decoder_ctrl.instr == 32'h10200073);
    assign mret_commit = wb_fire && wb_next.valid &&
        (wb_next.system_op == SYS_MRET);
    assign sret_commit = wb_fire && wb_next.valid &&
        (wb_next.system_op == SYS_SRET);
    assign mret_sret_flush      = mret_commit | sret_commit;

    assign trap_id_illegal = id_ex.valid && id_ex.illegal;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            trint_prev <= 1'b0;
            swint_prev <= 1'b0;
            exint_prev <= 1'b0;
            interrupt_epc_latched_valid <= 1'b0;
            interrupt_epc_latched <= 64'b0;
        end else begin
            trint_prev <= trint;
            swint_prev <= swint;
            exint_prev <= exint;

            if (pipeline_flush) begin
                interrupt_epc_latched_valid <= 1'b0;
            end else if (!interrupt_epc_latched_valid &&
                    !mret_commit && !sret_commit &&
                    (swint_take || trint_take || exint_take)) begin
                interrupt_epc_latched_valid <= 1'b1;
                interrupt_epc_latched <= interrupt_epc;
            end
        end
    end

    assign trint_new = trint && !trint_prev;
    assign swint_new = swint && !swint_prev;
    assign exint_new = exint && !exint_prev;
    assign int_recheck_csr = wb_fire && wb_next.valid && wb_next.is_csr && (
        wb_next.csr_addr == CSR_MSTATUS ||
        wb_next.csr_addr == CSR_MIE     ||
        wb_next.csr_addr == CSR_MIP     ||
        wb_next.csr_addr == CSR_SSTATUS ||
        wb_next.csr_addr == CSR_SIE     ||
        wb_next.csr_addr == CSR_SIP
    );

    logic int_fetch_eval;
    logic int_mmode_mie_set;
    u64   mstatus_after_wb;
    assign int_fetch_eval = if_id.valid && int_priv_en;

    always_comb begin
        mstatus_after_wb  = mstatus_c;
        int_mmode_mie_set = 1'b0;
        if (wb_fire && wb_next.valid && wb_next.is_csr &&
                wb_next.csr_addr == CSR_MSTATUS &&
                csr_funct_writes_state(wb_next.csr_funct3, wb_next.csr_rsdata)) begin
            mstatus_after_wb = (~MSTATUS_MASK & mstatus_c) |
                (csr_write_result(
                    mstatus_c, wb_next.csr_rsdata, wb_next.csr_funct3, wb_next.result) &
                    MSTATUS_MASK);
            int_mmode_mie_set = (mstatus_after_wb[3] && !mstatus_c[3]) ||
                (mstatus_after_wb[8] && !mstatus_c[8]);
        end
    end

    always_comb begin
        interrupt_trap  = 1'b0;
        interrupt_cause = 64'b0;
        if (interrupt_epc_latched_valid) begin
            interrupt_epc = interrupt_epc_latched;
        end else if (int_mmode_mie_set) begin
            interrupt_epc = wb_next.decoder_ctrl.pc + 64'd4;
        end else if (int_recheck_csr)
            interrupt_epc = wb_next.decoder_ctrl.pc + 64'd4;
        else if (if_id.valid)
            interrupt_epc = if_id.decoder_ctrl.pc;
        else
            interrupt_epc = fetch_pc;
        swint_take      = 1'b0;
        trint_take      = 1'b0;
        exint_take      = 1'b0;
        if (!mret_commit && !sret_commit) begin
            if (priv_mode == PRIV_M) begin
                if (swint_global_en && int_mie_eff[3] && mip_c[3] && swint &&
                        (swint_new || int_mmode_mie_set ||
                         (int_recheck_csr && swint) || if_id.valid))
                    swint_take = 1'b1;
                if (trint_global_en && int_mie_eff[7] && mip_c[7] && trint &&
                        (trint_new || int_mmode_mie_set ||
                         (int_recheck_csr && trint) || if_id.valid))
                    trint_take = 1'b1;
                if (exint_global_en && int_mie_eff[11] && mip_c[11] && exint &&
                        (exint_new || int_mmode_mie_set ||
                         (int_recheck_csr && exint) || if_id.valid))
                    exint_take = 1'b1;
            end else begin
                if (swint_global_en && int_mie_eff[3] && mip_c[3] && swint &&
                        (swint_new || (int_recheck_csr && swint) || int_fetch_eval))
                    swint_take = 1'b1;
                if (trint_global_en && int_mie_eff[7] && mip_c[7] && trint &&
                        (trint_new || (int_recheck_csr && trint) || int_fetch_eval))
                    trint_take = 1'b1;
                if (exint_global_en && int_mie_eff[11] && mip_c[11] && exint &&
                        (exint_new || (int_recheck_csr && exint) || int_fetch_eval))
                    exint_take = 1'b1;
            end
        end
        if (swint_take) begin
            interrupt_trap  = 1'b1;
            interrupt_cause = 64'h8000_0000_0000_0003;
        end else if (trint_take) begin
            interrupt_trap  = 1'b1;
            interrupt_cause = 64'h8000_0000_0000_0007;
        end else if (exint_take) begin
            interrupt_trap  = 1'b1;
            interrupt_cause = 64'h8000_0000_0000_000B;
        end
    end

    assign mmu_fault_effective = mmu_fault_valid &&
        ((mmu_fault_cause != 64'd12) || (mmu_fault_vaddr == fetch_pc));

    function automatic logic csr_funct_writes_state(u3 f3, i64 csr_rs);
        unique case (f3)
            3'b001, /* CSRRW */
            3'b101: /* CSRRWI */
                    return 1'b1;
            3'b010, /* CSRRS */
            3'b011, /* CSRRC */
            3'b110, /* CSRRSI */
            3'b111: /* CSRRCI */
                    return csr_rs != 64'b0;
            default:
                return 1'b0;
        endcase
    endfunction

    function automatic logic instr_mtvec_csr_writes(u32 instr);
        u3  f3;
        u5  rs;
        logic imm;
        f3  = instr[14:12];
        rs  = instr[19:15];
        imm = (f3 == 3'b101 || f3 == 3'b110 || f3 == 3'b111);
        return instr[6:0] == 7'b1110011 && instr[31:20] == CSR_MTVEC[11:0] &&
            csr_funct_writes_state(f3, imm ? {59'b0, rs} : 64'b1);
    endfunction

    always_comb begin
        mtvec_csr_in_flight =
            (if_id.valid && instr_mtvec_csr_writes(if_id.decoder_ctrl.instr)) ||
            (id_ex.valid && id_ex.is_csr && id_ex.csr_addr == CSR_MTVEC) ||
            (ex_mem.valid && ex_mem.is_csr && ex_mem.csr_addr == CSR_MTVEC &&
                !(wb_fire && wb_next.valid && wb_next.is_csr &&
                    wb_next.csr_addr == CSR_MTVEC));
    end

    assign trap_event = mmu_fault_effective | trap_id_illegal | alu_trap_valid |
        mem_trap_valid |
        (interrupt_trap & !atomic_busy & !mtvec_csr_in_flight) | ecall_commit;
    assign pipeline_flush = trap_event | mret_sret_flush;
    assign trap_suppress  = mmu_fault_effective | trap_id_illegal | alu_trap_valid |
        mem_trap_valid |
        (interrupt_trap & !atomic_busy & !mtvec_csr_in_flight);

    assign redirect_valid_fetch =
        trap_event | mret_commit | sret_commit | csr_commit_flush | redirect_take_branch;
    assign redirect_pc =
        mret_commit ? mepc_c :
        (sret_commit ? sepc_c :
        (trap_event ? trap_vector_csr :
        (csr_commit_flush ? wb_next.decoder_ctrl.pc + 64'd4 :
        redirect_pc_alu)));

    always_comb begin : csr_commit_write
        automatic u64 raw;
        csr_write_pulse       = 1'b0;
        csr_write_value       = '0;
        csr_write_addr_pulse = '0;
        raw                   = wb_next.result;
        if (wb_fire && wb_next.valid && wb_next.is_csr &&
                csr_funct_writes_state(wb_next.csr_funct3, wb_next.csr_rsdata)) begin
                unique case (wb_next.csr_funct3)
                    3'b001, /* CSRRW */
                    3'b101: raw = wb_next.csr_rsdata; /* CSRRWI */
                    3'b010, /* CSRRS */
                    3'b110: raw = wb_next.result | wb_next.csr_rsdata; /* CSRRSI */
                    3'b011, /* CSRRC */
                    3'b111: raw = wb_next.result & (~wb_next.csr_rsdata); /* CSRRCI */
                    default: raw = wb_next.result;
                endcase
                csr_write_pulse       = 1'b1;
                csr_write_addr_pulse = csr_addr_t'(wb_next.csr_addr);
                csr_write_value      = raw;
            end
    end

    always_comb begin : trap_tvec_eff
        mtvec_eff = mtvec_c;
        stvec_eff = stvec_c;
        if (csr_write_pulse && csr_write_addr_pulse == CSR_MTVEC)
            mtvec_eff = (~MTVEC_MASK & mtvec_c) | (csr_write_value & MTVEC_MASK);
        if (csr_write_pulse && csr_write_addr_pulse == CSR_STVEC)
            stvec_eff = (~STVEC_MASK & stvec_c) | (csr_write_value & STVEC_MASK);
    end

    always_comb begin
        trap_en_csr        = 1'b0;
        trap_epc_csr       = wb_next.decoder_ctrl.pc;
        trap_cause_csr     = (priv_mode == PRIV_U) ? 64'd8 :
            ((priv_mode == PRIV_S) ? 64'd9 : 64'd11);
        trap_tval_csr      = 64'b0;
        trap_prev_priv_csr = priv_mode;
        trap_is_interrupt  = 1'b0;
        trap_code_idx      = trap_cause_csr[5:0];
        trap_to_s          = 1'b0;
        trap_vector_csr    = mtvec_eff;

        if (mmu_fault_effective) begin
            trap_en_csr        = 1'b1;
            trap_epc_csr       = (mmu_fault_cause == 64'd12) ?
                fetch_pc : ex_mem.decoder_ctrl.pc;
            trap_cause_csr     = mmu_fault_cause;
            trap_tval_csr      = mmu_fault_vaddr;
            trap_code_idx      = mmu_fault_cause[5:0];
        end else if (trap_id_illegal) begin
            trap_en_csr        = 1'b1;
            trap_epc_csr       = id_ex.decoder_ctrl.pc;
            trap_cause_csr     = 64'd2;
            trap_tval_csr      = {32'b0, id_ex.decoder_ctrl.instr};
            trap_code_idx      = 6'd2;
        end else if (alu_trap_valid) begin
            trap_en_csr        = 1'b1;
            trap_epc_csr       = alu_trap_epc;
            trap_cause_csr     = alu_trap_cause;
            trap_tval_csr      = alu_trap_tval;
            trap_code_idx      = alu_trap_cause[5:0];
        end else if (mem_trap_valid) begin
            trap_en_csr        = 1'b1;
            trap_epc_csr       = mem_trap_epc;
            trap_cause_csr     = mem_trap_cause;
            trap_tval_csr      = mem_trap_tval;
            trap_code_idx      = mem_trap_cause[5:0];
        end else if (interrupt_trap) begin
            trap_en_csr        = 1'b1;
            trap_epc_csr       = interrupt_epc;
            trap_cause_csr     = interrupt_cause;
            trap_tval_csr      = 64'b0;
            trap_code_idx      = interrupt_cause[5:0];
        end else if (ecall_commit) begin
            trap_en_csr = 1'b1;
        end

        trap_en_csr = trap_en_csr & trap_event;

        if (trap_en_csr) begin
            trap_is_interrupt = trap_cause_csr[63];
            if (priv_mode != PRIV_M) begin
                if (trap_is_interrupt)
                    trap_to_s = mideleg_c[trap_code_idx];
                else
                    trap_to_s = medeleg_c[trap_code_idx];
            end
            if (trap_is_interrupt && (trap_to_s ? stvec_eff[0] : mtvec_eff[0]))
                trap_vector_csr = {trap_to_s ? stvec_eff[63:2] : mtvec_eff[63:2], 2'b00} +
                    {56'b0, trap_code_idx, 2'b0};
            else
                trap_vector_csr = {trap_to_s ? stvec_eff[63:2] : mtvec_eff[63:2], 2'b00};
        end
    end

    function automatic u64 csr_write_result(
        input u64 old_val,
        input u64 rs_val,
        input u3  f3,
        input u64 wb_result
    );
        unique case (f3)
            3'b001, 3'b101: return rs_val;
            3'b010, 3'b110: return wb_result | rs_val;
            3'b011, 3'b111: return wb_result & (~rs_val);
            default:        return old_val;
        endcase
    endfunction

    logic int_mstatus_mie;
    logic int_mstatus_spp;
    logic int_sstatus_sie;
    logic int_priv_en;
    logic swint_global_en;
    logic trint_global_en;
    logic exint_global_en;
    u64   int_mie_eff;

    always_comb begin
        int_mstatus_mie = mstatus_c[3];
        int_mstatus_spp = mstatus_c[8];
        int_sstatus_sie = mstatus_c[1];
        int_mie_eff     = mie_c;
        int_priv_en     = (priv_mode != PRIV_M);
        int_global_en   = 1'b0;
        unique case (priv_mode)
            PRIV_M: int_global_en = mstatus_c[3] | mstatus_c[8];
            PRIV_S: int_global_en = mstatus_c[1];
            PRIV_U: int_global_en = mstatus_c[0];
            default: int_global_en = 1'b0;
        endcase
        if (mret_commit) begin
            int_mstatus_mie = mstatus_c[7];
            if (mstatus_c[12:11] != PRIV_M)
                int_priv_en = 1'b1;
        end else if (sret_commit) begin
            int_sstatus_sie = mstatus_c[5];
            int_priv_en     = 1'b1;
        end else if (wb_fire && wb_next.valid && wb_next.is_csr &&
                csr_funct_writes_state(wb_next.csr_funct3, wb_next.csr_rsdata)) begin
            if (wb_next.csr_addr == CSR_MSTATUS) begin
                automatic u64 mstatus_wb;
                mstatus_wb = (~MSTATUS_MASK & mstatus_c) |
                    (csr_write_result(
                        mstatus_c, wb_next.csr_rsdata, wb_next.csr_funct3, wb_next.result) &
                        MSTATUS_MASK);
                int_mstatus_mie = mstatus_wb[3];
                int_mstatus_spp = mstatus_wb[8];
                int_sstatus_sie = mstatus_wb[1];
            end
            if (wb_next.csr_addr == CSR_SSTATUS)
                int_sstatus_sie = (((~SSTATUS_MASK & mstatus_c) |
                    (csr_write_result(
                        mstatus_c, wb_next.csr_rsdata, wb_next.csr_funct3, wb_next.result) &
                        SSTATUS_MASK)) >> 1) != 64'd0;
            if (wb_next.csr_addr == CSR_MIE)
                int_mie_eff = csr_write_result(
                    mie_c, wb_next.csr_rsdata, wb_next.csr_funct3, wb_next.result);
            if (wb_next.csr_addr == CSR_SIE)
                int_mie_eff = (~SIE_MASK & mie_c) |
                    (csr_write_result(
                        mie_c, wb_next.csr_rsdata, wb_next.csr_funct3, wb_next.result) &
                        SIE_MASK);
        end

        swint_global_en = mideleg_c[3] ?
            ((priv_mode == PRIV_U) || ((priv_mode == PRIV_S) && int_sstatus_sie)) :
            ((priv_mode == PRIV_M) ? (int_mstatus_mie | int_mstatus_spp) :
            ((priv_mode != PRIV_M) || int_mstatus_mie));
        trint_global_en = mideleg_c[7] ?
            ((priv_mode == PRIV_U) || ((priv_mode == PRIV_S) && int_sstatus_sie)) :
            ((priv_mode == PRIV_M) ? (int_mstatus_mie | int_mstatus_spp) :
            ((priv_mode != PRIV_M) || int_mstatus_mie));
        exint_global_en = mideleg_c[11] ?
            ((priv_mode == PRIV_U) || ((priv_mode == PRIV_S) && int_sstatus_sie)) :
            ((priv_mode == PRIV_M) ? (int_mstatus_mie | int_mstatus_spp) :
            ((priv_mode != PRIV_M) || int_mstatus_mie));
    end

    CsrRegs csr_regs_inst (
                    .clk       (clk),
                    .reset     (reset),
                    .read_addr (ex_mem.csr_addr),
                    .read_data (csr_read_rdata_wire),
                    .write_en  (csr_write_pulse),
                    .write_addr(csr_write_addr_pulse),
                    .write_data(csr_write_value),
                    .trap_en   (trap_event),
                    .trap_to_s (trap_to_s),
                    .trap_epc  (trap_epc_csr),
                    .trap_cause(trap_cause_csr),
                    .trap_tval (trap_tval_csr),
                    .trap_prev_priv(trap_prev_priv_csr),
                    .mret_en   (mret_commit),
                    .sret_en   (sret_commit),
                    .hw_swint  (swint),
                    .hw_trint  (trint),
                    .hw_exint  (exint),
                    .dbg_mhartid  (mhartid_c),
                    .dbg_mcycle   (mcycle_c),
                    .dbg_mstatus  (mstatus_c),
                    .dbg_mepc     (mepc_c),
                    .dbg_mtvec    (mtvec_c),
                    .dbg_mcause   (mcause_c),
                    .dbg_mtval    (mtval_c),
                    .dbg_mip      (mip_c),
                    .dbg_mie      (mie_c),
                    .dbg_mscratch (mscratch_c),
                    .dbg_satp     (satp_c),
                    .dbg_pmpaddr0 (pmpaddr0_c),
                    .dbg_pmpcfg0  (pmpcfg0_c),
                    .dbg_mideleg  (mideleg_c),
                    .dbg_medeleg  (medeleg_c),
                    .dbg_sepc     (sepc_c),
                    .dbg_stval    (stval_c),
                    .dbg_stvec    (stvec_c),
                    .dbg_scause   (scause_c),
                    .dbg_sscratch (sscratch_c)
                );

    assign custom_trap_commit = wb_fire && wb_next.valid &&
        (wb_next.decoder_ctrl.instr == 32'h0005006b);

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            valid_c     <= 1'b0;
            pc_c        <= '0;
            instr_c     <= '0;
            w_en_c      <= 1'b0;
            wd_c        <= '0;
            wdata_c     <= '0;
            mem_addr_c  <= '0;
            mem_op_c    <= MEM_NONE;
        end else begin
            valid_c <= wb_fire && !trap_suppress;
            if (wb_fire) begin
                pc_c       <= wb_next.decoder_ctrl.pc;
                instr_c    <= wb_next.decoder_ctrl.instr;
                w_en_c     <= wb_next.reg_write;
                wd_c       <= {3'b0, wb_next.wd};
                wdata_c    <= wb_next.result;
                mem_addr_c <= wb_next.mem_addr;
                mem_op_c   <= wb_next.mem_op;
            end
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            priv_mode <= PRIV_M;
        else if (trap_event)
            priv_mode <= trap_to_s ? PRIV_S : PRIV_M;
        else if (mret_commit)
            priv_mode <= priv_mode_t'(mstatus_c[12:11]);
        else if (sret_commit)
            priv_mode <= mstatus_c[8] ? PRIV_S : PRIV_U;
    end

    /**
     * CPU models
     */
    Fetch fetch(
        .clk(clk),
        .reset(reset),
        .stall(stall_fetch),
        .priv_mode(priv_mode),
        .redirect_valid(redirect_valid_fetch),
        .redirect_pc(redirect_pc),
        .dresp(fetch_dresp),
        .dreq(fetch_dreq),
        .if_id(if_id),
        .fetch_pc(fetch_pc)
    );

    Decoder decoder(
        .clk(clk),
        .reset(reset),
        .stall(stall_fetch),
        .if_id(if_id),
        .id_ex(id_ex),
        .RegFile_read(RegFile_read),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );

    ALU ALU(
        .clk(clk),
        .reset(reset),
        .stall(stall_ex),
        .pipeline_flush(pipeline_flush),
        .muldiv_busy(muldiv_busy),
        .id_ex(id_ex),
        .mem_wb(mem_wb),
        .wb_fire(wb_fire),
        .wb_next(wb_next),
        .ex_mem(ex_mem),
        .redirect_valid(redirect_valid_alu),
        .redirect_pc(redirect_pc_alu),
        .trap_valid(alu_trap_valid),
        .trap_cause(alu_trap_cause),
        .trap_tval(alu_trap_tval),
        .trap_epc(alu_trap_epc)
    );

    Mem mem(
        .clk(clk),
        .reset(reset),
        .hazard_stall(hazard_stall),
        .priv_mode(priv_mode),
        .ex_mem(ex_mem),
        .csr_read_rdata(csr_read_rdata_wire),
        .pipeline_flush(pipeline_flush),
        .mem_wb(mem_wb),
        .dreq(dreq),
        .dresp(dresp),
        .mem_busy(mem_busy),
        .atomic_busy(atomic_busy),
        .mem_inst_done(mem_inst_done),
        .wb_fire(wb_fire),
        .wb_next(wb_next),
        .trap_valid(mem_trap_valid),
        .trap_cause(mem_trap_cause),
        .trap_tval(mem_trap_tval),
        .trap_epc(mem_trap_epc)
    );

    Wb wb(
        .mem_wb(mem_wb),
        .RegFile_write(RegFile_write)
    );

    RegFile regfile(
        .clk(clk),
        .reset(reset),
        .RegFile_read(RegFile_read),
        .RegFile_write(RegFile_write),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .reg_c(reg_c)
    );

    Hazard hazard(
        .id_ex(id_ex),
        .ex_mem(ex_mem),
        .stall(hazard_stall)
    );

    assign pipeline_flush_o = pipeline_flush;

    `UNUSED_OK({iresp});
endmodule
`endif
