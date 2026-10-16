typedef class fwvip_i2c_tgt_agent;

// An EEPROM-style target: 256 bytes behind an 8-bit pointer. The first byte
// of a write sets the pointer; each later write byte is stored at the
// pointer, and each read byte comes from it; both advance it (wrapping).
// The pointer persists across transactions, so "write the offset, STOP,
// then read" is a random read. Unwritten bytes read as init_byte(offset).
//
// Every decision waits lat_min..lat_max cycles of the agent's clock
// provider first, so the target core stretches SCL for that long.
// nack_at >= 0 NACKs that data byte of every write (0 is the pointer byte),
// storing nothing for it.
class fwvip_i2c_mem_responder_seq extends fwvip_i2c_tgt_seq;
    `uvm_object_utils(fwvip_i2c_mem_responder_seq)

    bit [7:0]       mem[bit [7:0]];
    bit [7:0]       ptr;
    int unsigned    lat_min = 0;
    int unsigned    lat_max = 0;
    int             nack_at = -1;
    fwvip_clock_if  clock;          // from the agent, if it has one

    protected int unsigned m_wr_idx;

    function new(string name = "fwvip_i2c_mem_responder_seq");
        super.new(name);
    endfunction

    static function bit [7:0] init_byte(bit [7:0] off);
        return off ^ 8'ha5;
    endfunction

    function bit [7:0] peek(bit [7:0] off);
        return mem.exists(off) ? mem[off] : init_byte(off);
    endfunction

    protected task stretch();
        int unsigned lat = $urandom_range(lat_max, lat_min);
        if (lat == 0) return;
        if (clock == null)
            `uvm_fatal("FWVIP_I2C", "fwvip_i2c_mem_responder_seq: latency needs the agent's clock provider")
        clock.tick(lat);
    endtask

    virtual task addressed(input bit [9:0] addr, input bit addr_10b,
                           input bit read, output bit ack);
        stretch();
        m_wr_idx = 0;
        ack      = 1'b1;
    endtask

    virtual task rx_byte(input bit [7:0] data, output bit ack);
        stretch();
        if (nack_at >= 0 && m_wr_idx == nack_at) begin
            ack = 1'b0;
        end else begin
            ack = 1'b1;
            if (m_wr_idx == 0) ptr = data;
            else begin
                mem[ptr] = data;
                ptr++;
            end
        end
        m_wr_idx++;
    endtask

    virtual task tx_byte(output bit [7:0] data, input bit ack);
        stretch();
        data = peek(ptr);
        ptr++;
    endtask

    task body();
        fwvip_i2c_tgt_agent agent;
        if (clock == null && m_sequencer != null && $cast(agent, m_sequencer.get_parent()))
            clock = agent.m_clock;
        super.body();
    endtask
endclass
