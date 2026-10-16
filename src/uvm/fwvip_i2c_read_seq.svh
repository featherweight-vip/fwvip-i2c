// One read: START, `addr`, `n` bytes, STOP. Set the fields before start();
// `t` holds the completed transaction (t.seg[0].data the bytes read).
class fwvip_i2c_read_seq extends fwvip_i2c_ctrl_seq_base;
    `uvm_object_utils(fwvip_i2c_read_seq)

    bit [6:0]       addr;
    int unsigned    n = 1;
    fwvip_i2c_xact  t;

    function new(string name = "fwvip_i2c_read_seq");
        super.new(name);
    endfunction

    task body();
        read(t, addr, n);
    endtask
endclass
