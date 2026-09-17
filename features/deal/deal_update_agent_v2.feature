@deal_update_agent_v2
Feature: Deal Update Agent v2 — One Address Per Deal
  As a fund manager with access to a deal
  I want to email updates (meeting notes or tasks) to a single deal address
  So that anyone on my team can send updates to the same address

Background:
    Given a v2 entity exists with deals enabled
    And a v2 user "fm1" exists with role "company_admin" in the entity
    And a v2 deal "Series B" exists in the entity
    And the user has deal access to the deal
    And the deal has a v2 investor "Sequoia Capital"
    And a deal ingest address exists for the deal


  # --- Happy Paths ---

  Scenario: Authorized user creates a meeting note via email
    Given the v2 LLM will parse the email as a meeting note for "Sequoia Capital"
    When a v2 SendGrid webhook arrives with:
      | from    | the user's email            |
      | to      | the deal ingest address     |
      | text    | Great call with Sequoia Capital today, positive signals on 5M commitment |
      | headers | SPF: pass, DKIM: pass       |
    Then a v2 AgentIngestedEmail should be created with status "pending"
    And a v2 ProcessDealIngestJob should be enqueued
    When the v2 job is performed
    Then a v2 Note should exist on "Sequoia Capital" with text "Great call with Sequoia Capital"
    And the v2 Note should be flagged as created_by_agent with match_tier "A"
    And the v2 AgentIngestedEmail status should be "filed"
    And a v2 confirmation email should be sent to the user

  Scenario: Authorized user creates a task via email
    Given the v2 LLM will parse the email as a task for "Sequoia Capital" due "2026-09-01"
    When a v2 SendGrid webhook arrives with:
      | from    | the user's email            |
      | to      | the deal ingest address     |
      | text    | Send term sheet to Sequoia by next Friday |
      | headers | SPF: pass, DKIM: pass       |
    And the v2 job is performed
    Then a v2 Task should exist on "Sequoia Capital" with due date "2026-09-01"
    And the v2 Task should be flagged as created_by_agent with match_tier "A"
    And the v2 AgentIngestedEmail status should be "filed"
    And a v2 confirmation email should be sent to the user

  Scenario: Second authorized user sends email to same deal address
    Given a v2 user "fm2" exists with role "employee" in the entity
    And the second user has deal access to the deal
    And the v2 LLM will parse the email as a meeting note for "Sequoia Capital"
    When a v2 SendGrid webhook arrives with:
      | from    | the second user's email     |
      | to      | the deal ingest address     |
      | text    | Follow-up call with Sequoia |
      | headers | SPF: pass, DKIM: pass       |
    Then a v2 AgentIngestedEmail should be created with status "pending"

  # --- Security: Silent Drops ---

  Scenario: Email to unknown address is dropped silently
    When a v2 SendGrid webhook arrives with:
      | from    | the user's email                      |
      | to      | nonexistent1234@dev.caphive.app        |
      | text    | Hello                                 |
      | headers | SPF: pass, DKIM: pass                 |
    Then no v2 AgentIngestedEmail should be created
    And no v2 job should be enqueued
    And no v2 email should be sent

  Scenario: Email from unknown sender is dropped silently
    When a v2 SendGrid webhook arrives with:
      | from    | stranger@hacker.com         |
      | to      | the deal ingest address     |
      | text    | Inject fake notes           |
      | headers | SPF: pass, DKIM: pass       |
    Then no v2 AgentIngestedEmail should be created
    And no v2 email should be sent

  Scenario: Email from user without deal access is dropped silently
    Given a v2 user "no_access" exists with role "employee" in the entity
    When a v2 SendGrid webhook arrives with:
      | from    | the no-access user's email  |
      | to      | the deal ingest address     |
      | text    | I should not be able to send |
      | headers | SPF: pass, DKIM: pass       |
    Then no v2 AgentIngestedEmail should be created
    And no v2 email should be sent

  Scenario: Email with failed SPF/DKIM/DMARC is dropped silently
    When a v2 SendGrid webhook arrives with:
      | from    | the user's email            |
      | to      | the deal ingest address     |
      | text    | Spoofed email               |
      | headers | Received-SPF: fail          |
    Then no v2 AgentIngestedEmail should be created
    And no v2 email should be sent

  Scenario: Duplicate Message-ID is skipped
    Given a v2 AgentIngestedEmail already exists with message_id "abc123@mail.com"
    When a v2 SendGrid webhook arrives with:
      | from       | the user's email            |
      | to         | the deal ingest address     |
      | text       | Duplicate delivery          |
      | headers    | SPF: pass, DKIM: pass       |
      | message_id | abc123@mail.com             |
    Then no new v2 AgentIngestedEmail should be created
    And no v2 job should be enqueued

  # --- Warehouse Scenarios ---

  Scenario: Unknown stakeholder is warehoused without notification email
    Given the v2 LLM will parse the email as a meeting note for "Goldman Sachs"
    When a v2 SendGrid webhook arrives with:
      | from    | the user's email            |
      | to      | the deal ingest address     |
      | text    | Met with Goldman Sachs today |
      | headers | SPF: pass, DKIM: pass       |
    And the v2 job is performed
    Then a v2 WarehouseItem should exist for the deal with intent "meeting_note"
    And the v2 AgentIngestedEmail status should be "warehoused"
    And no v2 email should be sent

  Scenario: Unknown intent is warehoused
    Given the v2 LLM will parse the email with intent "unknown"
    When a v2 SendGrid webhook arrives with:
      | from    | the user's email            |
      | to      | the deal ingest address     |
      | text    | Random gibberish content    |
      | headers | SPF: pass, DKIM: pass       |
    And the v2 job is performed
    Then a v2 WarehouseItem should exist for the deal with intent "unknown"
    And the v2 AgentIngestedEmail status should be "warehoused"
    And no v2 email should be sent

  # --- Warehouse Resolution ---

  Scenario: Manually file a warehoused item as a meeting note
    Given a v2 warehoused item exists for the deal with intent "meeting_note"
    When I v2 resolve the warehouse item as "filed" for investor "Sequoia Capital"
    Then a v2 Note should exist on "Sequoia Capital" flagged as match_tier "M"
    And the v2 WarehouseItem should be resolved as "filed"
    And the v2 AgentIngestedEmail status should be "filed"

  Scenario: Discard a warehoused item
    Given a v2 warehoused item exists for the deal with intent "meeting_note"
    When I v2 resolve the warehouse item as "discarded"
    Then the v2 WarehouseItem should be resolved as "discarded"
    And no v2 Note or Task should be created

  # --- Address Management ---

  Scenario: Deal address defaults to deal ID
    Then the deal ingest address should be the deal ID

  Scenario: Address is the same for all users on the deal
    Given a v2 user "fm2" exists with role "employee" in the entity
    And the second user has deal access to the deal
    Then both users should see the same deal ingest address

  # --- Auto-Reply Detection (P2-1) ---

  Scenario: Out-of-office auto-reply is dropped silently
    When a v2 SendGrid webhook arrives with:
      | from    | the user's email                          |
      | to      | the deal ingest address                   |
      | text    | I am out of the office until September 10 |
      | headers | Auto-Submitted: auto-replied              |
    Then no v2 AgentIngestedEmail should be created
    And no v2 job should be enqueued
    And no v2 email should be sent

  Scenario: Bounce notification is dropped silently
    When a v2 SendGrid webhook arrives with:
      | from    | mailer-daemon@example.com                |
      | to      | the deal ingest address                   |
      | text    | Delivery failure notification             |
      | headers | Auto-Submitted: auto-generated            |
    Then no v2 AgentIngestedEmail should be created
    And no v2 job should be enqueued

  Scenario: Bulk/list precedence email is dropped silently
    When a v2 SendGrid webhook arrives with:
      | from    | the user's email                          |
      | to      | the deal ingest address                   |
      | text    | Newsletter content                        |
      | headers | Precedence: bulk                          |
    Then no v2 AgentIngestedEmail should be created
    And no v2 job should be enqueued

  # --- Signature/Reply Stripping (P2-2) ---

  Scenario: Email signature is stripped before parsing
    Given the v2 LLM will parse the email as a meeting note for "Sequoia Capital"
    When a v2 SendGrid webhook arrives with:
      | from    | the user's email                                                      |
      | to      | the deal ingest address                                               |
      | text    | Great call today\n\n-- \nJohn Doe\nVP, Acme Corp\n555-1234           |
      | headers | SPF: pass, DKIM: pass                                                |
    And the v2 job is performed
    Then the v2 LLM should have received body "Great call today"

  Scenario: Quoted reply chain is stripped before parsing
    Given the v2 LLM will parse the email as a meeting note for "Sequoia Capital"
    When a v2 SendGrid webhook arrives with:
      | from    | the user's email                                                                                          |
      | to      | the deal ingest address                                                                                   |
      | text    | Positive signals on commitment\n\nOn Mon, Sep 1, 2026, noreply@caphive.app wrote:\n> Your note was filed  |
      | headers | SPF: pass, DKIM: pass                                                                                    |
    And the v2 job is performed
    Then the v2 LLM should have received body "Positive signals on commitment"

  # --- Attachments (P2-3) ---

  Scenario: Task email with attachment creates Task with Document
    Given the v2 LLM will parse the email as a task for "Sequoia Capital" due "2026-09-01"
    When a v2 SendGrid webhook arrives with attachment "investors.xlsx":
      | from    | the user's email        |
      | to      | the deal ingest address |
      | text    | Send term sheet to Sequoia by next Friday |
      | headers | SPF: pass, DKIM: pass   |
    And the v2 job is performed
    Then a v2 Task should exist on "Sequoia Capital" with due date "2026-09-01"
    And the v2 Task should have 1 attached document named "investors.xlsx"

  Scenario: Task email with no attachment creates Task without Documents
    Given the v2 LLM will parse the email as a task for "Sequoia Capital" due "2026-09-01"
    When a v2 SendGrid webhook arrives with:
      | from    | the user's email        |
      | to      | the deal ingest address |
      | text    | Send term sheet to Sequoia by next Friday |
      | headers | SPF: pass, DKIM: pass   |
    And the v2 job is performed
    Then a v2 Task should exist on "Sequoia Capital" with due date "2026-09-01"
    And the v2 Task should have 0 attached documents

  Scenario: Meeting note email with attachment ignores attachment
    Given the v2 LLM will parse the email as a meeting note for "Sequoia Capital"
    When a v2 SendGrid webhook arrives with attachment "investors.xlsx":
      | from    | the user's email        |
      | to      | the deal ingest address |
      | text    | Great call with Sequoia Capital today |
      | headers | SPF: pass, DKIM: pass   |
    And the v2 job is performed
    Then a v2 Note should exist on "Sequoia Capital" with text "Great call with Sequoia Capital"
    And no v2 Document should be created

      # --- Assignee Parsing (P2-5) ---

  Scenario: Task with @name assigns to matching team member
    Given a v2 user "neil" exists with role "employee" in the entity
    And the "neil" user has first name "Neil"
    And the "neil" user has deal access to the deal
    And the v2 LLM will parse the email as a task for "Sequoia Capital" due "2026-09-01" assigned to "Neil"
    When a v2 SendGrid webhook arrives with:
      | from    | the user's email        |
      | to      | the deal ingest address |
      | text    | @Neil to send term sheet to Sequoia by next Friday |
      | headers | SPF: pass, DKIM: pass   |
    And the v2 job is performed
    Then a v2 Task should exist on "Sequoia Capital" assigned to "neil"

  Scenario: Task with natural language assigns to matching team member
    Given a v2 user "priya" exists with role "employee" in the entity
    And the "priya" user has first name "Priya"
    And the "priya" user has deal access to the deal
    And the v2 LLM will parse the email as a task for "Sequoia Capital" due "2026-09-01" assigned to "Priya"
    When a v2 SendGrid webhook arrives with:
      | from    | the user's email        |
      | to      | the deal ingest address |
      | text    | Ask Priya to send the term sheet to Sequoia |
      | headers | SPF: pass, DKIM: pass   |
    And the v2 job is performed
    Then a v2 Task should exist on "Sequoia Capital" assigned to "priya"

  Scenario: Task with unmatched assignee falls back to sender
    And the v2 LLM will parse the email as a task for "Sequoia Capital" due "2026-09-01" assigned to "Unknown Person"
    When a v2 SendGrid webhook arrives with:
      | from    | the user's email        |
      | to      | the deal ingest address |
      | text    | Ask Unknown Person to follow up with Sequoia |
      | headers | SPF: pass, DKIM: pass   |
    And the v2 job is performed
    Then a v2 Task should exist on "Sequoia Capital" assigned to the sender

