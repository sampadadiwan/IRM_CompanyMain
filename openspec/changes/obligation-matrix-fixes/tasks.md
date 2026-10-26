# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Note:** This change is a bug-fix bundle. All code changes for phases 1-6 are already implemented
> on the branch `feature/obligation-matrix-fixes`. Phase 5 is being reworked per product feedback
> (remove `context` parameter, use legal category filter as primary scope). Phase 8 is new work.
> Tasks that are already done on the branch are noted.

## 1. Tag Splitting and Target Resolution (Boxes ①②)

- [x] 1.1 Modify `SideLetterObligationAgent#split_investment_doc_tags` to split the configured
      `investment_doc_tag` string on commas and trim whitespace from each tag. Verify by calling
      `agent.new.split_investment_doc_tags(agent_record)` in console with "SHA,SPA" and confirming
      `["SHA", "SPA"]` is returned.
      **LLD:** [Method Contracts](#method-contracts) — `split_investment_doc_tags`
      **Code traceability:** `# H1, H2 comma-split; E1 single tag; E2 whitespace trimmed`

- [x] 1.2 Modify `SideLetterObligationAgent#investment_tag_conditions` to build OR-combined LIKE
      conditions from the tag array instead of a single LIKE for the whole string. Verify by
      checking the generated SQL: `agent.new.investment_tag_conditions(["SHA", "SPA"]).to_sql`
      should produce `tag_list LIKE '%SHA%' OR tag_list LIKE '%SPA%'`.
      **LLD:** [Queries and Indexes](#queries-and-indexes) — tag matching query

- [x] 1.3 Modify `SideLetterObligationAgent#portfolio_investment_targets` to use the split tags
      and OR conditions. Verify by running
      `CpCsExtractionAgent.new.targets(entity_id)` in console for an entity with mixed SHA/SPA
      documents and confirming the correct PIs are returned.
      **LLD:** [Method Contracts](#method-contracts) — `portfolio_investment_targets`

- [x] 1.4 Write/update `features/ai/cp_cs_extraction_agent.feature` scenarios covering:
      H1 (multi-tag single PI), H2 (batch with comma tags), E1 (single tag), E2 (whitespace),
      E3 (zero targets), E4 (PI with no matching docs).
      Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/cp_cs_extraction_agent.feature`
      and confirm it passes before starting phase 2.

## 2. Dispatch Router Fix (Box ③)

- [x] 2.1 Modify `SupportAgentJob#resolve_step_ui_target` to change the condition from
      `count == 1` to `count >= 1`, so the Entity fallback only fires when the agent returns zero
      sub-targets. Add YARD comment explaining the logic.
      Verify by confirming the CP/CS agent can be run from a PI page without the
      "CapitalCommitment expected, got Entity" error.
      **LLD:** [Method Contracts](#method-contracts) — `resolve_step_ui_target`
      **Code traceability:** `# H3 step-UI dispatch; E3 zero targets → Entity fallback; X1 graceful empty`

- [x] 2.2 The `cp_cs_extraction_agent.feature` from phase 1 already covers H3 (run from PI page)
      and X1 (Entity fallback on zero targets). Confirm those scenarios still pass:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/cp_cs_extraction_agent.feature`

## 3. Extraction Pipeline — Multi-Document Support (Box ④)

- [x] 3.1 Modify `CpCsExtractionAgent#locate_side_letter` to collect ALL matching documents per
      PI (not just the first). Verify by running the agent on a PI with SHA + SPA docs and
      confirming both appear in `ctx[:pi_docs]`.
      **LLD:** [File Map](#file-map) — `cp_cs_extraction_agent.rb`
      **Code traceability:** `# H1 multi-doc locate; E5 dedup across docs`

- [x] 3.2 Modify `CpCsExtractionAgent#extract_obligations` to iterate each document per PI,
      calling the LLM separately for each. Verify extraction count reflects obligations from all
      documents.
      **Code traceability:** `# H1 multi-doc extract; X2 LLM failure handled`

- [x] 3.3 Modify `CpCsExtractionAgent#upsert_obligations` to handle the multi-document extraction
      results. Dedup is handled by existing `upsert_portfolio_obligations` matching on
      source_clause. Verify by confirming no duplicate obligations when both SHA and SPA docs
      mention the same clause.
      **Code traceability:** `# E5 dedup across docs on same PI`

- [x] 3.4 Add `CpCsExtractionAgent.config_issues` to validate `investment_doc_tag` is set and
      `notify_tag` has matching employees.
      **LLD:** [Method Contracts](#method-contracts) — `.config_issues`

- [x] 3.5 Confirm `features/ai/cp_cs_extraction_agent.feature` covers E5 (dedup) and X2 (LLM
      failure). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/cp_cs_extraction_agent.feature`
      and confirm green before starting phase 4.

## 4. Progress Panel and Run Button (Box ⑦)

- [x] 4.1 Add the "Run CP/CS Agent" button and `cp_cs_progress_wrapper` fixed-ID wrapper div to
      `portfolio_investments/show.html.erb`. Verify the button appears when the agent is enabled
      and the wrapper div has a predictable ID.
      **LLD:** [File Map](#file-map) — `portfolio_investments/show.html.erb`
      **Code traceability:** `# H3 run from PI page; E8 no duplicate panels`

- [x] 4.2 Modify `SupportAgentsController#run` to send dual Turbo Stream replace targets:
      `progress_panel_#{report.id}` and `cp_cs_progress_wrapper`. Verify by running the agent
      and confirming the panel appears in the wrapper.
      **LLD:** [Controllers, Params and Responses](#controllers-params-and-responses)
      **Code traceability:** `# E8 navigate away/return → single panel`

- [x] 4.3 Add estimated closing date input to the agent run modal. Verify the date is passed to
      the extraction prompt via `ctx[:estimated_closing_date]`.
      **LLD:** [File Map](#file-map) — `_agent_run_modal.html.erb`

- [x] 4.4 Confirm `features/ai/cp_cs_extraction_agent.feature` covers E8 (navigate away/return).
      Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/cp_cs_extraction_agent.feature`
      and confirm green before starting phase 5.

## 5. Unified Matrix with Legal Category Filter (Box ⑤) — REWORK

> **Rework note:** This phase replaces the `context` parameter approach with a unified matrix
> where the legal category Ransack filter is the primary scoping mechanism. The stakeholder
> dropdown adapts based on the selected legal category. This is new work that replaces the
> existing phase 5 implementation on the branch.

- [x] 5.1 Remove the `context` parameter from `SideLetterObligationsController#index`:
      - Remove `@obligation_context = params[:context]`
      - Remove the context-based `where(legal_category:)` scoping block
      - Remove `context:` from breadcrumb path
      - Simplify breadcrumb to `{ 'Obligation Matrix': side_letter_obligations_path }`
      Verify by loading the matrix — title should always be "LP Obligation Matrix".
      **LLD:** [Controllers, Params and Responses](#controllers-params-and-responses)
      **Why:** Product feedback — one unified matrix with the Ransack filter as primary scope.

- [x] 5.2 Add stakeholder scoping by legal category in `SideLetterObligationsController#index`:
      - Read `legal_cat = params.dig(:q, :legal_category_eq)`
      - When legal_cat is "0" or "1" (CP/CS): `@stakeholders` = portfolio companies from
        `Investor.where(id: PortfolioInvestment.where(id: SideLetterObligation.where(entity_id:, sourceable_type: 'PortfolioInvestment').select(:sourceable_id)).select(:portfolio_company_id))`
      - When legal_cat is "2" (SLO): `@stakeholders` = investors from the capital commitment →
        side letter chain
      - When blank: `@stakeholders` = union of both sets (current behavior)
      Verify by filtering by legal category and checking the stakeholder dropdown options.
      **LLD:** [Queries and Indexes](#queries-and-indexes) — stakeholder scoping
      **Why:** When viewing CP/CS obligations, showing LP names in the stakeholder filter is
      confusing — those are for SLO. The dropdown should show relevant stakeholders.

- [x] 5.3 Modify `index.html.erb` to remove all context-driven logic:
      - Remove the `@obligation_context` conditional for title — always "LP Obligation Matrix"
      - Remove the context-driven info banner — replace with one unified banner explaining all
        obligation types
      - Remove the hidden `context` field from the search form
      - Remove the `context:` param from the "Clear" link
      - Keep `show_legal_category` always true (legal category column always visible)
      - Legal category filter always shows all options (no context-based exclusion)
      Verify by loading the matrix with and without legal_category_eq param.
      **LLD:** [File Map](#file-map) — `index.html.erb`
      **Why:** No more three virtual pages — one page with standard Ransack filtering.

- [x] 5.4 Keep the matrix breadcrumb simple — just link to the matrix without any context params.
      Remove the misleading "Side Letters" link for portfolio-sourced obligations in the show
      action breadcrumb.
      **Code traceability:** `# breadcrumb no longer carries context`

- [x] 5.5 Keep fund_id and stakeholder_id subquery-based filters (already working).
      Verify by filtering by fund and stakeholder in combination with legal category filter.
      **LLD:** [Queries and Indexes](#queries-and-indexes) — fund/stakeholder filters

- [ ] 5.6 Write/update `features/fund/side_letter_matrix.feature` covering:
      H4 (matrix with legal category pre-selected), E6 (SLO filter shows LP stakeholders),
      E7 (filter preserved), E9 (no filter shows all stakeholders), E10 (clear filters).
      Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/side_letter_matrix.feature`
      and confirm green before starting phase 6.

## 6. Form Helpers and Edit Form Scoping (Box ⑥)

- [x] 6.1 Add `legal_category_form_options` helper to `SideLetterObligationsHelper` returning
      string enum keys. Keep existing `legal_category_options` unchanged (integer values for
      Ransack). Verify by calling both in console and confirming the different value types.
      **LLD:** [Method Contracts](#method-contracts) — `SideLetterObligationsHelper`
      **Code traceability:** `# H5 edit saves; X3 old integer bug fixed`

- [x] 6.2 Update `_form.html.erb` to use `legal_category_form_options` instead of
      `legal_category_options`. Hide MFN checkbox for CP/CS obligations. Exclude SLO option from
      legal category dropdown for CP/CS. Verify by opening the edit form for a CP obligation.
      **LLD:** [File Map](#file-map) — `_form.html.erb`

- [x] 6.3 Update `_inline_edit_row.html.erb` to use `legal_category_form_options`. Verify inline
      edit saves without ArgumentError.
      **LLD:** [File Map](#file-map) — `_inline_edit_row.html.erb`

- [x] 6.4 Verify the Ransack filter on the matrix index page still uses `legal_category_options`
      (integer values) and works correctly. Filter by "Condition Precedent" and confirm results.
      **Code traceability:** `# E7 Ransack filter uses integer values`

- [x] 6.5 Write/update `features/fund/side_letter_obligation_e2e.feature` covering H5 (edit
      legal category), X3 (old integer bug fixed). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/side_letter_obligation_e2e.feature`
      and confirm green before starting phase 7.

## 7. Documentation, Traceability and QA

- [x] 7.1 Add/update business and technical design docs under `docs/cp_cs_extraction_agent/`.
      **LLD:** [File Map](#file-map) — design docs

- [ ] 7.2 Verify traceability: list every H/E/X ID in design.md and every ID comment in
      `features/ai/cp_cs_extraction_agent.feature`, `features/fund/side_letter_matrix.feature`,
      and `features/fund/side_letter_obligation_e2e.feature`. Confirm the two sets are equal —
      no ID without a scenario, no scenario without an ID. If a new edge case was found during
      implementation, add it to design.md AND as a scenario.

- [ ] 7.3 Run all Cucumber features together to confirm no regressions:
      ```
      TEST_ENV_NUMBER=$RANDOM bundle exec cucumber \
        features/ai/cp_cs_extraction_agent.feature \
        features/fund/side_letter_matrix.feature \
        features/fund/side_letter_obligation_e2e.feature \
        features/ai/support_agents/side_letter_obligation_agent.feature
      ```

- [ ] 7.4 Deploy to staging (`bundle exec cap staging deploy`) and run qa-checklist.md against
      the deployed build. Record the sign-off in qa-checklist.md.

## 8. SLO Agent on Commitment Page and CP/CS Redirect (Boxes ⑧ + ④ redirect)

> **New phase:** Adds the "Run SLO Agent" button to the capital commitment show page and
> updates CP/CS agent redirect URLs to use Ransack params with optional stakeholder pre-filter.

- [x] 8.1 Add "Run SLO Agent" button and `slo_progress_wrapper` fixed-ID wrapper div to
      `capital_commitments/show.html.erb`. Button visible only when the SLO agent is enabled
      for the entity. Uses the same pattern as the CP/CS button on the PI page.
      **LLD:** [File Map](#file-map) — `capital_commitments/show.html.erb`
      **Code traceability:** `# H6 SLO from commitment page`
      **Why:** Admins need a quick way to run SLO extraction for a single commitment without
      going to the batch page — mirrors the CP/CS button on PI page.

- [x] 8.2 Modify `SupportAgentsController#run` to handle the `slo_progress_wrapper` target for
      SLO agent runs from the commitment page. Dual Turbo Stream replace targets:
      `progress_panel_#{report.id}` and `slo_progress_wrapper`.
      **LLD:** [Controllers, Params and Responses](#controllers-params-and-responses)
      **Why:** Same fixed-wrapper pattern as CP/CS to prevent duplicate panels on navigation.

- [x] 8.3 Override `CpCsExtractionAgent#broadcast_redirect_to_matrix` to redirect all
      single-target runs to the standalone matrix with stakeholder pre-filter:
      - `report.owner` is `Investor` (company-scoped) → `stakeholder_id: investor.id`
      - `report.owner` is `PortfolioInvestment` (single PI) → `stakeholder_id: pi.portfolio_company_id`
      - Otherwise (Entity/batch) → agent show page (parent behaviour)
      All matrix redirects use `q: { legal_category_eq: 0 }`.
      **LLD:** [Controllers, Params and Responses](#controllers-params-and-responses)
      **Code traceability:** `# H7 single-company redirect; H4 legal category pre-selected`
      **Why:** After running the agent on a single PI or company, counsel expects to land
      on that company's obligations — not all obligations across the entity.

- [x] 8.4 Override `SideLetterObligationAgent#broadcast_redirect_to_matrix` to redirect
      single-commitment runs directly to the standalone matrix with
      `side_letter_obligations_path(q: { legal_category_eq: 2 }, stakeholder_id: investor.id)`
      so counsel lands on that LP's SLO obligations without manual filtering. Batch runs
      (report.owner is Entity) fall back to the agent show page (parent behaviour).
      **Code traceability:** `# H6 SLO agent redirect with legal category and stakeholder`
      **Why:** Mirrors the CP/CS single-company redirect pattern — after running the agent
      on a specific commitment, the user expects to see only that LP's obligations.

- [x] 8.5 Update agent show page / results tabs to use "Open Obligation Matrix" as the button
      text (replacing any context-specific wording like "CP/CS Obligation Matrix" or
      "Side Letter Obligation Matrix"). The link includes the appropriate `legal_category_eq`
      Ransack param.
      **Code traceability:** `# H4 agent link pre-selects legal category`
      **Why:** Unified button text reflects that there is one matrix page with filter
      pre-selection, not separate context-driven pages.

- [x] 8.6 Add batch redirect hook in `SupportAgentJob`: after `broadcast_batch_complete`,
      call `agent_class.broadcast_batch_redirect(support_agent.id)` if the agent class
      responds to it and there were successes. Both CP/CS and SLO agents define
      `broadcast_batch_redirect` to redirect to the agent's Obligations tab
      (`support_agent_path(support_agent, tab: "obligations")`). Other agents are
      unaffected (guarded by `respond_to?`).
      **Why:** "Run Now" on the agent General tab goes through `SupportAgentJob`'s
      inline loop, not `process_batch` — the redirect must be hooked in the job.

- [x] 8.7 Add trigger type icons to the obligation matrix row partial
      (`_side_letter_obligation.html.erb`). In the Type column, after
      `obligation.obligation_type.humanize`, add a conditional icon:
      - `obligation.recurring?` → `<i class="ti ti-repeat text-info">` with tooltip "Recurring"
      - `obligation.trigger_one_time? || obligation.trigger_calendar_event?` → `<i class="ti ti-calendar-event text-muted">` with tooltip "One-time"
      - `obligation.trigger_type.in?(%w[fund_event deal_event status_change ongoing])` → `<i class="ti ti-bolt text-warning">` with tooltip "Event-driven"
      Icons are mutually exclusive (if/elsif/elsif). Applies to all legal categories
      (CP, CS, SLO) since the partial is shared. No new queries — uses existing model methods.
      **Code traceability:** `# H9 trigger type icons on matrix rows`
      **Why:** Product feedback — counsel needs to see if an obligation is recurring before
      approving, without opening the edit form.

- [ ] 8.8 Write/update Cucumber scenarios covering:
      H6 (SLO from commitment page), H7 (single-company CP/CS redirect with stakeholder).
      Run:
      ```
      TEST_ENV_NUMBER=$RANDOM bundle exec cucumber \
        features/ai/cp_cs_extraction_agent.feature \
        features/ai/support_agents/side_letter_obligation_agent.feature
      ```
      and confirm green before proceeding to phase 7 (final verification).
