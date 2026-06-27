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
    input   logic       pipeline_flush,
    output  logic       muldiv_busy,
    output  EX_MEM_t    ex_mem,
    output  logic       redirect_valid,
    output  addr_t      redirect_pc,
    output  logic       trap_valid,
    output  u64         trap_cause,
    output  u64         trap_tval,
    output  u64         trap_epc
);

    EX_MEM_t ex_mem_next;
    i64      result_tmp;

    forward_t forwardA;
    forward_t forwardB;

    i64 operandA;
    i64 operandB;
    i64 forwarded_rs2;

    logic branch_taken;
    addr_t jalr_target;

    logic div_op;
    logic div_start;
    logic div_consume;
    logic div_active;
    logic div_done;
    logic div_wait;
    i64   div_result;

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

    i64 csr_opnd_pick;

    assign csr_opnd_pick = id_ex.is_csr ?
        (id_ex.csr_imm ? {59'b0, id_ex.csr_zimm} : operandA) :
        64'b0;

    logic [5:0] shamt_v;
    
    always_comb begin
        if (id_ex.alu_op2_is_rs2)
            shamt_v = operandB[5:0];
        else
            shamt_v = id_ex.ALU_ctrl.shamt[5:0];
    end

    assign div_op = id_ex.valid && id_ex.cflow == CFLOW_ALU && (
        id_ex.ALU_ctrl.opr == DIV  || id_ex.ALU_ctrl.opr == DIVU ||
        id_ex.ALU_ctrl.opr == REM  || id_ex.ALU_ctrl.opr == REMU
    );
    assign div_start   = div_op && !div_active && !stall && !pipeline_flush;
    assign div_consume = div_op && div_done && !stall && !pipeline_flush;
    assign div_wait    = div_op && !div_done;
    assign muldiv_busy = div_op && !pipeline_flush && (!div_done || stall);

    MulDivUnit muldiv_unit (
        .clk(clk),
        .reset(reset),
        .flush(pipeline_flush),
        .start(div_start),
        .consume(div_consume),
        .opr(id_ex.ALU_ctrl.opr),
        .word_index(id_ex.ALU_ctrl.word_index),
        .lhs(operandA),
        .rhs(operandB),
        .busy(div_active),
        .done(div_done),
        .result(div_result)
    );

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

    assign jalr_target = operandA + id_ex.imm_pc;

    addr_t jalr_target_aligned;
    assign jalr_target_aligned = jalr_target & ~64'd1;

    always_comb begin : redirect_logic
        automatic addr_t branch_target;
        automatic addr_t branch_fallthrough;
        automatic addr_t jal_target;

        branch_target      = id_ex.decoder_ctrl.pc + id_ex.imm_pc;
        branch_fallthrough = id_ex.decoder_ctrl.pc + 64'd4;
        jal_target         = id_ex.decoder_ctrl.pc + id_ex.imm_pc;
        redirect_valid     = 1'b0;
        redirect_pc        = id_ex.decoder_ctrl.pc;

        if (id_ex.valid) begin
            unique case (id_ex.cflow)
                CFLOW_BR: begin
                    if (branch_taken) begin
                        if (!id_ex.decoder_ctrl.pred_taken ||
                                id_ex.decoder_ctrl.pred_target != branch_target) begin
                            redirect_valid = 1'b1;
                            redirect_pc    = branch_target;
                        end
                    end else if (id_ex.decoder_ctrl.pred_taken) begin
                        redirect_valid = 1'b1;
                        redirect_pc    = branch_fallthrough;
                    end
                end
                CFLOW_JAL: begin
                    if (!id_ex.decoder_ctrl.pred_taken ||
                            id_ex.decoder_ctrl.pred_target != jal_target) begin
                        redirect_valid = 1'b1;
                        redirect_pc    = jal_target;
                    end
                end
                CFLOW_JALR: begin
                    if (jalr_target_aligned[1:0] == 2'b00) begin
                        redirect_valid = 1'b1;
                        redirect_pc    = jalr_target_aligned;
                    end
                end
                default: ;
            endcase
        end
    end

    assign trap_valid = id_ex.valid && id_ex.cflow == CFLOW_JALR &&
        (jalr_target_aligned[1:0] != 2'b00);
    assign trap_cause = 64'd0;
    assign trap_tval  = jalr_target_aligned;
    assign trap_epc   = id_ex.decoder_ctrl.pc;

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
                MUL:  r32 = a32 * b32;
                XOR:  r32 = a32 ^ b32;
                DIV,
                DIVU,
                REM,
                REMU: r32 = div_result[31:0];
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
                MUL:     result_tmp = operandA * operandB;
                DIV,
                DIVU,
                REM,
                REMU:    result_tmp = div_result;
                NOTOPR:  result_tmp = 64'b0;
                default: result_tmp = 64'b0;
            endcase
        end
    end

    always_comb begin : ex_mem_pack
        ex_mem_next = '0;
        if (!div_wait) begin
            ex_mem_next.alu_result   = result_tmp;
            ex_mem_next.wd           = id_ex.wd;
            ex_mem_next.reg_write    = id_ex.reg_write;
            ex_mem_next.decoder_ctrl = id_ex.decoder_ctrl;
            ex_mem_next.valid        = id_ex.valid;
            ex_mem_next.mem_op       = id_ex.mem_op;
            ex_mem_next.ls_funct3    = id_ex.ls_funct3;
            ex_mem_next.amo_funct5   = id_ex.amo_funct5;
            ex_mem_next.store_data   = forwarded_rs2;
            ex_mem_next.is_csr       = id_ex.is_csr;
            ex_mem_next.csr_addr     = id_ex.csr_addr;
            ex_mem_next.csr_funct3   = id_ex.csr_funct3;
            ex_mem_next.csr_rsdata   = csr_opnd_pick;
            ex_mem_next.system_op    = id_ex.system_op;
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            ex_mem <= '0;
        else if (pipeline_flush)
            ex_mem <= '0;
        else if (!stall)
            ex_mem <= ex_mem_next;
    end

endmodule
`endif
