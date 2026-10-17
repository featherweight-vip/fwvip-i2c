// 10-bit addressing (UM10204 §3.1.11): the target answers TGT_ADDR10 as
// well as TGT_ADDR, with one memory behind both. Writes and reads at the
// 10-bit address, a 7-bit write then an Sr to a 10-bit read, a 10-bit
// write of no data bytes then an Sr to a 10-bit read (the bus form the
// monitor folds into one read segment), and addresses NACKed at either
// header byte. The scoreboard checks the bus and every byte read.
class fwvip_i2c_addr_10b_seq extends fwvip_i2c_b2b_seq_base;
    `uvm_object_utils(fwvip_i2c_addr_10b_seq)

    function new(string name = "fwvip_i2c_addr_10b_seq");
        super.new(name);
    endfunction

    task body();
        fwvip_i2c_xact t;
        bit [7:0] w60[] = '{8'h60, 8'h3e, 8'hc1, 8'h07};
        bit [7:0] r60[] = '{8'h3e, 8'hc1, 8'h07};
        bit [7:0] r61[] = '{8'hc1, 8'h07};
        bit [7:0] p60[] = '{8'h60};
        bit [7:0] p61[] = '{8'h61};
        bit [7:0] none[];
        bit [7:0] wr[]  = '{8'h00, 8'h5a};

        // Write and read back at the 10-bit address: set the pointer,
        // STOP, read.
        write(t, TGT_ADDR10, w60, 1'b1);
        check(t.status == FWVIP_I2C_OK, $sformatf("10-bit write: %s", t.convert2string()));
        write(t, TGT_ADDR10, p60, 1'b1);
        read(t, TGT_ADDR10, 3, 1'b1);
        check(t.status == FWVIP_I2C_OK && t.seg[0].data == r60,
              $sformatf("10-bit read: %s", t.convert2string()));

        // The same in one transaction: pointer write, Sr, 10-bit read.
        write_read(t, TGT_ADDR10, p61, 2, 1'b1);
        check(t.status == FWVIP_I2C_OK && t.seg.size() == 2 && t.seg[1].data == r61,
              $sformatf("10-bit write-Sr-read: %s", t.convert2string()));

        // 7-bit pointer write, Sr, 10-bit read: one memory behind both.
        t = fwvip_i2c_xact::type_id::create("w7_r10");
        void'(t.add_write(TGT_ADDR, p60));
        void'(t.add_read(TGT_ADDR10, 3, 1'b1));
        do_xact(t);
        check(t.status == FWVIP_I2C_OK && t.seg[1].data == r60,
              $sformatf("7-bit write, Sr, 10-bit read: %s", t.convert2string()));

        // A 10-bit write of no data bytes, then Sr and a 10-bit read.
        t = fwvip_i2c_xact::type_id::create("w10_0_r10");
        void'(t.add_write(TGT_ADDR10, none, 1'b1));
        void'(t.add_read(TGT_ADDR10, 2, 1'b1));
        do_xact(t);
        check(t.status == FWVIP_I2C_OK && t.seg.size() == 2,
              $sformatf("empty 10-bit write, Sr, 10-bit read: %s", t.convert2string()));

        // NACKed at the first header byte (A9:A8 differ), and at the
        // second (addr[7:0] differs), writing and reading.
        write(t, {~TGT_ADDR10[9:8], TGT_ADDR10[7:0]}, wr, 1'b1);
        check(t.status == FWVIP_I2C_ADDR_NACK && t.nack_seg == 0,
              $sformatf("10-bit write, A9:A8 differ: %s", t.convert2string()));
        write(t, TGT_ADDR10 ^ 10'h001, wr, 1'b1);
        check(t.status == FWVIP_I2C_ADDR_NACK && t.nack_seg == 0,
              $sformatf("10-bit write, addr[7:0] differs: %s", t.convert2string()));
        read(t, TGT_ADDR10 ^ 10'h080, 2, 1'b1);
        check(t.status == FWVIP_I2C_ADDR_NACK && t.nack_seg == 0,
              $sformatf("10-bit read, addr[7:0] differs: %s", t.convert2string()));

        // 7-bit addressing is unaffected.
        mem_read(t, 8'h61, 2);
        check(t.seg[0].data == r61, $sformatf("7-bit read after 10-bit: %s", t.convert2string()));
    endtask
endclass
