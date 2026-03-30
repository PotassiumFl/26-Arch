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

        if (ex_mem.reg_write && ex_mem.wd != 0 && ex_mem.wd == id_ex.rs1)
            forwardA = FORWARD_MEM;
        else if (wb_fire && wb_next.reg_write && wb_next.wd != 0 && wb_next.wd == id_ex.rs1)
            forwardA = FORWARD_WB;
        else if (mem_wb.reg_write && mem_wb.wd != 0 && mem_wb.wd == id_ex.rs1)
            forwardA = FORWARD_EX;

        if (ex_mem.reg_write && ex_mem.wd != 0 && ex_mem.wd == id_ex.rs2)
            forwardB = FORWARD_MEM;
        else if (wb_fire && wb_next.reg_write && wb_next.wd != 0 && wb_next.wd == id_ex.rs2)
            forwardB = FORWARD_WB;
        else if (mem_wb.reg_write && mem_wb.wd != 0 && mem_wb.wd == id_ex.rs2)
            forwardB = FORWARD_EX;
    end

endmodule

`endif
