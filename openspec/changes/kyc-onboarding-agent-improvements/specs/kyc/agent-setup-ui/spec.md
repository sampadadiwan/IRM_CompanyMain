# Spec Delta

## Purpose

Provides a structured 3-column table UI for configuring the KYC Onboarding Agent's Field-to-Document Consistency mappings, replacing the raw text format with dropdowns and free-text inputs so admins can set up document verification without memorizing syntax.

## ADDED Requirements

### Requirement: Setup table renders on agent settings page

The agent settings page for a KycOnboardingAgent SHALL display a "Document Verification Setup" section containing a table with three columns: Document (dropdown), Information to pull (text input), and Field to verify (dropdown). The section SHALL appear below the existing toggle fields.

#### Scenario: Setup table visible on agent edit page
- **WHEN** an admin opens the edit page for a KycOnboardingAgent
- **THEN** they see a "Document Verification Setup" section with the 3-column table

#### Scenario: Setup table not visible for other agent types
- **WHEN** an admin opens the edit page for a non-KycOnboardingAgent (e.g., PortfolioCompanyAgent)
- **THEN** the "Document Verification Setup" section is not shown

### Requirement: Document dropdown shows standard File-type fields

The Document column SHALL be a dropdown populated with all `FormCustomField` records with `field_type: "File"` from the entity's KYC form types (IndividualKyc, NonIndividualKyc). The dropdown labels SHALL use the field's `label` attribute (e.g., "Upload PAN", "Upload Address Proof"). The labels SHALL reflect the entity's actual field names — "PAN" on Indian entities, "Tax ID" on US entities — without any code-level translation.

#### Scenario: Document dropdown shows entity's File-type fields
- **WHEN** an admin opens the Document dropdown on the setup table
- **THEN** the dropdown lists all File-type FormCustomField labels from the entity's KYC form types

#### Scenario: Document dropdown reflects entity-specific labels
- **WHEN** an Indian entity has a FormCustomField labelled "Upload PAN" and a US entity has "Upload Tax ID"
- **THEN** the Indian entity's dropdown shows "Upload PAN" and the US entity's shows "Upload Tax ID"

#### Scenario: No File-type fields exist
- **WHEN** the entity's KYC form types have no File-type FormCustomField records
- **THEN** the Document dropdown is empty and the admin cannot create a valid mapping row

### Requirement: Field to verify dropdown shows standard non-File fields

The Field to verify column SHALL be a dropdown populated with standard (non-File) `FormCustomField` records from the entity's KYC form types. Custom fields SHALL NOT appear in this dropdown in this phase.

#### Scenario: Field to verify dropdown shows standard fields
- **WHEN** an admin opens the Field to verify dropdown
- **THEN** the dropdown lists standard non-File FormCustomField labels from the entity's KYC form types

### Requirement: Add and remove mapping rows

The setup table SHALL have a "+ Add Row" button that appends an empty row. Each row SHALL have a remove (✕) button that removes it. Changes SHALL be reflected immediately in the UI without page reload.

#### Scenario: Add a new row
- **WHEN** an admin clicks the "+ Add Row" button
- **THEN** a new empty row is appended to the table

#### Scenario: Remove an existing row
- **WHEN** an admin clicks the ✕ button on a row
- **THEN** that row is removed from the table

#### Scenario: Same document in multiple rows
- **WHEN** an admin adds three rows all selecting "Upload Bank Details" with different extraction prompts and target fields
- **THEN** all three rows are accepted and saved

### Requirement: Configuration persists as structured JSON

On save, the setup table rows SHALL be serialized into the agent's `json_fields` as structured JSON. On page reload, the table SHALL reconstruct from the stored JSON and display the saved rows correctly. Rows with an empty Document selection SHALL be silently discarded on save.

#### Scenario: Save and reload preserves configuration
- **WHEN** an admin configures 3 rows and saves the agent
- **THEN** on reload, the setup table shows the same 3 rows with the saved values

#### Scenario: Empty document row is discarded
- **WHEN** an admin adds a row but leaves the Document dropdown unselected and saves
- **THEN** that row is not stored and does not appear on reload

### Requirement: Backward compatibility with old text format

The agent's mapping parser SHALL read both the old text format (`attribute=prompt;attribute=prompt` strings in `json_fields` keyed by `FormCustomField` name with `meta_data: "doc_extraction"`) and the new structured JSON format. Existing agents with old-format configurations SHALL continue working without migration.

#### Scenario: Old text format still works
- **WHEN** an agent has Field-to-Document Consistency configured in the old text format
- **THEN** the agent's consistency check runs correctly using the old format mappings

#### Scenario: New structured JSON format works
- **WHEN** an agent has Field-to-Document Consistency configured via the new setup table
- **THEN** the agent's consistency check runs correctly using the new format mappings

#### Scenario: Re-saving migrates to new format
- **WHEN** an admin opens and saves an agent that had old-format configuration
- **THEN** the configuration is stored in the new structured JSON format
