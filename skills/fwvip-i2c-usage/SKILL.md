---
name: fwvip-i2c-usage
description: Connect and drive the fwvip-i2c Verification IP — bind its controller, target and
  monitor agents into a UVM env (register macros + config DB), write controller sequences and
  target responders, and subscribe to the monitor's reconstructed transactions. Use when
  integrating fwvip-i2c into a testbench or generating I2C stimulus with it.
tools: Read, Write, Edit, Bash, Grep, Glob
---

# fwvip-i2c — usage

The UVM layer over the `fw-proto-i2c` transactor kit (7-bit addressing,
Standard/Fast/Fast-plus timing set by the kit cores' parameters). Package
`fwvip_i2c_pkg`; DFM export `org.fwvip.i2c.vip-uvm-hvlsrc` (it pulls in
`fw.proto.i2c.class`, the kit's transactors and bridges, and
`org.fwvip.core.core-uvm-pkg`). A bench also needs
`org.fwvip.core.clock-reset-xtor` for the clock/reset providers.

## What it provides

| Role | Agent | Config (config DB "cfg") | Shape |
|---|---|---|---|
| Controller | `fwvip_i2c_ctrl_agent` | `fwvip_i2c_ctrl_config` (it is the kit's `i2c_controller_if`) | active: `fwvip_i2c_xact` items on `m_seqr`; `ap` publishes each completed item |
| Target | `fwvip_i2c_tgt_agent` | `fwvip_i2c_tgt_config` (it is the kit's `i2c_target_if`; holds `addr`, `addr_mask`) | responder: a `fwvip_i2c_tgt_seq` subclass running on `m_seqr` answers each bus event |
| Monitor | `fwvip_i2c_mon_agent` | `fwvip_i2c_mon_config` (it is the kit's `i2c_monitor_if`) | passive: `ap` publishes one `fwvip_i2c_xact` per STOP; checks event order (`I2C_MON` errors) |

`fwvip_i2c_xact`: `seg[$]` of `fwvip_i2c_segment` (`addr`, `read`,
`data[]`, `addr_ack`, `ack[]`), plus `status` (`FWVIP_I2C_OK`,
`_ADDR_NACK`, `_DATA_NACK`, `_ARB_LOST`) and `nack_seg`/`nack_byte`. After
a run, `data` holds exactly what crossed the bus and `ack[i]` is the bit
after `data[i]`. `same_bus(o, why)` compares two items (the controller's
and the monitor's view of one transaction should match).

## Wiring

HDL top: the kit's wrappers on a wired-AND bus you model yourself:

```sv
wire scl = !(ctl_scl_oe || tgt_scl_oe);
wire sda = !(ctl_sda_oe || tgt_sda_oe);
i2c_controller_xtor u_ctl (.clock, .reset, .scl_o(ctl_scl_o), .scl_oe(ctl_scl_oe), .scl_i(scl),
                           .sda_o(ctl_sda_o), .sda_oe(ctl_sda_oe), .sda_i(sda));
i2c_target_xtor     u_tgt (/* same, tgt_* */);
i2c_monitor_xtor    u_mon (.clock, .reset, .scl_i(scl), .sda_i(sda));
fwvip_clock_xtor_if               u_clk_if (.clock, .reset);
fwvip_reset_xtor_if #(.ACTIVE(1)) u_rst_if (.clock, .reset);
```

HVL top (`include "fwvip_i2c_macros.svh"`):

```sv
`fwvip_i2c_ctrl_register(hdl.u_ctl.u_if, "uvm_test_top.m_env.m_ctrl*")
`fwvip_i2c_tgt_register(hdl.u_tgt.u_if,  "uvm_test_top.m_env.m_tgt*", 7'h50)
`fwvip_i2c_mon_register(hdl.u_mon.u_if,  "uvm_test_top.m_env.m_mon*")
fwvip_clock_config_p #(virtual fwvip_clock_xtor_if)::set(null, "uvm_test_top.m_env*", "clock", hdl.u_clk_if);
fwvip_reset_config_p #(virtual fwvip_reset_xtor_if #(1))::set(null, "uvm_test_top.m_env*", "reset", hdl.u_rst_if);
run_test();
```

The target agent picks up "clock" (optional) for responder latency. Wait
for reset (`fwvip_reset_config::wait_reset()`) before stimulus.

## Driving the controller

Extend `fwvip_i2c_ctrl_seq_base`: `write(t, addr7, data[])`,
`read(t, addr7, n)` (the last byte read is NACKed), `do_xact(t)` for a
hand-built item (`t.add_write(...)`, `t.add_read(...)`). Ready-made:
`fwvip_i2c_write_seq`, `fwvip_i2c_read_seq`, `fwvip_i2c_rand_seq`
(`n_xacts`, `max_bytes`, `read_pct`, `addrs`). `rand_addr7()` avoids the
reserved ranges (`fwvip_i2c_addr7_reserved` in `fwvip_i2c_xtor_pkg`).

On a NACK the driver issues STOP; on arbitration loss it does not (the
core has released the bus) and the caller retries.

## Writing a target responder

Extend `fwvip_i2c_tgt_seq` and override `addressed(addr, addr_10b, read,
ack)`, `rx_byte(data, ack)` (a write byte; return its ACK) and
`tx_byte(data, ack)` (supply a read byte). Start it in the background:
`fork resp.start(env.m_tgt.m_seqr); join_none`. The config NACKs
addresses that do not match `addr`/`addr_mask` without calling you. While
your task blocks, the target core holds SCL low (clock stretching).

`fwvip_i2c_mem_responder_seq` is an EEPROM-style model: 256 bytes, the
first write byte sets the pointer, later writes and every read advance it;
`lat_min`/`lat_max` cycles of stretch per decision; `nack_at` NACKs that
write byte; `init_byte(off)` is what unwritten bytes read as.

## Example and commands

`tests/uvm/` is a runnable back-to-back bench (env with a bus + data
scoreboard, six cases):

```sh
dfm run tests                     # smoke addr_nack data_nack stretch rand_traffic mon_teeth
dfm run tests --tests stretch
dfm run smoke
```

Plusargs: `+fwvip_i2c_mon_trace` (each reconstructed transaction),
`+fwvip_i2c_bus_trace` (every bus edge, from the bench's HDL top).

## Pitfalls

- **Repeated START is not usable yet.** The v1 kit target core does not
  tell an Sr from another data byte. Multi-segment items are modeled but
  untested; use write + STOP + read for a register read.
- **10-bit addressing is not implemented** by the v1 cores; keep
  `addr_10b = 0`.
- **No responder running ⇒ a hung bus.** An addressed target waits for
  its responder with SCL held low. Start one before stimulus; set a UVM
  timeout.
- **Target timing minimum.** The kit target core misses a bit when SCL is
  low for only one of its clocks after an ACK (fw-proto-i2c
  `tests/formal/PROPERTIES.md`). The default core timing (`T_LOW=4`) is
  well clear of it.
- Don't rebuild the kit: transactors, bridges and role APIs are
  `fw-proto-i2c`'s.
