# frozen_string_literal: true

Feature: KYC Onboarding Agent — Improvements
  As a fund administrator
  I want the KYC onboarding agent to validate only PAN/Tax ID documents,
  respect entity-level AML settings, and support the new config format
  So that validation is scoped correctly and AML charges are controlled per entity

  # Tests for improvements introduced in feature/kyc-onboarding-agent-improvements:
  #   Phase 3 — PAN/Tax ID document filter (check_document_validity)
  #   Phase 4 — AML entity setting guard (trigger_aml_if_complete)
  #   Phase 6 — Dual-format document mapping parser (parse_field_document_mappings)

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing investor "investor_name=Test Investor"
    And the entity has an active employee
    And there is a completed KYC for the investor

  # ── Phase 3: PAN / Tax ID document filter ──────────────────────────────

  Scenario: Non-PAN document is skipped during document validity check
    Given the KYC onboarding agent is fully enabled
    And the KYC has an uploaded document labeled "Bank Statement"
    When I run the KYC onboarding agent
    Then the report should have no document validity issue for "Bank Statement"

  Scenario: PAN document is sent for LLM validation
    Given the KYC onboarding agent is fully enabled
    And the KYC has an uploaded document labeled "Upload PAN"
    And the LLM will confirm the document matches its label
    When I run the KYC onboarding agent
    Then the report should have a document validity issue for "Upload PAN"

  Scenario: Tax ID document with different label is sent for LLM validation
    Given the KYC onboarding agent is fully enabled
    And the KYC has an uploaded document labeled "Upload Tax ID"
    And the LLM will confirm the document matches its label
    When I run the KYC onboarding agent
    Then the report should have a document validity issue for "Upload Tax ID"

  Scenario: Address Proof document is skipped during validity check
    Given the KYC onboarding agent is fully enabled
    And the KYC has an uploaded document labeled "Address Proof"
    When I run the KYC onboarding agent
    Then the report should have no document validity issue for "Address Proof"

  Scenario: Multiple documents — only PAN is validated, others skipped
    Given the KYC onboarding agent is fully enabled
    And the KYC has an uploaded document labeled "Upload PAN"
    And the KYC has an uploaded document labeled "Bank Statement"
    And the KYC has an uploaded document labeled "Address Proof"
    And the LLM will confirm the document matches its label
    When I run the KYC onboarding agent
    Then the report should have a document validity issue for "Upload PAN"
    And the report should have no document validity issue for "Bank Statement"
    And the report should have no document validity issue for "Address Proof"

  # ── Phase 4: AML entity setting guard ──────────────────────────────────

  Scenario: AML toggle ON but entity AML not enabled — AML is skipped
    Given the KYC onboarding agent is fully enabled
    And AML is not enabled for the entity
    And the KYC has an uploaded document labeled "Passport"
    When I run the KYC onboarding agent
    Then the report final status should be "ready"
    And the AML job should not have been enqueued for the investor KYC

  Scenario: AML toggle ON and entity AML enabled — AML fires
    Given the KYC onboarding agent is fully enabled
    And AML is enabled for the entity
    And the KYC has an uploaded document labeled "Passport"
    When I run the KYC onboarding agent
    Then the report final status should be "ready"
    And the AML job should have been enqueued for the investor KYC

  # ── Phase 6: Dual-format document mapping parser ───────────────────────

  Scenario: New JSON format doc_verification_rules used for consistency check
    Given the KYC onboarding agent is fully enabled
    And the agent has new-format doc verification rules mapping "Upload PAN" to "PAN" with prompt "PAN / Tax ID number"
    And the KYC has an uploaded document labeled "Upload PAN"
    And the LLM will return extracted fields as JSON
    When I run the KYC onboarding agent
    Then the field-to-document consistency check should have run for "Upload PAN"

  Scenario: Old text-format FormCustomField config still works for consistency check
    Given the KYC onboarding agent is fully enabled
    And the agent has old-format doc extraction field "Upload PAN" mapping "PAN" to "PAN / Tax ID number"
    And the KYC has an uploaded document labeled "Upload PAN"
    And the LLM will return extracted fields as JSON
    When I run the KYC onboarding agent
    Then the field-to-document consistency check should have run for "Upload PAN"

  Scenario: New format takes precedence over old format when both exist
    Given the KYC onboarding agent is fully enabled
    And the agent has new-format doc verification rules mapping "Upload PAN" to "PAN" with prompt "PAN number"
    And the agent has old-format doc extraction field "Upload PAN" mapping "PAN" to "Old PAN prompt"
    And the KYC has an uploaded document labeled "Upload PAN"
    And the LLM will return extracted fields as JSON
    When I run the KYC onboarding agent
    Then the field-to-document consistency check should have run for "Upload PAN"
