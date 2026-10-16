// Random single-segment traffic: `n_xacts` writes and reads to the
// addresses in `addrs` (a random legal address each time if empty), each
// 0..`max_bytes` bytes (reads at least 1).
class fwvip_i2c_rand_seq extends fwvip_i2c_ctrl_seq_base;
    `uvm_object_utils(fwvip_i2c_rand_seq)

    int unsigned  n_xacts   = 20;
    int unsigned  max_bytes = 8;
    int unsigned  read_pct  = 50;
    bit [6:0]     addrs[$];

    function new(string name = "fwvip_i2c_rand_seq");
        super.new(name);
    endfunction

    task body();
        repeat (n_xacts) begin
            fwvip_i2c_xact t;
            bit [6:0] a = (addrs.size() != 0) ? addrs[$urandom_range(addrs.size() - 1)] : rand_addr7();
            if ($urandom_range(99) < read_pct) begin
                read(t, a, $urandom_range(max_bytes, 1));
            end else begin
                bit [7:0] d[] = new[$urandom_range(max_bytes)];
                foreach (d[i]) d[i] = 8'($urandom);
                write(t, a, d);
            end
        end
    endtask
endclass
