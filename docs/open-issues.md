# Open issues

## v1 limitations

What the current kit and VIP do not do, and where each limitation shows up:

- **Repeated START.** The v1 target core cannot tell a repeated START from
  the start of another data byte (see the header of
  `i2c_target_xtor_core.sv`). `fwvip_i2c_xact` models multi-segment
  transactions, but nothing exercises them. Use write + STOP + read instead.
- **Target timing minimum.** The target core misses a bit when SCL is low
  for only one of its clocks after an ACK. The kit's formal harness found
  this; see {doc}`verification`. A fix to the core, or a documented minimum
  oversampling ratio, is still to be decided.
- **Bus timing is fixed per wrapper.** The controller core's `T_*`
  parameters are not passed through `i2c_controller_xtor`, and the runtime
  `cfg_*` timing of design.md §5 is not implemented (see {doc}`reference`).
- **10-bit addressing** is not implemented by the cores. The target config
  NACKs 10-bit addresses.
- **Arbitration loss is not reported by the monitor core**, so the monitor
  agent cannot publish `ARB_LOST`. The UVM bench has one controller; only
  the kit's `i2c_arb_tb` exercises arbitration.
- **Reserved addresses** get no special handling. A target config refuses
  one unless `allow_reserved` is set, and `rand_addr7()` avoids them.

## Design questions

This package intentionally has **no L1-equivalent layer** initially
(design.md §6). Unlike `fwvip-chi`, whose CHI flits are a natural
stand-alone unit, I2C's natural stand-alone unit is already the
byte-with-ACK that the monitor exposes.

The other open design questions are in [`design.md`](design.md) §8: Hs-mode
and Ultra Fast mode, 10-bit and reserved-address handling, SMBus scoping,
timing-violation detection, a DUT register-model follow-on package,
general-call handling, and revisiting the L1 decision. They are not
duplicated here. Issues 1 and 2 of §8 (the arbitration test and the formal
`PROPERTIES.md`) are done in the kit.
