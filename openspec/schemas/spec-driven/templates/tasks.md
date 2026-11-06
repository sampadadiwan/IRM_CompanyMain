# Tasks

> **Phase gate:** each numbered group below is a phase. A phase ends with three tasks, in order:
> (a) **UI review** — when the phase adds or changes screens: screenshot each one next to the
> reference screen named in design.md's *Screen standards* and apply the UI self-review checklist
> (breadcrumbs, lazy tabs, Turbo streams, stats cards, filters, Actions dropdown, tooltips/help,
> full width); (b) **N+1 check** — run the phase's features under Prosopite and fix every N+1 in
> this change's code; (c) run the phase's Cucumber features green. Do not start the next phase
> until all three pass — fix the phase you're on rather than coming back later.

## 1. <!-- Task Group Name -->

- [ ] 1.1 <!-- Task description -->
- [ ] 1.2 <!-- Task description -->
- [ ] 1.3 Write `features/<domain>/<phase_1_name>.feature` covering this phase's worked examples
      (happy path + edge/error cases from design.md, or business-rules.md when the change has one).
- [ ] 1.4 UI review (if this phase adds/changes screens): screenshots of each screen beside its
      reference screen from design.md *Screen standards*; fix anything that differs.
- [ ] 1.5 N+1 check: `PROSOPITE=1 TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/<domain>/<phase_1_name>.feature`,
      then read `log/prosopite.log`; fix every N+1 whose stack is in this change's code (truncate the
      log first; never commit it).
- [ ] 1.6 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/<domain>/<phase_1_name>.feature`
      (wait on the run's PID, never a pgrep loop) and confirm it passes before starting phase 2.

## 2. <!-- Task Group Name -->

- [ ] 2.1 <!-- Task description -->
- [ ] 2.2 <!-- Task description -->
- [ ] 2.3 Write `features/<domain>/<phase_2_name>.feature` covering this phase's worked examples.
- [ ] 2.4 UI review (if screens changed) against design.md *Screen standards*.
- [ ] 2.5 N+1 check under Prosopite; fix every N+1 in this change's code.
- [ ] 2.6 Run the phase's features green before starting phase 3.

<!-- Add further numbered phases as needed, each ending with the same gate — feature file, UI review
     (or "no screens changed"), N+1 check under Prosopite, green run — before the next phase starts. -->
