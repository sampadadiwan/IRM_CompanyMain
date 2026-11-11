# Spec Delta

## Purpose

Provides Fund Managers a centralized dashboard on the KYC Onboarding Agent page to monitor, filter, act on, and analyse KYC validation results across their entity.

## ADDED Requirements

### Requirement: Dashboard tab visibility

The KYC Onboarding Agent show page SHALL display a "KYC Dashboard" tab after the "Execution History" tab. The tab SHALL appear only when the agent type is `KycOnboardingAgent`. Clicking it SHALL load the dashboard content without a full page reload.

#### Scenario: Tab appears for KYC Onboarding Agent
- **WHEN** a user opens the show page of a SupportAgent with agent_type "KycOnboardingAgent"
- **THEN** a "KYC Dashboard" tab is visible after "Execution History"

#### Scenario: Tab does not appear for other agent types
- **WHEN** a user opens the show page of a SupportAgent with agent_type "PortfolioCompanyAgent"
- **THEN** no "KYC Dashboard" tab is visible

### Requirement: Stat cards display

The dashboard SHALL display six stat cards at the top: "KYCs Validated", "Pending to be Validated", "Successful", "Failed", "Partially Failed", and "Expired". Each card SHALL show a count and a percentage of the total. Counts SHALL be computed as follows:

- **KYCs Validated**: count of completed InvestorKycs in the agent's entity
- **Pending to be Validated**: completed InvestorKycs with no latest SupportAgentReport for this agent AND not expired
- **Successful**: InvestorKycs whose latest report has final_status "ready" AND not expired
- **Failed**: InvestorKycs whose latest report has final_status "blocked" and zero field_issues or document_issues with severity "success" or type "info" AND not expired
- **Partially Failed**: InvestorKycs whose latest report has final_status "blocked" and at least one field_issue or document_issue with severity "success" or type "info" AND not expired
- **Expired**: InvestorKycs whose expiry_date is in the past — this takes priority over all other statuses

Expired is mutually exclusive: Pending + Successful + Failed + Partially Failed + Expired SHALL equal KYCs Validated.

#### Scenario: All six stat cards render with correct counts
- **WHEN** the entity has 100 completed KYCs, 20 with no report (none expired), 48 with ready reports (none expired), 2 with ready reports but expired, 13 with blocked/all-failing reports (none expired), 2 with blocked/all-failing but expired, 8 with blocked/some-matching reports (none expired), 2 with blocked/some-matching but expired, and 5 more with no report but expired
- **THEN** the cards show: Validated=100, Pending=20, Successful=48, Failed=13, Partially Failed=8, Expired=11 (2+2+2+5). Counts sum to 100.

#### Scenario: No completed KYCs
- **WHEN** the entity has zero completed InvestorKycs
- **THEN** all six stat cards show 0 and an empty-state message appears below

### Requirement: Stat card filtering

Clicking a stat card SHALL filter the table below to show only KYCs matching that status. Clicking the same card again SHALL clear the filter. Only one stat card filter SHALL be active at a time — selecting a new card SHALL deselect the previous one. The active card SHALL have a visually highlighted state (distinct border or background).

#### Scenario: Click stat card to filter table
- **WHEN** a user clicks the "Failed" stat card
- **THEN** the table shows only KYCs with a blocked report and zero matched items, and the "Failed" card is highlighted

#### Scenario: Click same stat card to clear filter
- **WHEN** a user clicks the "Failed" stat card while it is already active
- **THEN** the table returns to showing all KYCs and no card is highlighted

#### Scenario: Click different stat card replaces filter
- **WHEN** the "Failed" card is active and the user clicks "Successful"
- **THEN** the table shows only successful KYCs, "Successful" is highlighted, and "Failed" is no longer highlighted

### Requirement: KYC table display

The dashboard SHALL display a paginated table of InvestorKycs with columns: KYC ID, Customer Name, Customer Type (Individual / Non-Individual), Submitted On, Status, Docs (uploaded/required), Agent Run On, Result Summary, and Actions. Pagination SHALL default to 10 rows per page.

#### Scenario: Table renders with correct columns
- **WHEN** the dashboard loads with completed KYCs in the entity
- **THEN** the table displays rows with KYC ID, Customer Name, Customer Type, Submitted On, Status, Docs, Agent Run On, Result Summary, and Actions columns

#### Scenario: Result Summary format
- **WHEN** a KYC's latest report checked 12 items and 8 matched
- **THEN** the Result Summary column shows "8 of 12 items matched" with a fraction "8 / 12"

#### Scenario: Pending KYC row
- **WHEN** a KYC has no latest SupportAgentReport
- **THEN** Status shows "Pending", Agent Run On shows "—", and Result Summary shows "—"

### Requirement: Table filters

The table SHALL provide: a free-text search box (searches KYC ID, Customer Name, PAN), a Customer Type dropdown (All / Individual / Non-Individual), a Status dropdown (All / Pending / Successful / Failed / Partially Failed / Expired), a Submitted On date range picker, and a "Clear Filters" button. All filters SHALL combine with AND logic. Stat card filters SHALL combine with dropdown/search filters using AND logic.

#### Scenario: Filter by Customer Type
- **WHEN** the user selects "Non-Individual" in the Customer Type dropdown
- **THEN** only KYCs with kyc_type "Non-Individual" (NonIndividualKyc) are shown

#### Scenario: Combined stat card and dropdown filter
- **WHEN** the "Failed" stat card is active and the user selects "Individual" in Customer Type
- **THEN** only failed Individual KYCs are shown

#### Scenario: Clear filters
- **WHEN** the user clicks "Clear Filters"
- **THEN** all dropdown filters reset to "All", the search box clears, the date range clears, and any active stat card filter is removed

### Requirement: Run output detail panel

Each table row with a completed agent report SHALL have an action icon (eye icon) that opens a slide-out panel showing the item-wise validation results. The panel header SHALL show the KYC ID, Customer Name, and Run Date. The panel body SHALL display a table with columns: Item, Expected/Provided, Matched, Status (Matched / Partial / Failed). The panel SHALL have tabs: All Items, Matched, Failed, Partial — each filtering the item list. The panel SHALL close on clicking a Close button, clicking outside it, or pressing Escape.

#### Scenario: Open run output panel
- **WHEN** the user clicks the eye icon on a KYC row whose latest report has field_issues and document_issues
- **THEN** a slide-out panel opens showing item rows derived from the report's field_issues and document_issues

#### Scenario: Filter items by tab
- **WHEN** the panel is open and the user clicks the "Failed" tab
- **THEN** only items with a blocking/failed status are shown

#### Scenario: Panel disabled for pending KYC
- **WHEN** a KYC has no agent report (Pending status)
- **THEN** the eye icon is disabled or hidden

### Requirement: Bulk run on pending KYCs

The dashboard SHALL display a "Run Agent on All Pending" button showing the pending count. Clicking it SHALL show a confirmation modal stating the count. On confirmation, the system SHALL queue a batch job that runs the KycOnboardingAgent on all completed InvestorKycs in the entity that have no latest SupportAgentReport. A real-time progress panel SHALL show batch progress via Turbo Stream. On completion, stat cards and the table SHALL refresh automatically. The button SHALL be disabled when no pending KYCs exist or when a batch is already running.

#### Scenario: Batch run on pending KYCs
- **WHEN** the entity has 50 pending KYCs and the user clicks "Run Agent on All Pending" and confirms
- **THEN** a batch job is queued for 50 KYCs, a progress panel appears, and on completion the stats and table refresh

#### Scenario: Button disabled when no pending KYCs
- **WHEN** all completed KYCs already have a latest report
- **THEN** the "Run Agent on All Pending" button is disabled and shows count "(0)"

#### Scenario: Button disabled during active batch
- **WHEN** a batch run is already in progress
- **THEN** the button is disabled with a spinner indicator

### Requirement: Half-donut charts

The dashboard SHALL display two half-donut (semicircle) charts side by side: one for Individual KYCs and one for Non-Individual KYCs. Each chart SHALL show segments for Successful, Partially Failed, Failed, and Expired. Each segment SHALL show its percentage. Charts SHALL update when the fund filter changes.

#### Scenario: Charts render with correct data
- **WHEN** the entity has 80 Individual KYCs (60 successful, 10 partial, 7 failed, 3 expired) and 20 Non-Individual KYCs (12 successful, 4 partial, 3 failed, 1 expired)
- **THEN** the Individual chart shows 75%/12.5%/8.75%/3.75% and the Non-Individual chart shows 60%/20%/15%/5%

#### Scenario: No KYCs of one type
- **WHEN** the entity has only Individual KYCs
- **THEN** the Non-Individual chart shows an empty state: "No Non-Individual KYCs"

### Requirement: Inline row actions

Each table row SHALL provide the following actions: View Detail (eye icon), Re-run Agent (play icon), and Mark Verified (check icon). "Mark Verified" SHALL only be shown for KYCs with a Successful agent status (final_status "ready"). "Re-run Agent" SHALL trigger the agent on that single KYC and refresh the row on completion.

#### Scenario: Mark Verified from table
- **WHEN** the user clicks "Mark Verified" on a KYC row with a successful agent report
- **THEN** the KYC's verified flag is set to true, the row refreshes to show the updated status

#### Scenario: Mark Verified hidden for non-successful KYC
- **WHEN** a KYC has a failed or partially-failed agent report
- **THEN** the "Mark Verified" action is not shown for that row

#### Scenario: Re-run Agent
- **WHEN** the user clicks "Re-run Agent" on a KYC row
- **THEN** the agent runs on that KYC, a spinner shows on the row, and the row refreshes with the new result

### Requirement: Top failure reasons panel

The dashboard SHALL display a panel showing the top 5 most common failure reasons aggregated from all latest SupportAgentReports in the entity. Each reason SHALL show the issue description and the count of affected KYCs. Reasons SHALL be extracted from field_issues and document_issues with severity "blocking". The list SHALL be sorted by count descending. The panel SHALL update when the fund filter changes. Each failure reason SHALL be clickable and expand to show the list of affected investor names as links to their KYC pages. Clicking the same reason again SHALL collapse the list.

#### Scenario: Top failure reasons display
- **WHEN** across all latest reports, "PAN Mismatch" appears in 34 reports, "Missing Address Proof" in 28, and "Expired KYC" in 15
- **THEN** the panel shows these three reasons in descending order with their counts

#### Scenario: Failure reason drill-down
- **WHEN** the user clicks on a failure reason row (e.g. "Missing PAN Number (12)")
- **THEN** the row expands to show the 12 affected investor names as clickable links to their KYC pages

#### Scenario: Failure reason collapse
- **WHEN** the user clicks on an expanded failure reason row
- **THEN** the list of affected investors collapses

#### Scenario: No failures
- **WHEN** all latest reports have final_status "ready" (no blocking issues)
- **THEN** the panel shows "No failures found" or is hidden

### Requirement: Fund filter

The dashboard SHALL provide a fund dropdown above the table. It SHALL list "All Funds" (default) plus each fund linked to KYCs in the entity (via capital_commitments). Selecting a fund SHALL filter all dashboard components — stat cards, charts, table, and top failure reasons — to only KYCs linked to that fund.

#### Scenario: Filter by fund
- **WHEN** the user selects "Fund ABC" in the fund dropdown
- **THEN** stat cards, charts, table, and failure reasons show data only for KYCs with capital_commitments to "Fund ABC"

#### Scenario: KYC in multiple funds
- **WHEN** a KYC has capital_commitments to both "Fund ABC" and "Fund XYZ"
- **THEN** the KYC appears when either fund is selected

### Requirement: Document tracking

The dashboard table SHALL display a "Docs" column showing the ratio of uploaded documents to required documents for each KYC, formatted as "X / Y". Required documents SHALL be determined from FormCustomField records (field_type "File", required) for the KYC's form type, plus any documents listed in the agent's `json_fields["required_docs"]` configuration. Uploaded documents SHALL be counted from the KYC's `documents` association. The column SHALL use color coding: green when all docs are uploaded (X = Y), orange when some are missing (0 < X < Y), red when none are uploaded (X = 0 and Y > 0). When no required documents are configured (Y = 0), the column SHALL show "—".

#### Scenario: All documents uploaded
- **WHEN** a KYC has 5 required documents and 5 uploaded documents
- **THEN** the Docs column shows "5 / 5" in green text

#### Scenario: Some documents missing
- **WHEN** a KYC has 7 required documents and 4 uploaded documents
- **THEN** the Docs column shows "4 / 7" in orange text

#### Scenario: No documents uploaded
- **WHEN** a KYC has 5 required documents and 0 uploaded documents
- **THEN** the Docs column shows "0 / 5" in red text

#### Scenario: No required documents configured
- **WHEN** no FormCustomField File-type fields exist for the KYC's form type and the agent has no required_docs config
- **THEN** the Docs column shows "—"

### ~~Requirement: CSV export~~ *(Removed — not in product design)*
