`ifndef __MMU_SV
`define __MMU_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "src/PMP.sv"
`endif

module MMU
    import common::*;
    import pmp_pkg::*; (
    input  logic       clk,
    input  logic       reset,
    input  logic       flush,
    input  priv_mode_t priv_mode,
    input  u64         satp,
    input  u64         mstatus,
    input  u64         pmpaddr0,
    input  u64         pmpcfg0,
    input  dbus_req_t  vreq,
    output dbus_resp_t vresp,
    output dbus_req_t  preq,
    input  dbus_resp_t presp,
    output logic       fault_valid,
    output u64         fault_vaddr,
    output u64         fault_cause
);
    typedef enum logic [2:0] {
        S_IDLE,
        S_WALK_REQ,
        S_WALK_WAIT,
        S_ACCESS,
        S_ACCESS_WAIT,
        S_FAULT
    } state_t;

    state_t state;
    dbus_req_t saved_req;
    dbus_req_t preq_next;
    dbus_req_t preq_q;
    logic      preq_hold;
    u64 base_addr;
    u64 pte_addr;
    u64 pte;
    logic [1:0] level;
    logic [8:0] vpn [0:2];
    u64 fault_cause_r;

    logic translate_en;
    logic pte_valid;
    logic pte_leaf;
    logic perm_ok;
    logic align_ok;
    u64 translated_addr;
    logic passthrough_pmp_ok;
    logic access_pmp_ok;

    assign translate_en = (priv_mode != PRIV_M) && (satp[63:60] == 4'd8);

    always_comb begin
        vpn[0] = saved_req.addr[20:12];
        vpn[1] = saved_req.addr[29:21];
        vpn[2] = saved_req.addr[38:30];
    end

    function automatic u64 page_fault_cause(input dbus_access_t access);
        unique case (access)
            DBUS_FETCH: return 64'd12;
            DBUS_STORE: return 64'd15;
            default:    return 64'd13;
        endcase
    endfunction

    function automatic logic leaf_perm_ok(
        input u64 entry,
        input dbus_access_t access,
        input priv_mode_t mode,
        input u64 mstatus
    );
        logic mxr;
        logic sum;
        logic ok;
        mxr = mstatus[19];
        sum = mstatus[18];
        unique case (access)
            DBUS_FETCH: ok = entry[3];
            DBUS_STORE: ok = entry[2];
            default:    ok = entry[1] || (mxr && entry[3]);
        endcase
        if (mode == PRIV_U)
            ok = ok && entry[4];
        else if (mode == PRIV_S && entry[4] && !sum)
            ok = 1'b0;
        return ok;
    endfunction

    function automatic logic leaf_align_ok(input u64 entry, input logic [1:0] lvl);
        if (lvl == 2'd2)
            return entry[27:10] == 18'b0;
        if (lvl == 2'd1)
            return entry[18:10] == 9'b0;
        return 1'b1;
    endfunction

    always_comb begin
        pte_valid = pte[0] && !(pte[2] && !pte[1]);
        pte_leaf  = pte[1] || pte[3];
        unique case (saved_req.access)
            DBUS_FETCH: perm_ok = pte[3];
            DBUS_STORE: perm_ok = pte[2];
            default:    perm_ok = pte[1] || (mstatus[19] && pte[3]);
        endcase
        if (saved_req.priv == PRIV_U)
            perm_ok = perm_ok && pte[4];
        else if (saved_req.priv == PRIV_S && pte[4] && !mstatus[18])
            perm_ok = 1'b0;
        align_ok = 1'b1;
        if (pte_leaf && level == 2'd2)
            align_ok = (pte[27:10] == 18'b0);
        else if (pte_leaf && level == 2'd1)
            align_ok = (pte[18:10] == 9'b0);

        translated_addr = saved_req.addr;
        unique case (level)
            2'd2: translated_addr = {8'b0, pte[53:28], saved_req.addr[29:0]};
            2'd1: translated_addr = {8'b0, pte[53:19], saved_req.addr[20:0]};
            default: translated_addr = {8'b0, pte[53:10], saved_req.addr[11:0]};
        endcase

        passthrough_pmp_ok = !vreq.valid || pmp_check(
            vreq.addr, vreq.access, vreq.priv, mstatus, pmpaddr0, pmpcfg0);
        access_pmp_ok = pmp_check(
            translated_addr, saved_req.access, saved_req.priv,
            mstatus, pmpaddr0, pmpcfg0);
    end

    u64 satp_prev;
    logic mmu_flush;

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            satp_prev <= '0;
        else
            satp_prev <= satp;
    end

    assign mmu_flush = flush || (satp != satp_prev);

    assign preq = preq_hold ? preq_q : preq_next;

    always_comb begin
        preq_next = '0;
        vresp = '0;
        fault_valid = 1'b0;
        fault_vaddr = saved_req.addr;
        fault_cause = fault_cause_r;
        pte_addr = base_addr + ({55'b0, vpn[level]} << 3);

        unique case (state)
            S_IDLE: begin
                if (!translate_en && passthrough_pmp_ok) begin
                    preq_next = vreq;
                    vresp = presp;
                end
            end
            S_WALK_REQ,
            S_WALK_WAIT: begin
                preq_next.valid  = 1'b1;
                preq_next.addr   = pte_addr;
                preq_next.size   = MSIZE8;
                preq_next.strobe = 8'b0;
                preq_next.data   = 64'b0;
                preq_next.access = DBUS_LOAD;
                preq_next.priv   = PRIV_M;
            end
            S_ACCESS: begin
                if (access_pmp_ok) begin
                    preq_next = saved_req;
                    preq_next.addr = translated_addr;
                end
            end
            S_ACCESS_WAIT: begin
                vresp = presp;
            end
            S_FAULT: begin
                vresp.data_ok = 1'b1;
                vresp.addr_ok = 1'b1;
                fault_valid = 1'b1;
            end
            default: ;
        endcase
    end

    logic preq_drop;
    assign preq_drop = state == S_FAULT
        || (state == S_ACCESS && (!pte_valid || !perm_ok || !align_ok || !access_pmp_ok));

    always_ff @(posedge clk or posedge reset) begin
        if (reset || mmu_flush) begin
            preq_hold <= 1'b0;
            preq_q <= '0;
        end else if (preq_hold) begin
            if (presp.data_ok || preq_drop) begin
                preq_hold <= 1'b0;
                preq_q <= '0;
            end
        end else if (preq_next.valid && state != S_FAULT) begin
            preq_hold <= 1'b1;
            preq_q <= preq_next;
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset || mmu_flush) begin
            state <= S_IDLE;
            saved_req <= '0;
            base_addr <= 64'b0;
            pte <= 64'b0;
            level <= 2'd0;
            fault_cause_r <= 64'b0;
        end else begin
            unique case (state)
                S_IDLE: begin
                    if (translate_en && vreq.valid) begin
                        saved_req <= vreq;
                        saved_req.priv <= priv_mode;
                        base_addr <= {8'b0, satp[43:0], 12'b0};
                        level <= 2'd2;
                        fault_cause_r <= page_fault_cause(vreq.access);
                        state <= S_WALK_REQ;
                    end else if (!translate_en && vreq.valid && !passthrough_pmp_ok) begin
                        saved_req <= vreq;
                        fault_cause_r <= pmp_fault_cause(vreq.access);
                        state <= S_FAULT;
                    end
                end
                S_WALK_REQ: begin
                    state <= S_WALK_WAIT;
                end
                S_WALK_WAIT: begin
                    if (presp.data_ok) begin
                        pte <= presp.data;
                        if (!presp.data[0] || (presp.data[2] && !presp.data[1])) begin
                            state <= S_FAULT;
                        end else if (presp.data[1] || presp.data[3]) begin
                            if (leaf_perm_ok(presp.data, saved_req.access, saved_req.priv, mstatus)
                                    && leaf_align_ok(presp.data, level))
                                state <= S_ACCESS;
                            else
                                state <= S_FAULT;
                        end else if (level == 2'd0) begin
                            state <= S_FAULT;
                        end else begin
                            base_addr <= {8'b0, presp.data[53:10], 12'b0};
                            level <= level - 2'd1;
                            state <= S_WALK_REQ;
                        end
                    end
                end
                S_ACCESS: begin
                    if (!pte_valid || !perm_ok || !align_ok || !access_pmp_ok)
                        fault_cause_r <= (!pte_valid || !perm_ok || !align_ok) ?
                            page_fault_cause(saved_req.access) :
                            pmp_fault_cause(saved_req.access);
                    if (!pte_valid || !perm_ok || !align_ok || !access_pmp_ok)
                        state <= S_FAULT;
                    else
                        state <= S_ACCESS_WAIT;
                end
                S_ACCESS_WAIT: begin
                    if (presp.data_ok)
                        state <= S_IDLE;
                end
                S_FAULT: begin
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule

`endif
