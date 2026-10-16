// The controller agent's driver: runs each fwvip_i2c_xact to completion as
// a sequence of per-byte calls on the config, fills in its result fields,
// then publishes it on `ap`. One transaction at a time: I2C has one bus.
class fwvip_i2c_ctrl_driver extends uvm_driver #(fwvip_i2c_xact);
    `uvm_component_utils(fwvip_i2c_ctrl_driver)

    fwvip_i2c_ctrl_config                 m_cfg;
    uvm_analysis_port #(fwvip_i2c_xact)  ap;
    int unsigned                         n_done;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
    endfunction

    task run_phase(uvm_phase phase);
        fwvip_i2c_xact t;
        forever begin
            seq_item_port.get_next_item(t);
            execute(t);
            n_done++;
            ap.write(t);
            seq_item_port.item_done();
        end
    endtask

    // START/Sr + address per segment, then its data bytes; STOP at the end
    // or at the first NACK. Arbitration loss abandons the transaction with
    // no STOP: the core has already released the bus.
    virtual task execute(fwvip_i2c_xact t);
        bit ack, arb_lost;
        t.status    = FWVIP_I2C_OK;
        t.nack_seg  = -1;
        t.nack_byte = -1;
        foreach (t.seg[i]) begin
            fwvip_i2c_segment s = t.seg[i];
            int unsigned n = s.data.size();
            s.ack = new[n];
            m_cfg.start(s.addr, s.addr_10b, s.read, i != 0, ack, arb_lost);
            if (arb_lost) begin
                t.status = FWVIP_I2C_ARB_LOST;
                s.data   = new[0];
                s.ack    = new[0];
                return;
            end
            s.addr_ack = ack;
            if (!ack) begin
                t.status   = FWVIP_I2C_ADDR_NACK;
                t.nack_seg = i;
                s.data     = new[0];
                s.ack      = new[0];
                m_cfg.stop();
                return;
            end
            for (int unsigned j = 0; j < n; j++) begin
                if (s.read) begin
                    bit [7:0] d;
                    s.ack[j] = (j + 1 < n);
                    m_cfg.rx_byte(s.ack[j], d, arb_lost);
                    s.data[j] = d;
                end else begin
                    m_cfg.tx_byte(s.data[j], ack, arb_lost);
                    s.ack[j] = ack;
                end
                if (arb_lost) begin
                    t.status = FWVIP_I2C_ARB_LOST;
                    s.data   = new[j](s.data);
                    s.ack    = new[j](s.ack);
                    return;
                end
                if (!s.read && !ack) begin
                    t.status    = FWVIP_I2C_DATA_NACK;
                    t.nack_seg  = i;
                    t.nack_byte = j;
                    s.data      = new[j + 1](s.data);
                    s.ack       = new[j + 1](s.ack);
                    m_cfg.stop();
                    return;
                end
            end
        end
        m_cfg.stop();
    endtask
endclass
