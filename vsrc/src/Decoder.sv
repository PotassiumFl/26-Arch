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

    u32 instr;
    u7  opcode;
    u3  funct3;
    logic funct7_30;
    i64 imm_i;
    i64 imm_s;
    i64 imm_u;

    assign instr     = if_id.decoder_ctrl.instr;
    assign opcode    = instr[6:0];
    assign funct3    = instr[14:12];
    assign funct7_30 = instr[30];
    assign imm_i     = {{52{instr[31]}}, instr[31:20]};
    assign imm_s     = {{52{instr[31]}}, instr[31:25], instr[11:7]};
    assign imm_u     = {{32{instr[31]}}, instr[31:12], 12'b0};

    assign RegFile_read.rs1 = (opcode == 7'b0110111) ? 5'b0 : instr[19:15];
    assign RegFile_read.rs2 = (opcode == 7'b0110111 || opcode == 7'b0000011) ? 5'b0 : instr[24:20];

    always_comb begin : main_decoder_logic
        id_ex_next = '0;

        id_ex_next.valid = if_id.valid;
        id_ex_next.decoder_ctrl = if_id.decoder_ctrl;
        id_ex_next.rs1 = instr[19:15];
        id_ex_next.rs2 = instr[24:20];
        id_ex_next.wd  = instr[11:7];
        id_ex_next.rs2_val = rs2_data;
        id_ex_next.mem_op = MEM_NONE;
        id_ex_next.ls_funct3 = funct3;
        id_ex_next.alu_op2_is_rs2 = 1'b0;
        id_ex_next.uses_rs2 = 1'b0;

        id_ex_next.ALU_ctrl.operand  = rs1_data;
        id_ex_next.ALU_ctrl.operand2 = rs2_data;
        id_ex_next.ALU_ctrl.shamt    = {1'b0, instr[24:20]};

        if (if_id.valid) begin
            case (opcode)

                7'b0110111: begin
                    id_ex_next.reg_write = 1'b1;
                    id_ex_next.ALU_ctrl.operand  = 64'b0;
                    id_ex_next.ALU_ctrl.operand2 = imm_u;
                    id_ex_next.ALU_ctrl.opr = ADD;
                end

                7'b0000011: begin
                    id_ex_next.reg_write = 1'b1;
                    id_ex_next.mem_op = MEM_LOAD;
                    id_ex_next.ALU_ctrl.operand2 = imm_i;
                    id_ex_next.ALU_ctrl.opr = ADD;
                end

                7'b0100011: begin
                    id_ex_next.reg_write = 1'b0;
                    id_ex_next.mem_op = MEM_STORE;
                    id_ex_next.uses_rs2 = 1'b1;
                    id_ex_next.ALU_ctrl.operand2 = imm_s;
                    id_ex_next.ALU_ctrl.opr = ADD;
                end

                7'b0010011: begin
                    id_ex_next.reg_write = 1'b1;
                    id_ex_next.ALU_ctrl.operand2 = imm_i;
                    case (funct3)
                        3'b000: id_ex_next.ALU_ctrl.opr = ADD;
                        3'b100: id_ex_next.ALU_ctrl.opr = XOR;
                        3'b110: id_ex_next.ALU_ctrl.opr = OR;
                        3'b111: id_ex_next.ALU_ctrl.opr = AND;
                        default: id_ex_next.ALU_ctrl.opr = NOTOPR;
                    endcase
                end

                7'b0011011: begin
                    id_ex_next.reg_write = 1'b1;
                    id_ex_next.ALU_ctrl.operand2 = imm_i;
                    id_ex_next.ALU_ctrl.word_index = WORD;
                    case (funct3)
                        3'b000: id_ex_next.ALU_ctrl.opr = ADD;
                        default: id_ex_next.ALU_ctrl.opr = NOTOPR;
                    endcase
                end

                7'b0110011: begin
                    id_ex_next.reg_write = 1'b1;
                    id_ex_next.alu_op2_is_rs2 = 1'b1;
                    id_ex_next.uses_rs2 = 1'b1;
                    case (funct3)
                        3'b000: id_ex_next.ALU_ctrl.opr = funct7_30 ? SUB : ADD;
                        3'b100: id_ex_next.ALU_ctrl.opr = XOR;
                        3'b110: id_ex_next.ALU_ctrl.opr = OR;
                        3'b111: id_ex_next.ALU_ctrl.opr = AND;
                        default: id_ex_next.ALU_ctrl.opr = NOTOPR;
                    endcase
                end

                7'b0111011: begin
                    id_ex_next.reg_write = 1'b1;
                    id_ex_next.alu_op2_is_rs2 = 1'b1;
                    id_ex_next.uses_rs2 = 1'b1;
                    id_ex_next.ALU_ctrl.word_index = WORD;
                    case (funct3)
                        3'b000: id_ex_next.ALU_ctrl.opr = funct7_30 ? SUB : ADD;
                        default: id_ex_next.ALU_ctrl.opr = NOTOPR;
                    endcase
                end

                default: id_ex_next.reg_write = 1'b0;
            endcase
        end
    end

    assign id_ex = id_ex_next;

endmodule

`endif
