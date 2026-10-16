// Random traffic: writes and reads of 0..8 bytes, mostly to the target and
// some to addresses nobody answers, with 0..8 cycles of stretch.
class fwvip_i2c_rand_traffic_seq extends fwvip_i2c_b2b_seq_base;
    `uvm_object_utils(fwvip_i2c_rand_traffic_seq)

    function new(string name = "fwvip_i2c_rand_traffic_seq");
        super.new(name);
    endfunction

    task body();
        fwvip_i2c_rand_seq r = fwvip_i2c_rand_seq::type_id::create("r");
        env.m_resp.lat_max = 8;
        r.n_xacts = 40;
        repeat (3) r.addrs.push_back(TGT_ADDR);
        r.addrs.push_back(other_addr());
        r.start(m_sequencer, this);
    endtask
endclass
