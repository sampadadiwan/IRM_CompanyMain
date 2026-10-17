# Tasks

> **Reproduce first**, then fix. Every cucumber run needs a fresh `TEST_ENV_NUMBER` and Redis on 6379.

## 1. Reproduce

- [x] 1.1 Write `features/security/tenant_isolation_batch1.feature` (S1–S8, R1–R7 plus S2-H, R4-H, each
      with an `# <ID> — …` comment) and `features/step_definitions/tenant_isolation_batch1_steps.rb`.
      Verify: `--dry-run` shows no undefined or ambiguous steps.
- [x] 1.2 Run against current code: 15 of 17 fail, S2-H and R4-H pass.

## 2. Fix

- [x] 2.1 S1 grant update params; S2 fund belongs to the investor's company; S8 escaped notice.
- [x] 2.2 S3 user params; S4 search entity; S5 own offers; S6 fund reports for staff; S7a deal edit.
- [x] 2.3 R1 import entity from owner; R1b importer admin of the import's entity.
- [x] 2.4 R2 revert on grant delete; R3 same-client revocation; R7 locked single-transaction switch/revert.
- [x] 2.5 R4 scheduled report entity + rescue fix; R5 UserPolicy / login-as by advisor home.
- [x] 2.6 Run the feature: 17/17 pass.
- [x] 2.7 Advisor-journey review follow-ups (report: Fix, follow-ups table): S1-E, R7 lock/save!, R7-X,
      R2 savepoint, R4-X, R1b-H, R1-U, R5-UI. Feature now 22/22.

## 3. Regression and cleanup

- [x] 3.1 Regression (pcuc, 4 workers): `features/security`, `features/advisor`, `features/core/report_builder`,
      `features/deal`, `features/secondaries`, `features/admin/support_client_mapping*.feature`,
      `features/login/two_factor_method_reset.feature`, `features/core/user.feature`,
      `features/core/document.feature`, `features/core/folder.feature`, `features/fund/fund_access.feature`,
      `features/fund/capital_calls.feature`, `features/core/investor_access.feature`,
      `features/core/investor_access_tag_notifications.feature`, `features/core/access_rights.feature`.
      Result 2026-10-17: 585/587; after the review follow-ups 613/615. The 2 failures (`features/security/rack_attack_404_blocking.feature:87,97`,
      strike/block expiry) fail identically on clean `main` code with this change stashed - pre-existing.
- [x] 3.2 `bundle exec rubocop` on the changed files: no new offences.
- [ ] 3.3 After deploy: audit prod for damage already done (read-only) — grants whose entity
      differs from their creation audit, advisor fund ARs on funds of another company than the
      investor's, users whose entity_id changed via the users form.
