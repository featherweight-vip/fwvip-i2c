// The back-to-back scoreboard. Two checks:
//
//  - Bus: every transaction the controller agent completed must match, in
//    order, what the monitor agent reconstructed from the pins (status,
//    addresses, every byte and ACK bit).
//  - Data: a reference of the memory responder (fwvip_i2c_mem_responder_seq:
//    the first write byte sets the pointer, later bytes store and advance,
//    reads fetch and advance) built from the controller's completed
//    transactions to TGT_ADDR. Every byte read must match it.
class fwvip_i2c_b2b_sb extends uvm_component;
    `uvm_component_utils(fwvip_i2c_b2b_sb)

    uvm_analysis_imp_ctrl #(fwvip_i2c_xact, fwvip_i2c_b2b_sb)  ctrl_export;
    uvm_analysis_imp_mon  #(fwvip_i2c_xact, fwvip_i2c_b2b_sb)  mon_export;

    bit [7:0]         ref_mem[bit [7:0]];
    bit [7:0]         ref_ptr;
    fwvip_i2c_xact    m_ctrl_q[$];
    fwvip_i2c_xact    m_mon_q[$];
    int unsigned      n_matched, n_bus_bad, n_bytes_checked, n_data_bad;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ctrl_export = new("ctrl_export", this);
        mon_export  = new("mon_export", this);
    endfunction

    function void write_ctrl(fwvip_i2c_xact t);
        check_data(t);
        m_ctrl_q.push_back(t);
        pair();
    endfunction

    function void write_mon(fwvip_i2c_xact t);
        m_mon_q.push_back(t);
        pair();
    endfunction

    protected function void pair();
        while (m_ctrl_q.size() != 0 && m_mon_q.size() != 0) begin
            fwvip_i2c_xact c = m_ctrl_q.pop_front();
            fwvip_i2c_xact m = m_mon_q.pop_front();
            string why;
            if (c.same_bus(m, why)) n_matched++;
            else begin
                n_bus_bad++;
                `uvm_error("SB", $sformatf("bus mismatch (%s):\n  controller %s\n  monitor    %s",
                                           why, c.convert2string(), m.convert2string()))
            end
        end
    endfunction

    protected function void check_data(fwvip_i2c_xact t);
        foreach (t.seg[i]) begin
            fwvip_i2c_segment s = t.seg[i];
            if (s.addr[6:0] != TGT_ADDR || !s.addr_ack) continue;
            if (s.read) begin
                foreach (s.data[j]) begin
                    bit [7:0] e = ref_mem.exists(ref_ptr) ? ref_mem[ref_ptr]
                                                          : fwvip_i2c_mem_responder_seq::init_byte(ref_ptr);
                    n_bytes_checked++;
                    if (s.data[j] != e) begin
                        n_data_bad++;
                        `uvm_error("SB", $sformatf("read byte %0d at 0x%02h: got %02h want %02h (%s)",
                                                   j, ref_ptr, s.data[j], e, t.convert2string()))
                    end
                    ref_ptr++;
                end
            end else begin
                foreach (s.data[j]) begin
                    if (!s.ack[j]) continue;
                    if (j == 0) ref_ptr = s.data[j];
                    else begin
                        ref_mem[ref_ptr] = s.data[j];
                        ref_ptr++;
                    end
                end
            end
        end
    endfunction

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (m_ctrl_q.size() != 0 || m_mon_q.size() != 0)
            `uvm_error("SB", $sformatf("unpaired at the end: %0d from the controller, %0d from the monitor",
                                       m_ctrl_q.size(), m_mon_q.size()))
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SB", $sformatf("%0d transactions matched the bus (%0d mismatched); %0d bytes read checked (%0d wrong)",
                                  n_matched, n_bus_bad, n_bytes_checked, n_data_bad), UVM_LOW)
    endfunction
endclass
