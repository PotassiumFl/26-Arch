`ifndef __CORE_SV
`define __CORE_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "include/csr.sv"
`include "src/CPU.sv"
`endif



module core import common::*; import csr_pkg::*;(
	input  logic       clk, reset,
	output ibus_req_t  ireq,
	input  ibus_resp_t iresp,
	output dbus_req_t  fetch_dreq,
	input  dbus_resp_t fetch_dresp,
	output dbus_req_t  dreq,
	input  dbus_resp_t dresp,
	input  logic       trint, swint, exint,
	input  logic       mmu_fault_valid,
	input  u64         mmu_fault_vaddr,
	input  u64         mmu_fault_cause,
	output priv_mode_t priv_mode,
	output u64         satp
);

	/**
	 * variables for difftest commit
	 */
	logic 	valid_c;
	u64 	pc_c;
	u32 	instr_c;
	logic 	w_en_c;
	u8 		wd_c;
	i64 	wdata_c;
	i64 	reg_c [0:31];
	mem_op_t mem_op_c;
	u64 	mem_addr_c;
	u64 	mhartid_c;
	u64 	mcycle_c;
	u64 	mstatus_c;
	u64 	mepc_c;
	u64 	mtvec_c;
	u64 	mcause_c;
	u64 	mtval_c;
	u64 	mip_c;
	u64 	mie_c;
	u64 	mscratch_c;
	u64 	satp_c;
	u64 	mideleg_c;
	u64 	medeleg_c;
	u64 	sepc_c;
	u64 	stval_c;
	u64 	stvec_c;
	u64 	scause_c;
	u64 	sscratch_c;

	CPU cpu(
		.clk(clk),
		.reset(reset),
		.iresp(iresp),
		.ireq(ireq),
		.fetch_dresp(fetch_dresp),
		.fetch_dreq(fetch_dreq),
		.dresp(dresp),
		.dreq(dreq),
		.mmu_fault_valid(mmu_fault_valid),
		.mmu_fault_vaddr(mmu_fault_vaddr),
		.mmu_fault_cause(mmu_fault_cause),
		.priv_mode_c(priv_mode),
		.valid_c(valid_c),
		.pc_c(pc_c),
		.instr_c(instr_c),
		.w_en_c(w_en_c),
		.wd_c(wd_c),
		.wdata_c(wdata_c),
		.reg_c(reg_c),	
		.mem_addr_c(mem_addr_c),
		.mem_op_c(mem_op_c),
		.mhartid_c(mhartid_c),
		.mcycle_c(mcycle_c),
		.mstatus_c(mstatus_c),
		.mepc_c(mepc_c),
		.mtvec_c(mtvec_c),
		.mcause_c(mcause_c),
		.mtval_c(mtval_c),
		.mip_c(mip_c),
		.mie_c(mie_c),
		.mscratch_c(mscratch_c),
		.satp_c(satp_c),
		.mideleg_c(mideleg_c),
		.medeleg_c(medeleg_c),
		.sepc_c(sepc_c),
		.stval_c(stval_c),
		.stvec_c(stvec_c),
		.scause_c(scause_c),
		.sscratch_c(sscratch_c)
	);

	assign satp = satp_c;

`ifdef VERILATOR
	DifftestInstrCommit DifftestInstrCommit(
		.clock              (clk),
		.coreid             (mhartid_c[7:0]),
		.index              (0),
		.valid              (valid_c),
		.pc                 (pc_c),
		.instr              (instr_c),
		.skip               ((mem_op_c == MEM_STORE || mem_op_c == MEM_LOAD) && mem_addr_c[31] == 0),
		.isRVC              (0),
		.scFailed           (0),
		.wen                (w_en_c),
		.wdest              (wd_c),
		.wdata              (wdata_c)
	);

	DifftestArchIntRegState DifftestArchIntRegState (
		.clock              (clk),
		.coreid             (mhartid_c[7:0]),
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
		.coreid             (mhartid_c[7:0]),
		.valid              ('0),
		.code               ('0),
		.pc                 ('0),
		.cycleCnt           ('0),
		.instrCnt           ('0)
	);

	DifftestCSRState DifftestCSRState(
		.clock              (clk),
		.coreid             (mhartid_c[7:0]),
		.priviledgeMode     (priv_mode),
		.mstatus            (mstatus_c),
		.sstatus            (mstatus_c & SSTATUS_MASK),
		.mepc               (mepc_c),
		.sepc               (sepc_c),
		.mtval              (mtval_c),
		.stval              (stval_c),
		.mtvec              (mtvec_c),
		.stvec              (stvec_c),
		.mcause             (mcause_c),
		.scause             (scause_c),
		.satp               (satp_c),
		.mip                (mip_c),
		.mie                (mie_c),
		.mscratch           (mscratch_c),
		.sscratch           (sscratch_c),
		.mideleg            (mideleg_c),
		.medeleg            (medeleg_c)
	);
`endif
endmodule
`endif
