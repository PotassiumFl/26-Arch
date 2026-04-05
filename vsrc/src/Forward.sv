`ifndef __FORWARD_SV
`define __FORWARD_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module Forward import common::*;(
    input ID_EX_t  id_ex,
    input EX_MEM_t ex_mem,
    input MEM_WB_t mem_wb,
    input logic    wb_fire,
    input MEM_WB_t wb_next,

    output forward_t forwardA,
    output forward_t forwardB
);

    always_comb begin : forward
        forwardA = FORWARD_NONE;
        forwardB = FORWARD_NONE;

        if (ex_mem.reg_write && ex_mem.wd != 0 && ex_mem.wd == id_ex.rs1) begin
            if (ex_mem.mem_op == MEM_LOAD) begin
                if (wb_fire)
                    forwardA = FORWARD_WB;
            end else
                forwardA = FORWARD_MEM;
        end else if (mem_wb.reg_write && mem_wb.wd != 0 && mem_wb.wd == id_ex.rs1)
            forwardA = FORWARD_EX;

        if (ex_mem.reg_write && ex_mem.wd != 0 && ex_mem.wd == id_ex.rs2) begin
            if (ex_mem.mem_op == MEM_LOAD) begin
                if (wb_fire)
                    forwardB = FORWARD_WB;
            end else
                forwardB = FORWARD_MEM;
        end else if (mem_wb.reg_write && mem_wb.wd != 0 && mem_wb.wd == id_ex.rs2)
            forwardB = FORWARD_EX;
    end

endmodule

`endif
