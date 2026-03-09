`ifndef __ALU__SV
`define __ALU__SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module ALU import common::*; (
    input   i1          clk,
    input   ALU_ctrl_t  ALU_ctrl,
    input   i64         operand,operand2,
    output  i64         result,
    output  i1          branch_index
);

    always_comb begin : ALU
        case (ALU_ctrl.opr)
            ADD  : result = operand + operand2;
            SUB  : result = operand - operand2;
            XOR  : result = operand ^ operand2;
            OR   : result = operand | operand2;
            AND  : result = operand & operand2;
            default: result = 0;
        endcase
    end
    
endmodule
`endif