`ifndef __DECODER_SV
`define __DECODER_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module Decoder import common::*; (
    input  logic            clk, reset,
    input  logic            stall,
    input  IF_ID_t          if_id,
    output ID_EX_t          id_ex,
    output RegFile_read_t   RegFile_read,
    input  i64              rs1_data,
    input  i64              rs2_data
);

    ID_EX_t id_ex_next;

    u32       instr;
    funct7_t  opcode;
    u3        funct3;
    logic     funct7_30;
    u7        funct7_full;
    i64       imm_i;
    i64       imm_s;
    i64       imm_u;
    i64       imm_b;
    i64       imm_j;

    assign instr      = if_id.decoder_ctrl.instr;
    assign opcode     = funct7_t'(instr[6:0]);
    assign funct3     = instr[14:12];
    assign funct7_30  = instr[30];
    assign funct7_full = instr[31:25];
    assign imm_i      = {{52{instr[31]}}, instr[31:20]};
    assign imm_s      = {{52{instr[31]}}, instr[31:25], instr[11:7]};
    assign imm_u      = {{32{instr[31]}}, instr[31:12], 12'b0};
    assign imm_b      = {{52{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
    assign imm_j      = {{44{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

    assign RegFile_read.rs1 = (opcode == LUI || opcode == AUIPC) ? 5'b0 : instr[19:15];
    assign RegFile_read.rs2 = (opcode == LUI || opcode == AUIPC || opcode == LOAD
                               || opcode == JAL || opcode == JALR) ? 5'b0 : instr[24:20];

    always_comb begin : main_decoder_logic
        id_ex_next = '0;

        id_ex_next.valid          = if_id.valid;
        id_ex_next.decoder_ctrl   = if_id.decoder_ctrl;
        id_ex_next.rs1            = instr[19:15];
        id_ex_next.rs2            = instr[24:20];
        id_ex_next.wd             = instr[11:7];
        id_ex_next.rs2_val        = rs2_data;
        id_ex_next.mem_op         = MEM_NONE;
        id_ex_next.ls_funct3      = funct3;
        id_ex_next.alu_op2_is_rs2 = 1'b0;
        id_ex_next.uses_rs2       = 1'b0;
        id_ex_next.cflow          = CFLOW_ALU;
        id_ex_next.imm_pc         = 64'b0;

        id_ex_next.ALU_ctrl.operand  = rs1_data;
        id_ex_next.ALU_ctrl.operand2 = rs2_data;
        id_ex_next.ALU_ctrl.shamt    = instr[25:20];
        id_ex_next.ALU_ctrl.cond_index = NOTCOND;

        if (if_id.valid) begin
            begin
            case (opcode)

                LUI: begin
                    id_ex_next.rs1               = 5'b0;
                    id_ex_next.rs2               = 5'b0;
                    id_ex_next.reg_write         = 1'b1;
                    id_ex_next.ALU_ctrl.operand  = 64'b0;
                    id_ex_next.ALU_ctrl.operand2 = imm_u;
                    id_ex_next.ALU_ctrl.opr      = ADD;
                end

                AUIPC: begin
                    id_ex_next.rs1               = 5'b0;
                    id_ex_next.rs2               = 5'b0;
                    id_ex_next.reg_write         = 1'b1;
                    id_ex_next.ALU_ctrl.operand  = if_id.decoder_ctrl.pc;
                    id_ex_next.ALU_ctrl.operand2 = imm_u;
                    id_ex_next.ALU_ctrl.opr      = ADD;
                end

                LOAD: begin
                    id_ex_next.reg_write         = 1'b1;
                    id_ex_next.mem_op            = MEM_LOAD;
                    id_ex_next.ALU_ctrl.operand2 = imm_i;
                    id_ex_next.ALU_ctrl.opr      = ADD;
                end

                STORE: begin
                    id_ex_next.reg_write         = 1'b0;
                    id_ex_next.mem_op            = MEM_STORE;
                    id_ex_next.uses_rs2          = 1'b1;
                    id_ex_next.ALU_ctrl.operand2 = imm_s;
                    id_ex_next.ALU_ctrl.opr      = ADD;
                end

                JAL: begin
                    id_ex_next.rs1               = 5'b0;
                    id_ex_next.rs2               = 5'b0;
                    id_ex_next.reg_write         = 1'b1;
                    id_ex_next.cflow             = CFLOW_JAL;
                    id_ex_next.imm_pc            = imm_j;
                    id_ex_next.ALU_ctrl.opr      = ADD;
                end

                JALR: begin
                    id_ex_next.rs2               = 5'b0;
                    id_ex_next.reg_write         = 1'b1;
                    id_ex_next.cflow             = CFLOW_JALR;
                    id_ex_next.imm_pc            = imm_i;
                    id_ex_next.ALU_ctrl.operand  = rs1_data;
                    id_ex_next.ALU_ctrl.operand2 = imm_i;
                    id_ex_next.ALU_ctrl.opr      = ADD;
                end

                BRANCH: begin
                    id_ex_next.reg_write         = 1'b0;
                    id_ex_next.cflow             = CFLOW_BR;
                    id_ex_next.imm_pc            = imm_b;
                    id_ex_next.uses_rs2          = 1'b1;
                    id_ex_next.alu_op2_is_rs2    = 1'b1;
                    unique case (funct3)
                        3'b000: id_ex_next.ALU_ctrl.cond_index = EQUAL;
                        3'b001: id_ex_next.ALU_ctrl.cond_index = NE;
                        3'b100: id_ex_next.ALU_ctrl.cond_index = LESS;
                        3'b101: id_ex_next.ALU_ctrl.cond_index = GREATER;
                        3'b110: id_ex_next.ALU_ctrl.cond_index = LESSU;
                        3'b111: id_ex_next.ALU_ctrl.cond_index = GREATERU;
                        default: id_ex_next.ALU_ctrl.cond_index = NOTCOND;
                    endcase
                end

                OP_IMM: begin
                    id_ex_next.reg_write = 1'b1;
                    unique case (funct3)
                        3'b000: begin // addi
                            id_ex_next.ALU_ctrl.operand2 = imm_i;
                            id_ex_next.ALU_ctrl.opr      = ADD;
                        end
                        3'b010: begin // slti
                            id_ex_next.ALU_ctrl.operand2 = imm_i;
                            id_ex_next.ALU_ctrl.opr      = SLT;
                        end
                        3'b011: begin // sltiu
                            id_ex_next.ALU_ctrl.operand2 = imm_i;
                            id_ex_next.ALU_ctrl.opr      = SLTU;
                        end
                        3'b100: begin
                            id_ex_next.ALU_ctrl.operand2 = imm_i;
                            id_ex_next.ALU_ctrl.opr      = XOR;
                        end
                        3'b110: begin
                            id_ex_next.ALU_ctrl.operand2 = imm_i;
                            id_ex_next.ALU_ctrl.opr      = OR;
                        end
                        3'b111: begin
                            id_ex_next.ALU_ctrl.operand2 = imm_i;
                            id_ex_next.ALU_ctrl.opr      = AND;
                        end
                        3'b001: begin // slli (RV64 shamt in [25:20])
                            id_ex_next.ALU_ctrl.operand2 = imm_i;
                            id_ex_next.ALU_ctrl.opr      = SLL;
                            id_ex_next.ALU_ctrl.shamt    = instr[25:20];
                        end
                        3'b101: begin // srli / srai
                            id_ex_next.ALU_ctrl.operand2 = imm_i;
                            id_ex_next.ALU_ctrl.opr      = (funct7_full == 7'b0100000) ? SRA : SRL;
                            id_ex_next.ALU_ctrl.shamt    = instr[25:20];
                        end
                        default: id_ex_next.ALU_ctrl.opr = NOTOPR;
                    endcase
                end

                OP_IMM_32: begin
                    id_ex_next.reg_write           = 1'b1;
                    id_ex_next.ALU_ctrl.word_index = WORD;
                    unique case (funct3)
                        3'b000: begin
                            id_ex_next.ALU_ctrl.operand2 = imm_i;
                            id_ex_next.ALU_ctrl.opr      = ADD;
                        end
                        3'b001: begin
                            id_ex_next.ALU_ctrl.opr      = SLL;
                            id_ex_next.ALU_ctrl.shamt    = instr[25:20];
                        end
                        3'b101: begin
                            id_ex_next.ALU_ctrl.opr      = (funct7_full == 7'b0100000) ? SRA : SRL;
                            id_ex_next.ALU_ctrl.shamt    = instr[25:20];
                        end
                        default: id_ex_next.ALU_ctrl.opr = NOTOPR;
                    endcase
                end

                OP: begin
                    id_ex_next.reg_write      = 1'b1;
                    id_ex_next.alu_op2_is_rs2 = 1'b1;
                    id_ex_next.uses_rs2       = 1'b1;
                    unique case (funct3)
                        3'b000: id_ex_next.ALU_ctrl.opr =
                            (funct7_full == 7'b0100000) ? SUB : ADD;
                        3'b001: id_ex_next.ALU_ctrl.opr = SLL;
                        3'b010: id_ex_next.ALU_ctrl.opr = SLT;
                        3'b011: id_ex_next.ALU_ctrl.opr = SLTU;
                        3'b100: id_ex_next.ALU_ctrl.opr = XOR;
                        3'b101: id_ex_next.ALU_ctrl.opr =
                            (funct7_full == 7'b0100000) ? SRA : SRL;
                        3'b110: id_ex_next.ALU_ctrl.opr = OR;
                        3'b111: id_ex_next.ALU_ctrl.opr = AND;
                        default: id_ex_next.ALU_ctrl.opr = NOTOPR;
                    endcase
                end

                OP_32: begin
                    id_ex_next.reg_write           = 1'b1;
                    id_ex_next.alu_op2_is_rs2      = 1'b1;
                    id_ex_next.uses_rs2            = 1'b1;
                    id_ex_next.ALU_ctrl.word_index = WORD;
                    unique case (funct3)
                        3'b000: id_ex_next.ALU_ctrl.opr =
                            (funct7_full == 7'b0100000) ? SUB : ADD;
                        3'b001: id_ex_next.ALU_ctrl.opr = SLL;
                        3'b101: id_ex_next.ALU_ctrl.opr =
                            (funct7_full == 7'b0100000) ? SRA : SRL;
                        default: id_ex_next.ALU_ctrl.opr = NOTOPR;
                    endcase
                end

                default: id_ex_next.reg_write = 1'b0;
            endcase
            end
        end
    end

    assign id_ex = id_ex_next;

endmodule

`endif
