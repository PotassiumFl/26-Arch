`ifndef __ALU__SV
`define __ALU__SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module ALU import common::*; (
    input   i1          clk,reset,
    
    input   ID_EX_t     id_ex,
    output  EX_MEM_t    ex_mem
);

    EX_MEM_t ex_mem_next;
    i64 result_tmp;

    always_comb begin : ALU_ex
        case(id_ex.ALU_ctrl.opr)
            ADD: result_tmp = id_ex.ALU_ctrl.operand + id_ex.ALU_ctrl.operand2;
            SUB: result_tmp = id_ex.ALU_ctrl.operand - id_ex.ALU_ctrl.operand2;
            XOR: result_tmp = id_ex.ALU_ctrl.operand ^ id_ex.ALU_ctrl.operand2;
            OR : result_tmp = id_ex.ALU_ctrl.operand | id_ex.ALU_ctrl.operand2;
            AND: result_tmp = id_ex.ALU_ctrl.operand & id_ex.ALU_ctrl.operand2;
            default: result_tmp = 64'b0;
        endcase
    end

    always_comb begin : word_ex
        if(id_ex.ALU_ctrl.word_index == WORD)
            ex_mem_next.alu_result =
                {{32{result_tmp[31]}},result_tmp[31:0]};
        else
            ex_mem_next.alu_result = result_tmp;
    end

    assign ex_mem_next.rd        = id_ex.rd;
    assign ex_mem_next.reg_write = id_ex.reg_write;

    always_ff @(posedge clk or posedge reset) begin

        if(reset)
            ex_mem <= '0;
        else
            ex_mem <= ex_mem_next;

    end
    
endmodule
`endif