`ifndef __MEM_SV
`define __MEM_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module Mem import common::*; (
    input logic clk,
    input logic reset,
    input logic hazard_stall,
    input EX_MEM_t ex_mem,
    output MEM_WB_t mem_wb,
    output dbus_req_t dreq,
    input dbus_resp_t dresp,
    output logic mem_busy,
    output logic wb_fire,
    output MEM_WB_t wb_next
);

    MEM_WB_t mem_wb_next;

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            mem_busy <= 1'b0;
        else if (mem_busy) begin
            if (dresp.data_ok)
                mem_busy <= 1'b0;
        end else if (!mem_busy && ex_mem.valid && ex_mem.mem_op != MEM_NONE)
            mem_busy <= 1'b1;
    end

    addr_t daddr;
    u3     off;
    assign daddr = ex_mem.alu_result;
    assign off   = daddr[2:0];

    always_comb begin
        dreq = '0;
        dreq.valid = mem_busy;
        dreq.addr  = daddr;
        if (mem_busy) begin
            unique case (ex_mem.mem_op)
                MEM_LOAD: begin
                    dreq.strobe = 8'b0;
                    unique case (ex_mem.ls_funct3)
                        3'b000, 3'b100: dreq.size = MSIZE1;
                        3'b001, 3'b101: dreq.size = MSIZE2;
                        3'b010, 3'b110: dreq.size = MSIZE4;
                        3'b011:           dreq.size = MSIZE8;
                        default:          dreq.size = MSIZE8;
                    endcase
                end
                MEM_STORE: begin
                    unique case (ex_mem.ls_funct3)
                        3'b000: begin
                            dreq.size = MSIZE1;
                            dreq.strobe = strobe_t'(8'b1 << off);
                            dreq.data = i64'(ex_mem.store_data[7:0]) << (8 * off);
                        end
                        3'b001: begin
                            dreq.size = MSIZE2;
                            dreq.strobe = strobe_t'(8'b11 << off);
                            dreq.data = i64'(ex_mem.store_data[15:0]) << (8 * off);
                        end
                        3'b010: begin
                            dreq.size = MSIZE4;
                            dreq.strobe = strobe_t'(8'h0F << off);
                            dreq.data = i64'(ex_mem.store_data[31:0]) << (8 * off);
                        end
                        3'b011: begin
                            dreq.size = MSIZE8;
                            dreq.strobe = 8'hFF;
                            dreq.data = ex_mem.store_data;
                        end
                        default: begin
                            dreq.size = MSIZE8;
                            dreq.strobe = 8'hFF;
                            dreq.data = ex_mem.store_data;
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

    always_comb begin
        mem_wb_next.valid        = ex_mem.valid;
        mem_wb_next.wd           = ex_mem.wd;
        mem_wb_next.reg_write    = ex_mem.reg_write;
        mem_wb_next.decoder_ctrl = ex_mem.decoder_ctrl;
        if (ex_mem.mem_op == MEM_LOAD)
            mem_wb_next.result = load_extend(dresp.data, ex_mem.alu_result, ex_mem.ls_funct3);
        else
            mem_wb_next.result = ex_mem.alu_result;
    end

    assign wb_fire = ((mem_busy && dresp.data_ok)
        || (!hazard_stall && ex_mem.mem_op == MEM_NONE)) && mem_wb_next.valid;
    assign wb_next = mem_wb_next;

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            mem_wb <= '0;
        else if (mem_busy && dresp.data_ok)
            mem_wb <= mem_wb_next;
        else if (!hazard_stall && ex_mem.mem_op == MEM_NONE)
            mem_wb <= mem_wb_next;
    end

endmodule

`endif
