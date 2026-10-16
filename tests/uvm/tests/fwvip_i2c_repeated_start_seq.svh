// Repeated START: transactions of two and three segments joined by Sr --
// write then read (the register read), read then write, write then write
// -- plus an Sr to an address nobody answers, and a NACK that ends a
// transaction before its Sr. The scoreboard checks every byte read; this
// case checks the statuses and that the segments after a NACK are dropped.
class fwvip_i2c_repeated_start_seq extends fwvip_i2c_b2b_seq_base;
    `uvm_object_utils(fwvip_i2c_repeated_start_seq)

    function new(string name = "fwvip_i2c_repeated_start_seq");
        super.new(name);
    endfunction

    task body();
        fwvip_i2c_xact t;
        bit [7:0] wr[]   = '{8'hc0, 8'h41, 8'hc2, 8'h03};
        bit [7:0] w30[]  = '{8'h30, 8'h9a, 8'h1b};
        bit [7:0] p30[]  = '{8'h30};
        bit [7:0] r30[]  = '{8'h9a, 8'h1b};
        bit [7:0] r21[]  = '{8'h41, 8'hc2};
        bit [7:0] w22[]  = '{8'h22, 8'h77};
        bit [7:0] w40[]  = '{8'h40, 8'h55};
        bit [7:0] w50[]  = '{8'h50, 8'haa, 8'hbb, 8'hcc};

        // write -> Sr -> read
        mem_write(t, 8'h20, wr);
        mem_read_sr(t, 8'h20, 4);
        check(t.status == FWVIP_I2C_OK && t.seg.size() == 2,
              $sformatf("write-Sr-read: %s", t.convert2string()));
        check(t.seg[1].data == wr, $sformatf("write-Sr-read data: %s", t.convert2string()));

        // write -> Sr -> write -> Sr -> read: the second write only moves
        // the pointer back.
        t = fwvip_i2c_xact::type_id::create("w_w_r");
        void'(t.add_write(TGT_ADDR, w30));
        void'(t.add_write(TGT_ADDR, p30));
        void'(t.add_read(TGT_ADDR, 2));
        do_xact(t);
        check(t.status == FWVIP_I2C_OK && t.seg.size() == 3,
              $sformatf("write-Sr-write-Sr-read: %s", t.convert2string()));
        check(t.seg[2].data == r30,
              $sformatf("write-Sr-write-Sr-read data: %s", t.convert2string()));

        // read -> Sr -> write: Sr after the NACKed last read byte.
        mem_read(t, 8'h20, 1);
        t = fwvip_i2c_xact::type_id::create("r_w");
        void'(t.add_read(TGT_ADDR, 2));
        void'(t.add_write(TGT_ADDR, w22));
        do_xact(t);
        check(t.status == FWVIP_I2C_OK && t.seg.size() == 2,
              $sformatf("read-Sr-write: %s", t.convert2string()));
        check(t.seg[0].data == r21,
              $sformatf("read-Sr-write data: %s", t.convert2string()));
        mem_read_sr(t, 8'h22, 1);
        check(t.seg[1].data[0] == 8'h77, $sformatf("written after Sr: %s", t.convert2string()));

        // write -> Sr -> an address nobody answers: ADDR_NACK in segment
        // 1, and the write before it still landed.
        t = fwvip_i2c_xact::type_id::create("w_nack");
        void'(t.add_write(TGT_ADDR, w40));
        void'(t.add_read(other_addr(), 1));
        do_xact(t);
        check(t.status == FWVIP_I2C_ADDR_NACK && t.nack_seg == 1 && t.seg.size() == 2,
              $sformatf("Sr to a silent address: %s", t.convert2string()));
        mem_read_sr(t, 8'h40, 1);
        check(t.seg[1].data[0] == 8'h55, $sformatf("write before the NACKed Sr: %s", t.convert2string()));

        // A data NACK in segment 0 ends the transaction with STOP: the read
        // segment never runs and is dropped from the item.
        env.m_resp.nack_at = 2;
        t = fwvip_i2c_xact::type_id::create("nack_w_r");
        void'(t.add_write(TGT_ADDR, w50));
        void'(t.add_read(TGT_ADDR, 1));
        do_xact(t);
        env.m_resp.nack_at = -1;
        check(t.status == FWVIP_I2C_DATA_NACK && t.nack_seg == 0 && t.nack_byte == 2 &&
              t.seg.size() == 1, $sformatf("NACK before Sr: %s", t.convert2string()));
    endtask
endclass
