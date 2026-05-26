`ifndef __FETCH_SV
`define __FETCH_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module Fetch import common::*;(
    input  logic       clk, reset,
    input  logic       stall,
    input  priv_mode_t priv_mode,

    input  logic       redirect_valid,
    input  addr_t      redirect_pc,

    input  dbus_resp_t dresp,
    output dbus_req_t  dreq,

    output IF_ID_t     if_id
);

    u64 pc;
    u32 instr;

    /**
     * Fetch state indicate
     */
    logic waiting; 
    logic instr_valid;
    logic redirect_pending;
    addr_t redirect_target;

    /**
     * front pipeline
     */
    IF_ID_t if_id_next;

    /**
     * dbus ctrl
     */
    assign dreq.valid  = waiting;
    assign dreq.addr   = pc;
    assign dreq.size   = MSIZE4;
    assign dreq.strobe = 8'b0;
    assign dreq.data   = 64'b0;
    assign dreq.access = DBUS_FETCH;
    assign dreq.priv   = priv_mode;

    always_ff @(posedge clk or posedge reset) begin : fetch_main
        if(reset) begin
            pc <= PCINIT;
            waiting <= 1'b1;
            instr_valid <= 1'b0;
            redirect_pending <= 1'b0;
            redirect_target <= PCINIT;
        end
        else begin
            if(redirect_valid) begin
                if (waiting) begin
                    redirect_pending <= 1'b1;
                    redirect_target <= redirect_pc;
                end else begin
                    pc <= redirect_pc;
                    waiting <= 1'b1;
                    redirect_pending <= 1'b0;
                end
                instr_valid <= 1'b0;
            end
            else if(waiting) begin
                if(dresp.data_ok) begin
                    if (redirect_pending) begin
                        pc <= redirect_target;
                        waiting <= 1'b1;
                        instr_valid <= 1'b0;
                        redirect_pending <= 1'b0;
                    end else begin
                        instr <= pc[2] ? dresp.data[63:32] : dresp.data[31:0];
                        instr_valid <= 1'b1;
                        waiting <= 1'b0;
                    end
                end
            end
            else if(!stall) begin
                pc <= pc + 4;
                waiting <= 1'b1;
                instr_valid <= 1'b0;
            end
        end
    end

    /**
     * store pipeline
     */
    always_comb begin
        if_id_next.valid              = instr_valid;
        if_id_next.decoder_ctrl.instr = instr;
        if_id_next.decoder_ctrl.pc    = pc;
    end

    /**
     * pipeline step
     */
    always_ff @(posedge clk or posedge reset) begin : if_id_pipeline
        if(reset)
            if_id <= '0;
        else if(redirect_valid)
            if_id <= '0;
        else if(!stall)
            if_id <= if_id_next;
    end

endmodule

`endif