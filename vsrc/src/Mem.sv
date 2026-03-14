`ifndef __MEM_SV
`define __MEM_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module Mem import common::*; (
    input logic clk,
    input logic reset,
    input logic stall,
    input EX_MEM_t ex_mem,
    output MEM_WB_t mem_wb
);
    MEM_WB_t mem_wb_next;

    assign mem_wb_next.result       = ex_mem.alu_result;
    assign mem_wb_next.wd           = ex_mem.wd;
    assign mem_wb_next.reg_write    = ex_mem.reg_write;
    assign mem_wb_next.decoder_ctrl = ex_mem.decoder_ctrl;
    assign mem_wb_next.valid        = ex_mem.valid;

    always_ff @(posedge clk or posedge reset) begin
        if(reset)
            mem_wb <= '0;
        else if(!stall)
            mem_wb <= mem_wb_next;
    end

endmodule

`endif