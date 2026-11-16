## The macro gate inside mod calls sees mod windows (2026-11-16)

- `game.info().macros` (and `menu_open`) count a mod window with the keys as a focused window (FUN_101a33e0's
  focus test). But every mod call moves the host out of the World first (`std::mem::take(&mut w.lua)`), so the
  World read from inside a pad / key filter or the mod phase held an empty host, and a focused mod window never shut
  the gate there. A crossbar mod's filter then fired slots while another window (its own manager) had the keys.
- `Host::lend` now leaves a host behind that answers `focused()` as the real one did when the call began.
