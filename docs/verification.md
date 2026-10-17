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
| `repeated_start` | transactions of two and three segments joined by Sr: write then read (a random read with no STOP), write then write then read, read then write; an Sr to an absent address (`ADDR_NACK` in segment 1, the write before it stored); a data NACK before an Sr (STOP, the read segment dropped) |
| `addr_10b` | 10-bit addressing (the target answers `TGT_ADDR10` = 0x2a5 as well as 0x50, with one memory behind both): a write and a read back, a pointer write then Sr and a read in one transaction, a 7-bit write then Sr and a 10-bit read, a 10-bit write of no bytes then Sr and a read, and addresses NACKed at the first header byte and at the second, writing and reading |
| `rand_traffic` | 40 random transactions of 1–3 segments (an Sr follows a segment 25% of the time), each a write or read of 0–8 bytes, mostly to the target and some to an absent address, a quarter of them 10-bit, with 0–8 cycles of stretch |
| `mon_teeth` | clean traffic, then events no legal bus produces (a byte and a STOP outside a transaction, a data byte after a NACK) are fed to the monitor agent, which must flag each one |

`mon_teeth` is there so that the monitor's checks are known to fire: if the
agent stopped checking, every other case would still pass.

All eight pass (`dfm run tests`). CI runs `smoke` and `mon_teeth` on every
push, and all eight nightly.

The kit's CI runs its sims, lint and `fv-quick` on every push: the
back-to-back BMC at depth 45 plus the clock-sync BMC, about a minute.
The depth-80 BMC (about 30 minutes) and the covers run nightly.

## The kit (`packages/fw-proto-i2c/tests/`)

| Component | Covers |
|---|---|
| `i2c_proto_tb` | the required back-to-back sim: controller and target transactors on one bus, including repeated START after a write, after a read and after a NACKed address, and 10-bit addressing (write, read, a 10-bit read after an Sr, a NACK at either header byte) |
| `i2c_proto_fast_tb` | the same case with every controller timing phase at 1 clock, the fastest bus the cores support |
| `arb/i2c_arb_tb` | two controllers start at the same time against one target; the one addressing 0x60 must lose arbitration to the one addressing 0x10, which is unaffected (design.md §8 issue 1) |
| `arb/i2c_arb_sync_tb` | the same collision with the two controllers at different `T_LOW`/`T_HIGH`, sharing seven address bits: clock synchronization (UM10204 §3.1.7). Each contended SCL low phase must last the longer `T_LOW`, and each contended high phase at most the shorter `T_HIGH` |
| `formal/i2c_proto_fv` | a BMC of a controller core and a target core on a real open-drain bus; invariants and cover goals in `tests/formal/PROPERTIES.md` (design.md §8 issue 2) |
| `formal/i2c_ctl_sync_fv` | a BMC of the controller core alone, with a free other device on SCL and SDA: it counts high time only while SCL reads high, and every low phase is a full `T_LOW` |

## What testing found

The UVM bench's bus scoreboard found a kit bug that the kit's own sims had
missed. After a STOP, the controller core kept driving SDA from the last
written byte's MSB, so a write ending in a byte with MSB 0 produced a
spurious START/STOP pair. The bug is fixed in the kit, and `i2c_proto_tb`
now ends a write with 0x3C, so its STOP count catches a regression.

The kit's formal harness found that **the target core lost bit 7 of the
byte after an ACK when SCL was low for only one of its clocks.** After the
ACK, the target sampled the same low phase twice: once to see the ACK end,
and again to start the next byte. With a 1-clock low, the second sample
already saw SCL high, so the target came in one bit late. The read path had
the same bug, and so did the monitor core. All three now start the next byte
on the fall itself, so a 1-clock low or high phase is enough. Two
regressions guard the fix:

- `i2c_proto_fast_tb` runs the back-to-back sim at 1-clock timing. It
  starts with a read, so a broken read path can't be hidden by a broken
  write.
- The formal harness gained a read-direction integrity check, invariant 7.

This bench runs at the default timing (`T_LOW = 4`), which hid the bug.

Adding repeated START showed that the kit's "known gap" was not real. The
target core takes the SCL drop before an Sr as the start of a data byte,
and the Sr edge then overrides that, as for a STOP. The kit sims, the
formal harness (an Sr cover goal, plus invariants 8 and 9 on START/STOP
edges and address integrity) and the `repeated_start` case here now cover
it. The same work found that the formal harness's `u_ctl.*` hierarchical
references had always been undriven constants in the sv2v + yosys flow, so
the old arbitration invariant checked nothing. The harness now uses ports
only (`tests/formal/PROPERTIES.md`).

The controller didn't synchronize its clock with another controller's
(UM10204 §3.1.7). It counted `T_HIGH` without watching SCL, so when a
controller with a shorter high phase pulled SCL low, this one kept counting
high through the other's low phase. With different enough timings the two
then disagree on which bit they are on, which `i2c_arb_sync_tb` shows as a
lost address ACK. The high phase now also ends when SCL reads low. Writing
that test also found that the low phase after a START and the one before a
STOP lasted `T_HD_STA`, not `T_LOW`, and that the START setup and hold
counts were swapped. Both are fixed. The formal harness's bit-count
invariants (2 and 3), dropped when the hierarchical references turned out
to be dead, are back on a formal-only debug output of the controller core.

10-bit addressing (UM10204 §3.1.11) is in the cores now. A 10-bit
`start()` sends the whole header itself, including the Sr and read header
for a read. The target asks its model about the first byte through a new
`i2c_target_if` method, `addressed_10b_hi()`, and remembers an ACKed write
header for the read header that follows. The monitor core flags the
header's second byte as an address byte. The first `rand_traffic` run with
10-bit segments showed one wrong assumption in the bench: a 10-bit read
NACKed before its read header puts only a write header on the bus, so the
monitor sees a write. `same_bus` now compares only A9:A8 for a NACKed
10-bit address. Formal invariant 9 checks the 10-bit address phases, with
cover goals for a 10-bit write and read header.

## Not covered yet
- **Arbitration at the UVM level**: the kit's `i2c_arb_tb` covers it, but
  the bench has one controller, and the kit monitor core does not report
  arbitration loss. See {doc}`arbitration` for the plan.
- Hs-mode, Ultra Fast mode, SMBus, general call, and timing-violation
  detection: see {doc}`open-issues` and design.md §8.
