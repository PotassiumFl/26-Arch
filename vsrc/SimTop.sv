`ifdef VERILATOR
`include "include/common.sv"
`include "src/core.sv"
`include "util/DBusToCBus.sv"
`include "util/DBusArbiter.sv"
`include "src/MMU.sv"

module SimTop import common::*;(
  input         clock,
  input         reset,
  input  [63:0] io_logCtrl_log_begin,
  input  [63:0] io_logCtrl_log_end,
  input  [63:0] io_logCtrl_log_level,
  input         io_perfInfo_clean,
  input         io_perfInfo_dump,
  output        io_uart_out_valid,
  output [7:0]  io_uart_out_ch,
  output        io_uart_in_valid,
  input  [7:0]  io_uart_in_ch
);

    cbus_req_t  oreq;
    cbus_resp_t oresp;
    logic trint, swint, exint;

    ibus_req_t  ireq;
    ibus_resp_t iresp;
    dbus_req_t  fetch_dreq, mem_dreq, cpu_dreq, mmu_dreq;
    dbus_resp_t fetch_dresp, mem_dresp, cpu_dresp, mmu_dresp;
    cbus_req_t  dcreq;
    cbus_resp_t dcresp;
    priv_mode_t priv_mode;
    u64 satp;
    logic mmu_fault_valid;
    u64 mmu_fault_vaddr;
    u64 mmu_fault_cause;

    core core(
      .clk(clock), .reset,
      .ireq, .iresp,
      .fetch_dreq, .fetch_dresp,
      .dreq(mem_dreq), .dresp(mem_dresp),
      .trint, .swint, .exint,
      .mmu_fault_valid, .mmu_fault_vaddr, .mmu_fault_cause,
      .priv_mode, .satp
    );

    DBusArbiter dbus_mux(
        .clk(clock), .reset,
        .ireqs({fetch_dreq, mem_dreq}),
        .iresps({fetch_dresp, mem_dresp}),
        .oreq(cpu_dreq),
        .oresp(cpu_dresp)
    );

    MMU mmu(
        .clk(clock), .reset,
        .priv_mode, .satp,
        .vreq(cpu_dreq),
        .vresp(cpu_dresp),
        .preq(mmu_dreq),
        .presp(mmu_dresp),
        .fault_valid(mmu_fault_valid),
        .fault_vaddr(mmu_fault_vaddr),
        .fault_cause(mmu_fault_cause)
    );

    DBusToCBus dcvt(
        .clk(clock),
        .reset(reset),
        .dreq(mmu_dreq),
        .dresp(mmu_dresp),
        .dcreq(dcreq),
        .dcresp(dcresp)
    );

    assign oreq = dcreq;
    assign dcresp = oresp;
    assign iresp = '0;

    RAMHelper2 ram(
        .clk(clock), .reset, .oreq, .oresp, .trint, .swint, .exint
    );

    assign {io_uart_out_valid, io_uart_out_ch, io_uart_in_valid} = '0;

endmodule
`endif