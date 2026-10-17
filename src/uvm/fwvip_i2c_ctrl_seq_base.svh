// Base for controller sequences: helpers that build one transaction, run it
// and return it completed.
class fwvip_i2c_ctrl_seq_base extends uvm_sequence #(fwvip_i2c_xact);
    `uvm_object_utils(fwvip_i2c_ctrl_seq_base)

    function new(string name = "fwvip_i2c_ctrl_seq_base");
        super.new(name);
    endfunction

    // Run `t` to completion.
    task do_xact(fwvip_i2c_xact t);
        start_item(t);
        finish_item(t);
    endtask

    // START, address `addr` (write), `data`, STOP. addr_10b=1 in these
    // helpers makes `addr` a 10-bit address.
    task write(output fwvip_i2c_xact t, input bit [9:0] addr, input bit [7:0] data[],
               input bit addr_10b = 1'b0);
        t = fwvip_i2c_xact::type_id::create("wr");
        void'(t.add_write(addr, data, addr_10b));
        do_xact(t);
    endtask

    // START, address `addr` (read), `n` bytes (the last NACKed), STOP.
    // t.seg[0].data holds what was read.
    task read(output fwvip_i2c_xact t, input bit [9:0] addr, input int unsigned n,
              input bit addr_10b = 1'b0);
        t = fwvip_i2c_xact::type_id::create("rd");
        void'(t.add_read(addr, n, addr_10b));
        do_xact(t);
    endtask

    // START, address `addr` (write), `data`, Sr, address `addr` (read),
    // `n` bytes, STOP: the usual register read, with no STOP to let another
    // controller in between. t.seg[1].data holds what was read.
    task write_read(output fwvip_i2c_xact t, input bit [9:0] addr,
                    input bit [7:0] data[], input int unsigned n,
                    input bit addr_10b = 1'b0);
        t = fwvip_i2c_xact::type_id::create("wr_rd");
        void'(t.add_write(addr, data, addr_10b));
        void'(t.add_read(addr, n, addr_10b));
        do_xact(t);
    endtask

    // A random 10-bit address.
    static function bit [9:0] rand_addr10();
        return 10'($urandom);
    endfunction

    // A random legal (non-reserved) 7-bit address.
    static function bit [6:0] rand_addr7();
        bit [6:0] a;
        do a = 7'($urandom); while (fwvip_i2c_addr7_reserved(a));
        return a;
    endfunction
endclass
