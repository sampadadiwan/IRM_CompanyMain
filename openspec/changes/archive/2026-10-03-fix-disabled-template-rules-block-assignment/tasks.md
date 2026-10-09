# Tasks

> **Reproduce first.** Phase 1 writes the Cucumber scenarios from the report's Verification
> table that fail against the CURRENT code, and runs them to watch them fail. A bug fix that
> was never seen failing might be fixing nothing.

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens.

> **Every cucumber run needs a fresh `TEST_ENV_NUMBER`** (unset, runs share one sqlite DB and
> corrupt each other) and **local Redis up on 6379**.

## 1. Reproduce

- [x] 1.1 Add the scenarios to `features/core/workflow_auto_assignment.feature` covering H1, H2,
      E1, E2, E3, E4, E5, X1 and X2 from the report's Verification table, rewriting the existing
      "A disabled template's rule does not fall through to the next rule" scenario
      (`:136`, report: Blast Radius) into E2's fall-through assertion. Reuse the existing
      `there is an auto-assignment rule for template ... type ... with conditions ...` and
      `the workflow template ... is disabled` steps; add steps only for what is genuinely new
      (an orphaned rule for X1, a failing launch for X2).
- [x] 1.2 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/workflow_auto_assignment.feature`
      and confirm the failures. **Observed:** 18 scenarios, 5 failed — H1, H2, E2, E3 and X1 fail
      against current code; E1, E4, E5 and X2 pass. Report's Verification note updated to match.

## 2. Fix the rule walk

- [x] 2.1 In `WorkflowAutoAssignmentService#find_matching_rule`, select on
      `rule.workflow_template&.enabled? && rule.matches?(workflowable)` so a rule whose template is
      disabled is skipped and the walk continues (report: Fix, row 1). Verify with
      `bin/rails runner` against a disabled catch-all ahead of a live rule — the live template is
      returned.
- [x] 2.2 Change the chain's ordering to `order(:priority, :id)` so equal priorities resolve by
      creation order (report: Fix, row 2). Verify by replaying the walk twice in `bin/rails runner`
      for an entity with two rules at the same priority and getting the same rule both times.
- [x] 2.3 Remove `step :check_template_enabled`, its `End(:template_disabled)` output and the
      `check_template_enabled` method, and rewrite the class-level comment block so it describes
      skip-and-continue instead of the old no-fallthrough rationale (report: Fix, row 3). Verify
      with `grep -n "template_disabled" app/packs/core/workflow_templates/services/workflow_auto_assignment_service.rb`
      returning nothing.
- [x] 2.4 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/workflow_auto_assignment.feature`
      and confirm H1, H2, E1, E2, E3, E4, E5, X1 and X2 all pass before starting phase 3.

## 3. The rule chain analyzer

Added to this change at the user's request: the chain the runtime walks has no screen anywhere, which
is why both misconfigurations were invisible. One analyzer serves the disable message, the per-rule
badge and the index banner.

- [x] 3.1 Add `WorkflowRuleChain` (`app/packs/core/workflow_templates/services/workflow_rule_chain.rb`):
      for an entity and workflowable_type, the rules in `(priority, id)` order, each classified
      `:active`, `:dormant` (template disabled), `:orphaned` (template row gone) or `:shadowed` (an
      earlier **live** rule is a catch-all, or has an identical condition set), plus `#successor_for`
      and a type-level `#verdict`. Shadow detection covers only those two honest cases — no attempt to
      prove implication across `gt`/`lt`/`in`, where a wrong badge would be worse than a missed one.
      Verify in `bin/rails runner` against entity 157's four KYC rules: rule 22 `:active`, rules 1-3
      `:dormant`; then with template 3 enabled, rule 1 `:active` and rules 2, 3, 22 `:shadowed`.
- [x] 3.2 Run `bundle exec rubocop` on the new file and confirm no new offenses.

## 4. Surface it on screen

- [x] 4.1 In `WorkflowTemplatesHelper#workflow_template_toggle_message`, replace "they are kept, not
      deleted" with wording that says the rules go dormant and are kept, and names the template that
      takes over for the records they matched — or says nothing will (report: Fix, row 4), using
      `WorkflowRuleChain#successor_for`. Verify in `bin/rails runner` for a template with a live
      successor and one without, checking both message variants.
- [x] 4.2 Rewrite the `rules_inert_note` paragraph in `views/workflow_templates/show.html.erb` to say
      the rules are dormant, that the next matching rule for the type applies, and that they resume
      unchanged on enable (report: Fix, row 5). Verify by loading a disabled template's page.
- [x] 4.3 Add a Status column to the rules table on `show.html.erb`: `Active`, `Dormant — template
      disabled`, or `Shadowed by "<template>" (priority N)` with the blocking rule's template linked,
      so the blocker is reachable from the page the admin is actually on.
- [x] 4.4 Add a warning banner to `_index.html.erb`, one per workflowable_type whose `#verdict` says
      no live rule can match, naming the disabled templates involved.
- [x] 4.5 Add scenarios to `features/core/workflow_templates.feature` for E6 (the disable
      confirmation names the successor), E7 (the dormant-rules note), E8 (a shadowed rule's badge
      names its blocker) and E9 (the index banner when every rule for a type is dormant).
- [x] 4.6 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/workflow_templates.feature`
      and confirm it is green before starting phase 5.

## 5. Documentation

- [x] 5.1 Update `docs/user_guides/workflow_templates_user_guide.md` at lines 142, 635 and 688 so all
      three passages describe skip-and-continue, and so the FAQ at 688 — the support chatbot's source
      for "why did my record get no journey" — says a record gets nothing only when no live
      template's rule matches (report: Fix, row 6). Verify with
      `grep -n "no other rule" docs/user_guides/workflow_templates_user_guide.md` returning nothing.
- [x] 5.2 Document the rule Status column and the index banner in the same guide, with an FAQ for
      "why is my new rule shadowed?" answering why, how and what happens.
- [x] 5.3 Update the mermaid diagram in the guide's enable/disable section to show the walk continuing
      past a disabled template, and lint every diagram in the file:
      `d=$(mktemp -d); echo '{"args":["--no-sandbox"]}' > $d/p.json; npx -y @mermaid-js/mermaid-cli -q -p $d/p.json -i docs/user_guides/workflow_templates_user_guide.md -o $d/out.md; echo exit=$?`
      exits 0. **Note:** this surfaced two pre-existing breakages in the same file (also broken at
      `537fef155`) — a participant named `Actor`, a reserved word, and a `;` inside a message, which
      mermaid reads as a statement separator. Both fixed, since the diagrams never rendered for users.
- [x] 5.4 Run the guide lint feature and confirm it is green:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/user_guide_lint.feature`.

## 6. Regression and cleanup

> **Archived with 6.1-6.4 open.** Phases 1-5 ran green: `workflow_auto_assignment.feature` and
> `workflow_templates.feature` 18/18 each on a clean `537fef155` base, `user_guide_lint.feature` 5/5,
> rubocop clean on the new and rewritten files, every guide diagram rendering. The wider runs below
> were stopped by the user before finishing. The journey and KYC features did complete — 79 scenarios,
> 3 failed (`capital_distribution_journey.feature:172`, `investor_kyc_journey.feature:136` and `:211`),
> all human sign-off scenarios unrelated to rule ordering, and never confirmed as pre-existing because
> the run's assertion text was lost to a grep filter. Worth re-checking against the base commit.


- [ ] 6.1 Run the feature directory the fix touches:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core` and confirm it is green.
- [ ] 6.2 Run the Blast Radius callers marked as needing checking:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/capital_call_journey.feature features/fund/capital_distribution_journey.feature`
      and confirm both are green — in particular the scenarios that disable every template for a
      kind, whose outcome must not change.
- [ ] 6.3 Run the investor KYC features, since the reported symptom was on KYCs:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_journey.feature features/core/investor_kyc_workflow_auto_assignment.feature`
      and confirm both are green.
- [ ] 6.4 Run `bundle exec rubocop` on every changed file and confirm no new offenses, including the
      `IRM/RelationBlankPresent` cop.
