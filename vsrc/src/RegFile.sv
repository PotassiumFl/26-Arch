`ifndef __REGFILE_SV
`define __REGFILE_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module regFile import common::*;(
    input logic             clk,reset,ALU_done,
    input RegFile_ctrl_t    RegFile_ctrl,
    output i64              rs1_data,rs2_data
);

    i64 [63:0] regFile;

    always @(posedge clk) begin
        if(reset) begin
            for(integer i = 0;i<64;i=i+1)
                regFile[i]<=64'b0; 
        end
        else if(RegFile_ctrl.w_en && RegFile_ctrl.wd!=0) begin
            regFile[RegFile_ctrl.wd]<=RegFile_ctrl.write_data;
        end
    end

    assign rs1_data = RegFile_ctrl.rs1==0?64'b0:regFile[RegFile_ctrl.rs1];
    assign rs2_data = RegFile_ctrl.rs2==0?64'b0:regFile[RegFile_ctrl.rs2];
    
    
endmodule

`endif