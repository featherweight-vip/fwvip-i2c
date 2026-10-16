// Random traffic: `n_xacts` transactions to the addresses in `addrs` (a
// random legal address each time if empty). Each segment is a write of
// 0..`max_bytes` bytes or a read of 1..`max_bytes`; after each one, with
// probability `sr_pct`%, another segment follows a repeated START, up to
// `max_segs` per transaction.
class fwvip_i2c_rand_seq extends fwvip_i2c_ctrl_seq_base;
    `uvm_object_utils(fwvip_i2c_rand_seq)

    int unsigned  n_xacts   = 20;
    int unsigned  max_bytes = 8;
    int unsigned  read_pct  = 50;
    int unsigned  sr_pct    = 25;
    int unsigned  max_segs  = 3;
    bit [6:0]     addrs[$];

    function new(string name = "fwvip_i2c_rand_seq");
        super.new(name);
    endfunction

    task body();
        repeat (n_xacts) begin
            fwvip_i2c_xact t = fwvip_i2c_xact::type_id::create("t");
            do add_rand_seg(t);
            while (t.seg.size() < max_segs && $urandom_range(99) < sr_pct);
            do_xact(t);
        end
    endtask

    protected function void add_rand_seg(fwvip_i2c_xact t);
        bit [6:0] a = (addrs.size() != 0) ? addrs[$urandom_range(addrs.size() - 1)] : rand_addr7();
        if ($urandom_range(99) < read_pct) begin
            void'(t.add_read(a, $urandom_range(max_bytes, 1)));
        end else begin
            bit [7:0] d[] = new[$urandom_range(max_bytes)];
            foreach (d[i]) d[i] = 8'($urandom);
            void'(t.add_write(a, d));
        end
    endfunction
endclass
