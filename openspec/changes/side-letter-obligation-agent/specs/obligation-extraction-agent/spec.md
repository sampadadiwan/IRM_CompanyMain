# obligation-extraction-agent

## ADDED Requirements

### Requirement: Agent registration
The system SHALL register `SideLetterObligationAgent` as a SupportAgent type following existing conventions: an `AGENT_TYPES` entry, a `SUPPORT_AGENT_FORM_CONFIGS` entry (category "Ops") whose form custom fields configure `side_letter_doc_label`, `auto_extract_on_upload`, `default_reminder_days_before`, `overdue_escalation_days`, and `notify_tag`, and an entity license bitflag appended to the END of the `flag :support_agents` array.

#### Scenario: Setup provisions the agent
- **WHEN** the support agents setup runs for an entity with the license flag enabled
- **THEN** a `SupportAgent` with `agent_type = "SideLetterObligationAgent"` exists with its form type, config fields, and default schedule

#### Scenario: Agent hidden without license flag
- **WHEN** an entity does not have the agent's license flag enabled
- **THEN** the agent cannot be run for that entity

### Requirement: Side letter document location by configured label
The extraction run SHALL locate side letter documents on a commitment by exact name match against the configured `side_letter_doc_label`, and SHALL emit an informational (non-blocking) issue when a commitment has no matching document.

#### Scenario: Matching document found
- **WHEN** a commitment has a document named exactly as configured
- **THEN** that document is used as the extraction source

#### Scenario: No side letter on commitment
- **WHEN** a commitment has no matching document
- **THEN** the agent report records an info-level "no side letter" issue and no obligations are created

### Requirement: LLM extraction with mandatory citations
The extraction run SHALL extract obligations from the side letter text as structured records (type, title, description, source clause, trigger type, frequency, deadline, suggested owner team, confidence) and MUST discard any extracted obligation lacking a `source_clause` citation. All extracted obligations SHALL be persisted with `extracted_by = ai` and `review_status = pending_review`; extraction SHALL never create active obligations, tasks, or alerts directly.

#### Scenario: Extracted obligations await review
- **WHEN** extraction completes on a side letter
- **THEN** all created obligations have `review_status = pending_review` and no tasks exist for them

#### Scenario: Citation-less extraction discarded
- **WHEN** the LLM returns an obligation without a source clause
- **THEN** it is not persisted and the omission is noted in the agent report

### Requirement: Re-extraction diffs against existing obligations
Re-running extraction on a side letter SHALL match extracted obligations against existing ones by side letter, source clause, and obligation type; it MUST NOT modify or duplicate `approved` obligations, and SHALL surface changed or new extractions as new `pending_review` rows marked as deltas.

#### Scenario: Amendment produces a reviewable delta
- **WHEN** extraction reruns after the side letter document is replaced and a clause changed
- **THEN** the previously approved obligation is untouched and a new pending obligation flagged as a delta is created for review

#### Scenario: Identical re-extraction is idempotent
- **WHEN** extraction reruns with no document changes
- **THEN** no duplicate obligations are created

### Requirement: Per-commitment agent reports
Each extraction run SHALL produce a `SupportAgentReport` per commitment summarizing counts (extracted, pending review, approved), extraction failures as blocking issues, and unreviewed backlog as warnings, following the standard issue severity shape.

#### Scenario: Report generated on batch run
- **WHEN** a batch extraction run processes 10 commitments
- **THEN** each commitment has a latest `SupportAgentReport` from this agent and the batch summary reflects successes and failures
