// Data NACK: the target NACKs the third data byte of a write. The
// controller stops there (DATA_NACK at byte 3, the pointer byte being 0),
// the bytes before it are stored, and the NACKed one is not.
class fwvip_i2c_data_nack_seq extends fwvip_i2c_b2b_seq_base;
    `uvm_object_utils(fwvip_i2c_data_nack_seq)

    function new(string name = "fwvip_i2c_data_nack_seq");
        super.new(name);
    endfunction

    task body();
        fwvip_i2c_xact t;
        bit [7:0] wr[] = '{8'h11, 8'h22, 8'h33, 8'h44, 8'h55};
        bit [7:0] got[];
        env.m_resp.nack_at = 3;
        mem_write(t, 8'h80, wr);
        check(t.status == FWVIP_I2C_DATA_NACK && t.nack_seg == 0 && t.nack_byte == 3,
              $sformatf("write: %s", t.convert2string()));
        check(t.seg[0].data.size() == 4, $sformatf("bytes on the bus: %s", t.convert2string()));
        env.m_resp.nack_at = -1;
        mem_read(t, 8'h80, 3);
        got = t.seg[0].data;
        check(got[0] == 8'h11 && got[1] == 8'h22, $sformatf("stored bytes: %s", t.convert2string()));
        check(got[2] == fwvip_i2c_mem_responder_seq::init_byte(8'h82),
              $sformatf("the NACKed byte was stored: %s", t.convert2string()));
    endtask
endclass
