# Tasks

> **Phase gate:** each numbered group below is a phase. A phase ends with three tasks, in order:
> (a) **UI review** — when the phase adds or changes screens: screenshot each one next to the
> reference screen named in design.md's *Screen standards* and apply the UI self-review checklist
> (breadcrumbs, lazy tabs, Turbo streams, stats cards, filters, Actions dropdown, tooltips/help,
> full width); (b) **N+1 check** — run the phase's features under Prosopite and fix every N+1 in
> this change's code; (c) run the phase's Cucumber features green. Do not start the next phase
> until all three pass — fix the phase you're on rather than coming back later.

> **Before phase 1:** design approval of [Key changes needing approval](design.md#key-changes-needing-approval)
> (K1–K10). Open questions 1–3 were answered on 2026-11-09: the weekly pack goes to support@caphive.com
> (per-region `SECURITY_EVENTS_WEEKLY_TO`), no LP sign-in email in this change, 13 months' retention.

> **Traceability:** every scenario carries `# <ID> — <path>` above it; the feature header links to
> [business-rules.md](business-rules.md); code comments name the IDs of the paths they implement.

## 1. Recording core + sign-in, two-factor and account hooks (Phase 1)

- [ ] 1.1 Migration `create_security_events` per [LLD Schema Detail](lld.md#schema-detail); update `db/schema.rb` and `db/schema_test.rb` (do not migrate the shared dev DB from a side branch). Verify: `bin/rails db:migrate:status` in test env shows it up; schema diff has only the new table.
- [ ] 1.2 `SecurityEvent` model (`readonly?`, `write!`, ransack allowlist, `STANDARD_COLUMNS`) per [LLD Method Contracts](lld.md#method-contracts). Verify: `bin/rails runner` in test env — `write!` twice with one uid leaves one row; `update` raises `ReadOnlyRecord` (X4).
- [ ] 1.3 `SecurityEvents::Catalogue` (29 kinds, categories, detail keys, alert flags — design card ②) and `SecurityEvents::Context` (IP/UA/request id/actor/impersonator from `Audited.store`, digest). Verify: confirm `Audited.store[:current_controller]` is set during a request by logging it once in a scratch run, then remove the log line.
- [ ] 1.4 `SecurityEvents.record` with the three tiers (after-commit enqueue → inline `write!` → warn log) and `recorded.security_event` notification ([LLD Error Mapping](lld.md#error-mapping-and-logging)); comment IDs E34, E35, E36, X3.
- [ ] 1.5 `SecurityEventWriteJob` (`:default`, `log_arguments = false`, uid idempotency, user lookup for web failures; alert call stubbed to a no-op until phase 3) per [LLD Background Jobs](lld.md#background-jobs). Verify: job performed twice with one attrs hash → one row (E33).
- [ ] 1.6 Sign-in hooks S1a–S1m, S2a–S2b, S3 from design card ② (incl. `config/initializers/security_event_warden.rb`, devise-api `after_successful_sign_in`, `Users::PasswordsController` wrappers). Verify: each listed line is one `SecurityEvents.record(...)` call; `git diff --stat` touches only the files in [LLD File Map](lld.md#file-map) row ②.
- [ ] 1.7 Two-factor and account hooks T1–T4, A1–A6: `User#record_security_changes` after-commit (K2) plus explicit lines at `two_factor_controller.rb:362` and `entities_controller.rb:127`. Verify: in a runner, toggling `two_factor_enabled` on a test user records `two_factor.disabled`.
- [ ] 1.8 Write `features/security/security_events_sign_in.feature` covering H1–H15, E1–E22, H28, E33–E37, X3–X5, E46, E49 (business-rules §1, §2, §5, §7), each with its `# ID — path` comment.
- [ ] 1.9 UI review: no screens changed in this phase — confirm sign-in, two-factor, magic-link and reset pages show the same text as before (E46).
- [ ] 1.10 N+1 check: `PROSOPITE=1 TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/security/security_events_sign_in.feature`, then read `log/prosopite.log` (truncate first; never commit) and fix every N+1 in this change's code.
- [ ] 1.11 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/security/security_events_sign_in.feature` (wait on the run's PID) until green, before starting phase 2.

## 2. Access, support, credential and export hooks (Phase 2)

- [ ] 2.1 Rolify `after_add`/`after_remove` on `User` (K1, `user.rb:173`) recording `role.granted`/`role.revoked`; grep `app lib` for any direct `users_roles` / `roles.delete_all` writes and list them in design *Risks*. Verify: H17 and E25 pass in a scratch scenario before continuing.
- [ ] 2.2 `enable_support` in `record_security_changes` and the one system event in `User.disable_support_for_all` (K3). Verify: E27 in a runner — one row.
- [ ] 2.3 Support hooks P1–P3: `users_controller.rb:267,301`, `sessions_controller.rb:51` (before `reset_session`), `support_client_mapping.rb:77,109` (K4). Verify: Login as in dev records `support.signed_in_as` with actor = support user.
- [ ] 2.4 Credential hooks K1–K3: `api_tokens_controller.rb:16,29`, `mobile_devices_controller.rb:12`, mobile `sessions_controller.rb:51`, Doorkeeper `after_successful_authorization` (`doorkeeper.rb:500`). Verify: the event row for H22 holds the name and no token string.
- [ ] 2.5 Export hooks D1–D4: `ApplicationController` xlsx `after_action` (K6, only 2xx/3xx), folder/document download, firm dump, report and secondary-sale downloads. Verify: a refused xlsx (E30) records nothing.
- [ ] 2.6 Write `features/security/security_events_access.feature` covering H16–H27, E23–E32, E47, E48, X1, X2 (business-rules §3, §4, §7).
- [ ] 2.7 UI review: no screens changed in this phase — confirm user edit, Login as, API tokens and download flash messages unchanged (E47, E48).
- [ ] 2.8 N+1 check: `PROSOPITE=1 TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/security/security_events_access.feature`; fix every N+1 in this change's code.
- [ ] 2.9 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/security/security_events_access.feature features/security/security_events_sign_in.feature` until green, before starting phase 3.

## 3. Screen, admin alerts, weekly pack and clean-up (Phase 3)

- [ ] 3.1 `SecurityEventPolicy` (`index?`, `Scope` per design card ⑥) per [LLD Security Detail](lld.md#security-detail). Verify: in a runner, `Scope` for Sara returns no firm-18 rows.
- [ ] 3.2 Route, `SecurityEventsController#index` (html + xlsx), views copying `capital_calls/_index` and `_grid_stats` (mock: `mocks/security_events_index.html`), `index.xlsx.axlsx` with formula-prefix escaping, menu entry in `_company_menus.html.erb:138` (K10). Verify: page renders for Rahul in dev with `@bread_crumbs` set.
- [ ] 3.3 `SecurityEventDownloadJob` + `SecurityEventsMailer#download` (modelled on `AuditDownloadJob`, re-scoping with a reloaded user). Verify: X9 in a scratch scenario.
- [ ] 3.4 `SecurityEventAlert`, `SecurityEventNotifier < BaseNotifier`, `SecurityEventsMailer#admin_alert`; wire into `SecurityEventWriteJob` (fresh insert only). Verify: H32 email lists Rahul and Meera; E41 sends nothing.
- [ ] 3.5 `SecurityEventWeeklyPackJob` + `SecurityEventsMailer#weekly_pack`, `SecurityEventPurgeJob`; cron entries in `config/initializers/sidekiq.rb` with per-region local anchors (K9); the pack reads
  `SECURITY_EVENTS_WEEKLY_TO` (add `SECURITY_EVENTS_WEEKLY_TO=support@caphive.com` to `.env.production.in` and
  `.env.production.us`; unset → warning, no email). Verify: `Sidekiq::Cron::Job.find("SecurityEventPurgeJob")` exists after boot in a non-local env config check.
- [ ] 3.6 Write `features/security/security_events_screen.feature` (H29–H35, E38–E44, X12) and `features/security/security_events_tenant_isolation.feature` (E45, X6–X11) in the style of `tenant_isolation_batch1.feature`.
- [ ] 3.7 UI review: screenshot Security Events (dev DB via the Warden runner script) beside Capital Calls `_index` and the mock; check breadcrumbs, header buttons, cards = filtered rows (E40), filter, tooltips, empty state, full width; fix differences.
- [ ] 3.8 N+1 check: `PROSOPITE=1 TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/security/security_events_screen.feature features/security/security_events_tenant_isolation.feature`; fix every N+1 in this change's code.
- [ ] 3.9 Run all four `features/security/security_events_*.feature` with `TEST_ENV_NUMBER=$RANDOM` until green.

## 4. Close-out

- [ ] 4.1 Coverage: list every H/E/X ID in business-rules.md and every `# ID —` comment in `features/security/security_events_*.feature`; confirm the sets are equal (96 IDs); add a row AND a scenario for any edge found during apply.
- [ ] 4.2 `bundle exec rubocop` on changed files, `bundle exec brakeman -q` and `bundle exec bundle-audit check` clean for the change.
- [ ] 4.3 Update `docs/security/security_event_review_methodology.md` §3–§4 to name the Security Events screen and weekly pack as the application-log source (with a mermaid diagram), and mark M11 fixed in `docs/security/owasp_top10_review_2026_11.md`. Verify: links resolve.
- [ ] 4.4 (QA, not the apply agent) Run [qa-checklist.md](qa-checklist.md) on staging_in and record the sign-off.
