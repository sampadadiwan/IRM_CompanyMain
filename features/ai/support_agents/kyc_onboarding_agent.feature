Feature: KYC Onboarding Agent
  As a fund administrator
  I want the KYC onboarding agent to validate investor KYC records end-to-end
  So that only complete, verified KYCs proceed to AML screening

  # The agent runs these steps in order:
  #   initialize_agent → check_field_completeness → check_document_presence →
  #   check_document_validity → check_field_to_document_consistency →
  #   check_expiry_status → generate_progress_reports → send_reminders →
  #   trigger_aml_if_complete
  #
  # Document validity (check_document_validity) uses the real LLM — real PDFs
  # from public/sample_uploads/ are uploaded so the model sees meaningful content.
  # GenerateAmlReportJob is stubbed to prevent outbound AML API calls.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing investor "investor_name=Test Investor"
    And the entity has an active employee
    And there is a completed KYC for the investor

  # ── Happy path ──────────────────────────────────────────────────────────

  Scenario: All checks pass and AML is triggered
    Given the KYC onboarding agent is fully enabled
    And the KYC has an uploaded document labeled "Passport"
    When I run the KYC onboarding agent
    Then the report final status should be "ready"
    And the AML job should have been enqueued for the investor KYC

  # ── Initialization guard ─────────────────────────────────────────────────

  Scenario: KYC not submitted by investor is skipped entirely
    Given the KYC onboarding agent is fully enabled
    And the KYC has not been submitted by the investor
    When I run the KYC onboarding agent
    Then no report should be created for the KYC

  # ── Document presence ────────────────────────────────────────────────────

  Scenario: Missing required document blocks AML
    Given the KYC onboarding agent requires a "Passport" document
    And the KYC has no documents uploaded
    When I run the KYC onboarding agent
    Then the report final status should be "blocked"
    And the report should have a blocking document issue mentioning "Passport"
    And the AML job should not have been enqueued for the investor KYC

  # ── Document validity (LLM stub) ─────────────────────────────────────────
  # doc.file.url returns a web-relative path (/uploads/...) that RubyLLM cannot
  # resolve as a filesystem path in test; the LLM receives only the text prompt.
  # We stub the LLM response to exercise the mismatch-handling code path.

  Scenario: LLM reports mismatch for a document and blocks AML
    Given the KYC onboarding agent is fully enabled
    And the KYC has an uploaded document labeled "Bank Statement"
    And the LLM will flag the document as not matching its label
    When I run the KYC onboarding agent
    Then the report final status should be "blocked"
    And the report should have a blocking document issue mentioning "Bank Statement"
    And the AML job should not have been enqueued for the investor KYC

  # ── Expiry checks ────────────────────────────────────────────────────────

  Scenario: Expired KYC produces a blocking issue and triggers a reminder email
    Given the KYC onboarding agent has expiry checking and reminders enabled
    And the KYC expired 10 days ago
    When I run the KYC onboarding agent
    Then the report final status should be "blocked"
    And the report should contain a field issue of type "kyc_expired"
    And a KYC expiry reminder email should have been sent
    And the expiry reminder email should show the expiry date as Mon dd yyyy
    And the AML job should not have been enqueued for the investor KYC

  Scenario: KYC expiring soon produces a warning and triggers a reminder email
    Given the KYC onboarding agent has expiry checking and reminders enabled
    And the KYC expires in 14 days
    When I run the KYC onboarding agent
    Then the report final status should be "ready"
    And the report should contain a field issue of type "kyc_expiring_soon"
    And a KYC expiry reminder email should have been sent

  Scenario: KYC expiring today is a warning, not expired — valid through the expiry date
    Given the KYC onboarding agent has expiry checking and reminders enabled
    And the KYC expires today
    When I run the KYC onboarding agent
    Then the report final status should be "ready"
    And the report should contain a field issue of type "kyc_expiring_soon"
    And the report should not contain a field issue of type "kyc_expired"

  Scenario: Expiry issues are not counted as missing fields
    Given the KYC onboarding agent has expiry checking and reminders enabled
    And the KYC expired 10 days ago
    When I run the KYC onboarding agent
    Then the report should contain a field issue of type "kyc_expired"
    And the report missing-field count should be 0

  # ── Reminder cadence (milestone bands, not one per run) ──────────────────

  Scenario: Reminder is not re-sent for the same milestone on a later run
    Given the KYC onboarding agent has expiry checking and reminders enabled
    And the KYC expires in 14 days
    When I run the KYC onboarding agent
    And I run the KYC onboarding agent
    Then exactly 1 KYC expiry reminder email should have been sent

  Scenario: Reminder is re-sent when the KYC crosses into a new milestone band
    Given the KYC onboarding agent has expiry checking and reminders enabled
    And the KYC expires in 40 days
    When I run the KYC onboarding agent
    And the reminder was last sent on a previous day
    And the KYC expires in 10 days
    And I run the KYC onboarding agent
    Then exactly 2 KYC expiry reminder emails should have been sent

  Scenario: Blank warning thresholds fall back to the 60,30,15 defaults
    Given the KYC onboarding agent has expiry checking and reminders enabled
    And the agent expiry warning thresholds are blank
    And the KYC expires in 14 days
    When I run the KYC onboarding agent
    Then the report should contain a field issue of type "kyc_expiring_soon"
    And a KYC expiry reminder email should have been sent

  # ── Reminder recipients ──────────────────────────────────────────────────

  Scenario: Sandboxed entity redirects the expiry reminder to sandbox emails
    Given the KYC onboarding agent has expiry checking and reminders enabled
    And the entity is in sandbox mode with sandbox email "sandbox@example.com"
    And the KYC expired 10 days ago
    When I run the KYC onboarding agent
    Then the expiry reminder email should have been sent to "sandbox@example.com"

  Scenario: Entity with no active employees skips the expiry reminder gracefully
    Given the KYC onboarding agent has expiry checking and reminders enabled
    And the entity has no active employees
    And the KYC expired 10 days ago
    When I run the KYC onboarding agent
    Then the report should contain a field issue of type "kyc_expired"
    And no KYC expiry reminder email should have been sent

  # ── Feature flag combinations ────────────────────────────────────────────

  Scenario: All validation flags disabled — pipeline completes and AML is triggered
    Given the KYC onboarding agent has all validation flags disabled
    When I run the KYC onboarding agent
    Then the report final status should be "ready"
    And the AML job should have been enqueued for the investor KYC

  Scenario: AML trigger disabled — pipeline completes cleanly without enqueuing a job
    Given the KYC onboarding agent is fully enabled
    And the KYC has an uploaded document labeled "Passport"
    And the KYC onboarding agent has AML triggering disabled
    When I run the KYC onboarding agent
    Then the report final status should be "ready"
    And the AML job should not have been enqueued for the investor KYC

  # ── No active employee guard ─────────────────────────────────────────────

  Scenario: Entity with no active employees — AML is skipped gracefully without crashing
    Given the KYC onboarding agent is fully enabled
    And the KYC has an uploaded document labeled "Passport"
    And the entity has no active employees
    When I run the KYC onboarding agent
    Then the report final status should be "ready"
    And the AML job should not have been enqueued for the investor KYC
    And the AML report entry should mention "no active entity employee"
