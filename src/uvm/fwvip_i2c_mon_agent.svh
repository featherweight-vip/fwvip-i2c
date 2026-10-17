// Passive agent (design.md §6): coalesces the kit monitor's byte-level
// events back into fwvip_i2c_xact items -- START, address byte, data bytes,
// Sr, ..., STOP -- and publishes each on `ap` at its STOP. Statuses follow
// the controller agent's: ADDR_NACK for a NACKed address byte, DATA_NACK
// for a NACKed write byte (the last byte of a read is NACKed by design).
//
// 10-bit addresses (UM10204 §3.1.11) fold into one segment the way the
// controller agent records them: the write header's two bytes (the kit
// monitor reports both as address bytes), and for a read, the Sr and read
// header (11110 A9 A8 R) that follow a write header with no data bytes.
// The kit's controller sends exactly that for a 10-bit read. A read header
// after a 10-bit write that moved data (the short form some controllers
// use) starts a read segment of its own, at that write's address.
//
// The event order is checked as it is reconstructed; a violation is a
// UVM_ERROR with id I2C_MON:
//   - a STOP, Sr or byte outside a transaction
//   - a data byte before any address byte
//   - a data byte after a NACK (the controller must STOP or Sr)
//   - a START while a transaction is open (the kit core reports a START
//     mid-transaction as repeated, so this is a monitor-core fault)
// At check_phase no transaction may be open. Set `check_enable = 0` to
// publish without checking. +fwvip_i2c_mon_trace prints every transaction.
class fwvip_i2c_mon_agent extends uvm_component;
    `uvm_component_utils(fwvip_i2c_mon_agent)

    fwvip_i2c_mon_config                 m_cfg;
    uvm_analysis_port #(fwvip_i2c_xact)  ap;
    bit                                  check_enable = 1;
    bit                                  check_quiescent_at_end = 1;
    bit                                  trace;
    int unsigned                         n_xacts;
    int unsigned                         n_errors;
    string                               last_error;

    protected fwvip_i2c_xact     m_cur;
    protected fwvip_i2c_segment  m_seg;
    protected bit                m_nacked;
    protected bit                m_addr_lo;  // next address byte is a 10-bit addr[7:0]

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(fwvip_i2c_mon_config)::get(this, "", "cfg", m_cfg))
            `uvm_fatal(get_type_name(), "no fwvip_i2c_mon_config \"cfg\" in the config DB")
        trace = $test$plusargs("fwvip_i2c_mon_trace");
        ap = new("ap", this);
        m_cfg.attach(this);
    endfunction

    task run_phase(uvm_phase phase);
        m_cfg.start();
    endtask

    protected function void violation(string msg);
        n_errors++;
        last_error = msg;
        if (check_enable) `uvm_error("I2C_MON", msg)
    endfunction

    function bit in_txn();
        return m_cur != null;
    endfunction

    function void observe_start(bit repeated);
        if (repeated) begin
            if (m_cur == null) begin
                violation("repeated START outside a transaction");
                m_cur = fwvip_i2c_xact::type_id::create("mon");
            end
        end else begin
            if (m_cur != null) violation("START while a transaction is open");
            m_cur = fwvip_i2c_xact::type_id::create("mon");
        end
        m_seg     = null;
        m_nacked  = 0;
        m_addr_lo = 0;
    endfunction

    function void observe_stop();
        if (m_cur == null) begin
            violation("STOP outside a transaction");
            return;
        end
        n_xacts++;
        if (trace) `uvm_info("I2C_MON", m_cur.convert2string(), UVM_LOW)
        ap.write(m_cur);
        m_cur = null;
        m_seg = null;
    endfunction

    function void observe_byte(bit addr_phase, bit [7:0] data, bit ack);
        if (m_cur == null) begin
            violation($sformatf("byte 0x%02h outside a transaction", data));
            return;
        end
        if (addr_phase) begin
            if (m_addr_lo) begin
                // addr[7:0] of a 10-bit write header
                m_addr_lo          = 0;
                m_seg.addr[7:0]    = data;
                m_seg.addr_ack     = ack;
            end else if (data[7:3] == 5'b11110 && data[0]) begin
                // 10-bit read header: completes the 10-bit write header
                // before the Sr if that moved no data, else a new segment
                // at its address
                fwvip_i2c_segment p = (m_cur.seg.size() != 0) ? m_cur.seg[$] : null;
                if (p != null && p.addr_10b && !p.read && p.addr_ack &&
                    p.addr[9:8] == data[2:1] && p.data.size() == 0) begin
                    m_seg = p;
                end else begin
                    m_seg = fwvip_i2c_segment::type_id::create("seg");
                    m_seg.addr     = (p != null && p.addr_10b && p.addr[9:8] == data[2:1])
                                     ? p.addr : {data[2:1], 8'h00};
                    m_seg.addr_10b = 1;
                    m_cur.seg.push_back(m_seg);
                end
                m_seg.read     = 1;
                m_seg.addr_ack = ack;
            end else begin
                m_seg = fwvip_i2c_segment::type_id::create("seg");
                m_seg.addr_ack = ack;
                if (data[7:3] == 5'b11110) begin
                    // 10-bit write header, first byte
                    m_seg.addr     = {data[2:1], 8'h00};
                    m_seg.addr_10b = 1;
                    m_seg.read     = 0;
                    m_addr_lo      = ack;
                end else begin
                    m_seg.addr = {3'b000, data[7:1]};
                    m_seg.read = data[0];
                end
                m_cur.seg.push_back(m_seg);
            end
            m_nacked = !ack;
            if (!ack && m_cur.status == FWVIP_I2C_OK) begin
                m_cur.status   = FWVIP_I2C_ADDR_NACK;
                m_cur.nack_seg = m_cur.seg.size() - 1;
            end
            return;
        end
        if (m_addr_lo) begin
            violation($sformatf("data byte 0x%02h where a 10-bit addr[7:0] belongs", data));
            m_addr_lo = 0;
        end
        if (m_seg == null) begin
            violation($sformatf("data byte 0x%02h before an address byte", data));
            return;
        end
        if (m_nacked) violation($sformatf("data byte 0x%02h after a NACK", data));
        m_seg.data = new[m_seg.data.size() + 1](m_seg.data);
        m_seg.ack  = new[m_seg.ack.size() + 1](m_seg.ack);
        m_seg.data[m_seg.data.size() - 1] = data;
        m_seg.ack[m_seg.ack.size() - 1]   = ack;
        m_nacked = !ack;
        if (!ack && !m_seg.read && m_cur.status == FWVIP_I2C_OK) begin
            m_cur.status    = FWVIP_I2C_DATA_NACK;
            m_cur.nack_seg  = m_cur.seg.size() - 1;
            m_cur.nack_byte = m_seg.data.size() - 1;
        end
    endfunction

    // Not reported by the v1 kit monitor core.
    function void observe_arb_lost();
    endfunction

    // Forget the open transaction and the counts: after a test that
    // provoked violations on purpose.
    function void clear();
        m_cur      = null;
        m_seg      = null;
        m_addr_lo  = 0;
        n_errors   = 0;
        last_error = "";
    endfunction

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (check_enable && check_quiescent_at_end && m_cur != null)
            `uvm_error("I2C_MON", $sformatf("transaction still open at the end of the test: %s",
                                             m_cur.convert2string()))
    endfunction
endclass
