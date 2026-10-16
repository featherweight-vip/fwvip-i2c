// fwvip_i2c_pkg -- the I2C VIP's UVM layer (design.md §6). Agents bind to
// the kit's transactors through their configs:
//   fwvip_i2c_ctrl_agent  controller: fwvip_i2c_xact items -> i2c_controller_if
//   fwvip_i2c_tgt_agent   target: a responder sequence behind the kit's
//                         target bridge (its config is the i2c_target_if)
//   fwvip_i2c_mon_agent   passive: i2c_monitor_if events -> fwvip_i2c_xact
// Thin package: imports, package-scope types, then one class per .svh in
// dependency order.
`include "uvm_macros.svh"
`include "fwvip_i2c_macros.svh"

package fwvip_i2c_pkg;
    import uvm_pkg::*;
    import fw_proto_i2c_pkg::*;
    import fwvip_core_pkg::*;
    import fwvip_core_uvm_pkg::*;
    import fwvip_i2c_xtor_pkg::*;

    // How a transaction ended (fwvip_i2c_xact::status).
    typedef enum {
        FWVIP_I2C_OK,
        FWVIP_I2C_ADDR_NACK,
        FWVIP_I2C_DATA_NACK,
        FWVIP_I2C_ARB_LOST
    } fwvip_i2c_status_e;

    `include "fwvip_i2c_segment.svh"
    `include "fwvip_i2c_xact.svh"

    // ---- controller
    typedef uvm_sequencer #(fwvip_i2c_xact) fwvip_i2c_ctrl_sequencer;
    `include "fwvip_i2c_ctrl_config.svh"
    `include "fwvip_i2c_ctrl_driver.svh"
    `include "fwvip_i2c_ctrl_agent.svh"
    `include "fwvip_i2c_ctrl_seq_base.svh"
    `include "fwvip_i2c_write_seq.svh"
    `include "fwvip_i2c_read_seq.svh"
    `include "fwvip_i2c_rand_seq.svh"

    // ---- target
    `include "fwvip_i2c_tgt_item.svh"
    typedef uvm_sequencer #(fwvip_i2c_tgt_item) fwvip_i2c_tgt_sequencer;
    `include "fwvip_i2c_tgt_driver.svh"
    `include "fwvip_i2c_tgt_config.svh"
    `include "fwvip_i2c_tgt_agent.svh"
    `include "fwvip_i2c_tgt_seq.svh"
    `include "fwvip_i2c_mem_responder_seq.svh"

    // ---- monitor
    `include "fwvip_i2c_mon_config.svh"
    `include "fwvip_i2c_mon_agent.svh"
endpackage
