// Smoke: write four bytes at an offset, read them back with a random read,
// and read across written and unwritten bytes.
class fwvip_i2c_smoke_seq extends fwvip_i2c_b2b_seq_base;
    `uvm_object_utils(fwvip_i2c_smoke_seq)

    function new(string name = "fwvip_i2c_smoke_seq");
        super.new(name);
    endfunction

    task body();
        fwvip_i2c_xact t;
        bit [7:0] wr[] = '{8'ha0, 8'ha1, 8'ha2, 8'ha3};
        mem_write(t, 8'h10, wr);
        check(t.status == FWVIP_I2C_OK, $sformatf("write: %s", t.convert2string()));
        mem_read(t, 8'h10, 4);
        check(t.status == FWVIP_I2C_OK, $sformatf("read: %s", t.convert2string()));
        check(t.seg[0].data == wr, $sformatf("read back: %s", t.convert2string()));
        mem_read(t, 8'h0e, 8);
        check(t.status == FWVIP_I2C_OK, $sformatf("read: %s", t.convert2string()));
    endtask
endclass
