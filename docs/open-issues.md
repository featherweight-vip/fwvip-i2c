# Open issues

This package intentionally has **no L1-equivalent layer** initially
(design.md §6) — unlike `fwvip-chi`, whose CHI flits are a natural
stand-alone unit, I2C's natural stand-alone unit is already the
byte-with-ACK the monitor exposes.

The full list of open design questions (multi-master back-to-back test
shape, the formal `PROPERTIES.md` invariant mining pass, Hs-mode/Ultra Fast
mode, 10-bit/reserved-address handling, SMBus scoping, timing-violation
detection, a DUT register-model follow-on package, general-call handling,
and revisiting the L1 decision) lives in [`design.md`](design.md) §8 and is
not duplicated here — read that section for the current state and
recommendations.
