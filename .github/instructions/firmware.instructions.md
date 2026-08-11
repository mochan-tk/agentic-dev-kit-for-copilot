---
applyTo: "firmware/**"
---

# Firmware Rules (PlatformIO / embedded targets)

<!-- CUSTOMIZE: Adjust the `applyTo` glob above and the board/env names below
     to match this repository. Delete this file if the project has no firmware. -->

## Environment reality

- Cloud agents and CI runners have **no physical device**: no serial port, no
  flashing, no sensors. Anything that needs real hardware belongs to a task
  labeled `exec:ide` (see `.github/skills/task-routing/SKILL.md`). Never mark a
  hardware-dependent acceptance criterion as verified from a cloud environment.
- Host-side verification that *is* possible anywhere: `pio run -e <env>`
  (build) and `pio test -e native` (unit tests in the `native` environment).

## Design for testability

- Keep business logic (state machines, protocol parsing, message formatting)
  behind hardware-abstraction interfaces so it compiles and runs in the
  `native` env. Hardware access lives in thin adapter layers.
- Every new logic module ships with at least one `native` test. Tests are what
  allow agents to work on this code autonomously; untested firmware logic
  forces every change back to a human with a device.

## Coding constraints

- Respect the memory budget of the target MCU: prefer static allocation,
  avoid unbounded `String`/heap growth in long-running loops, and document any
  buffer size assumptions next to the buffer.
- No blocking waits in the main loop beyond <!-- CUSTOMIZE: threshold, e.g. 50 ms -->;
  use non-blocking patterns or the project's scheduler.
- Pin assignments, credentials, and endpoints come from `platformio.ini`
  build flags or config headers — never hard-code them in logic files.
- When changing `platformio.ini`, state in the PR which envs were rebuilt and
  paste the resulting RAM/Flash usage lines as evidence.
