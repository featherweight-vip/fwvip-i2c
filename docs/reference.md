# Reference

## Packages and DFM exports

| Export | Package | Contents |
|---|---|---|
| `org.fwvip.i2c.xtor-pkg` | `fwvip_i2c_xtor_pkg` | `ADDR_WIDTH_MAX` (10), `fwvip_i2c_addr7_reserved()` |
| `org.fwvip.i2c.vip-uvm-hvlsrc` | `fwvip_i2c_pkg` | the agents, items and sequences below; needs `fw.proto.i2c.class` and `org.fwvip.core.core-uvm-pkg` |

The register macros are in `fwvip_i2c_macros.svh`, which is on the
`vip-uvm-hvlsrc` include path.

## Constants and types

`fwvip_i2c_addr7_reserved(a)`
: true for `0000xxx` (general call, START byte, CBUS, other bus formats,
  Hs master code) and `1111xxx` (10-bit prefix, device ID), per UM10204
  Table 4. `rand_addr7()` avoids these addresses, and a target config
  refuses them unless `allow_reserved` is set.

`fwvip_i2c_status_e`
: `FWVIP_I2C_OK`, `FWVIP_I2C_ADDR_NACK`, `FWVIP_I2C_DATA_NACK`,
  `FWVIP_I2C_ARB_LOST`.

## Register macros

```systemverilog
`fwvip_i2c_ctrl_register(vif, inst)        // vif: an i2c_controller_xtor's u_if
`fwvip_i2c_tgt_register(vif, inst, addr)   // vif: an i2c_target_xtor's u_if; addr: 7 bits
`fwvip_i2c_mon_register(vif, inst)         // vif: an i2c_monitor_xtor's u_if
```

Each one sets the role's `*_config_p` under `"cfg"` for the agents
matching `inst`.

## Classes

### Items

| Class | Members |
|---|---|
| `fwvip_i2c_segment` | `addr[9:0]`, `addr_10b`, `read`, `data[]`, `addr_ack`, `ack[]`; `convert2string()`, `same_bus(o, why)` |
| `fwvip_i2c_xact` | `seg[$]`, `status`, `nack_seg`, `nack_byte`; `add_write(addr, data, addr_10b=0)`, `add_read(addr, n, addr_10b=0)`, `convert2string()`, `same_bus(o, why)` |

A segment with `addr_10b` set has a 10-bit address (UM10204 §3.1.11). The
kit's controller core sends the whole header for one: `11110 A9 A8 W` and
`addr[7:0]`, and for a read also an Sr and `11110 A9 A8 R`. Each header
byte is sent only if the one before it was ACKed, and `addr_ack` is the
ACK of the last one sent. A segment prints as `W 0x2a5/10`. For a NACKed
10-bit address, `same_bus` compares only A9:A8, because the header stopped
at the NACK and the rest never reached the bus.
| `fwvip_i2c_tgt_item` | `handler` (the responder); internal to the target agent |

### Controller

| Class | Notes |
|---|---|
| `fwvip_i2c_ctrl_config` / `_config_p #(vif_t)` | implements `i2c_controller_if` (`start`, `tx_byte`, `rx_byte`, `stop`); `_p` forwards to an `i2c_controller_xtor_bridge`, built on first use |
| `fwvip_i2c_ctrl_driver` | runs each item as per-byte calls; fills its results; `ap`, `n_done` |
| `fwvip_i2c_ctrl_agent` | `m_cfg`, `m_seqr` (`fwvip_i2c_ctrl_sequencer`), `m_driver`, `ap` |
| `fwvip_i2c_ctrl_seq_base` | `do_xact`, `write`, `read`, `write_read` (each with a trailing `addr_10b = 0`), `rand_addr7`, `rand_addr10` |
| `fwvip_i2c_write_seq`, `_read_seq`, `_rand_seq` | see {doc}`sequences` |

### Target

| Class | Notes |
|---|---|
| `fwvip_i2c_tgt_config` / `_config_p #(vif_t)` | implements `i2c_target_if`. `addr` (0x50), `addr_mask` (0x7f), `allow_reserved` (0), `addr_match(a)`; for a 10-bit address as well, `addr10_en` (0), `addr10`, `addr10_mask` (0x3ff), `addr10_match(a)`. Addresses that don't match are NACKed here, and so is the first byte of a 10-bit header whose A9:A8 don't match (`addressed_10b_hi`). Everything else goes to the responder. `_p::set(ctxt, inst, field, vif, addr, addr_mask)` |
| `fwvip_i2c_tgt_driver` | starts the config (and so the kit bridge); hands each bus event to the responder from the sequencer; `n_served` |
| `fwvip_i2c_tgt_agent` | `m_cfg`, `m_clock` (optional `"clock"`), `m_seqr` (`fwvip_i2c_tgt_sequencer`), `m_driver` |
| `fwvip_i2c_tgt_seq` | base responder; see {doc}`sequences` |
| `fwvip_i2c_mem_responder_seq` | EEPROM-style memory; see {doc}`sequences` |

### Monitor

| Class | Notes |
|---|---|
| `fwvip_i2c_mon_config` / `_config_p #(vif_t)` | implements `i2c_monitor_if`; forwards each event to the agent; `_p` runs an `i2c_monitor_xtor_bridge` |
| `fwvip_i2c_mon_agent` | coalesces events into `fwvip_i2c_xact` and publishes on `ap` at each STOP. A 10-bit header becomes one segment: the write header's two bytes, and for a read, the Sr and read header after a write header with no data bytes, which is what the kit's controller sends. A read header after a 10-bit write that moved data starts a read segment of its own, at that write's address |

`fwvip_i2c_mon_agent` members: `check_enable` (1), `check_quiescent_at_end`
(1), `n_xacts`, `n_errors`, `last_error`, `in_txn()`, `clear()`. It reports
these as `UVM_ERROR` with id `I2C_MON`:

- a STOP, repeated START or byte outside a transaction;
- a data byte before any address byte;
- a data byte after a NACK (the controller must STOP or Sr);
- a START while a transaction is open;
- a data byte where a 10-bit header's `addr[7:0]` belongs;
- at `check_phase`, a transaction still open.

Status follows the controller's: `ADDR_NACK` for a NACKed address byte,
`DATA_NACK` for a NACKed write byte. A read's last byte is NACKed by design
and is not an error. The v1 kit monitor core does not report arbitration
loss, so `observe_arb_lost()` does nothing.

## Kit transactors

From `fw-proto-i2c` (`fw.proto.i2c.xtor-sv`):

| Module | Pins |
|---|---|
| `i2c_controller_xtor` | `clock`, `reset`, `scl_{o,oe,i}`, `sda_{o,oe,i}` |
| `i2c_target_xtor` | same |
| `i2c_monitor_xtor` | `clock`, `reset`, `scl_i`, `sda_i` |

The register macros bind each wrapper's `u_if`.

`i2c_controller_xtor` sets the bus timing with parameters, counted in
ticks: `T_LOW` (4), `T_HIGH` (4), and `T_HD_STA`, `T_SU_STA`, `T_SU_STO`,
`T_BUF` (2 each). A tick is prescale+1 core clocks. `prescale` is a runtime
setting, made through the controller API's `set_prescale(bit [15:0])`
(the agent config forwards it). Its default is 0, which makes a tick one
clock. Each phase lasts exactly `T_*` × (prescale+1) clocks. The SCL
checks (stretch wait, clock synchronization, arbitration) still run on
every clock. Set the prescale only between transactions. Every `T_*` value
down to 1 works at prescale 0: the target and monitor cores follow SCL low
or high phases as short as one of their clocks. Separate runtime values per
phase (the `cfg_*` inputs proposed in design.md §5) are not implemented.
