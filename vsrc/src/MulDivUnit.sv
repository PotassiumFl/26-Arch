`ifndef __MULDIVUNIT_SV
`define __MULDIVUNIT_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module MulDivUnit import common::*; (
    input  logic       clk,
    input  logic       reset,
    input  logic       flush,
    input  logic       start,
    input  logic       consume,
    input  opr_t       opr,
    input  word_type_t word_index,
    input  i64         lhs,
    input  i64         rhs,
    output logic       busy,
    output logic       done,
    output i64         result
);

    typedef enum logic [1:0] {
        DIV_IDLE,
        DIV_RUN,
        DIV_DONE
    } div_state_t;

    div_state_t state;

    logic       rem_sel;
    logic       word_sel;
    logic       quotient_neg;
    logic       remainder_neg;
    logic [6:0] count;

    logic [63:0] divisor_reg;
    logic [63:0] dividend_shift_reg;
    logic [63:0] quotient_reg;
    logic [64:0] remainder_reg;
    i64          result_reg;

    logic       op_rem;
    logic       op_signed;
    logic       op_word;
    logic       lhs_neg;
    logic       rhs_neg;
    logic       divisor_zero;
    logic       signed_overflow;
    logic [63:0] lhs_mag;
    logic [63:0] rhs_mag;
    logic [63:0] dividend_start;
    i64          special_result;

    logic [64:0] divisor_ext;
    logic [64:0] rem_shift;
    logic [64:0] remainder_next;
    logic [63:0] quotient_next;
    logic [63:0] dividend_shift_next;
    logic [63:0] quotient_signed;
    logic [63:0] remainder_signed;
    logic [63:0] final_raw;
    i64          final_result;

    function automatic i64 sext32(input logic [31:0] value);
        return {{32{value[31]}}, value};
    endfunction

    function automatic logic [63:0] neg64(input logic [63:0] value);
        return ~value + 64'd1;
    endfunction

    always_comb begin : start_prepare
        op_rem          = (opr == REM || opr == REMU);
        op_signed       = (opr == DIV || opr == REM);
        op_word         = (word_index == WORD);
        lhs_neg         = 1'b0;
        rhs_neg         = 1'b0;
        divisor_zero    = 1'b0;
        signed_overflow = 1'b0;
        lhs_mag         = lhs;
        rhs_mag         = rhs;
        dividend_start  = lhs;
        special_result  = 64'b0;

        if (op_word) begin
            divisor_zero    = rhs[31:0] == 32'b0;
            lhs_neg         = op_signed && lhs[31];
            rhs_neg         = op_signed && rhs[31];
            signed_overflow = op_signed && lhs[31:0] == 32'h8000_0000 &&
                rhs[31:0] == 32'hffff_ffff;
            lhs_mag = {32'b0, lhs[31:0]};
            rhs_mag = {32'b0, rhs[31:0]};
            if (lhs_neg)
                lhs_mag = {32'b0, (~lhs[31:0] + 32'd1)};
            if (rhs_neg)
                rhs_mag = {32'b0, (~rhs[31:0] + 32'd1)};
            dividend_start = {lhs_mag[31:0], 32'b0};
            if (divisor_zero)
                special_result = op_rem ? sext32(lhs[31:0]) : 64'hffff_ffff_ffff_ffff;
            else if (signed_overflow)
                special_result = op_rem ? 64'b0 : sext32(32'h8000_0000);
        end else begin
            divisor_zero    = rhs == 64'b0;
            lhs_neg         = op_signed && lhs[63];
            rhs_neg         = op_signed && rhs[63];
            signed_overflow = op_signed && lhs == 64'h8000_0000_0000_0000 &&
                rhs == 64'hffff_ffff_ffff_ffff;
            if (lhs_neg)
                lhs_mag = neg64(lhs);
            if (rhs_neg)
                rhs_mag = neg64(rhs);
            dividend_start = lhs_mag;
            if (divisor_zero)
                special_result = op_rem ? lhs : 64'hffff_ffff_ffff_ffff;
            else if (signed_overflow)
                special_result = op_rem ? 64'b0 : 64'h8000_0000_0000_0000;
        end
    end

    always_comb begin : div_step
        divisor_ext         = {1'b0, divisor_reg};
        rem_shift           = {remainder_reg[63:0], dividend_shift_reg[63]};
        dividend_shift_next = {dividend_shift_reg[62:0], 1'b0};
        if (rem_shift >= divisor_ext) begin
            remainder_next = rem_shift - divisor_ext;
            quotient_next  = {quotient_reg[62:0], 1'b1};
        end else begin
            remainder_next = rem_shift;
            quotient_next  = {quotient_reg[62:0], 1'b0};
        end

        quotient_signed  = quotient_neg ? neg64(quotient_next) : quotient_next;
        remainder_signed = remainder_neg ? neg64(remainder_next[63:0]) : remainder_next[63:0];
        final_raw        = rem_sel ? remainder_signed : quotient_signed;
        final_result     = word_sel ? sext32(final_raw[31:0]) : final_raw;
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state              <= DIV_IDLE;
            rem_sel            <= 1'b0;
            word_sel           <= 1'b0;
            quotient_neg       <= 1'b0;
            remainder_neg      <= 1'b0;
            count              <= 7'b0;
            divisor_reg        <= 64'b0;
            dividend_shift_reg <= 64'b0;
            quotient_reg       <= 64'b0;
            remainder_reg      <= 65'b0;
            result_reg         <= 64'b0;
        end else if (flush) begin
            state              <= DIV_IDLE;
            count              <= 7'b0;
            divisor_reg        <= 64'b0;
            dividend_shift_reg <= 64'b0;
            quotient_reg       <= 64'b0;
            remainder_reg      <= 65'b0;
            result_reg         <= 64'b0;
        end else begin
            unique case (state)
                DIV_IDLE: begin
                    if (start) begin
                        rem_sel       <= op_rem;
                        word_sel      <= op_word;
                        quotient_neg  <= op_signed && (lhs_neg ^ rhs_neg);
                        remainder_neg <= op_signed && lhs_neg;
                        quotient_reg  <= 64'b0;
                        remainder_reg <= 65'b0;
                        if (divisor_zero || signed_overflow) begin
                            result_reg         <= special_result;
                            count              <= 7'b0;
                            divisor_reg        <= 64'b0;
                            dividend_shift_reg <= 64'b0;
                            state              <= DIV_DONE;
                        end else begin
                            result_reg         <= 64'b0;
                            divisor_reg        <= rhs_mag;
                            dividend_shift_reg <= dividend_start;
                            count              <= op_word ? 7'd32 : 7'd64;
                            state              <= DIV_RUN;
                        end
                    end
                end
                DIV_RUN: begin
                    dividend_shift_reg <= dividend_shift_next;
                    quotient_reg       <= quotient_next;
                    remainder_reg      <= remainder_next;
                    if (count == 7'd1) begin
                        result_reg <= final_result;
                        count      <= 7'b0;
                        state      <= DIV_DONE;
                    end else begin
                        count <= count - 7'd1;
                    end
                end
                DIV_DONE: begin
                    if (consume)
                        state <= DIV_IDLE;
                end
                default: state <= DIV_IDLE;
            endcase
        end
    end

    assign busy   = state != DIV_IDLE;
    assign done   = state == DIV_DONE;
    assign result = result_reg;

endmodule
`endif
