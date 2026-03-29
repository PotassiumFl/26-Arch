`ifndef __ALU__SV
`define __ALU__SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module ALU import common::*; (
    input   i1          clk,reset,
    input   ID_EX_t     id_ex,
    input   MEM_WB_t    mem_wb,
    input   logic       wb_fire,
    input   MEM_WB_t    wb_next,
    input   logic       stall,
    output  EX_MEM_t    ex_mem
);

    EX_MEM_t ex_mem_next;
    i64 result_tmp;

    u2 forwardA;
    u2 forwardB;

    i64 operandA;
    i64 operandB;
    i64 forwarded_rs2;

    Forward forward(
        .id_ex(id_ex),
        .ex_mem(ex_mem),
        .mem_wb(mem_wb),
        .wb_fire(wb_fire),
        .wb_next(wb_next),
        .forwardA(forwardA),
        .forwardB(forwardB)
    );

    always_comb begin : forward1
        case(forwardA)
            2'b00: operandA = id_ex.ALU_ctrl.operand;
            2'b10: operandA = ex_mem.alu_result;
            2'b11: operandA = wb_next.result;
            2'b01: operandA = mem_wb.result;
            default: operandA = id_ex.ALU_ctrl.operand;
        endcase
    end

    always_comb begin : forward_rs2_path
        case(forwardB)
            2'b00: forwarded_rs2 = id_ex.rs2_val;
            2'b10: forwarded_rs2 = ex_mem.alu_result;
            2'b11: forwarded_rs2 = wb_next.result;
            2'b01: forwarded_rs2 = mem_wb.result;
            default: forwarded_rs2 = id_ex.rs2_val;
        endcase
    end

    always_comb begin : forward2
        if (id_ex.alu_op2_is_rs2)
            operandB = forwarded_rs2;
        else
            operandB = id_ex.ALU_ctrl.operand2;
    end

    always_comb begin : opr_ex
        case(id_ex.ALU_ctrl.opr)
            ADD: result_tmp = operandA + operandB;
            SUB: result_tmp = operandA - operandB;
            XOR: result_tmp = operandA ^ operandB;
            OR : result_tmp = operandA | operandB;
            AND: result_tmp = operandA & operandB;
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

    assign ex_mem_next.wd        = id_ex.wd;
    assign ex_mem_next.reg_write = id_ex.reg_write;
    assign ex_mem_next.decoder_ctrl = id_ex.decoder_ctrl;
    assign ex_mem_next.valid     = id_ex.valid;
    assign ex_mem_next.mem_op    = id_ex.mem_op;
    assign ex_mem_next.ls_funct3 = id_ex.ls_funct3;
    assign ex_mem_next.store_data = forwarded_rs2;

    always_ff @(posedge clk or posedge reset) begin
        if(reset)
            ex_mem <= '0;
        else if(!stall)
            ex_mem <= ex_mem_next;
    end

endmodule
`endif
