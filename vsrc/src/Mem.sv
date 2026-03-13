`ifndef __MEM_SV
`define __MEM_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module Mem import common::*; (
    input logic clk,
    input logic reset,

    input EX_MEM_t ex_mem,
    output MEM_WB_t mem_wb
);
    MEM_WB_t mem_wb_next;

    assign mem_wb_next.result     = ex_mem.alu_result;
    assign mem_wb_next.rd         = ex_mem.rd;
    assign mem_wb_next.reg_write  = ex_mem.reg_write;


    always_ff @(posedge clk or posedge reset) begin
        if(reset)
            mem_wb <= '0;
        else
            mem_wb <= mem_wb_next;
    end

endmodule

`endif