## Effect schedulers: the task walk once a retail frame at any frame rate (2026-11-20)

<!-- dll-build: 30261102_0 -->

- Retail walks the effect tasks once a frame, and each task's countdown takes the frame's ticks: FUN_10057e10 takes
  `DAT_1047d158 +0xeb0` (or the Vana'diel change DAT_1065dcc4 for a clock task) before its ops, carrying the overshoot
  into the next op's wait. FUN_10069f90 sets +0xeb0 each frame to FUN_10014cf0: whole ticks, at least 2 (30 fps),
  at most 20 (FUN_10011a00; MODLOG "Camera shake"). A new task's first step is the same whole update (FUN_100748c0 ->
  vtable +0x20), so it takes the frame's ticks too; so does a task caught up by FUN_10056b20, right after the skip.
- Ours stepped the tasks every frame of ours with that frame's ticks, and a new task's first step took none. At
  300 fps a wait could end up to a retail frame later than at 30 fps (a damage number's digits,
  `damv_life_by_frame_rate`), and at any rate every wait after a task's start was one retail frame longer than
  retail's.
- Now (`Effects::tick`, `walk_ticks` / `walk_owed`): a retail frame starts when our ticks have reached the last one's
  end; the walk runs at the first tick of ours in it, with its whole ticks (at least 2, our surplus carried, at most
  20), and a task started in that frame takes the same ticks for its first step. A task started before the walk of
  its frame (or a child it starts, in any slot) is passed by it, once a frame; inside the walk only a slot past the
  running task is; one started after the walk is stepped by the next. What the tasks own (holds, roots, pins, light
  ramps, colour drives) still counts down every tick of ours.
- Tests: the ones that stepped 1-tick frames now step retail frames (2 ticks) and count frames.
  `record_loop_same_frames_at_any_rate` (no DATs) checks the same retail frames at 30, 60, 120, 144 and 300 fps;
  `pending_scheduler_child_steps_on_the_next_retail_walk` and `child_in_earlier_slot_before_the_walk_is_passed` (no
  DATs) check the once-a-frame rule for nested starts. With DATs, the first step's ticks move `fist_hit_sparks`
  (three nested starts, each a frame shorter), `klbt_ends_bntg`, `clone_inherits_wait` (78) and Selbina's `pat2`
  (2 ticks ahead of the clock).
