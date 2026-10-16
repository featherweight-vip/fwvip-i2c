// Target agent (design.md §6): its responder sequence answers every bus
// event addressed to the config's address. Fetches "cfg" (a
// fwvip_i2c_tgt_config) and, optionally, "clock" (fwvip-core's
// fwvip_clock_config, which responders use to count clock-stretch latency
// in cycles).
class fwvip_i2c_tgt_agent extends uvm_agent;
    `uvm_component_utils(fwvip_i2c_tgt_agent)

    fwvip_i2c_tgt_config     m_cfg;
    fwvip_clock_if           m_clock;     // null: no clock provider
    fwvip_i2c_tgt_sequencer  m_seqr;
    fwvip_i2c_tgt_driver     m_driver;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        fwvip_clock_config clk;
        super.build_phase(phase);
        if (!uvm_config_db #(fwvip_i2c_tgt_config)::get(this, "", "cfg", m_cfg))
            `uvm_fatal(get_type_name(), "no fwvip_i2c_tgt_config \"cfg\" in the config DB")
        if (uvm_config_db #(fwvip_clock_config)::get(this, "", "clock", clk))
            m_clock = clk;
        m_seqr   = fwvip_i2c_tgt_sequencer::type_id::create("m_seqr", this);
        m_driver = fwvip_i2c_tgt_driver::type_id::create("m_driver", this);
        m_driver.m_cfg = m_cfg;
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        m_driver.seq_item_port.connect(m_seqr.seq_item_export);
    endfunction
endclass
