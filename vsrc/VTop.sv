`ifndef __VTOP_SV
`define __VTOP_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "src/core.sv"
`include "util/DBusToCBus.sv"
`include "util/DBusArbiter.sv"
`include "src/MMU.sv"

`endif
module VTop 
	import common::*;(
	input logic clk, reset,

	output cbus_req_t  oreq,
	input  cbus_resp_t oresp,
	input logic trint, swint, exint
);

    ibus_req_t  ireq;
    ibus_resp_t iresp;
    dbus_req_t  fetch_dreq, mem_dreq, cpu_dreq, mmu_dreq;
    dbus_resp_t fetch_dresp, mem_dresp, cpu_dresp, mmu_dresp;
    cbus_req_t  dcreq;
    cbus_resp_t dcresp;
    priv_mode_t priv_mode;
    u64 satp;
    u64 mstatus_c;
    u64 pmpaddr0;
    u64 pmpcfg0;
    logic mmu_fault_valid;
    u64 mmu_fault_vaddr;
    u64 mmu_fault_cause;

    core core(
        .clk, .reset,
        .ireq, .iresp,
        .fetch_dreq, .fetch_dresp,
        .dreq(mem_dreq), .dresp(mem_dresp),
        .trint, .swint, .exint,
        .mmu_fault_valid, .mmu_fault_vaddr, .mmu_fault_cause,
        .priv_mode, .satp,
        .pmpaddr0, .pmpcfg0, .mstatus_out(mstatus_c)
    );

    DBusArbiter dbus_mux(
        .clk, .reset,
        .ireqs({fetch_dreq, mem_dreq}),
        .iresps({fetch_dresp, mem_dresp}),
        .oreq(cpu_dreq),
        .oresp(cpu_dresp)
    );

    MMU mmu(
        .clk, .reset,
        .priv_mode, .satp,
        .mstatus(mstatus_c),
        .pmpaddr0, .pmpcfg0,
        .vreq(cpu_dreq),
        .vresp(cpu_dresp),
        .preq(mmu_dreq),
        .presp(mmu_dresp),
        .fault_valid(mmu_fault_valid),
        .fault_vaddr(mmu_fault_vaddr),
        .fault_cause(mmu_fault_cause)
    );

    DBusToCBus dcvt(
        .clk, .reset,
        .dreq(mmu_dreq),
        .dresp(mmu_dresp),
        .dcreq(dcreq),
        .dcresp(dcresp)
    );

    assign oreq = dcreq;
    assign dcresp = oresp;
    assign iresp = '0;

	always_ff @(posedge clk) begin
		if (~reset) begin
			// $display("icreq %x, %x", icreq.valid, icreq.addr);
			// if (oreq.valid || dcreq.addr == 64'h40600004) $display("dcreq %x, %x, oreq %x, %x, dcresp %x", dcreq.addr, dcreq.valid, oreq.valid, oreq.addr, dcresp.ready);
		end
	end
	

endmodule



`endif