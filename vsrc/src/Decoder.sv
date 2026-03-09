`ifndef __DECODER_SV
`define __DECODER_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module decoder import common::*;(
    input  logic            clk, reset,
    input  Decoder_ctrl_t   decoder_ctrl,
    output ALU_ctrl_t       ALU_ctrl,
    output RegFile_ctrl_t   RegFile_ctrl,
    output imm_t            imm_ctrl,
    output i64              imm,
    output i1               branch_ctrl,
    output i64              offset
);

    assign ALU_ctrl.word_index = decoder_ctrl.instr[3]?WORD:NORMAL;
    assign imm_ctrl = decoder_ctrl.instr[5]?REG:IMM;
    assign ALU_ctrl.shamt = decoder_ctrl.instr[5]?decoder_ctrl.instr[25:20]:{1'b0,decoder_ctrl.instr[24:20]};

    assign RegFile_ctrl.rs1=decoder_ctrl.instr[19:15];
    assign RegFile_ctrl.rs2=decoder_ctrl.instr[24:20];
    assign RegFile_ctrl.wd = decoder_ctrl.instr[11:7];

    always_comb begin : imm_generator
        case (decoder_ctrl.instr[6:0]) inside
            7'b0?1?011: imm = {{53{decoder_ctrl.instr[31]}},decoder_ctrl.instr[30:20]};
            7'b0110111:imm = {{45{decoder_ctrl.instr[31]}},decoder_ctrl.instr[30:12]};
            default: imm=64'h00000000;
        endcase
    end

    always_comb begin : offset_generator
        case (decoder_ctrl.instr[6:0])
            7'b1100011:offset = {{53{decoder_ctrl.instr[31]}},decoder_ctrl.instr[7],decoder_ctrl.instr[30:25],decoder_ctrl.instr[11:8]};
            7'b1100111:offset = {{53{decoder_ctrl.instr[31]}},decoder_ctrl.instr[30:20]};
            7'b1101111:offset = {{45{decoder_ctrl.instr[31]}},decoder_ctrl.instr[19:12],decoder_ctrl.instr[20],decoder_ctrl.instr[30:21]};
            default: offset = 64'h00000000;
        endcase
    end

    always_comb begin : opr
        case (decoder_ctrl.instr[6:0]) inside
            7'b0?1?011: begin 
                case (decoder_ctrl.instr[14:12])
                    3'b000:ALU_ctrl.opr=decoder_ctrl.instr[30]?SUB:decoder_ctrl.instr[25]?MUL:ADD;
                    3'b001:ALU_ctrl.opr=SLL;
                    3'b010:ALU_ctrl.opr=SLT;
                    3'b011:ALU_ctrl.opr=SLTU;
                    3'b100:ALU_ctrl.opr=decoder_ctrl.instr[25]?DIV:XOR;
                    3'b101:ALU_ctrl.opr=decoder_ctrl.instr[30]?SRA:decoder_ctrl.instr[25]?DIVU:SRL;
                    3'b110:ALU_ctrl.opr=decoder_ctrl.instr[25]?REM:OR;
                    3'b111:ALU_ctrl.opr=decoder_ctrl.instr[25]?REMU:XOR;
                endcase
                end
            7'b1100011:begin
                case (decoder_ctrl.instr[14:12])
                    3'b000:ALU_ctrl.cond_index = EQUAL;
                    3'b001:ALU_ctrl.cond_index = NE;
                    3'b100:ALU_ctrl.cond_index = LESS;
                    3'b101:ALU_ctrl.cond_index = LESSU;
                    3'b110:ALU_ctrl.cond_index = GREATER;
                    3'b111:ALU_ctrl.cond_index = GREATERU; 
                    default: ALU_ctrl.cond_index = NOTCOND;
                endcase
                end
            default: ALU_ctrl.opr=NOTOPR;
        endcase
    end

endmodule
`endif