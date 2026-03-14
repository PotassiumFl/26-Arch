`ifndef __HAZARD_SV
`define __HAZARD_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module Hazard import common::*; (
    input ID_EX_t id_ex,
    input IF_ID_t if_id,

    output logic stall
);

    always_comb begin
        stall = 1'b0;
    end

endmodule

`endif