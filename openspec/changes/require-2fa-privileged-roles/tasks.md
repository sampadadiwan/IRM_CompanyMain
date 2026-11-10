# Tasks

> **Phase gate:** each numbered group below is a phase. A phase ends with three tasks, in order:
> (a) **UI review** — when the phase adds or changes screens: screenshot each one next to the
> reference screen named in design.md's *Screen standards* and apply the UI self-review checklist
> (breadcrumbs, lazy tabs, Turbo streams, stats cards, filters, Actions dropdown, tooltips/help,
> full width); (b) **N+1 check** — run the phase's features under Prosopite and fix every N+1 in
> this change's code; (c) run the phase's Cucumber features green. Do not start the next phase
> until all three pass — fix the phase you're on rather than coming back later.

Scope (user, 2026-11-09): required roles = `RequiredTwoFactor::REQUIRED_2FA_ROLES = %i[support super]`;
company admins not required; step-up turn-off for every user with 2FA on; same date in IN and US;
14 days' notice; no forced sign-out.

Worked examples: [business-rules.md](business-rules.md) (H1–H11, E1–E42, X1–X25). Files, contracts and
config: [lld.md](lld.md). Every scenario carries `# <ID> — <path>`; code comments name the IDs of the
branches they implement (e.g. `# X15 required refuses; E30 no method → password only`).

## 0. Approvals (before any code)

- [x] 0.1 User approves design.md [Key changes needing approval](design.md#key-changes-needing-approval) (16 items, incl. the User guard and `login_as?`) and the screen mocks in `mocks/screens.html`; verify: approval noted in design.md's "Changed during the build" table

## 1. Who must use 2FA and the sign-in gate

- [x] 1.1 Add `RequiredTwoFactor` (env `REQUIRED_2FA_ENFORCE_FROM`, `REQUIRED_2FA_ROLES = %i[support super]`, `stage`, `enforced?`, `enforce_from`, `role_label`, `reset!`) (LLD Method Contracts); verify: `bin/rails runner 'p RequiredTwoFactor.stage'` prints `:off` with the env unset and `:notice` with a future date
- [x] 1.2 Add `two_factor_required_role?` / `_required?` / `_applies?` / `_verified?` to `TwoFactorAuthenticatable`; `need_two_factor_authentication?` → applies (LLD File Map); verify: runner check on a dev support user with a past date returns required=true and on a company admin returns false
- [x] 1.3 Replace the four direct reads: `two_factor_dispatch.rb:42`, `passwords_controller.rb:17`, `tokens_controller.rb:20,52`, `mobile_sign_in.rb:43` (design D2); verify: `grep -n "two_factor_enabled?"` on those four files returns nothing
- [x] 1.4 `Users::TwoFactorController#commit_method!(mode)` shared by the three `verify_*` actions, writing the flag for required users and enqueuing `UserMailer#two_factor_enabled` (+ view) (design D3); verify: existing `features/login/two_factor_enrollment.feature` still green
- [x] 1.5 Required banner on `two_factor/select_mode.html.erb` (copy `#two_factor_reset_banner`) (design Screen standards); verify: dev sign-in as an un-enrolled support user shows it with "(Support)"
- [x] 1.6 Write `features/login/two_factor_required_roles.feature` (H1–H3, E1–E20, X1–X2) and the phase-1 part of `features/security/two_factor_required_roles.feature` (X3–X5), with env/time steps in `features/step_definitions/two_factor_required_steps.rb` (LLD Test Plumbing)
- [x] 1.7 UI review: set-up screen with the new banner beside `two_factor/select_mode` with the reset banner; fix differences
- [x] 1.8 N+1 check: truncate `log/prosopite.log`, run `PROSOPITE=1 TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/login/two_factor_required_roles.feature features/security/two_factor_required_roles.feature`, fix every N+1 in this change's code
- [x] 1.9 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/login/two_factor_required_roles.feature features/security/two_factor_required_roles.feature features/login/two_factor_*.feature features/mobile/` (wait on the PID) until green before starting phase 2

## 2. Banner, Set up now, Login as and roll-out

- [x] 2.1 `users/_two_factor_required_banner.html.erb` (copy `_reset_password`), rendered in `modernize`, `application`, `admin/application` beside it, only for `two_factor_required_role?` users; date via `l(...)` (design card ⑤); verify: dev page as an un-enrolled support user shows the amber banner and a company admin sees none
- [x] 2.2 `UserPolicy#start_two_factor_setup?` (self, not impersonating, required role, not verified) + `UsersController#start_two_factor_setup` + route + "Set up now" on the user-page row (LLD Controllers); verify: clicking it signs out with "Sign in again to set up two-factor authentication."
- [x] 2.3 `UserPolicy#login_as?` actor rule + `login_as_refusal_message`; `UsersController#login_as` maps it to the flash (design D7); verify: existing Login as features green
- [x] 2.4 `lib/tasks/two_factor_required.rake` with `report` (read-only, counts per required role + "not required" line) and `end_unverified_access` (dry run unless `EXECUTE=1`, refuses before the date; `forget_me!` + revoke `ApiToken` / Doorkeeper tokens) (LLD Configuration and Rollout); verify: `bundle exec rake two_factor_required:report` on dev prints counts and no emails
- [x] 2.5 Write `features/login/two_factor_required_rollout.feature` (H4–H8, E21–E29) and add X6–X10 to `features/security/two_factor_required_roles.feature`
- [x] 2.6 UI review: banner (amber + red) beside the "Please change your password at the earliest" banner; user-page row with "Set up now"; fix differences
- [x] 2.7 N+1 check under `PROSOPITE=1` for both features; confirm the banner adds 0 queries per page
- [x] 2.8 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/login/two_factor_required_rollout.feature features/security/two_factor_required_roles.feature` until green before starting phase 3

## 3. Turning two-factor off (every user), recovery and emails

- [x] 3.1 User guard `two_factor_disable_must_be_verified` (every user) + `disable_two_factor_verified!` + `skip_two_factor_disable_verification!`; add `two_factor_enabled` to `audit_fields` (`user.rb:18`); `UsersSyncController` calls the new skip (design D5; approval items 2, 3, 13); verify: `features/login/users_sync_api.feature` green
- [x] 3.2 `TwoFactorDisable` op (steps per LLD Method Contracts) (design card ⑥); verify: runner call with a wrong password returns the password error and bumps `failed_attempts`
- [x] 3.3 `UserPolicy#disable_two_factor?`; `UsersController#disable_two_factor` and `#send_two_factor_code` with bearer refusal and server cooldown; routes; Rack::Attack throttles (LLD Controllers, Security Detail); verify: `bin/rails routes | grep two_factor` lists both
- [x] 3.4 `users/_disable_two_factor_modal.html.erb` (copy `_reset_two_factor_modal`), user-page row badge + **Turn off 2FA**, `_form.html.erb` toggle row; extend `reset_two_factor_controller.js` with optional code target + `sendCode` (design Screen standards); verify: dev user page of a company admin with voluntary 2FA shows the popup like `mocks/screens.html` ④
- [x] 3.5 `UserMailer#two_factor_disabled`, `#two_factor_admin_notice` + views; `TwoFactorReset#notify_user` admin copy when actor ≠ user (design D9, D10, Notifications); verify: mails render with `Dec 08, 2026` dates
- [x] 3.6 Write `features/login/two_factor_turn_off.feature` (H9–H11, E30–E42) and add X11–X25 to `features/security/two_factor_required_roles.feature` (X11–X14 may live in the TO file per business-rules Feature column)
- [x] 3.7 UI review: popup beside the Reset Two-Factor Method popup; user-page row; Edit profile row beside its other toggle rows; fix differences
- [x] 3.8 N+1 check under `PROSOPITE=1` for both features
- [x] 3.9 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/login/two_factor_turn_off.feature features/security/two_factor_required_roles.feature features/login/two_factor_method_reset.feature features/login/user_registration_edit.feature` until green before starting phase 4

## 4. Docs, full regression and roll-out

- [x] 4.1 Update `docs/user_guides/two_factor_authentication_user_guide.md` (Where to find it, Disabling 2FA for every user, required for support / super, FAQs via the `user-guide-faqs` skill; lint with UserGuideLint) and `docs/modules/two_factor_auth/two_factor_authentication.md` (required roles constant, step-up turn-off, mermaid diagrams); verify: lint passes
- [x] 4.2 Coverage: list every H/E/X ID in business-rules.md and every `# ID —` comment in `features/`; confirm both sets equal the same 78 IDs
- [x] 4.3 `bundle exec rubocop` (incl. `IRM/RelationBlankPresent`), `bin/brakeman`, `bundle exec packwerk check` clean for the change; run the rake `distinct` query once on dev MySQL
- [x] 4.4 Full `features/security/` and `features/login/` run (pcuc `-n 4`, random `TEST_ENV_NUMBER`, check no other pcuc run first) green
- [ ] 4.5 (Ops, IN and US) `report` → set the same `REQUIRED_2FA_ENFORCE_FROM` (deploy + 14 days) on both boxes + restart → message the 11 support / super users → `report` every few days until 0 in both regions; record counts in design.md "Changed during the build"
- [ ] 4.6 (Ops, on the date, each region) `end_unverified_access` dry run, then `EXECUTE=1` if it names anyone; `report` once more
- [ ] 4.7 (QA) Run [qa-checklist.md](qa-checklist.md) on the staging build and record the sign-off
