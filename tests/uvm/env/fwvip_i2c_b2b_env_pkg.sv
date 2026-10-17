// The back-to-back bench's UVM side: the env (the VIP's three agents on one
// bus, the memory responder, the scoreboard).
`include "uvm_macros.svh"

package fwvip_i2c_b2b_env_pkg;
    import uvm_pkg::*;
    import fw_proto_i2c_pkg::*;
    import fwvip_core_pkg::*;
    import fwvip_core_uvm_pkg::*;
    import fwvip_i2c_pkg::*;

    // The target's addresses on the bench's bus: it answers both.
    localparam bit [6:0] TGT_ADDR   = 7'h50;
    localparam bit [9:0] TGT_ADDR10 = 10'h2a5;

    `uvm_analysis_imp_decl(_ctrl)
    `uvm_analysis_imp_decl(_mon)

    `include "fwvip_i2c_b2b_sb.svh"
    `include "fwvip_i2c_b2b_env.svh"
endpackage
