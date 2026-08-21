@deal_update_agent
Feature: Deal Update Agent — Email Ingestion Pipeline
  As a fund manager with access to a deal
  I want to email updates (meeting notes or tasks) to a unique deal address
  So that the deal board stays current without manual data entry

  Background:
    Given an entity exists with deals enabled
    And a user exists with role "company_admin" in the entity
    And a deal "Series B" exists in the entity
    And the deal has an investor "Sequoia Capital"
    And a deal ingest address exists for the user on the deal

  # --- Happy Paths ---

  Scenario: Authenticated email with known stakeholder creates a meeting note
    Given the LLM will parse the email as a meeting note for "Sequoia Capital"
    When a SendGrid webhook arrives with:
      | from    | the user's email            |
      | to      | the deal ingest address     |
      | text    | Great call with Sequoia Capital today, positive signals on 5M commitment |
      | headers | SPF: pass, DKIM: pass       |
    Then an AgentIngestedEmail should be created with status "pending"
    And a ProcessDealIngestJob should be enqueued
    When the job is performed
    Then a Note should exist on "Sequoia Capital" with text "Great call with Sequoia Capital"
    And the Note should be flagged as created_by_agent with match_tier "A"
    And the AgentIngestedEmail status should be "filed"
    And a confirmation email should be sent to the user

  Scenario: Authenticated email with task intent creates a task
    Given the LLM will parse the email as a task for "Sequoia Capital" due "2026-09-01"
    When a SendGrid webhook arrives with:
      | from    | the user's email            |
      | to      | the deal ingest address     |
      | text    | Send term sheet to Sequoia by next Friday |
      | headers | SPF: pass, DKIM: pass       |
    And the job is performed
    Then a Task should exist on "Sequoia Capital" with due date "2026-09-01"
    And the Task should be flagged as created_by_agent with match_tier "A"
    And the AgentIngestedEmail status should be "filed"
    And a confirmation email should be sent to the user

  # --- Security: Silent Drops ---

  Scenario: Email to unknown address is dropped silently
    When a SendGrid webhook arrives with:
      | from    | the user's email                      |
      | to      | nonexistent1234@updates.caphive.com   |
      | text    | Hello                                 |
      | headers | SPF: pass, DKIM: pass                 |
    Then no AgentIngestedEmail should be created
    And no job should be enqueued
    And no email should be sent

  Scenario: Email from wrong sender is dropped silently
    When a SendGrid webhook arrives with:
      | from    | stranger@hacker.com         |
      | to      | the deal ingest address     |
      | text    | Inject fake notes           |
      | headers | SPF: pass, DKIM: pass       |
    Then no AgentIngestedEmail should be created
    And no email should be sent

  Scenario: Email with failed SPF/DKIM/DMARC is dropped silently
    When a SendGrid webhook arrives with:
      | from    | the user's email            |
      | to      | the deal ingest address     |
      | text    | Spoofed email               |
      | headers | Received-SPF: fail          |
    Then no AgentIngestedEmail should be created
    And no email should be sent

  Scenario: Duplicate Message-ID is skipped
    Given an AgentIngestedEmail already exists with message_id "abc123@mail.com"
    When a SendGrid webhook arrives with:
      | from       | the user's email            |
      | to         | the deal ingest address     |
      | text       | Duplicate delivery          |
      | headers    | SPF: pass, DKIM: pass       |
      | message_id | abc123@mail.com             |
    Then no new AgentIngestedEmail should be created
    And no job should be enqueued

  Scenario: Email to a revoked address is dropped silently
    Given the deal ingest address has been revoked
    When a SendGrid webhook arrives with:
      | from    | the user's email            |
      | to      | the deal ingest address     |
      | text    | Should not process          |
      | headers | SPF: pass, DKIM: pass       |
    Then no AgentIngestedEmail should be created
    And no email should be sent

  # --- Warehouse Scenarios ---

  Scenario: Unknown stakeholder is warehoused
    Given the LLM will parse the email as a meeting note for "Goldman Sachs"
    When a SendGrid webhook arrives with:
      | from    | the user's email            |
      | to      | the deal ingest address     |
      | text    | Met with Goldman Sachs today |
      | headers | SPF: pass, DKIM: pass       |
    And the job is performed
    Then a WarehouseItem should exist for the deal with intent "meeting_note"
    And the AgentIngestedEmail status should be "warehoused"
    And a warehouse notification email should be sent to the user

  Scenario: Unknown intent is warehoused
    Given the LLM will parse the email with intent "unknown"
    When a SendGrid webhook arrives with:
      | from    | the user's email            |
      | to      | the deal ingest address     |
      | text    | Random gibberish content    |
      | headers | SPF: pass, DKIM: pass       |
    And the job is performed
    Then a WarehouseItem should exist for the deal with intent "unknown"
    And the AgentIngestedEmail status should be "warehoused"

  # --- Warehouse Resolution ---

  Scenario: Manually file a warehoused item as a meeting note
    Given a warehoused item exists for the deal with intent "meeting_note"
    When I resolve the warehouse item as "filed" for investor "Sequoia Capital"
    Then a Note should exist on "Sequoia Capital" flagged as match_tier "M"
    And the WarehouseItem should be resolved as "filed"
    And the AgentIngestedEmail status should be "filed"

  Scenario: Discard a warehoused item
    Given a warehoused item exists for the deal with intent "meeting_note"
    When I resolve the warehouse item as "discarded"
    Then the WarehouseItem should be resolved as "discarded"
    And no Note or Task should be created
