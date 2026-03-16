`ifndef __CORE_SV
`define __CORE_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

`include "src/CPU.sv"

module core import common::*;(
	input  logic       clk, reset,
	output ibus_req_t  ireq,
	input  ibus_resp_t iresp,
	output dbus_req_t  dreq,
	input  dbus_resp_t dresp,
	input  logic       trint, swint, exint
);

	/**
	 * variables for difftest commit
	 */
	logic valid_c;
	u64 pc_c;
	u32 instr_c;
	logic w_en_c;
	u8 wd_c;
	i64 wdata_c;
	i64 reg_c [0:31];
	
	CPU cpu(
		.clk(clk),
		.reset(reset),
		.iresp(iresp),
		.ireq(ireq),
		.dresp(dresp),
		.dreq(dreq),
		.valid_c(valid_c),
		.pc_c(pc_c),
		.instr_c(instr_c),
		.w_en_c(w_en_c),
		.wd_c(wd_c),
		.wdata_c(wdata_c),
		.reg_c(reg_c)
	);

`ifdef VERILATOR
	DifftestInstrCommit DifftestInstrCommit(
		.clock              (clk),
		.coreid             (0),
		.index              (0),
		.valid              (valid_c),
		.pc                 (pc_c),
		.instr              (instr_c),
		.skip               (0),
		.isRVC              (0),
		.scFailed           (0),
		.wen                (w_en_c),
		.wdest              (wd_c),
		.wdata              (wdata_c)
	);

	DifftestArchIntRegState DifftestArchIntRegState (
		.clock              (clk),
		.coreid             (0),
		.gpr_0              (reg_c[0]),
		.gpr_1              (reg_c[1]),
		.gpr_2              (reg_c[2]),
		.gpr_3              (reg_c[3]),
		.gpr_4              (reg_c[4]),
		.gpr_5              (reg_c[5]),
		.gpr_6              (reg_c[6]),
		.gpr_7              (reg_c[7]),
		.gpr_8              (reg_c[8]),
		.gpr_9              (reg_c[9]),
		.gpr_10             (reg_c[10]),
		.gpr_11             (reg_c[11]),
		.gpr_12             (reg_c[12]),
		.gpr_13             (reg_c[13]),
		.gpr_14             (reg_c[14]),
		.gpr_15             (reg_c[15]),
		.gpr_16             (reg_c[16]),
		.gpr_17             (reg_c[17]),
		.gpr_18             (reg_c[18]),
		.gpr_19             (reg_c[19]),
		.gpr_20             (reg_c[20]),
		.gpr_21             (reg_c[21]),
		.gpr_22             (reg_c[22]),
		.gpr_23             (reg_c[23]),
		.gpr_24             (reg_c[24]),
		.gpr_25             (reg_c[25]),
		.gpr_26             (reg_c[26]),
		.gpr_27             (reg_c[27]),
		.gpr_28             (reg_c[28]),
		.gpr_29             (reg_c[29]),
		.gpr_30             (reg_c[30]),
		.gpr_31             (reg_c[31])
	);

    DifftestTrapEvent DifftestTrapEvent(
		.clock              (clk),
		.coreid             (0),
		.valid              (0),
		.code               (0),
		.pc                 (0),
		.cycleCnt           (0),
		.instrCnt           (0)
	);

	DifftestCSRState DifftestCSRState(
		.clock              (clk),
		.coreid             (0),
		.priviledgeMode     (3),
		.mstatus            (0),
		.sstatus            (0 /* mstatus & 64'h800000030001e000 */),
		.mepc               (0),
		.sepc               (0),
		.mtval              (0),
		.stval              (0),
		.mtvec              (0),
		.stvec              (0),
		.mcause             (0),
		.scause             (0),
		.satp               (0),
		.mip                (0),
		.mie                (0),
		.mscratch           (0),
		.sscratch           (0),
		.mideleg            (0),
		.medeleg            (0)
	);
`endif
endmodule
`endif