// One write: START, `addr`, `data`, STOP. Set the fields before start();
// `t` holds the completed transaction afterwards.
class fwvip_i2c_write_seq extends fwvip_i2c_ctrl_seq_base;
    `uvm_object_utils(fwvip_i2c_write_seq)

    bit [6:0]       addr;
    bit [7:0]       data[];
    fwvip_i2c_xact  t;

    function new(string name = "fwvip_i2c_write_seq");
        super.new(name);
    endfunction

    task body();
        write(t, addr, data);
    endtask
endclass
