// One addressed segment of a transaction: START (or Sr), the address+R/W
// byte, then data bytes in one direction. With addr_10b, the address is
// 10 bits (UM10204 §3.1.11): the two-byte write header, and for a read
// also an Sr and the read header -- all one segment, which the kit's
// controller core sends as one start(). addr_ack is then the AND of every
// header byte's ACK.
//
// Before the transaction runs, `data` holds the bytes to write (write
// segment) or is sized to the number of bytes to read (read segment).
// Afterwards `data` holds exactly the bytes that crossed the bus (a write
// NACKed partway is truncated after the NACKed byte), and `ack[i]` is the
// ACK bit that followed `data[i]`: the target's for a write, the
// controller's for a read (1 for every byte but the last).
class fwvip_i2c_segment extends uvm_object;
    `uvm_object_utils(fwvip_i2c_segment)

    bit [9:0]  addr;
    bit        addr_10b;
    bit        read;
    bit [7:0]  data[];
    bit        addr_ack;
    bit        ack[];

    function new(string name = "fwvip_i2c_segment");
        super.new(name);
    endfunction

    // "W 0x50 10 a0 a1~": a trailing ~ marks a NACKed byte. A 10-bit
    // address prints as "W 0x2a5/10".
    function string convert2string();
        string s = addr_10b ? $sformatf("%s 0x%03h/10", read ? "R" : "W", addr)
                            : $sformatf("%s 0x%02h", read ? "R" : "W", addr[6:0]);
        if (!addr_ack) s = {s, " NACK"};
        foreach (data[i]) begin
            s = {s, $sformatf(" %02h", data[i])};
            if (!ack[i]) s = {s, "~"};
        end
        return s;
    endfunction

    // Same bus traffic: address, direction, bytes and every ACK bit. A
    // NACKed 10-bit header stops at the NACKed byte, so addr[7:0] (NACK at
    // the first byte) and the read header (NACK before it) may never have
    // reached the bus: for a NACKed 10-bit address only A9:A8 are compared.
    function bit same_bus(fwvip_i2c_segment o, output string why);
        bit addr_same;
        if (addr_10b && !addr_ack)
            addr_same = o.addr_10b && o.addr[9:8] == addr[9:8];
        else if (addr_10b)
            addr_same = o.addr_10b && o.addr == addr && o.read == read;
        else
            addr_same = !o.addr_10b && o.addr[6:0] == addr[6:0] && o.read == read;
        if (!addr_same || o.addr_ack != addr_ack) begin
            why = "address byte differs";
            return 0;
        end
        if (o.data.size() != data.size() || o.ack.size() != ack.size()) begin
            why = $sformatf("%0d bytes vs %0d", data.size(), o.data.size());
            return 0;
        end
        foreach (data[i])
            if (o.data[i] != data[i] || o.ack[i] != ack[i]) begin
                why = $sformatf("byte %0d differs", i);
                return 0;
            end
        return 1;
    endfunction
endclass
