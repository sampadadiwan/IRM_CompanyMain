# Tasks

> **Reproduce first**, then **phase gate** per numbered group. Every cucumber run: fresh
> `TEST_ENV_NUMBER`, Redis on 6379, run in the background and `wait $pid`.

## 1. Reproduce

- [x] 1.1 Write `features/misc/dr_drill_hygiene.feature` + steps covering H1–H3, E1–E3, X1–X3 (lock classification, teardown deploy-file guard, error-mail prefix). "ID — Edge case: …" comments.
- [x] 1.2 Run it and confirm it fails against current code (no `Dr::PulumiLock` / `Dr::DrillTeardown`, prefix has no tag). Record the output.
      - Recorded 2026-11-08: `10 scenarios (10 failed)`: 9 on missing `Dr::PulumiLock` / `Dr::DrillTeardown` / `DrillStack`; E4 reproduced the real bug (`expected false`: a drill stack would page WhatsApp).

## 2. Fix — pure logic (report Fix rows 1, 3, 4)

- [x] 2.1 `lib/dr/pulumi_lock.rb`: `classify(locks, local_host:, alive:)` → `:free` / `:running_here` / `:stale` / `:held_elsewhere`, plus an operator message with host, pid, user, age and, for stale, the exact `pulumi cancel --stack <stack>` command. Verify: `bin/rails runner` call on a sample lock.
- [x] 2.2 `lib/dr/drill_teardown.rb`: `targets_drill?(deploy_file_text, drill_ips)`, true only when the set of `server "…"` IPs equals the drill's app IPs exactly.
- [x] 2.3 `lib/drill_stack.rb` `DrillStack`: `region(env)`, `email_prefix(rails_env:, base_domain:, env:)` → `[Error][DR DRILL <region>] …` (unchanged with no flag). Use it in `exception_notification.rb:30`. `CriticalErrorWhatsapp.enabled?` returns false on a drill stack (E4).
- [x] 2.4 Run the feature; H1–H3, E1–E3, X1–X3 pass.

## 3. Fix — wire into the drill and setup_infra (report Fix rows 1–5)

- [x] 3.1 `aws.rake` `dr_drill`: before `with_dr_transcript`, take the `flock` run lock (refuse if held), list the stack's lock objects in the Pulumi S3 backend, classify, refuse on anything but `:free`. A refused run writes no drill row or report. Verify: `ruby -c`.
- [x] 3.2 `aws.rake` `dr_drill` ensure: when PASSED and `TEARDOWN=true`, **before** `git checkout`: if `Dr::DrillTeardown.targets_drill?` holds, run `cap <stage> nginx:switch_maintenance` and `cap <stage> whenever:clear_crontab` (warn-only). Otherwise warn "stop skipped: deploy file does not name the drill servers". Record the drill app IPs in `setup_infra` for it. Verify: `ruby -c`.
- [x] 3.3 `aws_utils.rb` `setup_infra`: in drill mode, write `DR_DRILL_STACK=<region>` to `.env.<stack>.<variant>` before the DR-branch commit; before phase 5, wait up to 5 min for SSH on every app server, then fail naming the server. Verify: `ruby -c`.
- [x] 3.4 Docs: `dr_guide.md` §1 drills paragraph (lock refusal, stale-lock command, email tag, teardown order). `gap_review_2026_11.md` G20/G21 marked fixed in code.
- [x] 3.6 (added on review) `DrillStack.grade_mark` + `dr:verify` drill-marker check; teardown summary recorded in the drill's `dr_drills.md` row (`Dr::DrillTeardown.summary` / `.add_teardown_cell`, `run_cmd` returns output) — report Fix rows 6, 7; feature rows H4, H5, E5, E6, X4, X5.
- [x] 3.5 Run the feature; all IDs pass.

- [x] 3.7 (found when the batch drill was started, 2026-11-08) `aws:dr_drill` aborted with `uninitialized constant Dr`: `aws:setup_infra` and `aws:dr_drill` run WITHOUT the Rails environment, so the autoloader never resolves `lib/dr`, and every scenario so far had Rails booted. Fixed with `lib/tasks/dr_requires.rb` (explicit requires plus the ActiveSupport extensions used), required from `aws_utils.rb`; `Dr::PulumiLock` no longer uses `Time.zone` (nil outside Rails). Regression row X6 runs the drill's Dr code in a fresh process that loads only the Rakefile.

- [x] 3.8 (2026-11-08 13:17 drill) The Teardown cell said "0 resources destroyed": the count matched "…subnet_1-0 deleted". `Dr::DrillTeardown.destroyed_count` now reads pulumi's summary line; feature row X7; the 13:17 row corrected to 46.

## 4. Regression and cleanup

- [x] 4.1 Run all three DR features (`dr_backup_schedule`, `dr_search_indexes`, `dr_drill_hygiene`) together: green.
- [ ] 4.2 Blast radius needs AWS: the batch staging drill (qa-checklist B1, B2, H1, H3, R1–R3).
- [x] 4.3 `bundle exec rubocop` on new files plus changed lines: clean.
- [x] 4.4 N+1 check: not applicable — no request path or job.
- [x] 4.5 UI check: not applicable — no screens touched.
