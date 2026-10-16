// The back-to-back cases (one sequence per case, chosen by +SEQ) and tests.
`include "uvm_macros.svh"

package fwvip_i2c_b2b_tests_pkg;
    import uvm_pkg::*;
    import fw_proto_i2c_pkg::*;
    import fwvip_i2c_pkg::*;
    import fwvip_i2c_b2b_env_pkg::*;

    `include "fwvip_i2c_b2b_seq_base.svh"
    `include "fwvip_i2c_smoke_seq.svh"
    `include "fwvip_i2c_addr_nack_seq.svh"
    `include "fwvip_i2c_data_nack_seq.svh"
    `include "fwvip_i2c_stretch_seq.svh"
    `include "fwvip_i2c_rand_traffic_seq.svh"

    `include "fwvip_i2c_b2b_test.svh"
    `include "fwvip_i2c_mon_teeth_test.svh"
endpackage
