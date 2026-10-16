typedef class fwvip_i2c_mon_agent;

// The monitor agent's seam: an i2c_monitor_if subscriber that forwards
// every bus event the kit's monitor reports to the agent. The vif-aware
// specialization runs the kit's i2c_monitor_xtor_bridge with this config
// as its subscriber.
class fwvip_i2c_mon_config extends uvm_object implements i2c_monitor_if;
    `uvm_object_utils(fwvip_i2c_mon_config)

    protected fwvip_i2c_mon_agent m_agent;

    function new(string name = "fwvip_i2c_mon_config");
        super.new(name);
    endfunction

    function void attach(fwvip_i2c_mon_agent agent);
        m_agent = agent;
    endfunction

    // Start delivering events (the specialization starts the kit bridge).
    virtual task start();
    endtask

    virtual function void observe_start(input bit repeated);
        if (m_agent != null) m_agent.observe_start(repeated);
    endfunction

    virtual function void observe_stop();
        if (m_agent != null) m_agent.observe_stop();
    endfunction

    virtual function void observe_byte(input bit addr_phase, input bit [7:0] data, input bit ack);
        if (m_agent != null) m_agent.observe_byte(addr_phase, data, ack);
    endfunction

    virtual function void observe_arb_lost();
        if (m_agent != null) m_agent.observe_arb_lost();
    endfunction
endclass

class fwvip_i2c_mon_config_p #(type vif_t = virtual i2c_monitor_xtor_if)
        extends fwvip_i2c_mon_config;
    typedef fwvip_i2c_mon_config_p #(vif_t) this_t;

    vif_t                    vif;
    i2c_monitor_xtor_bridge  m_bridge;

    function new(string name = "fwvip_i2c_mon_config_p");
        super.new(name);
    endfunction

    static function this_t set(uvm_component ctxt, string inst, string field, vif_t vif);
        this_t cfg = new();
        cfg.vif = vif;
        uvm_config_db #(fwvip_i2c_mon_config)::set(ctxt, inst, field, cfg);
        return cfg;
    endfunction

    virtual task start();
        m_bridge = new(vif, this);
        m_bridge.start_bridge();
    endtask
endclass
