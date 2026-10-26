# Spec Delta

## Purpose

Registers and runs the CP/CS Extraction Agent, which reads portfolio investment agreement documents (SHA, SPA, SSA) and proposes conditions precedent, conditions subsequent, and other actionable obligations for counsel review.

## ADDED Requirements

### Requirement: Agent registration
The system SHALL register the CP/CS Extraction Agent as a support agent type with an agent config form that includes an `investment_doc_tag` field accepting a comma-separated list of document tags (e.g. "SHA,SPA,SSA"). The agent MUST be licensed per entity via a bitflag and SHALL only be runnable when that flag is enabled.

#### Scenario: Agent provisioned with comma-separated tags
- **WHEN** an admin configures the CP/CS agent with `investment_doc_tag` set to "SHA,SPA"
- **THEN** the agent config is saved and the agent is runnable for that entity

#### Scenario: Agent hidden without license flag
- **WHEN** an entity does not have the CP/CS agent license flag enabled
- **THEN** the agent does not appear and cannot be run

### Requirement: Comma-separated document tag matching
The agent SHALL split the configured `investment_doc_tag` value on commas, trim whitespace from each tag, and locate documents on each portfolio investment that match ANY of the resulting tags. A portfolio investment is included in extraction targets when it has at least one document matching any configured tag.

#### Scenario: Multiple tags find documents of different types
- **WHEN** the agent is configured with "SHA,SPA" and a portfolio investment has one document tagged "SHA" and another tagged "SPA"
- **THEN** both documents are found and both are sent through the extraction pipeline

#### Scenario: Single tag still works
- **WHEN** the agent is configured with "SHA" (no comma)
- **THEN** only documents tagged "SHA" are matched, identical to single-tag behavior

#### Scenario: Tags with whitespace are trimmed
- **WHEN** the agent is configured with "SHA , SPA"
- **THEN** both "SHA" and "SPA" are matched after trimming

#### Scenario: No matching documents on a PI
- **WHEN** a portfolio investment has no documents matching any configured tag
- **THEN** that portfolio investment is excluded from extraction targets

### Requirement: Target resolution from entity, portfolio investment, or portfolio company
The agent SHALL resolve extraction targets based on the input: an entity ID expands to all portfolio investments with matching tagged documents (batch mode); a single portfolio investment is processed directly (single-PI mode); a portfolio company (investor) record expands to that company's portfolio investments only.

#### Scenario: Batch mode resolves all matching PIs
- **WHEN** the agent runs in batch mode for an entity with 50 portfolio investments, 5 of which have matching documents
- **THEN** only the 5 portfolio investments with matching documents are processed

#### Scenario: Single PI mode processes one investment
- **WHEN** the agent runs from a portfolio investment show page
- **THEN** only that one portfolio investment is processed

#### Scenario: Portfolio company mode scopes to one company
- **WHEN** the agent runs from a portfolio company page
- **THEN** only that company's portfolio investments with matching documents are processed

### Requirement: Multi-document extraction per portfolio investment
The agent SHALL extract obligations from each matching document on a portfolio investment separately and SHALL deduplicate across documents on the same PI by matching on source clause. Extraction SHALL use the same LLM pipeline, citation requirements, and upsert logic as the existing side letter extraction engine.

#### Scenario: Two documents on one PI yield deduplicated obligations
- **WHEN** extraction processes a PI with both an SHA and an SPA document, and both mention the same clause
- **THEN** the obligation is created once, not duplicated

#### Scenario: Extraction discards citations without source clause
- **WHEN** the LLM returns an obligation without a source clause from an investment agreement
- **THEN** it is discarded, consistent with the existing extraction engine behavior

### Requirement: Run CP/CS Agent button on portfolio investment page
The system SHALL display a "Run CP/CS Agent" button on each portfolio investment's show page when the CP/CS agent is enabled for the entity. Clicking the button SHALL trigger extraction for that single portfolio investment and display a step-by-step progress panel. After completion, the report SHALL include an "Open Obligation Matrix" link that opens the matrix with `legal_category_eq` pre-selected to Condition Precedent.

#### Scenario: Button visible when agent is enabled
- **WHEN** the CP/CS agent is enabled for the entity and a user views a portfolio investment page
- **THEN** a "Run CP/CS Agent" button is visible

#### Scenario: Button hidden when agent is disabled
- **WHEN** the CP/CS agent is not enabled for the entity
- **THEN** no "Run CP/CS Agent" button appears

#### Scenario: Running from PI page shows progress
- **WHEN** a user clicks "Run CP/CS Agent" on a portfolio investment page
- **THEN** a progress panel appears showing step indicators (Initialize, Locate Document, Extract Obligations, Save For Review, Generate Report)

#### Scenario: Completion links to matrix with legal category pre-selected
- **WHEN** the CP/CS agent completes extraction from a PI page
- **THEN** the "Open Obligation Matrix" link opens the matrix with `legal_category_eq=0` (Condition Precedent) pre-selected

### Requirement: Progress panel does not duplicate on navigation
The progress panel on the portfolio investment page SHALL be wrapped in a container with a fixed identifier so that navigating away and returning (via browser cache or Turbo page cache) always shows at most one progress panel.

#### Scenario: Navigate away and return
- **WHEN** a user runs the agent, navigates to another page, and returns to the PI page
- **THEN** only one progress panel is visible

#### Scenario: Re-running replaces existing panel
- **WHEN** a user re-runs the agent while a previous progress panel is displayed
- **THEN** the new progress panel replaces the old one in place

### Requirement: Step-UI dispatch resolves sub-targets correctly
When the agent is dispatched for a single target (step-UI mode), the dispatch logic SHALL expand the target into the agent's sub-targets (portfolio investments). The dispatch SHALL fall back to the raw entity record ONLY when the agent returns zero sub-targets, not when it returns one or more.

#### Scenario: Agent returns multiple sub-targets
- **WHEN** the dispatch logic calls the agent's target expansion and receives 3 portfolio investments
- **THEN** all 3 are processed through the extraction pipeline without falling back to the entity

#### Scenario: Agent returns zero sub-targets
- **WHEN** the dispatch logic calls the agent's target expansion and receives zero results (e.g. tag mismatch)
- **THEN** the dispatch falls back to the raw entity record

### Requirement: Estimated closing date for individual runs
When running the CP/CS agent for a single portfolio investment or from the agent modal, the system SHALL accept an optional estimated closing date parameter and pass it to the extraction prompt for context-aware obligation classification.

#### Scenario: Closing date provided
- **WHEN** a user runs the agent with an estimated closing date of "2026-12-31"
- **THEN** the extraction prompt includes that date for the LLM to use when classifying time-sensitive obligations

#### Scenario: Closing date omitted
- **WHEN** a user runs the agent without providing an estimated closing date
- **THEN** extraction proceeds normally without date context

### Requirement: CP/CS single-company redirect with stakeholder pre-filter
When the CP/CS agent completes a run scoped to a single portfolio company (investor), the report's "Open Obligation Matrix" link SHALL open the matrix with both `legal_category_eq` (Condition Precedent) and `stakeholder_id` (that company's ID) pre-selected, so counsel lands directly on that company's CP/CS obligations.

#### Scenario: Single-company run redirects with stakeholder pre-filter
- **WHEN** the CP/CS agent completes a run for a single portfolio company "Acme Corp"
- **THEN** the "Open Obligation Matrix" link opens the matrix with `legal_category_eq=0` and `stakeholder_id=<acme_id>` pre-selected

#### Scenario: Batch run redirects without stakeholder pre-filter
- **WHEN** the CP/CS agent completes a batch run for the entity
- **THEN** the "Open Obligation Matrix" link opens the matrix with only `legal_category_eq=0` pre-selected (no stakeholder filter)
