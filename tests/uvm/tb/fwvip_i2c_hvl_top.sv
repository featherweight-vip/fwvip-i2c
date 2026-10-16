// HVL top: binds each kit transactor to its VIP agent with the register
// macros, publishes fwvip-core's clock and reset providers, and runs the
// test.
`include "uvm_macros.svh"
`include "fwvip_i2c_macros.svh"

module fwvip_i2c_hvl_top;
    import uvm_pkg::*;
    import fwvip_core_uvm_pkg::*;
    import fwvip_i2c_pkg::*;
    import fwvip_i2c_b2b_env_pkg::*;
    import fwvip_i2c_b2b_tests_pkg::*;

    fwvip_i2c_hdl_top hdl();

    initial begin
        `fwvip_i2c_ctrl_register(hdl.u_ctl.u_if, "uvm_test_top.m_env.m_ctrl*")
        `fwvip_i2c_tgt_register(hdl.u_tgt.u_if, "uvm_test_top.m_env.m_tgt*", TGT_ADDR)
        `fwvip_i2c_mon_register(hdl.u_mon.u_if, "uvm_test_top.m_env.m_mon*")
        fwvip_clock_config_p #(virtual fwvip_clock_xtor_if)::set(
            null, "uvm_test_top.m_env*", "clock", hdl.u_clk_if);
        fwvip_reset_config_p #(virtual fwvip_reset_xtor_if #(1))::set(
            null, "uvm_test_top.m_env*", "reset", hdl.u_rst_if);
        run_test();
    end
endmodule
