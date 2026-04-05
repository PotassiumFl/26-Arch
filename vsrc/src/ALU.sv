`ifndef __ALU__SV
`define __ALU__SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module ALU import common::*; (
    input   i1          clk, reset,
    input   ID_EX_t     id_ex,
    input   MEM_WB_t    mem_wb,
    input   logic       wb_fire,
    input   MEM_WB_t    wb_next,
    input   logic       stall,
    output  EX_MEM_t    ex_mem,
    output  logic       redirect_valid,
    output  addr_t      redirect_pc
);

    EX_MEM_t ex_mem_next;
    i64      result_tmp;

    forward_t forwardA;
    forward_t forwardB;

    i64 operandA;
    i64 operandB;
    i64 forwarded_rs2;

    logic branch_taken;

    Forward forward (
        .id_ex(id_ex),
        .ex_mem(ex_mem),
        .mem_wb(mem_wb),
        .wb_fire(wb_fire),
        .wb_next(wb_next),
        .forwardA(forwardA),
        .forwardB(forwardB)
    );

    always_comb begin : forward1
        case (forwardA)
            FORWARD_NONE: operandA = id_ex.ALU_ctrl.operand;
            FORWARD_MEM:  operandA = ex_mem.alu_result;
            FORWARD_WB:   operandA = wb_next.result;
            FORWARD_EX:   operandA = mem_wb.result;
            default:      operandA = id_ex.ALU_ctrl.operand;
        endcase
    end

    always_comb begin : forward_rs2_path
        case (forwardB)
            FORWARD_NONE: forwarded_rs2 = id_ex.rs2_val;
            FORWARD_MEM:  forwarded_rs2 = ex_mem.alu_result;
            FORWARD_WB:   forwarded_rs2 = wb_next.result;
            FORWARD_EX:   forwarded_rs2 = mem_wb.result;
            default:      forwarded_rs2 = id_ex.rs2_val;
        endcase
    end

    always_comb begin : forward2
        if (id_ex.alu_op2_is_rs2)
            operandB = forwarded_rs2;
        else
            operandB = id_ex.ALU_ctrl.operand2;
    end

    logic [5:0] shamt_v;
    always_comb begin
        if (id_ex.alu_op2_is_rs2)
            shamt_v = operandB[5:0];
        else
            shamt_v = id_ex.ALU_ctrl.shamt[5:0];
    end

    always_comb begin : branch_cond
        branch_taken = 1'b0;
        if (id_ex.valid && id_ex.cflow == CFLOW_BR) begin
            unique case (id_ex.ALU_ctrl.cond_index)
                EQUAL:    branch_taken = (operandA == operandB);
                NE:       branch_taken = (operandA != operandB);
                LESS:     branch_taken = ($signed(operandA) < $signed(operandB));
                GREATER:  branch_taken = ($signed(operandA) >= $signed(operandB));
                LESSU:    branch_taken = (operandA < operandB);
                GREATERU: branch_taken = (operandA >= operandB);
                default:  branch_taken = 1'b0;
            endcase
        end
    end

    always_comb begin : redirect_logic
        redirect_valid = 1'b0;
        redirect_pc    = id_ex.decoder_ctrl.pc;
        if (id_ex.valid) begin
            unique case (id_ex.cflow)
                CFLOW_BR: begin
                    if (branch_taken) begin
                        redirect_valid = 1'b1;
                        redirect_pc    = id_ex.decoder_ctrl.pc + id_ex.imm_pc;
                    end
                end
                CFLOW_JAL: begin
                    redirect_valid = 1'b1;
                    redirect_pc    = id_ex.decoder_ctrl.pc + id_ex.imm_pc;
                end
                CFLOW_JALR: begin
                    redirect_valid = 1'b1;
                    redirect_pc    = (operandA + id_ex.imm_pc) & ~64'd1;
                end
                default: ;
            endcase
        end
    end

    logic [31:0] a32, b32, r32;
    always_comb begin : opr_ex
        result_tmp = 64'b0;
        a32        = operandA[31:0];
        b32        = operandB[31:0];
        r32        = 32'b0;

        if (id_ex.valid && (id_ex.cflow == CFLOW_JAL || id_ex.cflow == CFLOW_JALR))
            result_tmp = id_ex.decoder_ctrl.pc + 64'd4;
        else if (id_ex.ALU_ctrl.word_index == WORD) begin
            unique case (id_ex.ALU_ctrl.opr)
                ADD:  r32 = a32 + b32;
                SUB:  r32 = a32 - b32;
                SLL:  r32 = a32 << shamt_v[4:0];
                SLT:  r32 = ($signed(a32) < $signed(b32)) ? 32'd1 : 32'd0;
                SLTU: r32 = (a32 < b32) ? 32'd1 : 32'd0;
                XOR:  r32 = a32 ^ b32;
                SRL:  r32 = a32 >> shamt_v[4:0];
                SRA:  r32 = 32'($signed(a32) >>> shamt_v[4:0]);
                OR:   r32 = a32 | b32;
                AND:  r32 = a32 & b32;
                default: r32 = 32'b0;
            endcase
            result_tmp = {{32{r32[31]}}, r32};
        end else begin
            unique case (id_ex.ALU_ctrl.opr)
                ADD:     result_tmp = operandA + operandB;
                SUB:     result_tmp = operandA - operandB;
                SLL:     result_tmp = operandA << shamt_v;
                SLT:     result_tmp = ($signed(operandA) < $signed(operandB)) ? 64'd1 : 64'd0;
                SLTU:    result_tmp = (operandA < operandB) ? 64'd1 : 64'd0;
                XOR:     result_tmp = operandA ^ operandB;
                SRL:     result_tmp = operandA >> shamt_v;
                SRA:     result_tmp = i64'($signed(operandA) >>> shamt_v);
                OR:      result_tmp = operandA | operandB;
                AND:     result_tmp = operandA & operandB;
                NOTOPR,
                MUL,
                DIV,
                DIVU,
                REM,
                REMU: result_tmp = 64'b0;
                default: result_tmp = 64'b0;
            endcase
        end
    end

    assign ex_mem_next.alu_result   = result_tmp;
    assign ex_mem_next.wd            = id_ex.wd;
    assign ex_mem_next.reg_write     = id_ex.reg_write;
    assign ex_mem_next.decoder_ctrl  = id_ex.decoder_ctrl;
    assign ex_mem_next.valid         = id_ex.valid;
    assign ex_mem_next.mem_op        = id_ex.mem_op;
    assign ex_mem_next.ls_funct3     = id_ex.ls_funct3;
    assign ex_mem_next.store_data    = forwarded_rs2;

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            ex_mem <= '0;
        else if (!stall)
            ex_mem <= ex_mem_next;
    end

endmodule
`endif
