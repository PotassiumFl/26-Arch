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

    output IF_ID_t     if_id,
    output addr_t      fetch_pc
);

    u64 pc;
    u32 instr;
    funct7_t instr_opcode;
    i64 imm_b;
    i64 imm_j;
    logic pred_taken;
    addr_t pred_target;
    addr_t next_pc;

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
    assign fetch_pc    = pc;

    assign instr_opcode = funct7_t'(instr[6:0]);
    assign imm_b = {{52{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
    assign imm_j = {{44{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

    always_comb begin : predict_next_pc
        pred_taken  = 1'b0;
        pred_target = pc + 64'd4;
        unique case (instr_opcode)
            JAL: begin
                pred_taken  = instr_valid;
                pred_target = pc + imm_j;
            end
            BRANCH: begin
                pred_taken  = instr_valid && imm_b[63];
                pred_target = pc + imm_b;
            end
            default: ;
        endcase
        next_pc = pred_taken ? pred_target : (pc + 64'd4);
    end

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
                pc <= next_pc;
                waiting <= 1'b1;
                instr_valid <= 1'b0;
            end
        end
    end

    /**
     * store pipeline
     */
    always_comb begin
        if_id_next.valid                    = instr_valid;
        if_id_next.decoder_ctrl.instr       = instr;
        if_id_next.decoder_ctrl.pc          = pc;
        if_id_next.decoder_ctrl.pred_taken  = pred_taken;
        if_id_next.decoder_ctrl.pred_target = pred_target;
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