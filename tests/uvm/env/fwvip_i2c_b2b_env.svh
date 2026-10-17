// The back-to-back UVM env: the VIP's controller, target and monitor agents
// on one bus, a scoreboard over the controller's completions and the
// monitor's reconstruction, and the memory responder, which runs on the
// target agent from the start of the run (start_responder()). The target
// answers TGT_ADDR and the 10-bit TGT_ADDR10.
class fwvip_i2c_b2b_env extends uvm_env;
    `uvm_component_utils(fwvip_i2c_b2b_env)

    fwvip_i2c_ctrl_agent         m_ctrl;
    fwvip_i2c_tgt_agent          m_tgt;
    fwvip_i2c_mon_agent          m_mon;
    fwvip_i2c_b2b_sb             m_sb;
    fwvip_i2c_mem_responder_seq  m_resp;
    fwvip_reset_config           m_reset;
    fwvip_clock_config           m_clock;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_ctrl = fwvip_i2c_ctrl_agent::type_id::create("m_ctrl", this);
        m_tgt  = fwvip_i2c_tgt_agent::type_id::create("m_tgt", this);
        m_mon  = fwvip_i2c_mon_agent::type_id::create("m_mon", this);
        m_sb   = fwvip_i2c_b2b_sb::type_id::create("m_sb", this);
        if (!uvm_config_db #(fwvip_reset_config)::get(this, "", "reset", m_reset))
            `uvm_fatal(get_type_name(), "no reset provider (fwvip_reset_config) in the config DB")
        if (!uvm_config_db #(fwvip_clock_config)::get(this, "", "clock", m_clock))
            `uvm_fatal(get_type_name(), "no clock provider (fwvip_clock_config) in the config DB")
        m_resp = fwvip_i2c_mem_responder_seq::type_id::create("m_resp");
        begin
            fwvip_i2c_tgt_config tc;
            if (!uvm_config_db #(fwvip_i2c_tgt_config)::get(this, "m_tgt", "cfg", tc))
                `uvm_fatal(get_type_name(), "no fwvip_i2c_tgt_config \"cfg\" for m_tgt")
            tc.addr10_en = 1'b1;
            tc.addr10    = TGT_ADDR10;
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        m_ctrl.ap.connect(m_sb.ctrl_export);
        m_mon.ap.connect(m_sb.mon_export);
    endfunction

    task start_responder();
        fork
            m_resp.start(m_tgt.m_seqr);
        join_none
    endtask

    task wait_ready();
        m_reset.wait_reset();
    endtask
endclass
