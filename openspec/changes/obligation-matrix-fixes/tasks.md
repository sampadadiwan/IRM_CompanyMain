# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Note:** This change is a bug-fix bundle. All code changes are already implemented on the branch
> `feature/obligation-matrix-fixes`. The tasks below reflect the implementation order and the
> verification steps needed to confirm each fix works. Most Cucumber tests already exist on the
> branch (`features/ai/cp_cs_extraction_agent.feature`). Tasks that are already done on the branch
> are noted.

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

## 5. Context-Aware Obligation Matrix (Box ⑤)

- [x] 5.1 Modify `SideLetterObligationsController#index` to accept a `context` param and
      pre-filter the scope: `cp_cs` → CP and CS only, `side_letter` → SLO only, nil → all.
      Preserve context in breadcrumb and hidden form field. Verify by loading the matrix with
      `?context=cp_cs` and confirming only CP/CS obligations appear.
      **LLD:** [File Map](#file-map) — `side_letter_obligations_controller.rb`, [Queries and Indexes](#queries-and-indexes)
      **Code traceability:** `# H4 CP/CS context; E6 SLO context; E7 context preserved`

- [x] 5.2 Modify `index.html.erb` to adapt title, info banner text, legal category filter
      visibility, and hidden `context` field based on `@obligation_context`. Verify each context
      mode shows the correct title and filter options.
      **LLD:** [File Map](#file-map) — `index.html.erb`

- [x] 5.3 Modify `_matrix.html.erb` to conditionally show/hide the legal category column based on
      `show_legal_category` local. Wire the existing Stimulus `datatable` controller for
      client-side sorting. Verify sorting works by clicking column headers.
      **LLD:** [File Map](#file-map) — `_matrix.html.erb`

- [x] 5.4 Fix the matrix breadcrumb to include `context` in the URL and remove the misleading
      "Side Letters" link for CP/CS context.
      **Code traceability:** `# E7 context preserved in breadcrumb`

- [x] 5.5 Add fund_id and stakeholder_id subquery-based filters to avoid polymorphic JOIN issues.
      Verify by filtering by fund in CP/CS context and confirming correct results.
      **LLD:** [Queries and Indexes](#queries-and-indexes) — fund/stakeholder filters

- [x] 5.6 Write/update `features/fund/side_letter_matrix.feature` covering H4 (CP/CS matrix),
      E6 (SLO matrix context), E7 (context preserved across filter). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/side_letter_matrix.feature`
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
