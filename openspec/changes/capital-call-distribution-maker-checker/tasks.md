# Tasks

> **Phase gate:** each numbered group below is a phase. A phase ends with three tasks, in order:
> (a) **UI review** — when the phase adds or changes screens: screenshot each one next to the
> reference screen named in design.md's *Screen standards* and apply the UI self-review checklist
> (breadcrumbs, lazy tabs, Turbo streams, stats cards, filters, Actions dropdown, tooltips/help,
> full width); (b) **N+1 check** — run the phase's features under Prosopite and fix every N+1 in
> this change's code; (c) run the phase's Cucumber features green. Do not start the next phase
> until all three pass — fix the phase you're on rather than coming back later.

> **Open questions answered (2026-11-09)** ([design.md › Risks and open questions](design.md#risks-and-open-questions)):
> off for new firms, Request approval only when on, switching off announced rather than support-only, and notice
> approval stays out of scope (no follow-up). Before starting, the key changes K1–K17 still need approval. Do not migrate the shared dev DB from a side branch
> without asking. Never commit — leave work in the tree.

## 1. Firm setting and preparer log

- [ ] 1.1 Add migration `add_approval_maker_checker_to_entity_settings` (boolean, default false, null false) and
      `create_approval_makers` with the unique index (LLD › Schema Detail); update `db/schema.rb` and
      `db/schema_test.rb` by hand after migrating, then `db:clean_schema`. Verify: `bin/rails runner 'p EntitySetting.new.approval_maker_checker'` prints `false`.
- [ ] 1.2 Add `:approval_maker_checker` to `EntityPolicy::ENTITY_SETTING_ATTRIBUTES` and the "Approvals" block to
      `entities/_form_fields.html.erb` (copy the Weekly Task Digest block; ⓘ tooltip text from the proposal)
      (LLD › File Map ①). Verify: the entity edit form shows the switch for an Investment Fund entity.
- [ ] 1.3 Create `ApprovalMaker` model and `WithApprovalMakers` concern (`record_preparer!`, `preparer_ids` incl. the
      create-audit user, `preparers`, `approved_by_preparer?`, `maker_checker_on?`, `maker_checker_exempt?`) with ID
      comments (E8, E12, E13) (LLD › Method Contracts). Verify: `bin/rails runner` on a dev call returns its creator in `preparer_ids`.
- [ ] 1.4 Create `ApprovalMakerCache` and `ApprovalFigureWatch` (recording only — withdrawal comes in phase 3) and
      include them in `CapitalCall`, `CapitalDistribution`, `CapitalRemittance`, `CapitalDistributionPayment`,
      `CallFee`, `DistributionFee` with each model's `APPROVAL_FIGURES` (design card ② table); confirm
      `DistributionFee`'s figure columns from `db/schema.rb`. Verify: generating a call with 3 remittances inserts one row.
- [ ] 1.5 Re-grep `update_columns|update_all|insert_all` on the six tables and update the LLD bypass-writer list if
      anything new writes a figure column (LLD › Queries and Indexes).
- [ ] 1.6 Write `features/funds/maker_checker/maker_checker_setting.feature` (H1, E1–E3, X1–X2) and
      `features/funds/maker_checker/preparers.feature` (H2–H11, E4–E14) with `# ID — …` comments and a header link to
      business-rules.md; add `features/step_definitions/maker_checker_steps.rb` (grep step text first — dry-run hides
      ambiguous steps).
- [ ] 1.7 UI review: screenshot the entity form's Approvals block beside the Weekly Task Digest block it copies.
- [ ] 1.8 N+1 check: `PROSOPITE=1 TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/funds/maker_checker/maker_checker_setting.feature features/funds/maker_checker/preparers.feature`
      (run in the background, wait on its PID), then read `log/prosopite.log` (truncate first; never commit) and fix
      every N+1 in this change's code.
- [ ] 1.9 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/funds/maker_checker/maker_checker_setting.feature features/funds/maker_checker/preparers.feature`
      and confirm green before starting phase 2.


## UI explanations (added 2026-11-09 at the user's request — applies to every phase that adds or changes a screen)

- [ ] U.1 Every screen, control, status and message this change adds or changes explains itself to the person using it:
  help text saying **why** (in plain words), **what it means** and **what to do next**; an info tooltip
  (`ti ti-info-circle` with a Bootstrap tooltip) for longer explanations; disabled controls carry a tooltip saying why
  they are disabled and what to do instead (never a bare refusal); emails say why the person got them and what to do if
  it wasn't them. Follow the house UI rules (reference screens, theme colours only, one type scale, buttons not links,
  existing Bootstrap confirm modals). Verify: Cucumber assertions on the key help texts / tooltips, and screenshots of
  each changed screen compared with its reference.

## 2. The approval rule and the pages

- [ ] 2.1 Create `MakerCheckerPolicyMethods` (`maker_checker_allows?`, `awaiting_second_approver?`,
      `request_approval?`, `actor_ids` incl. `support_user_id`) and include it in `CapitalCallPolicy` and
      `CapitalDistributionPolicy`; add `&& maker_checker_allows?` to both `approve?` with ID comments (H12, X3, X10)
      (LLD › Method Contracts). Verify: policy check in `bin/rails runner` for a preparer returns false with the setting on.
- [ ] 2.2 Bulk jobs: when refused and `awaiting_second_approver?`, record "You prepared <name> — another approver
      must approve it"; preload preparer rows per batch (X7, X8) (LLD › File Map ⑤). Verify: bulk API on dev returns the message in the completion notification.
- [ ] 2.3 Call and distribution show pages: disabled Approve with tooltip wrapper, "Prepared by" row with ⓘ, and the
      "· by <name> (also prepared it)" label (H13–H15, E28, H17) — copy the markup in `mocks/approve_actions.html`
      (LLD › File Map ⑥). Verify: page renders for a preparer and a checker.
- [ ] 2.4 Journey checks `ApproveCall` / `ApproveDistribution`: fail-message suffix when the setting is on (E24, E25).
- [ ] 2.5 Write `features/funds/maker_checker/capital_call_approval.feature` (H12–H15, E15–E27),
      `features/funds/maker_checker/capital_distribution_approval.feature` (H16–H17, E28–E31) and
      `features/security/maker_checker_approval.feature` (X3–X12) with ID comments.
- [ ] 2.6 UI review: screenshots of the call and distribution pages (preparer, checker, setting off) beside
      `capital_calls/show` today and `mocks/approve_actions.html`; check tooltip, alignment and no new CSS.
- [ ] 2.7 N+1 check under `PROSOPITE=1` for the three features; show page must stay within the +3-query budget.
- [ ] 2.8 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/funds/maker_checker/capital_call_approval.feature features/funds/maker_checker/capital_distribution_approval.feature features/security/maker_checker_approval.feature`
      green, plus the existing `features/security/bulk_actions_authorization.feature` and capital call / distribution
      journey features (setting off ⇒ unchanged), before starting phase 3.

## 3. Request approval, withdrawal and notices

- [ ] 3.1 Create `MakerCheckerNotices` (`checkers`, `request` with the 1-hour throttle, `withdrawn`, `switched_off`),
      `MakerCheckerNotifier < BaseNotifier`, `MakerCheckerMailer#notice` + view (dates via `l(...)`, email format) with
      ID comments (H18, E32–E36, H25) (LLD › Method Contracts). Verify: `MakerCheckerNotices.checkers(call)` on dev returns only non-preparer approvers with fund access.
- [ ] 3.2 Add `post 'request_approval', on: :member` to both resources in `config/routes/fund.rb`; add the
      `request_approval` actions (add to the `set_*` `only:` lists) and the Actions item + popup built by
      `MakerCheckerHelper#maker_checker_action_summary` (tints blue/amber/green) (LLD › Controllers). Verify: `bin/rails routes | grep request_approval` shows both.
- [ ] 3.3 Create `ApprovalWithdraw` and wire it into `ApprovalFigureWatch` (in-transaction, parent `lock!`, child
      creates on an approved parent ignored, exempt settlements, no-actor warning log); append the withdrawal sentence
      to the update notices of calls, distributions, remittances and payments (H21–H24, E40–E53, X16)
      (LLD › Transactions). Verify: editing a remittance of an approved dev call with the setting on un-approves it.
- [ ] 3.4 `EntitySetting` after-commit: true → false calls `MakerCheckerNotices.switched_off` (H25, E54, E55).
- [ ] 3.5 Write `features/funds/maker_checker/approval_requests.feature` (H18–H20, E32–E39, E56, H25, E54–E55) and `features/funds/maker_checker/approval_withdrawal.feature` (H21–H24, E40–E53, X16), plus
      X13–X15 in `features/security/maker_checker_approval.feature`.
- [ ] 3.6 UI review: popup beside the KYC Request Updates popup; flashes; the three emails beside `ComplianceMailer#notice`.
- [ ] 3.7 N+1 check under `PROSOPITE=1` for F5–F7; `request_approval` within its query budget.
- [ ] 3.8 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/funds/maker_checker/approval_requests.feature features/funds/maker_checker/approval_withdrawal.feature features/security/maker_checker_approval.feature`
      green, plus the open-ended dealing features (E27, E31, E50 unchanged) and late-commitment remittance features,
      before starting phase 4.

## 4. Documentation, coverage and sign-off

- [ ] 4.1 Update `docs/user_guides/capital_calls_user_guide.md`, `capital_distributions_user_guide.md` and the entity
      settings guide: "Maker–checker" sections, the "Who counts as a preparer" table, and FAQs per the user-guide FAQ
      standard (`user-guide-faqs` skill); run UserGuideLint. Verify: lint passes.
- [ ] 4.2 Coverage: list every H/E/X ID in business-rules.md and every `# H…/E…/X…` comment in the seven feature
      files; confirm the two sets are equal (97 IDs). Any edge case found during apply gets a new row AND a scenario.
- [ ] 4.3 `bundle exec rubocop` (incl. `IRM/RelationBlankPresent`), Brakeman and bundler-audit clean for the change;
      run the new `DISTINCT` recipient query against the dev MySQL (33066) read-only.
- [ ] 4.4 Update design.md with a "Changed during the build" table for anything that moved; tick the LLD sign-off.
- [ ] 4.5 UI review: final screenshots of every changed screen against design.md *Screen standards*.
- [ ] 4.6 N+1 check: full `features/funds/maker_checker/` + `features/security/maker_checker_approval.feature` under `PROSOPITE=1`.
- [ ] 4.7 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/funds/maker_checker features/security/maker_checker_approval.feature` green.
- [ ] 4.8 (QA, not the apply agent) Run [qa-checklist.md](qa-checklist.md) on a deployed staging build and record the sign-off.
