`ifndef __FETCH_SV
`define __FETCH_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module Fetch import common::*;(
    input  logic       clk, reset,
    input  logic       stall,

    input  ibus_resp_t iresp,
    output ibus_req_t  ireq,

    output IF_ID_t     if_id
);

    u64 pc;
    u32 instr;

    logic waiting;
    logic instr_valid;

    IF_ID_t if_id_next;

    assign ireq.valid = waiting;
    assign ireq.addr  = pc;

    always_ff @(posedge clk or posedge reset) begin
        if(reset) begin
            pc <= PCINIT;
            waiting <= 1'b1;
            instr_valid <= 1'b0;
        end
        else begin
            if(waiting) begin
                if(iresp.data_ok) begin
                    instr <= iresp.data;
                    instr_valid <= 1'b1;
                    waiting <= 1'b0;
                end
            end
            else if(!stall) begin
                pc <= pc + 4;
                waiting <= 1'b1;
                instr_valid <= 1'b0;
            end
        end
    end

    always_comb begin
        if_id_next.valid = instr_valid;
        if_id_next.decoder_ctrl.instr = instr;
        if_id_next.decoder_ctrl.pc    = pc;
    end

    always_ff @(posedge clk or posedge reset) begin
        if(reset)
            if_id <= '0;
        else if(!stall)
            if_id <= if_id_next;
    end

endmodule

`endif