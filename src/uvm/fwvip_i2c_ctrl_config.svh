// The controller agent's seam: the kit's per-byte controller API
// (i2c_controller_if). The agent depends only on this abstract config; the
// bench sets the vif-aware specialization in the config DB under "cfg",
// usually with `fwvip_i2c_ctrl_register.
class fwvip_i2c_ctrl_config extends uvm_object implements i2c_controller_if;
    `uvm_object_utils(fwvip_i2c_ctrl_config)

    function new(string name = "fwvip_i2c_ctrl_config");
        super.new(name);
    endfunction

    virtual task start(input bit [9:0] addr, input bit addr_10b, input bit read,
                       input bit repeated, output bit ack, output bit arb_lost);
        `uvm_fatal("FWVIP_I2C", "fwvip_i2c_ctrl_config: no transactor bound (set a fwvip_i2c_ctrl_config_p)")
    endtask

    virtual task tx_byte(input bit [7:0] data, output bit ack, output bit arb_lost);
        `uvm_fatal("FWVIP_I2C", "fwvip_i2c_ctrl_config: no transactor bound (set a fwvip_i2c_ctrl_config_p)")
    endtask

    virtual task rx_byte(input bit ack, output bit [7:0] data, output bit arb_lost);
        `uvm_fatal("FWVIP_I2C", "fwvip_i2c_ctrl_config: no transactor bound (set a fwvip_i2c_ctrl_config_p)")
    endtask

    virtual task stop();
        `uvm_fatal("FWVIP_I2C", "fwvip_i2c_ctrl_config: no transactor bound (set a fwvip_i2c_ctrl_config_p)")
    endtask
endclass

// vif-aware specialization: holds the kit controller transactor's `u_if`
// and forwards the API to a kit i2c_controller_xtor_bridge, built on first
// use so it works whatever the call order is relative to phasing.
class fwvip_i2c_ctrl_config_p #(type vif_t = virtual i2c_controller_xtor_if)
        extends fwvip_i2c_ctrl_config;
    typedef fwvip_i2c_ctrl_config_p #(vif_t) this_t;

    vif_t                       vif;
    i2c_controller_xtor_bridge  m_bridge;

    function new(string name = "fwvip_i2c_ctrl_config_p");
        super.new(name);
    endfunction

    static function this_t set(uvm_component ctxt, string inst, string field, vif_t vif);
        this_t cfg = new();
        cfg.vif = vif;
        uvm_config_db #(fwvip_i2c_ctrl_config)::set(ctxt, inst, field, cfg);
        return cfg;
    endfunction

    protected function void ensure();
        if (m_bridge == null) m_bridge = new(vif);
    endfunction

    virtual task start(input bit [9:0] addr, input bit addr_10b, input bit read,
                       input bit repeated, output bit ack, output bit arb_lost);
        ensure();
        m_bridge.start(addr, addr_10b, read, repeated, ack, arb_lost);
    endtask

    virtual task tx_byte(input bit [7:0] data, output bit ack, output bit arb_lost);
        ensure();
        m_bridge.tx_byte(data, ack, arb_lost);
    endtask

    virtual task rx_byte(input bit ack, output bit [7:0] data, output bit arb_lost);
        ensure();
        m_bridge.rx_byte(ack, data, arb_lost);
    endtask

    virtual task stop();
        ensure();
        m_bridge.stop();
    endtask
endclass
