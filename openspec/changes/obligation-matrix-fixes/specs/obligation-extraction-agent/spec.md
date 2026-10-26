# Spec Delta

## MODIFIED Requirements

### Requirement: Side letter document location by configured label
The extraction run SHALL locate side letter documents on a commitment by exact name match against the configured `side_letter_doc_label`, and SHALL emit an informational (non-blocking) issue when a commitment has no matching document. For portfolio-investment-sourced extraction (CP/CS agent), the agent SHALL locate documents by tag match against the configured `investment_doc_tag`, splitting comma-separated tags and matching any one.

#### Scenario: Matching document found
- **WHEN** a commitment has a document named exactly as configured
- **THEN** that document is used as the extraction source

#### Scenario: No side letter on commitment
- **WHEN** a commitment has no matching document
- **THEN** the agent report records an info-level "no side letter" issue and no obligations are created

#### Scenario: Comma-separated tags match any tag
- **WHEN** the agent is configured with "SHA,SPA" and a portfolio investment has a document tagged "SPA"
- **THEN** that document is located for extraction

#### Scenario: No matching tagged document on a portfolio investment
- **WHEN** a portfolio investment has documents but none match any configured tag
- **THEN** that portfolio investment is skipped with an informational note

### Requirement: Per-commitment agent reports
Each extraction run SHALL produce a `SupportAgentReport` per target (commitment for SLO, portfolio investment for CP/CS) summarizing counts (extracted, pending review, approved), extraction failures as blocking issues, and unreviewed backlog as warnings, following the standard issue severity shape. For CP/CS runs from a portfolio company page, the report SHALL be owned by the portfolio company (investor) record so the step UI receives broadcasts on the company page. Report redirect URLs SHALL use Ransack filter params (`legal_category_eq`) and optionally `stakeholder_id` instead of the removed `context` parameter.

#### Scenario: Report generated on batch run
- **WHEN** a batch extraction run processes 10 commitments
- **THEN** each commitment has a latest `SupportAgentReport` from this agent and the batch summary reflects successes and failures

#### Scenario: Report owned by portfolio company for company-scoped runs
- **WHEN** a CP/CS extraction run is triggered from a portfolio company page
- **THEN** the `SupportAgentReport` is owned by the portfolio company (investor) record, not individual portfolio investments

#### Scenario: Report redirect uses Ransack params
- **WHEN** an extraction run completes and generates a report
- **THEN** the report's "Open Obligation Matrix" link includes `q[legal_category_eq]` with the appropriate value (0 for CP/CS agent, 2 for SLO agent) instead of a `context` parameter
