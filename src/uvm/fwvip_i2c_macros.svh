// Register macros: bind a kit transactor's `u_if` to a VIP agent through
// the config DB, from an HVL top. `inst` is the agent's path glob.
//
//   `fwvip_i2c_ctrl_register(hdl.u_ctl.u_if, "uvm_test_top.m_env.m_ctrl*")
//   `fwvip_i2c_tgt_register(hdl.u_tgt.u_if, "uvm_test_top.m_env.m_tgt*", 7'h50)
//   `fwvip_i2c_mon_register(hdl.u_mon.u_if, "uvm_test_top.m_env.m_mon*")

`define fwvip_i2c_ctrl_register(vif, inst) \
    void'(fwvip_i2c_pkg::fwvip_i2c_ctrl_config_p #(virtual i2c_controller_xtor_if)::set(null, inst, "cfg", vif));

`define fwvip_i2c_tgt_register(vif, inst, addr) \
    void'(fwvip_i2c_pkg::fwvip_i2c_tgt_config_p #(virtual i2c_target_xtor_if)::set(null, inst, "cfg", vif, addr));

`define fwvip_i2c_mon_register(vif, inst) \
    void'(fwvip_i2c_pkg::fwvip_i2c_mon_config_p #(virtual i2c_monitor_xtor_if)::set(null, inst, "cfg", vif));
