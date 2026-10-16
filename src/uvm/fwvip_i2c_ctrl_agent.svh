// Controller agent (design.md §6): sequences of fwvip_i2c_xact items,
// driven through the kit's controller API. Fetches "cfg" (a
// fwvip_i2c_ctrl_config) from the config DB. `ap` publishes every completed
// transaction, result fields filled in.
class fwvip_i2c_ctrl_agent extends uvm_agent;
    `uvm_component_utils(fwvip_i2c_ctrl_agent)

    fwvip_i2c_ctrl_config                m_cfg;
    fwvip_i2c_ctrl_sequencer             m_seqr;
    fwvip_i2c_ctrl_driver                m_driver;
    uvm_analysis_port #(fwvip_i2c_xact)  ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(fwvip_i2c_ctrl_config)::get(this, "", "cfg", m_cfg))
            `uvm_fatal(get_type_name(), "no fwvip_i2c_ctrl_config \"cfg\" in the config DB")
        m_seqr   = fwvip_i2c_ctrl_sequencer::type_id::create("m_seqr", this);
        m_driver = fwvip_i2c_ctrl_driver::type_id::create("m_driver", this);
        m_driver.m_cfg = m_cfg;
        ap = new("ap", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        m_driver.seq_item_port.connect(m_seqr.seq_item_export);
        m_driver.ap.connect(ap);
    endfunction
endclass
