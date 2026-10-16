// The monitor agent has teeth: traffic first (which must be clean), then
// event orders no legal bus produces -- a byte and a STOP with no START, a
// data byte after a NACK -- fed to the agent as if they came off the bus.
// The agent must flag each one as a UVM_ERROR; this test turns those
// errors into infos and checks that it saw them.
class fwvip_i2c_mon_teeth_test extends fwvip_i2c_b2b_test;
    `uvm_component_utils(fwvip_i2c_mon_teeth_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    protected function void expect_flag(string what, int unsigned n_before);
        if (m_env.m_mon.n_errors == n_before)
            `uvm_error(get_type_name(), {"the monitor agent did not flag ", what})
        else
            `uvm_info(get_type_name(), $sformatf("flagged: %s", m_env.m_mon.last_error), UVM_LOW)
    endfunction

    virtual task post_case();
        fwvip_i2c_mon_config cfg = m_env.m_mon.m_cfg;
        uvm_report_server    srv = uvm_report_server::get_server();
        int unsigned         n0, n_id0;
        if (m_env.m_mon.n_errors != 0)
            `uvm_error(get_type_name(), "traffic before the bad events was not clean")
        m_env.m_mon.set_report_severity_id_override(UVM_ERROR, "I2C_MON", UVM_INFO);
        n_id0 = srv.get_id_count("I2C_MON");

        n0 = m_env.m_mon.n_errors;
        cfg.observe_byte(1'b0, 8'h12, 1'b1);
        expect_flag("a byte outside a transaction", n0);

        n0 = m_env.m_mon.n_errors;
        cfg.observe_stop();
        expect_flag("a STOP outside a transaction", n0);

        // START, address ACKed, a write byte NACKed, then another byte.
        // The transaction never reaches a monitor STOP, so nothing reaches
        // the scoreboard.
        n0 = m_env.m_mon.n_errors;
        cfg.observe_start(1'b0);
        cfg.observe_byte(1'b1, {TGT_ADDR, 1'b0}, 1'b1);
        cfg.observe_byte(1'b0, 8'h34, 1'b0);
        cfg.observe_byte(1'b0, 8'h56, 1'b1);
        expect_flag("a data byte after a NACK", n0);

        if (srv.get_id_count("I2C_MON") == n_id0)
            `uvm_error(get_type_name(), "the monitor agent did not report the violations")
        m_env.m_mon.clear();
    endtask
endclass
