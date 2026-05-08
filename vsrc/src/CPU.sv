`ifndef __TOP_SV
`define __TOP_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "include/csr.sv"
`include "src/CsrRegs.sv"
`include "src/Fetch.sv"
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
    input  dbus_resp_t  dresp,
    output dbus_req_t   dreq,
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
	output u64          mideleg_c,
	output u64          medeleg_c,
	output u64          sepc_c,
	output u64          stval_c,
	output u64          stvec_c,
	output u64          scause_c,
	output u64          sscratch_c
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
    logic    wb_fire;
    MEM_WB_t wb_next;

    logic ex_mem_mem_op;
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

    logic redirect_valid_fetch;

    assign ex_mem_mem_op = ex_mem.valid && ex_mem.mem_op != MEM_NONE;
    assign stall_fetch =
        hazard_stall | ex_mem_mem_op;
    assign stall_ex =
        hazard_stall | (ex_mem_mem_op && !(mem_busy && dresp.data_ok));
    assign redirect_take_branch = redirect_valid_alu & ~stall_ex;
    assign csr_commit_flush     = wb_fire & wb_next.valid & wb_next.is_csr;
    assign redirect_valid_fetch =
        csr_commit_flush | redirect_take_branch;
    assign redirect_pc = csr_commit_flush ?
        wb_next.decoder_ctrl.pc + 64'd4 :
        redirect_pc_alu;

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

    CsrRegs csr_regs_inst (
                    .clk       (clk),
                    .reset     (reset),
                    .read_addr (ex_mem.csr_addr),
                    .read_data (csr_read_rdata_wire),
                    .write_en  (csr_write_pulse),
                    .write_addr(csr_write_addr_pulse),
                    .write_data(csr_write_value),
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
                    .dbg_mideleg  (mideleg_c),
                    .dbg_medeleg  (medeleg_c),
                    .dbg_sepc     (sepc_c),
                    .dbg_stval    (stval_c),
                    .dbg_stvec    (stvec_c),
                    .dbg_scause   (scause_c),
                    .dbg_sscratch (sscratch_c)
                );

    assign pc_c     = mem_wb.decoder_ctrl.pc;
    assign instr_c  = mem_wb.decoder_ctrl.instr;
    assign w_en_c   = mem_wb.reg_write;
    assign wd_c     = {3'b0,mem_wb.wd};
    assign wdata_c  = mem_wb.result;
    assign mem_addr_c = mem_wb.mem_addr;
    assign mem_op_c = mem_wb.mem_op;

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            valid_c <= 1'b0;
        else
            valid_c <= wb_fire;
    end

    /**
     * CPU models
     */
    Fetch fetch(
        .clk(clk),
        .reset(reset),
        .stall(stall_fetch),
        .redirect_valid(redirect_valid_fetch),
        .redirect_pc(redirect_pc),
        .iresp(iresp),
        .ireq(ireq),
        .if_id(if_id)
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
        .id_ex(id_ex),
        .mem_wb(mem_wb),
        .wb_fire(wb_fire),
        .wb_next(wb_next),
        .ex_mem(ex_mem),
        .redirect_valid(redirect_valid_alu),
        .redirect_pc(redirect_pc_alu)
    );

    Mem mem(
        .clk(clk),
        .reset(reset),
        .hazard_stall(hazard_stall),
        .ex_mem(ex_mem),
        .csr_read_rdata(csr_read_rdata_wire),
        .mem_wb(mem_wb),
        .dreq(dreq),
        .dresp(dresp),
        .mem_busy(mem_busy),
        .wb_fire(wb_fire),
        .wb_next(wb_next)
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
endmodule
`endif
