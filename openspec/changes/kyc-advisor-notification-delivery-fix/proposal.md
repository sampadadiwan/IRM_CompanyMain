# Proposal

## Why

Investor KYC notification emails don't reliably reach everyone who is actually
authorized to see the KYC. A prior fix on this branch made `InvestorKycPolicy#show?`
correctly authorize GP-side investor advisors (the `InvestorAdvisor` employee-grant
model) regardless of which entity they're currently switched into, and made
`InvestorKyc#notify_kyc` iterate both entity employees and entity investor advisors,
gated on that `show?` check. Two problems remain that make the fix incomplete:

1. `NotificationExtensions#email_enabled` — the gate that decides whether Noticed
   actually sends the email — only recognizes a recipient who currently belongs to
   the notified model's entity, or an LP-side `investor_access`. A GP-side advisor
   who is authorized but currently switched into a *different* entity is silently
   denied the email, even though `show?` says they're allowed to see the KYC. This
   is invisible to the existing Cucumber coverage because `BaseNotifier` bypasses
   `email_enabled` entirely in the test environment.
2. `notify_kyc`'s fan-out (looping every entity employee and every entity investor
   advisor, running a real `show?` authorization check — including DB queries —
   for each one) currently runs synchronously inside the web request that saves the
   KYC, via the `InvestorKycUpdate` Trailblazer operation.

A thorough review of the implementation on this branch (both the two fixes above
and the `InvestorKycPolicy#show?`/`notify_kyc` groundwork they build on) found six
further correctness bugs, three of them regressions serious enough to block merge:

3. The additive `email_enabled` branch (decided below) dispatches generically
   through `Pundit.policy(recipient, model)&.show?` for *any* model, gated only by
   the recipient's cached `investor_advisor` role. `DocumentPolicy#show?` already
   returns `true` unconditionally for a public document (`record.public_visibility`)
   with no entity or opt-out check — so the additive branch, as designed, emails
   every investor-advisor-role recipient for every public document app-wide,
   silently overriding an explicit `investor_access.email_enabled = false`
   opt-out and reaching models that have nothing to do with the advisor grant
   this fix was meant to recognize.
4. `notify_kyc`'s employee loop gates on `InvestorKycPolicy#show?`, which requires
   a capital commitment to exist before a plain employee can be notified (both via
   the `extended_permissioned_employee?` scope's join and the new
   `Fund.for_employee` branch). Before this branch, the same two notification
   methods notified every active entity employee unconditionally. A KYC commonly
   has zero capital commitments during onboarding — precisely when these two
   notifications fire — so ordinary employees now get no notification at all until
   a commitment exists, where before they got every one.
5. `InvestorKycPolicy#show?`'s new `elsif user.has_cached_role?(:employee)` branch
   is checked before the pre-existing "investor viewing their own KYC" branch.
   `User#setup_defaults` grants `:employee` (not `:investor`) to any user whose
   entity is typed `"Company"` or is a fund, which includes corporate and
   fund-of-funds LPs. Such a user is now diverted into the GP-scoped
   `Fund.for_employee` check — which can never match their own LP entity — instead
   of reaching the entity-id check that would correctly authorize them. A
   corporate or fund-of-funds LP user is denied access to their own KYC.
6. The same method's new `elsif (users_investor_advisor = ...)` branch is an
   exclusive `elsif`: merely holding *any* `InvestorAdvisor` row on the record's
   entity diverts a user into this branch, even when that grant's `allowed_roles`
   doesn't include `"employee"` (e.g. just `"investor"`, which the Advisors form
   can grant). Such a user is now denied outright instead of falling through to
   the pre-existing `for_investor_advisor` or investor-owns-this-KYC branches that
   previously covered them.
7. `InvestorAdvisor#is_employee?` and the new branch's privilege check miss two
   cases: a grant whose `allowed_roles` was serialized with symbols (a documented,
   still-functional legacy format per this file's own `setup_issues` method) never
   matches the string-only `.include?("employee")`; and a grant of
   `allowed_roles: ["company_admin"]` — strictly more privileged than `"employee"`
   — is denied by the hard `is_employee?` requirement.
8. `notify_kyc`'s two loops can double-email a user whose own `advisor_entity_id`
   is `nil` (a documented legacy state for advisor accounts created before
   `ensure_advisor_home` existed) if they're currently switched into the host
   entity: they match both the `not_investor_advisor_roles`-scoped employee loop
   and the `entity.investor_advisors` loop. The second loop also omits the
   `enable_kycs` check the first loop keeps, so a switched-in advisor granted
   `company_admin` (who bypasses `show?`'s first branch unconditionally) gets
   emailed even when their grant's own `enable_kycs` flag is off.

A tenth, pre-existing issue from an earlier commit on this branch (not part of
this change's original diff, but on the same PR) is folded in since it touches
the same notification path: commenting out `msg:` in
`InvestorKycsController#submit` instead of removing it leaves
`InvestorKycNotifier#message` resolving to `nil` with no `CustomNotification`
configured, which blanks the in-app "KYC submitted" notification body (the email
itself is unaffected, since the mailer view has its own fallback text).

## What Changes

- `NotificationExtensions#email_enabled` (`config/initializers/noticed.rb`) gets a
  third, additive check: when the recipient holds an `InvestorAdvisor` grant on
  the notified model's own entity (`model.entity.investor_advisors.exists?(user_id:
  recipient.id)` — entity-scoped, not the cheap cached-role check originally
  proposed), defer to the model's own Pundit policy `show?` to decide whether the
  recipient is actually authorized — independent of which entity they're
  currently switched into. Guarded against models/policies that don't support
  this (`Pundit::NotDefinedError`, `NoMethodError`, now logged at `warn` rather
  than silently swallowed), since `email_enabled` is shared across ~25 notifiers
  app-wide and most of their policies have not been audited for this scenario.
- `InvestorKyc#notify_kyc`'s two recipient loops (entity employees, entity investor
  advisors) move off the request thread into a new background job, following the
  existing `SendKycFormJob` pattern. `updated_notification` and
  `updates_requested_notification` become thin wrappers that enqueue the job.
- `notify_kyc`'s two loops are deduplicated by user id, both gate consistently on
  `enable_kycs`, and both fall back to an `enable_kycs`-only check (skipping the
  `show?`/fund-access requirement) when the KYC has no capital commitments yet —
  restoring pre-branch behavior for the common zero-commitment onboarding window
  instead of silently dropping every ordinary employee from notification.
- `InvestorKycPolicy#show?` is restructured (still elsif-equivalent in effect, not
  exclusive) so the new investor-advisor-grant branch only *adds* access rather
  than also gating out the branches below it, the investor-owns-this-KYC check is
  checked ahead of the `:employee`-role branch so an LP user who also happens to
  carry the `:employee` role isn't locked out of their own KYC, and a grant's
  privilege check accepts `company_admin` as well as `employee`.
- `InvestorAdvisor#is_employee?` (and the new `is_company_admin?`) compare against
  stringified `allowed_roles`, so legacy symbol-serialized grants match correctly.
- Restore `msg:` in `InvestorKycsController#submit`'s `notify_kyc_submitted` call
  (fixing the in-app notification body regression from the earlier commit that
  commented it out), and have `notify_kyc_submitted.html.erb` always render its
  own formatted body instead of the passed-in `msg` — preserving that commit's
  actual intent (a better-formatted email) without blanking the in-app notification.
- Remove the debugging instrumentation left on the branch from diagnosing these two
  issues (`byebug` breakpoints in `investor_kyc_mailer.rb`, temporary `puts` in
  `investor_kyc.rb`, temporary debug logging in the Cucumber step definitions).
- Add coverage for the `email_enabled` fix at a level Cucumber can actually exercise
  (it's bypassed by `BaseNotifier` in the test env), since the existing feature-test
  suite structurally cannot catch this class of bug, plus coverage for each of the
  `show?`/`notify_kyc` regressions found above.

**Not in scope**: auditing or fixing the same switch-state assumption in the ~24
other `BaseNotifier` subclasses' policies (Fund, Document, Task, CapitalCommitment,
Deal, KpiReport, SecondarySale, Offer, etc.) beyond the entity-scoped gate above,
which limits `email_enabled`'s new branch to recipients who actually hold a grant
on the model's own entity. (The original proposal claimed the generic dispatch
"only changes observable behavior for `InvestorKyc` notifications" under the
cheap cached-role gate; review disproved that via `DocumentPolicy`, which is why
the gate changed to the entity-scoped check instead.)

The entity-scoped gate closes the cross-entity leak but does not make the new
branch KYC-only: a record of any type owned by an entity the recipient holds a
grant on still consults its own policy, so a switched-away advisor now also
receives email for that entity's public documents. That consequence is accepted
and documented (see design.md — Impact Analysis) rather than audited away across
all 27 notifiers.

**Folded in during review**: a final KYC submit fired two notifications — the
generic "KYC updated" one from `InvestorKycUpdate`'s status-blind
`updated_notification` step, and "KYC submitted" from the controller's own private
sender. Pre-existing on `main`, but this change made the two paths disagree about
recipients (only one of them knows about investor advisors). The submitted
notification now routes through `notify_kyc` as `InvestorKyc#submitted_notification`
and wins outright on a submission, so all three KYC notification kinds share one
recipient rule. See design.md Decision 8 for the two intended behavior changes
that follow (advisors gain it; employees without fund access lose it).

## Capabilities

### New Capabilities
- `investor-kyc-notification-delivery`: who receives InvestorKyc notification
  emails and why, and who can view a KYC at all — covers the existing
  `show?`-gated fan-out already implemented on this branch (both entity employees
  and GP-side investor advisors, regardless of current switch state), this
  proposal's original two fixes (correct email delivery gating for switched-away
  advisors, and running the fan-out as a background job), and the six further
  correctness fixes to `show?`/`notify_kyc`/`email_enabled` found during review.

### Modified Capabilities
- None — no existing capability in `openspec/specs/` currently describes KYC
  notification behavior.

## Impact

- `config/initializers/noticed.rb` — `NotificationExtensions#email_enabled` and
  `investor_advisor_show_enabled`.
- `app/packs/core/investor_kycs/models/investor_kyc.rb` — `notify_kyc` extracted
  into a job and its two loops deduplicated/consistently gated;
  `updated_notification`/`updates_requested_notification` become thin wrappers.
- `app/packs/core/investor_kycs/policies/investor_kyc_policy.rb` — `show?`
  restructured per the Decisions in design.md.
- `app/packs/core/investors/models/investor_advisor.rb` — `is_employee?` fixed,
  new `is_company_admin?`.
- New file: `app/packs/core/investor_kycs/jobs/notify_kyc_job.rb`.
- `app/packs/core/investor_kycs/controllers/investor_kycs_controller.rb`,
  `app/packs/core/investor_kycs/views/investor_kyc_mailer/notify_kyc_submitted.html.erb`
  — restore `msg:` / fix the in-app notification body regression.
- `app/packs/core/investor_kycs/mailers/investor_kyc_mailer.rb`,
  `features/step_definitions/investor_kyc_send_workflow_steps.rb` — remove
  debugging instrumentation.
- Test coverage: existing Cucumber scenarios in
  `features/core/investor_kyc_send_workflow.feature` (scenarios 14–15) should keep
  passing unchanged (`config.active_job.queue_adapter = :inline` in test, so
  `perform_later` still runs synchronously), but cannot prove the job boundary
  matters in production — noted as a known gap, not solved by this change. New
  coverage is needed for `email_enabled` itself (Cucumber can't reach it) and for
  each `show?`/`notify_kyc` regression found during review.
- No `BaseNotifier` subclass or policy other than `InvestorKycPolicy` is modified.
