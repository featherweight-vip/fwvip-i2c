# Integration

A bench instantiates the kit's transactors on a wired-AND bus (HDL top),
binds each one to a VIP agent through the config DB (HVL top), and builds
the agents in its env. `tests/uvm/` is a complete example.

## Roles

| Role | Agent | Config DB `"cfg"` | Shape |
|---|---|---|---|
| Controller | `fwvip_i2c_ctrl_agent` | `fwvip_i2c_ctrl_config` (the kit's `i2c_controller_if`) | active: `fwvip_i2c_xact` items on `m_seqr`; `ap` publishes each completed item |
| Target | `fwvip_i2c_tgt_agent` | `fwvip_i2c_tgt_config` (the kit's `i2c_target_if`; `addr`, `addr_mask`) | responder: a `fwvip_i2c_tgt_seq` subclass on `m_seqr` answers each bus event |
| Monitor | `fwvip_i2c_mon_agent` | `fwvip_i2c_mon_config` (the kit's `i2c_monitor_if`) | passive: `ap` publishes one `fwvip_i2c_xact` per STOP |

Each config is the seam between UVM and the kit: an abstract class the
agent depends on, and a vif-aware `*_config_p` that holds the transactor's
`u_if` and runs the kit's bridge. The register macros create the `_p`
specialization for you.

## DFM

```yaml
- name: my-env
  needs:
  - org.fwvip.i2c.vip-uvm-hvlsrc      # fwvip_i2c_pkg; pulls in fw.proto.i2c.class
  - org.fwvip.core.core-uvm-pkg
  - org.fwvip.core.clock-reset-xtor    # the HDL top's clock/reset interfaces
```

## HDL top

The kit's transactors have open-drain pad pins (`*_o`, `*_oe`, `*_i`). The
bus is modeled in the top, never in a transactor: a line reads low while
any instance pulls it low (`*_oe = 1`).

```systemverilog
wire ctl_scl_o, ctl_scl_oe, ctl_sda_o, ctl_sda_oe;
wire tgt_scl_o, tgt_scl_oe, tgt_sda_o, tgt_sda_oe;
wire scl = !(ctl_scl_oe || tgt_scl_oe);
wire sda = !(ctl_sda_oe || tgt_sda_oe);

i2c_controller_xtor u_ctl (.clock, .reset,
    .scl_o(ctl_scl_o), .scl_oe(ctl_scl_oe), .scl_i(scl),
    .sda_o(ctl_sda_o), .sda_oe(ctl_sda_oe), .sda_i(sda));
i2c_target_xtor u_tgt (.clock, .reset,
    .scl_o(tgt_scl_o), .scl_oe(tgt_scl_oe), .scl_i(scl),
    .sda_o(tgt_sda_o), .sda_oe(tgt_sda_oe), .sda_i(sda));
i2c_monitor_xtor u_mon (.clock, .reset, .scl_i(scl), .sda_i(sda));

fwvip_clock_xtor_if               u_clk_if (.clock, .reset);
fwvip_reset_xtor_if #(.ACTIVE(1)) u_rst_if (.clock, .reset);
```

To verify a DUT, replace one of the transactors with the DUT's pads and add
its `*_oe` terms to the AND. Any number of controllers and targets can share
the bus this way.

## HVL top

```systemverilog
`include "uvm_macros.svh"
`include "fwvip_i2c_macros.svh"

initial begin
    `fwvip_i2c_ctrl_register(hdl.u_ctl.u_if, "uvm_test_top.m_env.m_ctrl*")
    `fwvip_i2c_tgt_register(hdl.u_tgt.u_if,  "uvm_test_top.m_env.m_tgt*", 7'h50)
    `fwvip_i2c_mon_register(hdl.u_mon.u_if,  "uvm_test_top.m_env.m_mon*")
    fwvip_clock_config_p #(virtual fwvip_clock_xtor_if)::set(
        null, "uvm_test_top.m_env*", "clock", hdl.u_clk_if);
    fwvip_reset_config_p #(virtual fwvip_reset_xtor_if #(1))::set(
        null, "uvm_test_top.m_env*", "reset", hdl.u_rst_if);
    run_test();
end
```

The target macro's third argument is its 7-bit address. For a mask, call
`fwvip_i2c_tgt_config_p #(virtual i2c_target_xtor_if)::set(null, inst,
"cfg", vif, addr, addr_mask)` directly. Every `set()` returns the config, so
you can adjust fields such as `allow_reserved` before the run.

## Env

```systemverilog
m_ctrl = fwvip_i2c_ctrl_agent::type_id::create("m_ctrl", this);
m_tgt  = fwvip_i2c_tgt_agent::type_id::create("m_tgt", this);
m_mon  = fwvip_i2c_mon_agent::type_id::create("m_mon", this);
// connect_phase:
m_ctrl.ap.connect(m_sb.ctrl_export);
m_mon.ap.connect(m_sb.mon_export);
```

The target agent also picks up `"clock"` (a `fwvip_clock_config`) if one is
set. Responders use it to count clock-stretch latency in cycles.

Before stimulus:

1. wait for reset (`fwvip_reset_config::wait_reset()`);
2. start a responder on every target agent in the background
   (`fork resp.start(m_tgt.m_seqr); join_none`).

An addressed target with no responder holds SCL low until one runs, so the
bus waits forever. Set a UVM timeout (`uvm_root::get().set_timeout(...)`) so
that a wedged bus fails the test instead of hanging it.

## Checking

The controller's and the monitor's items have the same shape, so comparing
them in order checks that the bus carried what the controller meant to send:
`c.same_bus(m, why)` compares status, addresses, every byte and every ACK
bit. The monitor agent also checks event order itself (errors with id
`I2C_MON`; see {doc}`reference`). The bench's scoreboard,
`tests/uvm/env/fwvip_i2c_b2b_sb.svh`, does both this and a data check
against a model of the memory responder.
