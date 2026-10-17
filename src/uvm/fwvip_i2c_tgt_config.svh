// The target agent's seam: it IS the i2c_target_if behind the kit's target
// bridge. The kit's target core reports every address phase; this config
// answers the ones that match `addr` under `addr_mask` by handing the event
// to the agent's responder sequence, and NACKs the rest itself. Data bytes
// (which follow only an ACKed address) always go to the responder.
//
// With `addr10_en` the target also answers the 10-bit address `addr10`
// under `addr10_mask` (UM10204 §3.1.11). This config ACKs a header's first
// byte (addressed_10b_hi()) when A9:A8 match; the full address then goes
// to the responder's addressed() like a 7-bit one, with addr_10b=1.
//
// Reserved addresses (fwvip_i2c_addr7_reserved: general call, START byte,
// 10-bit prefix, ...) are refused at start() unless `allow_reserved` is
// set; the kit gives none of them special handling (design.md §8 issues 4
// and 8).
class fwvip_i2c_tgt_config extends uvm_object implements i2c_target_if;
    `uvm_object_utils(fwvip_i2c_tgt_config)

    bit [6:0]  addr           = 7'h50;
    bit [6:0]  addr_mask      = 7'h7f;
    bit        allow_reserved = 1'b0;
    bit        addr10_en      = 1'b0;
    bit [9:0]  addr10         = 10'h000;
    bit [9:0]  addr10_mask    = 10'h3ff;

    protected fwvip_i2c_tgt_driver m_drv;

    function new(string name = "fwvip_i2c_tgt_config");
        super.new(name);
    endfunction

    function bit addr_match(bit [6:0] a);
        return ((a ^ addr) & addr_mask) == 7'h00;
    endfunction

    function bit addr10_match(bit [9:0] a);
        return addr10_en && ((a ^ addr10) & addr10_mask) == 10'h000;
    endfunction

    // Attach the driver; the vif-aware specialization also starts the kit
    // bridge.
    virtual task start(fwvip_i2c_tgt_driver drv);
        if (!allow_reserved && fwvip_i2c_addr7_reserved(addr))
            `uvm_fatal("FWVIP_I2C", $sformatf("target address 0x%02h is reserved (set allow_reserved to use it)", addr))
        m_drv = drv;
    endtask

    virtual task addressed(input bit [9:0] addr, input bit addr_10b,
                           input bit read, output bit ack);
        i2c_target_if h;
        if (addr_10b ? !addr10_match(addr) : !addr_match(addr[6:0])) begin
            ack = 1'b0;
            return;
        end
        m_drv.get_handler(h);
        h.addressed(addr, addr_10b, read, ack);
    endtask

    virtual task addressed_10b_hi(input bit [1:0] addr_hi, output bit ack);
        ack = addr10_en && ((addr_hi ^ addr10[9:8]) & addr10_mask[9:8]) == 2'b00;
    endtask

    virtual task rx_byte(input bit [7:0] data, output bit ack);
        i2c_target_if h;
        m_drv.get_handler(h);
        h.rx_byte(data, ack);
    endtask

    virtual task tx_byte(output bit [7:0] data, input bit ack);
        i2c_target_if h;
        m_drv.get_handler(h);
        h.tx_byte(data, ack);
    endtask
endclass

// vif-aware specialization: holds the kit target transactor's `u_if` and
// runs a kit i2c_target_xtor_bridge with this config as its model.
class fwvip_i2c_tgt_config_p #(type vif_t = virtual i2c_target_xtor_if)
        extends fwvip_i2c_tgt_config;
    typedef fwvip_i2c_tgt_config_p #(vif_t) this_t;

    vif_t                   vif;
    i2c_target_xtor_bridge  m_bridge;

    function new(string name = "fwvip_i2c_tgt_config_p");
        super.new(name);
    endfunction

    static function this_t set(uvm_component ctxt, string inst, string field, vif_t vif,
                               bit [6:0] addr = 7'h50, bit [6:0] addr_mask = 7'h7f);
        this_t cfg = new();
        cfg.vif       = vif;
        cfg.addr      = addr;
        cfg.addr_mask = addr_mask;
        uvm_config_db #(fwvip_i2c_tgt_config)::set(ctxt, inst, field, cfg);
        return cfg;
    endfunction

    virtual task start(fwvip_i2c_tgt_driver drv);
        super.start(drv);
        m_bridge = new(vif, this);
        m_bridge.start_bridge();
    endtask
endclass
