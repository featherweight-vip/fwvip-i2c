// Address NACK: writes and reads to addresses no target answers end with
// ADDR_NACK and a STOP, and the bus is usable afterwards.
class fwvip_i2c_addr_nack_seq extends fwvip_i2c_b2b_seq_base;
    `uvm_object_utils(fwvip_i2c_addr_nack_seq)

    function new(string name = "fwvip_i2c_addr_nack_seq");
        super.new(name);
    endfunction

    task body();
        fwvip_i2c_xact t;
        bit [7:0] wr[] = '{8'h00, 8'h5a};
        repeat (4) begin
            bit [6:0] a = other_addr();
            write(t, a, wr);
            check(t.status == FWVIP_I2C_ADDR_NACK && t.nack_seg == 0,
                  $sformatf("write to 0x%02h: %s", a, t.convert2string()));
            read(t, a, 2);
            check(t.status == FWVIP_I2C_ADDR_NACK && t.nack_seg == 0,
                  $sformatf("read from 0x%02h: %s", a, t.convert2string()));
        end
        mem_write(t, 8'h40, wr);
        check(t.status == FWVIP_I2C_OK, $sformatf("write after the NACKs: %s", t.convert2string()));
        mem_read(t, 8'h40, 2);
        check(t.seg[0].data == wr, $sformatf("read after the NACKs: %s", t.convert2string()));
    endtask
endclass
