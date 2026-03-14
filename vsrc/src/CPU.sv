`ifndef __TOP_SV
`define __TOP_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

`include "src/Fetch.sv"
`include "src/ALU.sv"
`include "src/Decoder.sv"
`include "src/Forward.sv"
`include "src/Hazard.sv"
`include "src/Mem.sv"
`include "src/RegFile.sv"
`include "src/Wb.sv"

module CPU import common::*;(
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
	output i64          reg_c [0:31]
);

    IF_ID_t  if_id;
    ID_EX_t  id_ex;
    EX_MEM_t ex_mem;
    MEM_WB_t mem_wb;

    RegFile_read_t RegFile_read;
    RegFile_write_t RegFile_write;

    i64 rs1_data;
    i64 rs2_data;

    logic stall;

    assign pc_c     = mem_wb.decoder_ctrl.pc;
    assign instr_c  = mem_wb.decoder_ctrl.instr;
    assign w_en_c   = mem_wb.reg_write;
    assign wd_c     = {3'b0,mem_wb.wd};
    assign wdata_c  = mem_wb.result;
    assign valid_c  = mem_wb.valid;

    Fetch fetch(
        .clk(clk),
        .reset(reset),
        .stall(stall),
        .iresp(iresp),
        .ireq(ireq),
        .if_id(if_id)
    );

    Decoder decoder(
        .clk(clk),
        .reset(reset),
        .stall(stall),
        .if_id(if_id),
        .id_ex(id_ex),
        .RegFile_read(RegFile_read),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );

    ALU ALU(
        .clk(clk),
        .reset(reset),
        .stall(stall),
        .id_ex(id_ex),
        .mem_wb(mem_wb),
        .ex_mem(ex_mem)
    );

    Mem mem(
        .clk(clk),
        .reset(reset),
        .stall(stall),
        .ex_mem(ex_mem),
        .mem_wb(mem_wb)
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
        .if_id(if_id),
        .stall(stall)
    );
endmodule
`endif