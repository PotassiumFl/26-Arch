`ifndef __WB_SV
`define __WB_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module Wb import common::*; (
    input MEM_WB_t mem_wb,
    output RegFile_write_t RegFile_write
);

    /**
     * RegFile ctrl
     */
    assign RegFile_write.wd = mem_wb.wd;
    assign RegFile_write.w_data = mem_wb.result;
    assign RegFile_write.w_en = mem_wb.reg_write;
    
endmodule

`endif