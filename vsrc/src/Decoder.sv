`ifndef __DECODER_SV
`define __DECODER_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module Decoder import common::*;(
    input  logic            clk,reset,

    input  IF_ID_t          if_id,
    output ID_EX_t          id_ex,
    output RegFile_ctrl_t   RegFile_ctrl,

    input i64               rs1_data,
    input i64               rs2_data
);

    i64     imm;
    i64     offset;
    imm_t   imm_ctrl;

    assign id_ex.ALU_ctrl.word_index = if_id.decoder_ctrl.instr[3]?WORD:NORMAL;
    assign imm_ctrl = if_id.decoder_ctrl.instr[5]?REG:IMM;
    assign id_ex.ALU_ctrl.shamt = if_id.decoder_ctrl.instr[5]?if_id.decoder_ctrl.instr[25:20]:{1'b0,if_id.decoder_ctrl.instr[24:20]};

    assign RegFile_ctrl.rs1 = if_id.decoder_ctrl.instr[19:15];
    assign RegFile_ctrl.rs2 = if_id.decoder_ctrl.instr[24:20];
    assign RegFile_ctrl.wd  = if_id.decoder_ctrl.instr[11:7];

    always_comb begin : imm_generator
        case (if_id.decoder_ctrl.instr[6:0]) inside
            7'b0?1?011:imm = {{53{if_id.decoder_ctrl.instr[31]}},if_id.decoder_ctrl.instr[30:20]};
            7'b0110111:imm = {{33{if_id.decoder_ctrl.instr[31]}},if_id.decoder_ctrl.instr[30:12],12'b0};
            default: imm=64'h00000000;
        endcase
    end

    always_comb begin : offset_generator
        case (if_id.decoder_ctrl.instr[6:0])
            7'b1100011:id_ex.ALU_ctrl.offset = {{52{if_id.decoder_ctrl.instr[31]}},if_id.decoder_ctrl.instr[7],if_id.decoder_ctrl.instr[30:25],if_id.decoder_ctrl.instr[11:8],1'b0};
            7'b1100111:id_ex.ALU_ctrl.offset = {{53{if_id.decoder_ctrl.instr[31]}},if_id.decoder_ctrl.instr[30:20]};
            7'b1101111:id_ex.ALU_ctrl.offset = {{44{if_id.decoder_ctrl.instr[31]}},if_id.decoder_ctrl.instr[19:12],if_id.decoder_ctrl.instr[20],if_id.decoder_ctrl.instr[30:21],1'b0};
            default: id_ex.ALU_ctrl.offset = 64'h00000000;
        endcase
    end

    always_comb begin : opr
        case (if_id.decoder_ctrl.instr[6:0]) inside
            7'b0?1?011: begin 
                case (if_id.decoder_ctrl.instr[14:12])
                    3'b000:id_ex.ALU_ctrl.opr=if_id.decoder_ctrl.instr[30]?SUB:if_id.decoder_ctrl.instr[25]?MUL:ADD;
                    3'b001:id_ex.ALU_ctrl.opr=SLL;
                    3'b010:id_ex.ALU_ctrl.opr=SLT;
                    3'b011:id_ex.ALU_ctrl.opr=SLTU;
                    3'b100:id_ex.ALU_ctrl.opr=if_id.decoder_ctrl.instr[25]?DIV:XOR;
                    3'b101:id_ex.ALU_ctrl.opr=if_id.decoder_ctrl.instr[30]?SRA:if_id.decoder_ctrl.instr[25]?DIVU:SRL;
                    3'b110:id_ex.ALU_ctrl.opr=if_id.decoder_ctrl.instr[25]?REM:OR;
                    3'b111:id_ex.ALU_ctrl.opr=if_id.decoder_ctrl.instr[25]?REMU:AND;
                endcase
                end
            7'b1100011:begin
                case (if_id.decoder_ctrl.instr[14:12])
                    3'b000:id_ex.ALU_ctrl.cond_index = EQUAL;
                    3'b001:id_ex.ALU_ctrl.cond_index = NE;
                    3'b100:id_ex.ALU_ctrl.cond_index = LESS;
                    3'b101:id_ex.ALU_ctrl.cond_index = GREATER;
                    3'b110:id_ex.ALU_ctrl.cond_index = LESSU;
                    3'b111:id_ex.ALU_ctrl.cond_index = GREATERU; 
                    default: id_ex.ALU_ctrl.cond_index = NOTCOND;
                endcase
                end
            default: id_ex.ALU_ctrl.opr=NOTOPR;
        endcase
    end

    assign id_ex.ALU_ctrl.operand = rs1_data;
    assign id_ex.ALU_ctrl.operand2 = (imm_ctrl==IMM)?imm:rs2_data;

endmodule
`endif