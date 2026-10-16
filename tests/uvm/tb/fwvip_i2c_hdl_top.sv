// HDL top: the kit's controller, target and monitor transactors on one
// open-drain bus, plus fwvip-core's clock and reset transactor interfaces.
// The wired-AND lives here, never in a transactor: a line reads low while
// any instance's _oe pulls it low.
module fwvip_i2c_hdl_top;

    reg clock = 0, reset = 1;
    always #5ns clock = ~clock;
    initial begin
        repeat (4) @(posedge clock);
        reset = 0;
    end

    fwvip_clock_xtor_if               u_clk_if (.clock(clock), .reset(reset));
    fwvip_reset_xtor_if #(.ACTIVE(1)) u_rst_if (.clock(clock), .reset(reset));

    wire ctl_scl_o, ctl_scl_oe, ctl_sda_o, ctl_sda_oe;
    wire tgt_scl_o, tgt_scl_oe, tgt_sda_o, tgt_sda_oe;

    wire scl = !(ctl_scl_oe || tgt_scl_oe);
    wire sda = !(ctl_sda_oe || tgt_sda_oe);

    i2c_controller_xtor u_ctl (
        .clock(clock), .reset(reset),
        .scl_o(ctl_scl_o), .scl_oe(ctl_scl_oe), .scl_i(scl),
        .sda_o(ctl_sda_o), .sda_oe(ctl_sda_oe), .sda_i(sda)
    );

    i2c_target_xtor u_tgt (
        .clock(clock), .reset(reset),
        .scl_o(tgt_scl_o), .scl_oe(tgt_scl_oe), .scl_i(scl),
        .sda_o(tgt_sda_o), .sda_oe(tgt_sda_oe), .sda_i(sda)
    );

    i2c_monitor_xtor u_mon (
        .clock(clock), .reset(reset),
        .scl_i(scl), .sda_i(sda)
    );

    // +fwvip_i2c_bus_trace prints every change on the bus and its drivers.
    initial if ($test$plusargs("fwvip_i2c_bus_trace")) forever begin
        @(scl or sda or ctl_scl_oe or ctl_sda_oe or tgt_scl_oe or tgt_sda_oe);
        $display("%t BUS scl=%b sda=%b ctl(scl_oe=%b sda_oe=%b) tgt(scl_oe=%b sda_oe=%b)",
                 $time, scl, sda, ctl_scl_oe, ctl_sda_oe, tgt_scl_oe, tgt_sda_oe);
    end
endmodule
