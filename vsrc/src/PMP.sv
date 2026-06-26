`ifndef __PMP_SV
`define __PMP_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

package pmp_pkg;
import common::*;

function automatic u64 pmp_fault_cause(input dbus_access_t access);
    unique case (access)
        DBUS_FETCH: return 64'd1;
        DBUS_STORE: return 64'd7;
        default:    return 64'd5;
    endcase
endfunction

function automatic logic pmp_perm_ok(
    input logic [7:0] cfg,
    input dbus_access_t access
);
    unique case (access)
        DBUS_FETCH: return cfg[2];
        DBUS_STORE: return cfg[1];
        default:    return cfg[0];
    endcase
endfunction

function automatic logic pmp_napot_match(input u64 paddr, input u64 cfg_addr);
    integer i;
    integer m;
    u64 mask;
    u64 base;
    u64 size;

    m = 0;
    for (i = 0; i < 54; i = i + 1) begin
        if (cfg_addr[i])
            m = m + 1;
        else
            break;
    end
    if (m == 0)
        return 1'b0;

    mask = (64'd1 << m) - 64'd1;
    base = (cfg_addr & ~mask) << 2;
    size = 64'd1 << (m + 3);
    return (paddr >= base) && (paddr < base + size);
endfunction

function automatic logic pmp_na4_match(input u64 paddr, input u64 cfg_addr);
    return paddr[63:2] == cfg_addr[63:2];
endfunction

function automatic logic pmp_entry_match(
    input u64 paddr,
    input u64 cfg_addr,
    input logic [1:0] a
);
    unique case (a)
        2'd2: return pmp_na4_match(paddr, cfg_addr);
        2'd3: return pmp_napot_match(paddr, cfg_addr);
        default: return 1'b0;
    endcase
endfunction

function automatic logic pmp_enabled(input u64 pmpcfg0);
    return pmpcfg0[4:3] != 2'd0;
endfunction

function automatic logic pmp_check(
    input u64           paddr,
    input dbus_access_t access,
    input priv_mode_t   priv,
    input u64           mstatus,
    input u64           pmpaddr0,
    input u64           pmpcfg0
);
    logic [7:0]       cfg;
    logic [1:0]       a;
    priv_mode_t       eff_priv;
    logic             matched;

    cfg = pmpcfg0[7:0];
    a   = cfg[4:3];

    if (!pmp_enabled(pmpcfg0))
        return 1'b1;

    if (priv == PRIV_M && !(mstatus[17] && access != DBUS_FETCH))
        return 1'b1;

    eff_priv = (priv == PRIV_M) ? priv_mode_t'(mstatus[12:11]) : priv;

    matched = 1'b0;
    if (a != 2'd0) begin
        if (pmp_entry_match(paddr, pmpaddr0, a)) begin
            matched = 1'b1;
            return pmp_perm_ok(cfg, access);
        end
    end

    if (!matched && eff_priv != PRIV_M)
        return 1'b0;
    return 1'b1;
endfunction

endpackage

`endif
