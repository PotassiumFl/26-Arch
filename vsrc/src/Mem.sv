`ifndef __MEM_SV
`define __MEM_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module Mem import common::*; (
    input  logic clk,
    input  logic reset,
    input  logic hazard_stall,
    input  priv_mode_t priv_mode,
    input  EX_MEM_t ex_mem,
    input  u64 csr_read_rdata,
    input  logic pipeline_flush,
    output MEM_WB_t mem_wb,
    output dbus_req_t dreq,
    input  dbus_resp_t dresp,
    output logic mem_busy,
    output logic atomic_busy,
    output logic mem_inst_done,
    output logic wb_fire,
    output MEM_WB_t wb_next,
    output logic trap_valid,
    output u64   trap_cause,
    output u64   trap_tval,
    output u64   trap_epc
);

    MEM_WB_t mem_wb_next;
    logic    mem_started;

    typedef enum logic [1:0] {
        ATOM_OFF,
        ATOM_LOAD,
        ATOM_STORE
    } atom_state_t;

    atom_state_t atom_state;
    logic [31:0] atom_old_word;
    logic [31:0] atom_store_word;

    logic        res_valid [0:1];
    addr_t       res_addr  [0:1];

    function automatic logic ls_misaligned(input addr_t addr, input u3 f3);
        unique case (f3)
            3'b000, 3'b100: return 1'b0;
            3'b001, 3'b101: return addr[0] != 1'b0;
            3'b010, 3'b110: return addr[1:0] != 2'b00;
            3'b011:         return addr[2:0] != 3'b000;
            default:        return 1'b0;
        endcase
    endfunction

    function automatic logic [31:0] amo_new_val(
        input amo_funct5_t op,
        input logic [31:0] old_val,
        input logic [31:0] rs2_val
    );
        unique case (op)
            AMO_ADD:  return old_val + rs2_val;
            AMO_SWAP: return rs2_val;
            AMO_XOR:  return old_val ^ rs2_val;
            AMO_OR:   return old_val | rs2_val;
            AMO_AND:  return old_val & rs2_val;
            AMO_MIN:  return ($signed(old_val) < $signed(rs2_val)) ? old_val : rs2_val;
            AMO_MAX:  return ($signed(old_val) > $signed(rs2_val)) ? old_val : rs2_val;
            AMO_MINU: return (old_val < rs2_val) ? old_val : rs2_val;
            AMO_MAXU: return (old_val > rs2_val) ? old_val : rs2_val;
            default:  return old_val;
        endcase
    endfunction

    function automatic logic [31:0] load_word32(input word_t raw, input addr_t a);
        u3 sh;
        sh = a[2:0];
        return raw[8*sh +: 32];
    endfunction

    function automatic logic res_match(input addr_t addr);
        addr_t aligned;
        aligned = {addr[63:2], 2'b00};
        return (res_valid[0] && res_addr[0] == aligned) ||
               (res_valid[1] && res_addr[1] == aligned);
    endfunction

    function automatic i64 sign_ext32(input logic [31:0] w);
        return {{32{w[31]}}, w};
    endfunction

    logic addr_misalign;
    logic in_atomic;
    logic atom_start;
    logic sc_start_ok;
    logic sc_start_fail;

    assign addr_misalign = ls_misaligned(ex_mem.alu_result, ex_mem.ls_funct3);
    assign in_atomic     = ex_mem.mem_op == MEM_ATOMIC;
    assign atomic_busy   = in_atomic && mem_busy;
    assign atom_start    = !mem_busy && ex_mem.valid && in_atomic && !addr_misalign;
    assign sc_start_ok   = atom_start && ex_mem.amo_funct5 == AMO_SC &&
        res_match(ex_mem.alu_result);
    assign sc_start_fail = atom_start && ex_mem.amo_funct5 == AMO_SC &&
        !res_match(ex_mem.alu_result);

    assign trap_valid = ex_mem.valid && ex_mem.mem_op != MEM_NONE &&
        addr_misalign && !mem_busy;
    assign trap_cause = (ex_mem.mem_op == MEM_STORE) ? 64'd6 : 64'd4;
    assign trap_tval  = ex_mem.alu_result;
    assign trap_epc   = ex_mem.decoder_ctrl.pc;

    always_ff @(posedge clk or posedge reset) begin : reservation_set
        integer i;
        if (reset) begin
            for (i = 0; i < 2; i = i + 1) begin
                res_valid[i] <= 1'b0;
                res_addr[i]  <= '0;
            end
        end else if (pipeline_flush || sc_start_ok || sc_start_fail) begin
            for (i = 0; i < 2; i = i + 1)
                res_valid[i] <= 1'b0;
        end else begin
            if (dreq.valid && dreq.access == DBUS_STORE)
                for (i = 0; i < 2; i = i + 1)
                    res_valid[i] <= 1'b0;
            if (atom_state == ATOM_LOAD && dresp.data_ok &&
                    ex_mem.amo_funct5 == AMO_LR) begin
                if (!res_valid[0]) begin
                    res_valid[0] <= 1'b1;
                    res_addr[0]  <= {ex_mem.alu_result[63:2], 2'b00};
                end else if (!res_valid[1]) begin
                    res_valid[1] <= 1'b1;
                    res_addr[1]  <= {ex_mem.alu_result[63:2], 2'b00};
                end else begin
                    res_valid[0] <= 1'b1;
                    res_addr[0]  <= {ex_mem.alu_result[63:2], 2'b00};
                end
            end
        end
    end

    always_ff @(posedge clk or posedge reset) begin : atom_fsm
        if (reset) begin
            atom_state      <= ATOM_OFF;
            atom_old_word   <= 32'b0;
            atom_store_word <= 32'b0;
        end else if (pipeline_flush) begin
            atom_state <= ATOM_OFF;
        end else begin
            case (atom_state)
                ATOM_OFF: begin
                    if (atom_start) begin
                        if (ex_mem.amo_funct5 == AMO_SC) begin
                            atom_store_word <= ex_mem.store_data[31:0];
                            if (res_match(ex_mem.alu_result))
                                atom_state <= ATOM_STORE;
                        end else
                            atom_state <= ATOM_LOAD;
                    end
                end
                ATOM_LOAD: begin
                    if (dresp.data_ok) begin
                        atom_old_word <= load_word32(dresp.data, ex_mem.alu_result);
                        if (ex_mem.amo_funct5 == AMO_LR)
                            atom_state <= ATOM_OFF;
                        else begin
                            atom_store_word <= amo_new_val(
                                ex_mem.amo_funct5,
                                load_word32(dresp.data, ex_mem.alu_result),
                                ex_mem.store_data[31:0]);
                            atom_state <= ATOM_STORE;
                        end
                    end
                end
                ATOM_STORE: begin
                    if (dresp.data_ok)
                        atom_state <= ATOM_OFF;
                end
                default: atom_state <= ATOM_OFF;
            endcase
        end
    end

    always_ff @(posedge clk or posedge reset) begin : mem_busy_ff
        if (reset)
            mem_busy <= 1'b0;
        else if (pipeline_flush) begin
            if (mem_started && !dresp.data_ok)
                mem_busy <= 1'b1;
            else
                mem_busy <= 1'b0;
        end else if (in_atomic && atom_state != ATOM_OFF) begin
            if (atom_state == ATOM_LOAD && dresp.data_ok &&
                    ex_mem.amo_funct5 == AMO_LR)
                mem_busy <= 1'b0;
            else if (atom_state == ATOM_STORE && dresp.data_ok)
                mem_busy <= 1'b0;
            else if (sc_start_fail)
                mem_busy <= 1'b0;
            else if (atom_start || sc_start_ok)
                mem_busy <= 1'b1;
        end else if (mem_busy) begin
            if (dresp.data_ok)
                mem_busy <= 1'b0;
        end else if (atom_start && !sc_start_fail)
            mem_busy <= 1'b1;
        else if (!mem_busy && ex_mem.valid &&
                (ex_mem.mem_op == MEM_LOAD || ex_mem.mem_op == MEM_STORE) &&
                !addr_misalign)
            mem_busy <= 1'b1;
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            mem_started <= 1'b0;
        else if (pipeline_flush && !mem_started)
            mem_started <= 1'b0;
        else if (!mem_busy)
            mem_started <= 1'b0;
        else if (mem_busy && dreq.valid)
            mem_started <= 1'b1;
        else if (in_atomic && atom_state == ATOM_LOAD && dresp.data_ok &&
                ex_mem.amo_funct5 != AMO_LR)
            mem_started <= 1'b0;
        else if (sc_start_ok)
            mem_started <= 1'b0;
    end

    addr_t daddr;
    u3     off;
    assign daddr = ex_mem.alu_result;
    assign off   = daddr[2:0];

    logic atom_dreq_valid;
    assign atom_dreq_valid = in_atomic && (
        atom_state == ATOM_LOAD || atom_state == ATOM_STORE);

    always_comb begin
        dreq       = '0;
        dreq.valid = (mem_busy && (mem_started || !pipeline_flush) && !in_atomic) ||
            (atom_dreq_valid && (mem_started || !pipeline_flush));
        dreq.addr  = daddr;
        dreq.priv  = priv_mode;

        if (in_atomic && atom_state != ATOM_OFF) begin
            if (atom_state == ATOM_STORE) begin
                dreq.access = DBUS_STORE;
                dreq.size   = MSIZE4;
                dreq.strobe = strobe_t'(8'h0F << off);
                dreq.data   = i64'(atom_store_word) << (8 * off);
            end else if (atom_state == ATOM_LOAD) begin
                dreq.access = DBUS_LOAD;
                dreq.size   = MSIZE4;
                dreq.strobe = 8'b0;
            end
        end else if (mem_busy) begin
            dreq.access = (ex_mem.mem_op == MEM_STORE) ? DBUS_STORE : DBUS_LOAD;
            unique case (ex_mem.mem_op)
                MEM_LOAD: begin
                    dreq.strobe = 8'b0;
                    unique case (ex_mem.ls_funct3)
                        3'b000, 3'b100:   dreq.size = MSIZE1;
                        3'b001, 3'b101:   dreq.size = MSIZE2;
                        3'b010, 3'b110:   dreq.size = MSIZE4;
                        3'b011:           dreq.size = MSIZE8;
                        default:          dreq.size = MSIZE8;
                    endcase
                end
                MEM_STORE: begin
                    unique case (ex_mem.ls_funct3)
                        3'b000: begin
                            dreq.size   = MSIZE1;
                            dreq.strobe = strobe_t'(8'b1 << off);
                            dreq.data   = i64'(ex_mem.store_data[7:0]) << (8 * off);
                        end
                        3'b001: begin
                            dreq.size   = MSIZE2;
                            dreq.strobe = strobe_t'(8'b11 << off);
                            dreq.data   = i64'(ex_mem.store_data[15:0]) << (8 * off);
                        end
                        3'b010: begin
                            dreq.size   = MSIZE4;
                            dreq.strobe = strobe_t'(8'h0F << off);
                            dreq.data   = i64'(ex_mem.store_data[31:0]) << (8 * off);
                        end
                        3'b011: begin
                            dreq.size   = MSIZE8;
                            dreq.strobe = 8'hFF;
                            dreq.data   = ex_mem.store_data;
                        end
                        default: begin
                            dreq.size   = MSIZE8;
                            dreq.strobe = 8'hFF;
                            dreq.data   = ex_mem.store_data;
                        end
                    endcase
                end
                default: ;
            endcase
        end
    end

    function automatic i64 load_extend(input word_t raw, input addr_t a, input u3 f3);
        u3 sh;
        logic [7:0] b;
        logic [15:0] h;
        logic [31:0] w;
        sh = a[2:0];
        unique case (f3)
            3'b000: begin
                b = raw[8*sh +: 8];
                return {{56{b[7]}}, b};
            end
            3'b001: begin
                h = raw[8*sh +: 16];
                return {{48{h[15]}}, h};
            end
            3'b010: begin
                w = raw[8*sh +: 32];
                return {{32{w[31]}}, w};
            end
            3'b011:
                return raw;
            3'b100: begin
                b = raw[8*sh +: 8];
                return {56'b0, b};
            end
            3'b101: begin
                h = raw[8*sh +: 16];
                return {48'b0, h};
            end
            3'b110: begin
                w = raw[8*sh +: 32];
                return {32'b0, w};
            end
            default: return raw;
        endcase
    endfunction

    logic [63:0] atom_wb_result;
    always_comb begin
        atom_wb_result = 64'b0;
        if (in_atomic) begin
            if (ex_mem.amo_funct5 == AMO_SC) begin
                if (sc_start_fail)
                    atom_wb_result = 64'd1;
                else
                    atom_wb_result = 64'b0;
            end else if (atom_state == ATOM_LOAD && dresp.data_ok)
                atom_wb_result = sign_ext32(load_word32(dresp.data, ex_mem.alu_result));
            else
                atom_wb_result = sign_ext32(atom_old_word);
        end
    end

    always_comb begin
        mem_wb_next.valid        = ex_mem.valid;
        mem_wb_next.wd           = ex_mem.wd;
        mem_wb_next.reg_write    = ex_mem.reg_write;
        mem_wb_next.decoder_ctrl = ex_mem.decoder_ctrl;
        mem_wb_next.mem_addr     = ex_mem.alu_result;
        mem_wb_next.mem_op       = ex_mem.mem_op;
        mem_wb_next.is_csr       = ex_mem.is_csr;
        mem_wb_next.csr_addr     = ex_mem.csr_addr;
        mem_wb_next.csr_funct3   = ex_mem.csr_funct3;
        mem_wb_next.csr_rsdata   = ex_mem.csr_rsdata;
        mem_wb_next.system_op    = ex_mem.system_op;
        if (in_atomic && (atom_state != ATOM_OFF || sc_start_fail))
            mem_wb_next.result = atom_wb_result;
        else if (ex_mem.mem_op == MEM_LOAD)
            mem_wb_next.result = load_extend(dresp.data, ex_mem.alu_result, ex_mem.ls_funct3);
        else if (ex_mem.is_csr)
            mem_wb_next.result = csr_read_rdata;
        else
            mem_wb_next.result = ex_mem.alu_result;
    end

    assign mem_inst_done =
        in_atomic ? (
            sc_start_fail ||
            (atom_state == ATOM_LOAD && dresp.data_ok && ex_mem.amo_funct5 == AMO_LR) ||
            (atom_state == ATOM_STORE && dresp.data_ok)
        ) : (mem_busy && dresp.data_ok);

    assign wb_fire = (mem_inst_done
        || (!hazard_stall && ex_mem.mem_op == MEM_NONE)) && mem_wb_next.valid;
    assign wb_next = mem_wb_next;

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            mem_wb <= '0;
        else if (pipeline_flush)
            mem_wb <= '0;
        else if (mem_inst_done)
            mem_wb <= mem_wb_next;
        else if (!hazard_stall && ex_mem.mem_op == MEM_NONE)
            mem_wb <= mem_wb_next;
    end

endmodule

`endif
