# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

## 1. Query Service + Stat Cards

- [x] 1.0 Add `kyc_basic_stats` method to `AgentReportsQuery` — counts ALL entity KYCs by `submission_status` using `InvestorKyc.where(entity_id:).group(:submission_status).count`. Returns `{not_sent: Integer, link_sent: Integer, draft_saved: Integer, completed: Integer, verified: Integer}`. No join needed. Verify in `rails c`. (Design: [card ③a](design.md#③a-basic-metrics))
- [x] 1.0b Create `_kyc_dashboard_basic_stats.html.erb` partial rendering 5 cards using `NumberStatsComponent`. Each card is a `link_to` that navigates to the normal KYC page (`investor_kycs_path(status: value)`). Section label: "KYC Form Status". Include YARD-style ERB header comment. (Design: [card ③a](design.md#③a-basic-metrics))
- [x] 1.1 Add `kyc_dashboard_data` method to `AgentReportsQuery` returning `{basic_stats:, stats:, chart_data:, records:, pagy:, top_failures:, pending_ids:}`. Implement `kyc_stat_counts` using a LEFT JOIN on `support_agent_reports` (latest=true) with COUNT + CASE WHEN for the 6 buckets (validated, pending, successful, failed, partial, expired). **Expired is mutually exclusive:** pending, successful, failed, and partial CASE WHENs must exclude expired KYCs (`AND (investor_kycs.expiry_date IS NULL OR investor_kycs.expiry_date >= CURDATE())`). Stat card counts must sum to Validated. Add `kyc_pending_ids` — returns IDs of completed KYCs with no latest report from this agent (used by bulk run button to pass `target_ids[]` to `run_batch`). Verify by running `rails c` and calling the method on a test agent. (LLD: [Method Contracts](lld.md#method-contracts), [Queries and Indexes](lld.md#queries-and-indexes))
- [x] 1.2 Add `kyc_chart_data` to `AgentReportsQuery` — same base query as stat counts but with GROUP BY `kyc_type`, returning `{individual: Hash, non_individual: Hash}`. **Same expired-first exclusion applies** — successful/failed/partial counts in the chart exclude expired KYCs. Verify shape in console.
- [x] 1.3 Add `kyc_top_failures(limit: 5)` to `AgentReportsQuery` — query latest reports for blocking field_issues and document_issues, aggregate by message, return top 5. Each failure reason also collects affected investor names and KYC IDs for drill-down. Return shape: `[{message:, count:, affected: [{kyc_id:, investor_name:}]}]`. (LLD: [Queries and Indexes](lld.md#queries-and-indexes))
- [x] 1.4 Add `kyc_filtered_records(params)` to `AgentReportsQuery` — filtered, paginated InvestorKyc scope with `includes(:investor, :support_agent_report, :documents)`. Supports filters: `status`, `kyc_type`, `q` (search), `fund_id`, `date_from`, `date_to`, `page`. Fund filter uses subquery on `capital_commitments`. Returns `[pagy, records]`. (LLD: [Queries and Indexes](lld.md#queries-and-indexes))
- [x] 1.4b Add `kyc_doc_ratios(kyc_ids)` to `AgentReportsQuery` — for a batch of KYC IDs, compute `{kyc_id => {uploaded: Integer, required: Integer}}`. Required = FormCustomField File-type required fields for the KYC's form_type + agent's `required_docs` config. Uploaded = `Document.where(owner_type: 'InvestorKyc', owner_id: kyc_ids).group(:owner_id).count`. Two queries total to avoid N+1. (LLD: [Queries and Indexes](lld.md#queries-and-indexes))
- [x] 1.5 Create `KycDashboardHelper` in `app/packs/ai/support_agents/helpers/kyc_dashboard_helper.rb` with methods: `kyc_agent_status`, `kyc_result_summary`, `kyc_doc_ratio`, `kyc_doc_ratio_color`, `kyc_run_output_items`, `show_mark_verified?`. (LLD: [Method Contracts](lld.md#method-contracts))
- [x] 1.6 Modify `SupportAgentsController#show` to call `@kyc_dashboard = query.kyc_dashboard_data(params)` when `@support_agent.agent_type == "KycOnboardingAgent"`. (LLD: [Controllers, Params and Responses](lld.md#controllers-params-and-responses))
- [x] 1.7 Create `_kyc_dashboard_stats.html.erb` partial rendering 6 stat cards using `NumberStatsComponent`. Each card links to the Turbo Frame with `?status=<value>`. Include YARD-style ERB header comment.
- [x] 1.8 Modify `show.html.erb` to add "KYC Dashboard" tab link and tab pane (conditional on `@support_agent.agent_type == "KycOnboardingAgent"`). Tab pane renders `_kyc_dashboard_tab.html.erb`.
- [x] 1.9 Create `_kyc_dashboard_tab.html.erb` — layout partial rendering `_kyc_dashboard_basic_stats` (Row 1 with "KYC Form Status" label) then `_kyc_dashboard_stats` (Row 2 with "Agent Validation Status" label), with "Run Agent on All Pending" button (hidden form POSTing `target_ids[]` + `target_type` to `run_batch`), `turbo_stream_from` subscription for batch progress channel, and empty `#batch_progress_panel` div. Include empty placeholders for charts and table (filled in phase 2 and 3).
- [x] 1.10 Write `features/ai/support_agents/kyc_agent_dashboard.feature` Phase 1 scenarios covering: H1 (dashboard loads with stats), H1b (basic metrics row shows form status counts and navigates to KYC page), E1 (no completed KYCs — basic metrics still show form statuses), E2 (all pending). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/support_agents/kyc_agent_dashboard.feature` and confirm green before starting phase 2.

## 1b. Bug Fixes (product call 2026-11-02)

- [x] 1b.1 Investigate non-individual count bug — dashboard shows 0 non-individuals but entity has 8. Check: (a) are the non-individual KYCs in "completed" status? (b) is `kyc_type` classification in chart query correct? (c) is the `GROUP BY kyc_type` value matching "Non-Individual" exactly? Fix the root cause. (Design: known issue from product call)

## 2. Charts + Top Failure Reasons

- [x] 2.1 Create `_kyc_dashboard_charts.html.erb` partial with two half-donut charts using Chartkick `pie_chart(data, donut: true)`. Apply CSS half-donut technique (container `height: 200px; overflow: hidden;`, chart height `400px`). Include legend. Show empty state when no KYCs of a type exist. Include YARD-style ERB header comment. (Design: [card ④](design.md#④-charts))
- [x] 2.2 Add top failure reasons section to the charts partial — collapsible ordered list of top 5 failures from `top_failures` array. Each failure reason is clickable and expands to show the list of affected investor names (as links to their KYC pages). Clicking again collapses. Show "No failures found" when empty.
- [x] 2.3 Wire charts partial into `_kyc_dashboard_tab.html.erb` (replace placeholder).
- [x] 2.4 Add scenarios to `kyc_agent_dashboard.feature` covering: H5 (charts correct breakdown), E4 (no KYCs of one type), E7 (no failures). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/support_agents/kyc_agent_dashboard.feature` and confirm green before starting phase 3.

## 3. KYC Table + Filters + Stimulus Controller

- [x] 3.1 Create `_kyc_dashboard_table.html.erb` partial inside a `<turbo-frame id="kyc-dashboard-table">`. Table with columns: KYC ID, Customer Name, Customer Type, Submitted On, Status (badge), Docs (X/Y with color), Agent Run On, Result Summary, Actions. Uses Pagy pagination. Docs column uses `kyc_doc_ratio` and `kyc_doc_ratio_color` helpers with `doc_ratios` hash from query. Include YARD-style ERB header comment. (Design: [card ⑤](design.md#⑤-kyc-table))
- [x] 3.2 Add filter form within the Turbo Frame: search box, Customer Type dropdown, Status dropdown, Submitted On date range, Fund dropdown, "Clear Filters" button. Form submits target the `kyc-dashboard-table` Turbo Frame.
- [x] 3.3 Create `kyc_dashboard_filter_controller.js` Stimulus controller: manages stat card active state (CSS class toggle), sends Turbo Frame requests with `?status=` param on card click, handles clear-filters. Include JSDoc header comment. (LLD: [File Map](lld.md#file-map))
- [x] 3.4 Wire table partial into `_kyc_dashboard_tab.html.erb` (replace placeholder). Wire stat cards to Stimulus controller.
- [x] 3.5 Add action icons column to table rows: eye (detail), play (re-run), check (verify). Use `show_mark_verified?` helper for conditional visibility.
- [x] 3.6 Add scenarios to `kyc_agent_dashboard.feature` covering: H2 (stat card filter), H3 (stat card toggle), H8 (docs column ratio), E3 (combined filters), E5 (expired mutually exclusive), E6 (fund filter), E9 (eye disabled for pending), E10 (mark verified hidden). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/support_agents/kyc_agent_dashboard.feature` and confirm green before starting phase 4.

## 4. Detail Panel + Inline Actions

- [x] 4.1 Add `kyc_run_output` member action to `SupportAgentsController`. Authorize with `show?`. Load report by ID, verify it belongs to the agent's entity. Respond with Turbo Frame rendering the panel partial. Add route in `config/routes/ai.rb`. (LLD: [Controllers, Params and Responses](lld.md#controllers-params-and-responses), [Security Review](lld.md#security-review))
- [x] 4.2 Rework `_kyc_run_output_panel.html.erb` — change from slide-out overlay to inline expand below row. Panel renders inside `<td colspan="N">` within a hidden `<tr class="kyc-detail-row">` sibling of each KYC row. Header shows KYC ID, Customer Name, Run Date. Item table with columns: Item, Expected/Provided, Matched, Status. Tabs: All Items, Matched, Failed, Warning. Close button collapses the row. Include YARD-style ERB header comment. (Design: [card ⑥](design.md#⑥-detail-panel))
- [x] 4.3 Rework `kyc_run_output_controller.js` Stimulus controller: toggle detail row visibility (show/hide `kyc-detail-row` sibling), tab filtering (show/hide items by `data-status`), close button. Remove slide animation, Escape key, and click-outside-to-close (no longer applicable for inline panel). Include JSDoc header comment.
- [x] 4.4 Wire inline actions (3 fixes required):
  - **Eye icon (View Details):** Each table row has a sibling `<tr class="kyc-detail-row d-none">` with `<td colspan="N"><turbo-frame id="kyc_run_output_frame_<kyc_id>">`. Eye icon link targets this per-row frame. Stimulus controller toggles visibility on click.
  - **Play icon (Re-run Agent):** Change from `link_to ... method: :post, data: { turbo_method: :post }` to `button_to run_with_steps_support_agent_path(...)` with `data: { turbo: false }` so the HTML format redirect fires (turbo_stream targets `progress_panel_new` which doesn't exist on this tab).
  - **Check icon (Mark Verified):** Fix HTTP method from `:patch` to `:put` (route is PUT). Use `button_to` with `method: :put` and `data: { turbo: false }` so the redirect to `investor_kyc_url` doesn't break the dashboard flow.
  (Design: [card ⑦](design.md#⑦-inline-actions))
- [x] 4.5 Add scenarios to `kyc_agent_dashboard.feature` covering: H6 (panel opens), H7 (mark verified), E8 (panel tab filter), X2 (re-run agent). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/support_agents/kyc_agent_dashboard.feature` and confirm green before starting phase 5.

## 5. Bulk Run + Polish

- [x] 5.1 Wire "Run Agent on All Pending" button: hidden form POSTs `target_ids[]` (from `kyc_pending_ids`) + `target_type=InvestorKyc` to `run_batch`. Uses `data-turbo-confirm` for confirmation (shows pending count). `_kyc_dashboard_tab.html.erb` must include `turbo_stream_from "batch_progress_#{support_agent.id}"` for ActionCable subscription and an empty `#batch_progress_panel` div. Button disabled when pending=0. Stats and table refresh on batch completion via `batch-progress` Stimulus controller's auto-reload. (Design: [card ②](design.md#②-dashboard-tab))
- [x] 5.2 Add scenarios to `kyc_agent_dashboard.feature` covering: H4 (bulk run), X1 (bulk run failure). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/support_agents/kyc_agent_dashboard.feature` and confirm green before starting phase 6.

## 5b. Docs Column Tooltip + Documents Tab (product call 2026-11-02)

- [x] 5b.1 Enhance `kyc_doc_ratios` in `AgentReportsQuery` — now takes records (not just IDs), returns `{uploaded:, required:, required_names:, uploaded_names:, missing_names:}` per KYC. Two bulk queries: `FormCustomField.pluck(:form_type_id, :label, :name)` for required names, `Document.pluck(:owner_id, :name)` for uploaded names. Missing computed via normalized name matching (same as `InvestorKycConcern`). (Design: [decision #14](design.md#design-decisions))
- [x] 5b.2 Add `kyc_doc_tooltip(ratio)` helper in `KycDashboardHelper` — builds multiline tooltip: "Required: ... / Uploaded: ... / Missing: ...". Keep existing `kyc_doc_ratio` and `kyc_doc_ratio_color` for the column text.
- [x] 5b.3 Update `_kyc_dashboard_table.html.erb` Docs column to add `title=` tooltip attribute with dotted underline style (`cursor: help`). Upload ratio text unchanged.
- [x] 5b.4 Tag items in `kyc_run_output_items` with `source:` — field_issues get `source: :field`, document_issues get `source: :document`. Add `data-source` attribute to each `<tr>` in the run output panel.
- [x] 5b.5 Add "Documents" tab to `_kyc_run_output_panel.html.erb` — add to the tabs loop alongside all/matched/failed/warning. Update `kyc_run_output_counts` to include `"documents"` count.
- [x] 5b.6 Update `kyc_run_output_controller.js` to handle the "documents" tab filter — show only items where `data-source="document"`.
- [x] 5b.7 Verify on local: Docs column shows upload ratio with tooltip on hover, Documents tab filters correctly in detail panel. Confirm no N+1.

## 6. Traceability + Final Verification

- [x] 6.1 Verify traceability: list every H/E/X ID in design.md's worked examples and every ID comment in `features/ai/support_agents/kyc_agent_dashboard.feature`. Confirm the two sets are equal — no ID without a scenario, no scenario without an ID. Add missing IDs if any were discovered during implementation.
- [x] 6.2 Add ID comments to code: each service method, helper, partial, and significant branch (guard, refusal, skip) gets a comment naming the H/E/X IDs whose path runs through it.
- [x] 6.3 Run full feature: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/support_agents/kyc_agent_dashboard.feature` — all scenarios green.
- [x] 6.4 Run `bundle exec rubocop` on all new/modified files — clean.
- [x] 6.5 Run qa-checklist.md on a deployed build and record the sign-off in the checklist's Sign-off table.
