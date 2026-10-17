# Open issues

## v1 limitations

What the current kit and VIP do not do, and where each limitation shows up:

- **Bus timing has a fixed shape per instance.** The controller's `T_*`
  parameters set the length of each phase, in ticks. The rate is set at
  runtime with `set_prescale()` (one tick = prescale+1 clocks), so the
  same instance can run Sm and Fm, but the ratio between the phases
  cannot change at runtime. Separate runtime `cfg_*` values per phase, as
  design.md §5 proposed, are not implemented (see {doc}`reference`).
- **Arbitration loss is not reported by the monitor core**, so the monitor
  agent cannot publish `ARB_LOST`. The UVM bench has one controller; only
  the kit's `i2c_arb_tb` exercises arbitration. {doc}`arbitration` proposes
  how to add it to the bench. It also finds that the controller core
  doesn't track bus busy, and argues that the monitor can't infer a loss
  from the pins.
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
`PROPERTIES.md`) are done in the kit, and so is the 10-bit half of issue 4;
its reserved-address half is still open.
