# Verification

There are two levels of testing: the VIP's back-to-back UVM bench, and the
kit's own sims and formal harness.

## The UVM bench (`tests/uvm/`)

On one wired-AND bus, the controller agent drives the kit's controller
transactor, the target agent runs `fwvip_i2c_mem_responder_seq` behind the
kit's target transactor (address `TGT_ADDR`), and the monitor agent watches
the bus. One image; each case is a `+SEQ=<sequence>` on
`fwvip_i2c_b2b_test` (or a test subclass). A 50 ms UVM timeout turns a
wedged bus into a failure.

The scoreboard (`fwvip_i2c_b2b_sb`) makes two checks on every case:

Bus
: each transaction the controller completed must match, in order, the
  monitor's reconstruction from the pins (`same_bus`: status, addresses,
  every byte and every ACK bit). At the end, nothing may be left unpaired.

Data
: every byte read from the target must match a reference model of the
  memory responder, built from the controller's completed writes.

The test also fails if the scoreboard matched no transaction at all, and
the monitor agent fails it on any out-of-order bus event.

| Case | What it does |
|---|---|
| `smoke` | writes 4 bytes at an offset, reads them back with a random read, and reads across written and unwritten bytes |
| `addr_nack` | writes and reads to addresses nobody answers end in `ADDR_NACK` + STOP; the bus still works afterwards |
| `data_nack` | the target NACKs the third data byte of a write: `DATA_NACK` at byte 3, earlier bytes stored, the NACKed one not |
| `stretch` | the target takes 5–40 cycles over every decision (SCL held low each time); 12 random transactions |
| `rand_traffic` | 40 random writes/reads of 0–8 bytes, mostly to the target and some to an absent address, with 0–8 cycles of stretch |
| `mon_teeth` | clean traffic, then events no legal bus produces (a byte and a STOP outside a transaction, a data byte after a NACK) are fed to the monitor agent, which must flag each one |

`mon_teeth` is there so that the monitor's checks are known to fire: if the
agent stopped checking, every other case would still pass.

All six pass (`dfm run tests`). CI runs `smoke` and `mon_teeth` on every
push.

## The kit (`packages/fw-proto-i2c/tests/`)

| Component | Covers |
|---|---|
| `i2c_proto_tb` | the required back-to-back sim: controller and target transactors on one bus |
| `arb/i2c_arb_tb` | two controllers start at the same time against one target; the one addressing 0x60 must lose arbitration to the one addressing 0x10, which is unaffected (design.md §8 issue 1) |
| `formal/i2c_proto_fv` | a BMC of a controller core and a target core on a real open-drain bus; invariants and cover goals in `tests/formal/PROPERTIES.md` (design.md §8 issue 2) |

## What testing found

The UVM bench's bus scoreboard found a kit bug that the kit's own sims had
missed. After a STOP, the controller core kept driving SDA from the last
written byte's MSB, so a write ending in a byte with MSB 0 produced a
spurious START/STOP pair. The bug is fixed in the kit, and `i2c_proto_tb`
now ends a write with 0x3C, so its STOP count catches a regression.

Open, from the kit's formal harness: **the target core misses bit 0 after
an ACK when SCL is low for only one of its clocks.** The BMC fails at step 68
with all timing parameters at 1 and passes at `T_LOW = 2`. The sims and this
bench run at `T_LOW = 4`, which hides the bug. A fix (in the target core) or a
documented minimum oversampling ratio is still to be decided; see
`PROPERTIES.md`.

## Not covered yet

- **Repeated START**: the v1 target core cannot tell a repeated START from
  the start of another data byte, so no case uses multi-segment items.
- **10-bit addressing**: not implemented by the v1 cores.
- **Arbitration at the UVM level**: the kit's `i2c_arb_tb` covers it, but
  the bench has one controller, and the kit monitor core does not report
  arbitration loss.
- Hs-mode, Ultra Fast mode, SMBus, general call, and timing-violation
  detection: see {doc}`open-issues` and design.md §8.
