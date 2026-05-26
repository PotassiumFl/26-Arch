`ifndef __DBUSARBITER_SV
`define __DBUSARBITER_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module DBusArbiter
    import common::*; #(
    parameter int NUM_INPUTS = 2,
    localparam int MAX_INDEX = NUM_INPUTS - 1
) (
    input  logic       clk,
    input  logic       reset,
    input  dbus_req_t  [MAX_INDEX:0] ireqs,
    output dbus_resp_t [MAX_INDEX:0] iresps,
    output dbus_req_t  oreq,
    input  dbus_resp_t oresp
);
    logic busy;
    int index, select;
    dbus_req_t saved_req;

    assign oreq = busy ? saved_req : '0;

    always_comb begin
        select = 0;
        for (int i = 0; i < NUM_INPUTS; i++) begin
            if (ireqs[i].valid) begin
                select = i;
                break;
            end
        end
    end

    always_comb begin
        iresps = '0;
        if (busy) begin
            for (int i = 0; i < NUM_INPUTS; i++) begin
                if (index == i)
                    iresps[i] = oresp;
            end
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            busy <= 1'b0;
            index <= 0;
            saved_req <= '0;
        end else if (busy) begin
            if (oresp.data_ok) begin
                busy <= 1'b0;
                saved_req <= '0;
            end
        end else begin
            busy <= ireqs[select].valid;
            index <= select;
            saved_req <= ireqs[select];
        end
    end
endmodule

`endif
