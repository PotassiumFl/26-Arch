`ifndef __FETCH_SV
`define __FETCH_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module Fetch import common::*;(
    input   logic           clk,reset,

    input   ibus_resp_t     iresp,
    output  ibus_req_t      ireq,

    output  IF_ID_t         if_id
);

    u64           pc;
    fetch_state_t state;
    

    always_ff @( posedge clk or posedge reset) begin : fetch
        if (reset) begin
            pc          <= PCINIT;
            state       <= IDLE;
            ireq.valid  <= 0;
            if_id.valid <= 0;
        end
        else begin
            case (state)
                IDLE: begin
                    ireq.valid <= 1;
                    ireq.addr  <= pc;
                    state      <= WAIT_ADDR;
                end 

                WAIT_ADDR:
                    if (iresp.addr_ok) begin
                        if_id.valid <= 1;
                        state       <= WAIT_DATA;
                    end

                WAIT_DATA:
                    if (iresp.data_ok) begin
                        if_id.valid <= 1;
                        if_id.decoder_ctrl.instr <= iresp.data;
                        if_id.decoder_ctrl.pc <= pc;

                        pc <= pc + 4;
                        state <= IDLE;
                    end
                default: state <= state;
            endcase
        end
    end

endmodule

`endif