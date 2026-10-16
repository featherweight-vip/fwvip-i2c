// Base for the back-to-back cases: a controller sequence with a handle to
// the env (scoreboard, memory responder, monitor). Bus and read data are
// checked by the env's scoreboard; a case checks what is particular to it
// with check().
class fwvip_i2c_b2b_seq_base extends fwvip_i2c_ctrl_seq_base;
    `uvm_object_utils(fwvip_i2c_b2b_seq_base)

    fwvip_i2c_b2b_env  env;

    function new(string name = "fwvip_i2c_b2b_seq_base");
        super.new(name);
    endfunction

    // What every case starts from: no clock stretching, no forced NACKs.
    virtual function void defaults();
        env.m_resp.lat_min = 0;
        env.m_resp.lat_max = 0;
        env.m_resp.nack_at = -1;
    endfunction

    function void check(bit cond, string what);
        if (!cond) `uvm_error(get_type_name(), {"check failed: ", what})
    endfunction

    // Let the monitor deliver the last STOP.
    task settle();
        env.m_clock.tick(50);
    endtask

    function bit [6:0] other_addr();
        bit [6:0] a;
        do a = rand_addr7(); while (a == TGT_ADDR);
        return a;
    endfunction

    // Write `data` starting at memory offset `off` (the pointer byte first).
    task mem_write(output fwvip_i2c_xact t, input bit [7:0] off, input bit [7:0] data[]);
        bit [7:0] b[] = new[data.size() + 1];
        b[0] = off;
        foreach (data[i]) b[i + 1] = data[i];
        write(t, TGT_ADDR, b);
    endtask

    // Random read of `n` bytes at offset `off`: set the pointer, STOP, read.
    task mem_read(output fwvip_i2c_xact t, input bit [7:0] off, input int unsigned n);
        bit [7:0] b[] = new[1];
        b[0] = off;
        write(t, TGT_ADDR, b);
        read(t, TGT_ADDR, n);
    endtask
endclass
