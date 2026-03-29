`ifndef __HAZARD_SV
`define __HAZARD_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module Hazard import common::*; (
    input ID_EX_t id_ex,
    input IF_ID_t if_id,
    input EX_MEM_t ex_mem,
    output logic stall
);

    `UNUSED_OK({if_id});

    always_comb begin
        stall = 1'b0;
        if (id_ex.valid && ex_mem.valid && ex_mem.mem_op == MEM_LOAD
            && ex_mem.reg_write && ex_mem.wd != 5'b0) begin
            if (id_ex.rs1 != 5'b0 && id_ex.rs1 == ex_mem.wd)
                stall = 1'b1;
            if (id_ex.uses_rs2 && id_ex.rs2 != 5'b0 && id_ex.rs2 == ex_mem.wd)
                stall = 1'b1;
        end
    end

endmodule

`endif
