# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

## 1. <!-- Task Group Name -->

- [ ] 1.1 <!-- Task description -->
- [ ] 1.2 <!-- Task description -->
- [ ] 1.3 Write `features/<domain>/<phase_1_name>.feature` covering this phase's worked examples
      (happy path + edge/error cases from design.md). Run it with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/<domain>/<phase_1_name>.feature` and
      confirm it passes before starting phase 2.

## 2. <!-- Task Group Name -->

- [ ] 2.1 <!-- Task description -->
- [ ] 2.2 <!-- Task description -->
- [ ] 2.3 Write `features/<domain>/<phase_2_name>.feature` covering this phase's worked examples.
      Run it with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/<domain>/<phase_2_name>.feature`
      and confirm it passes before starting phase 3.

<!-- Add further numbered phases as needed, each ending in its own feature file + a green run
     before the next phase starts. -->
