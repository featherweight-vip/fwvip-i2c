// fwvip_i2c_xtor_pkg -- the consumer-side constants every fwvip-<proto> has.
// I2C is a fixed carrier (one byte plus an ACK bit per exchange), so there
// are no widths to thread: just the address width the kit's link carries
// and the reserved 7-bit address ranges (UM10204 Table 4, design.md §8
// issue 4), so the VIP's configs and sequences agree on what a legal
// target address is.
package fwvip_i2c_xtor_pkg;

    // The kit's link carries 10 address bits: 7-bit addresses in addr[6:0],
    // or a 10-bit one with addr_10b.
    localparam int ADDR_WIDTH_MAX = 10;

    // 0000xxx (general call, START byte, CBUS, other bus formats, Hs master
    // code) and 1111xxx (10-bit prefix, device ID) are reserved.
    function automatic bit fwvip_i2c_addr7_reserved(bit [6:0] a);
        return a[6:3] == 4'b0000 || a[6:3] == 4'b1111;
    endfunction

endpackage
