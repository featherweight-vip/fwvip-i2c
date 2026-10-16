typedef class fwvip_i2c_tgt_config;

// The target agent's driver. It never polls anything: the kit's target
// bridge calls the config (i2c_target_if) once per bus event, the config
// asks this driver for the responder, and the driver takes it from the
// sequencer. Until a responder sequence runs on the agent's sequencer, an
// addressed target holds SCL low (clock stretching) and the bus waits.
class fwvip_i2c_tgt_driver extends uvm_driver #(fwvip_i2c_tgt_item);
    `uvm_component_utils(fwvip_i2c_tgt_driver)

    fwvip_i2c_tgt_config  m_cfg;
    int unsigned          n_served;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        m_cfg.start(this);
    endtask

    // The responder for one bus event.
    task get_handler(output i2c_target_if h);
        fwvip_i2c_tgt_item it;
        seq_item_port.get_next_item(it);
        h = it.handler;
        seq_item_port.item_done();
        if (h == null) `uvm_fatal(get_type_name(), "target item with no handler")
        n_served++;
    endtask
endclass
