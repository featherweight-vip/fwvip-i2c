// Clock stretching: the target takes 5..40 cycles over every decision, so
// its core holds SCL low through each one, and the controller must wait it
// out on every bit. Random traffic to the target.
class fwvip_i2c_stretch_seq extends fwvip_i2c_b2b_seq_base;
    `uvm_object_utils(fwvip_i2c_stretch_seq)

    function new(string name = "fwvip_i2c_stretch_seq");
        super.new(name);
    endfunction

    task body();
        fwvip_i2c_rand_seq r = fwvip_i2c_rand_seq::type_id::create("r");
        env.m_resp.lat_min = 5;
        env.m_resp.lat_max = 40;
        r.n_xacts = 12;
        r.addrs.push_back(TGT_ADDR);
        r.start(m_sequencer, this);
    endtask
endclass
