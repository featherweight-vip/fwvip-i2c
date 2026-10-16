// One transaction: START, one or more segments (the second and later begin
// with a repeated START), STOP. The controller agent runs it; the monitor
// agent reconstructs the same shape from the bus.
//
// `status` says how it ended. On ADDR_NACK or DATA_NACK, nack_seg /
// nack_byte say where (nack_byte is -1 for the address byte); the
// controller then issues STOP. On ARB_LOST the core has already released
// the bus and no STOP is sent: the caller retries the whole transaction.
//
// Known kit gap: the v1 target core does not tell a repeated START from
// another data byte (fw-proto-i2c i2c_target_xtor_core.sv header), so
// multi-segment transactions are modeled here but not yet exercised.
class fwvip_i2c_xact extends uvm_sequence_item;
    `uvm_object_utils(fwvip_i2c_xact)

    fwvip_i2c_segment    seg[$];
    fwvip_i2c_status_e   status = FWVIP_I2C_OK;
    int                  nack_seg = -1;
    int                  nack_byte = -1;

    function new(string name = "fwvip_i2c_xact");
        super.new(name);
    endfunction

    function fwvip_i2c_segment add_write(bit [6:0] addr, bit [7:0] data[]);
        fwvip_i2c_segment s = fwvip_i2c_segment::type_id::create("wr");
        s.addr = addr;
        s.read = 1'b0;
        s.data = data;
        seg.push_back(s);
        return s;
    endfunction

    function fwvip_i2c_segment add_read(bit [6:0] addr, int unsigned n);
        fwvip_i2c_segment s = fwvip_i2c_segment::type_id::create("rd");
        s.addr = addr;
        s.read = 1'b1;
        s.data = new[n];
        seg.push_back(s);
        return s;
    endfunction

    function string convert2string();
        string s = status.name();
        foreach (seg[i]) begin
            if (i == 0) s = {s, " ["};
            else        s = {s, " | Sr "};
            s = {s, seg[i].convert2string()};
        end
        return {s, "]"};
    endfunction

    // Same bus traffic as `o`: status and every segment.
    function bit same_bus(fwvip_i2c_xact o, output string why);
        if (o.status != status) begin
            why = $sformatf("status %s vs %s", status.name(), o.status.name());
            return 0;
        end
        if (o.seg.size() != seg.size()) begin
            why = $sformatf("%0d segments vs %0d", seg.size(), o.seg.size());
            return 0;
        end
        foreach (seg[i]) begin
            string w;
            if (!seg[i].same_bus(o.seg[i], w)) begin
                why = $sformatf("segment %0d: %s", i, w);
                return 0;
            end
        end
        return 1;
    endfunction
endclass
