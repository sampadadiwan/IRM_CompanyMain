# Tasks

> Reproduce first; phase gate per group. Every cucumber run: fresh `TEST_ENV_NUMBER`, Redis on 6379, background + `wait $pid`.

## 1. Reproduce

- [x] 1.1 Write `features/misc/dr_drill_contacts_users.feature` + steps for H1–H5, E1–E3, X1–X2 (interceptor, HTTP guard decision, cron predicate, verify grading). "ID — …" comments.
- [x] 1.2 Run it; confirm it fails against current code (no interceptor / guard / grading). Record the output.

## 2. Fix — choke points (report Fix rows 1–3, 6)

- [x] 2.1 `lib/drill_stack.rb`: `MailInterceptor.delivering_email` (no delivery, log, count), `OutboundGuard` (prepend to `Net::HTTP#request`; blocked hosts `*.wati.io`, `exp.host`, `*.twilio.com`; synthetic 200), `suppressed_count` / `record_suppressed` (Rails.cache `dr:drill_suppressed`), `grade_silence`. Inline comments. Verify: `ruby -c`; the no-Rails probe still loads (`dr_requires.rb`).
- [x] 2.2 `config/initializers/drill_stack.rb` (new): on `DrillStack.drill?`, register the interceptor and prepend the guard, and log one line saying so. Verify: `DR_DRILL_STACK=x bin/rails runner 'p ActionMailer::Base…'` shows it registered; without the flag, nothing.
- [x] 2.3 `config/initializers/sidekiq.rb:118`: `unless Rails.env.local? || DrillStack.drill?` (with `require` of `lib/drill_stack`). Verify: `ruby -c`.
- [x] 2.4 Run the feature; H1–H5, E1–E3 pass.

## 3. Fix — deploy, verify, docs (report Fix rows 4–5)

- [x] 3.1 `config/deploy.rb`: on `DR_DRILL=true`, replace `whenever:update_crontab` with `whenever:clear_crontab`. Verify: `ruby -c`; `cap -T` unaffected.
- [x] 3.2 `dr_verify.rake` (drill only): "Drill cannot contact users" via `DrillStack.grade_silence` (interceptor, guard, sidekiq-cron count, crontab lines, suppressed count). `Dr::ReportCatalog` entry. Verify: drift guard green.
- [x] 3.3 Docs: DR guide drills paragraph (silence + sign-in note); gap review G24 fixed in code.
- [x] 3.4 Run the feature plus all DR features and the WhatsApp feature: green.

- [x] 3.5 Safeguards (user, 2026-11-08): S1 — a scenario fails if any committed `.env*` file sets `DR_DRILL_STACK`; S2 — `DrillStack.activate!` logs a loud boot warning on a drill stack. Also: the guard answers the block form (`Net::HTTP.post`) and opens no socket to a messaging provider (row E4), found when proving it in a real Rails process.
      - Recorded 2026-11-08: phase 1 failed to load (`uninitialized constant DrillStack::OutboundGuard`); real-process proof: with the flag mail intercepted / http guarded / timed jobs off and the boot warning printed; without it nothing switched on; WATI and Expo answered locally, github.com passed through.

## 4. Regression and cleanup

- [x] 4.1 All DR features + `critical_error_whatsapp.feature` + mailer-heavy features touched by interceptors (none expected: the interceptor registers only on drill stacks).
- [ ] 4.2 Proven on a real stack by the next staging drill (qa-checklist B1, H1, H5, E1, R1, R2).
- [x] 4.3 Rubocop on new and changed lines: clean.
- [x] 4.4 N+1 check: not applicable — no queries.
- [x] 4.5 UI check: not applicable — no screens touched.
