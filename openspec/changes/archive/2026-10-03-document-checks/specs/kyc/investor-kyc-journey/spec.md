# Spec Delta

## MODIFIED Requirements

### Requirement: Validating documents
"Validate documents" SHALL pass by itself, showing "Validated by AI", when the KYC's Document Checks have
current results and none of its items needs attention (items resolved with Use document value or Mark as OK
count as OK). Otherwise it SHALL be current with "Mark reviewed" and a message:
- "Documents not checked yet — check documents or mark reviewed", with "Check documents", when the entity
  has document checks for the KYC's documents and they haven't been checked;
- "<n> document items need attention — resolve them or mark reviewed", with "Open document checks", when
  the current results have items needing attention;
- "Check the documents and mark reviewed" when the entity has no document checks for the KYC's documents.

Uploading, replacing or deleting a KYC document after the task passed SHALL move it back with "Documents
changed after validation". It SHALL then pass only on a newer completed document check, a newer resolution,
or a newer confirmation.

#### Scenario: AI full pass
- **WHEN** a document check finishes and no item needs attention
- **THEN** the task is ✓ "Validated by AI" with no click, and the open page updates

#### Scenario: AI could not validate
- **WHEN** a document check finishes with 2 items needing attention
- **THEN** the task is current with "2 document items need attention — resolve them or mark reviewed", and a user's Mark reviewed passes it as "Reviewed by <user>"

#### Scenario: Resolving the last item completes the task
- **WHEN** the only item needing attention is marked OK
- **THEN** the task is ✓ "Validated by AI" without anyone clicking Mark reviewed

#### Scenario: Not checked yet
- **WHEN** the entity has checks for the KYC's documents and the KYC has never been checked
- **THEN** the task is current with "Documents not checked yet — check documents or mark reviewed"

#### Scenario: No document questions
- **WHEN** the entity has no document checks for the KYC's documents
- **THEN** the task is current with "Check the documents and mark reviewed" until a user marks it reviewed

#### Scenario: Document replaced after validation
- **WHEN** a user replaces the PAN Card after the task passed
- **THEN** the journey moves back to "Validate documents" with "Documents changed after validation"
