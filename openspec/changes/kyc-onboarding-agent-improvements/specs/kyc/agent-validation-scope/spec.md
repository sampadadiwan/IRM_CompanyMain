# Spec Delta

## Purpose

Scopes the KYC Onboarding Agent's validation steps to reduce unnecessary AI calls, enforce correct document presence checking for standard vs custom fields, gate AML triggering on entity-level billing settings, and update agent descriptions to reference the actual documents collected.

## ADDED Requirements

### Requirement: Document Validity limited to PAN/Tax ID

The Document Validity step (Step 4) SHALL only send documents whose normalized name matches PAN or Tax ID patterns to the AI for label validation. All other uploaded documents (address proofs, bank statements, etc.) SHALL be skipped — no AI call and no validity result item generated for them.

#### Scenario: PAN document is validated
- **WHEN** the agent runs Document Validity and the KYC has a document named "Upload PAN"
- **THEN** the document is sent to the AI for label matching and a result item is recorded

#### Scenario: Tax ID document is validated
- **WHEN** the agent runs Document Validity and the KYC has a document named "Upload Tax ID"
- **THEN** the document is sent to the AI for label matching and a result item is recorded

#### Scenario: Address Proof document is skipped
- **WHEN** the agent runs Document Validity and the KYC has a document named "Upload Address Proof"
- **THEN** the document is NOT sent to the AI and no validity result item is generated for it

#### Scenario: Bank Details document is skipped
- **WHEN** the agent runs Document Validity and the KYC has a document named "Upload Bank Details"
- **THEN** the document is NOT sent to the AI and no validity result item is generated for it

#### Scenario: Document validity disabled
- **WHEN** the `validate_documents` toggle is OFF
- **THEN** the Document Validity step is skipped entirely (existing behavior, unchanged)

### Requirement: Document Presence separates standard and custom fields

The Document Presence step (Step 3) SHALL check all standard attachment fields (FormCustomField with `field_type: "File"` that are standard/built-in) for presence regardless of the `required` flag. For custom attachment fields, the step SHALL check only those where both `field_type` is an attachment type AND `required` is true. Missing standard documents SHALL be flagged as blocking. Missing non-required custom attachment fields SHALL NOT be flagged.

#### Scenario: Standard attachment field without required flag
- **WHEN** the entity has a standard File-type FormCustomField "Upload PAN" with `required: false`
- **THEN** the Document Presence step still checks for its upload and flags it as blocking if missing

#### Scenario: Custom attachment field with required true
- **WHEN** the entity has a custom File-type FormCustomField "Upload Partnership Deed" with `required: true`
- **THEN** the Document Presence step checks for its upload and flags it as blocking if missing

#### Scenario: Custom attachment field with required false
- **WHEN** the entity has a custom File-type FormCustomField "Upload Additional Reference" with `required: false`
- **THEN** the Document Presence step does NOT check for its upload

#### Scenario: All required documents present
- **WHEN** all standard attachment fields and required custom attachment fields have uploads
- **THEN** the step records "All required documents are present" as a success item

### Requirement: AML trigger checks entity-level AML setting

The Trigger AML step (Step 9) SHALL check `entity.entity_setting.aml_enabled` before triggering an AML report. If AML is not enabled for the entity, the step SHALL skip with the message "AML not enabled for entity" even when the agent's `trigger_aml` toggle is ON.

#### Scenario: AML enabled for entity and toggle ON
- **WHEN** the `trigger_aml` toggle is ON and the entity's AML setting is enabled and there are no blocking issues
- **THEN** the AML report is triggered (existing behavior)

#### Scenario: AML not enabled for entity but toggle ON
- **WHEN** the `trigger_aml` toggle is ON but the entity's AML setting is NOT enabled
- **THEN** the step is skipped with "AML not enabled for entity" and no AML report is triggered

#### Scenario: AML toggle OFF
- **WHEN** the `trigger_aml` toggle is OFF
- **THEN** the step is skipped with "Disabled" (existing behavior, unchanged)

#### Scenario: AML enabled but blocking issues exist
- **WHEN** the `trigger_aml` toggle is ON and entity AML is enabled but the KYC has blocking issues
- **THEN** the step is skipped with "Blocking issues present" (existing behavior, unchanged)

### Requirement: Agent descriptions reference actual documents

The agent's user-facing descriptions (DESCRIPTION, LONG_DESCRIPTION, SINGLE_LONG_DESCRIPTION) SHALL reference "Tax ID, Address Proof, Bank Details" instead of "passport, ID, etc." to match the actual documents collected in the KYC flow.

#### Scenario: Agent description text
- **WHEN** a user views the KYC Onboarding Agent's description
- **THEN** it references "Tax ID, Address Proof, Bank Details" and does not mention "passport"

#### Scenario: Single-run description text
- **WHEN** a user triggers a single KYC run and sees the agent description
- **THEN** it references "Tax ID, Address Proof, Bank Details" and does not mention "passport"
