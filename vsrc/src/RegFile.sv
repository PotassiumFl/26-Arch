`ifndef __REGFILE_SV
`define __REGFILE_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module RegFile import common::*; (
    input  logic            clk,reset,
    input  RegFile_read_t   RegFile_read,
    input  RegFile_write_t  RegFile_write,
    output i64              rs1_data,rs2_data,
    output i64              reg_c[0:31]
);

    i64 regFile [31:0];

    /**
     * RegFile write
     */
    always_comb begin
        for (int i = 0; i < 32; i++) begin
            if (i == 0) begin
                reg_c[i]='0;
            end else if (RegFile_write.w_en && (i[4:0] == RegFile_write.wd)) begin
                reg_c[i[4:0]] = RegFile_write.w_data; 
            end else begin
                reg_c[i[4:0]] = regFile[i[4:0]]; 
            end
        end
    end

    /**
     * RegFile update
     */
    always_ff @(posedge clk or posedge reset) begin : rst_write
        if (reset) begin
            for (int i = 0; i < 32; i++) begin
                regFile[i[4:0]] <= 64'b0;
            end
        end else begin
            for (int i = 0; i < 32; i++) begin
                regFile[i[4:0]] <= reg_c[i[4:0]];
            end
        end
    end

    /**
     * RegFile read
     */
    assign rs1_data = RegFile_read.rs1 == 0 ? 64'b0 : reg_c[RegFile_read.rs1];
    assign rs2_data = RegFile_read.rs2 == 0 ? 64'b0 : reg_c[RegFile_read.rs2];
    
endmodule

`endif