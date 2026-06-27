`ifndef __DBUSTOCBUS_SV
`define __DBUSTOCBUS_SV

`ifdef VERILATOR
`include "include/common.sv"
`else

`endif
/**
 * NOTE: CBus does not support byte write enable mask (write_en).
 */

module DBusToCBus
    import common::*;(
    input  logic       clk,
    input  logic       reset,
    input  logic       flush,
    input  dbus_req_t  dreq,
    output dbus_resp_t dresp,
    output cbus_req_t  dcreq,
    input  cbus_resp_t dcresp
);
    cbus_req_t saved_req;
    logic busy;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            busy <= 1'b0;
            saved_req <= '0;
        end else if (flush) begin
            busy <= 1'b0;
            saved_req <= '0;
        end else if (busy) begin
            if (dcresp.ready && dcresp.last) begin
                busy <= 1'b0;
                saved_req <= '0;
            end
        end else if (dreq.valid) begin
            busy <= 1'b1;
            saved_req.valid    <= 1'b1;
            saved_req.is_write <= |dreq.strobe;
            saved_req.size     <= dreq.size;
            saved_req.addr     <= dreq.addr;
            saved_req.strobe   <= dreq.strobe;
            saved_req.data     <= dreq.data;
            saved_req.len      <= MLEN1;
            saved_req.burst    <= AXI_BURST_FIXED;
        end
    end

    assign dcreq = busy ? saved_req : '0;

    logic done;
    assign done = busy && dcresp.ready && dcresp.last;

    assign dresp.addr_ok = done;
    assign dresp.data_ok = done;
    assign dresp.data    = dcresp.data;
endmodule



`endif