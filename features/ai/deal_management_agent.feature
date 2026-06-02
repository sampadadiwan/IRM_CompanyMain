Feature: Deal Management Agent
  As a fund operator I want a DealManagementAgent that monitors an open deal,
  flags stagnant investors and overdue activities, checks document completeness,
  extracts deal terms, summarises investor notes, scores investors, and sends
  a single digest email covering all issues — all from a single configurable support agent.

  Background:
    Given there is a user "first_name=DealAdmin" for an entity "name=DealTestFund;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a DealManagementAgent configured for the entity

  # ── 1. Agent registration ─────────────────────────────────────────────────

  @deal_management @registration
  Scenario: DealManagementAgent is a recognised support agent type
    Then "DealManagementAgent" is a recognised support agent type

  # ── 2. Deal gating ────────────────────────────────────────────────────────

  @deal_management @gating
  Scenario: A closed deal is not processed
    Given there is an open deal with 2 active investors
    And the deal is closed
    When the DealManagementAgent runs for the deal
    Then no deal-level SupportAgentReport is saved

  @deal_management @gating
  Scenario: An open deal with all capabilities disabled produces a report with no blocking issues
    Given there is an open deal with 2 active investors
    And all DealManagementAgent capabilities are disabled
    When the DealManagementAgent runs for the deal
    Then a deal-level SupportAgentReport is saved
    And the report has no blocking issues

  # ── 3. Deal progress — stagnation ────────────────────────────────────────

  @deal_management @progress
  Scenario: A stagnant investor is flagged as a blocking issue
    Given there is an open deal with 1 active investor
    And the investor has had no activity for 20 days
    When the DealManagementAgent runs for the deal with check_progress enabled
    Then the deal report progress_issues contains 1 stagnant blocking issue

  @deal_management @progress
  Scenario: A recently active investor is not flagged as stagnant
    Given there is an open deal with 1 active investor
    And the investor was updated 2 days ago
    When the DealManagementAgent runs for the deal with check_progress enabled
    Then the deal report progress_issues contains 0 stagnant issues

  @deal_management @progress
  Scenario: A Declined investor is excluded from the stagnation check
    Given there is an open deal with 1 declined investor
    And the declined investor has had no activity for 30 days
    When the DealManagementAgent runs for the deal with check_progress enabled
    Then the deal report progress_issues contains 0 stagnant issues

  @deal_management @progress
  Scenario: An overdue activity is reported as a blocking issue
    Given there is an open deal with 1 active investor
    And the investor has an overdue activity "NDA Executed" due 10 days ago
    When the DealManagementAgent runs for the deal with check_progress enabled
    Then the deal report progress_issues contains 1 overdue blocking issue for "NDA Executed"

  # ── 4. Document checklist ─────────────────────────────────────────────────

  @deal_management @checklist
  Scenario: A missing required document is a blocking issue
    Given there is an open deal with no documents in the data room
    And the agent requires documents "NDA, Term Sheet"
    When the DealManagementAgent runs for the deal with check_documents enabled
    Then the document_issues contain 2 blocking issues for missing documents

  @deal_management @checklist
  Scenario: A present required document is a success issue
    Given there is an open deal with a document "NDA" in the data room
    And the agent requires documents "NDA"
    When the DealManagementAgent runs for the deal with check_documents enabled
    Then the document_issues contain 1 success issue for "NDA"

  @deal_management @checklist
  Scenario: Document name matching is case-insensitive
    Given there is an open deal with a document "nda" in the data room
    And the agent requires documents "NDA"
    When the DealManagementAgent runs for the deal with check_documents enabled
    Then the document_issues contain 1 success issue for "NDA"

  @deal_management @checklist
  Scenario: Blank required_docs skips the checklist
    Given there is an open deal with no documents in the data room
    And the agent has required_docs set to ""
    When the DealManagementAgent runs for the deal with check_documents enabled
    Then the document_issues contain 0 blocking issues

  # ── 5. Term extraction ────────────────────────────────────────────────────

  @deal_management @term_extraction
  Scenario: LLM extracts deal terms and stores them in the deal report
    Given there is an open deal with a document "Information Memorandum" in the data room
    And the LLM returns deal terms JSON with pre_money_valuation "$10M"
    When the DealManagementAgent runs for the deal with extract_terms enabled
    Then the deal report extracted_terms contains "pre_money_valuation" with value "$10M"

  @deal_management @term_extraction
  Scenario: Term extraction is cached when documents and prompt are unchanged
    Given there is an open deal with a document "Information Memorandum" in the data room
    And a prior deal report exists with a valid term extraction cache
    When the DealManagementAgent runs for the deal with extract_terms enabled
    Then the LLM is not called for term extraction
    And the deal report extracted_terms are carried forward from the cache

  @deal_management @term_extraction
  Scenario: Term extraction re-runs when a document is added to the data room
    Given there is an open deal with a document "Information Memorandum" in the data room
    And a prior deal report exists with a valid term extraction cache
    And a new document "Cap Table" is added to the deal data room
    When the DealManagementAgent runs for the deal with extract_terms enabled
    Then the LLM is called for term extraction

  # ── 6. Investor pipeline ─────────────────────────────────────────────────

  @deal_management @investor_pipeline
  Scenario: Investor with documents receives a note summary in their report
    Given there is an open deal with 1 active investor
    And the investor has 1 document in their folder
    And the LLM returns a note summary "Key theme: strong engagement"
    When the DealManagementAgent runs for the deal with summarize_notes enabled
    Then the investor-level SupportAgentReport has summary_text "Key theme: strong engagement"

  @deal_management @investor_pipeline
  Scenario: Investor without documents is saved as skipped with no LLM call
    Given there is an open deal with 1 active investor
    And the investor has no documents
    When the DealManagementAgent runs for the deal with summarize_notes enabled
    Then the investor-level SupportAgentReport final_status is "skipped"
    And the LLM is not called for summarization

  @deal_management @investor_pipeline
  Scenario: Investor scoring writes ai_score and ai_grade back to DealInvestor
    Given there is an open deal with 1 active investor
    And the investor has 1 document in their folder
    And the agent has a scoring_skill_file uploaded
    And the LLM returns a valid investor score of 78 grade "B+"
    When the DealManagementAgent runs for the deal with score_investors enabled
    Then the DealInvestor has ai_score 78 and ai_grade "B+"
    And the investor-level SupportAgentReport contains the score data

  @deal_management @investor_pipeline
  Scenario: Declined investor is excluded from the investor pipeline
    Given there is an open deal with 1 active investor and 1 declined investor
    When the DealManagementAgent runs for the deal
    Then only 1 investor-level SupportAgentReport is saved

  # ── 7. Email digest ───────────────────────────────────────────────────────

  @deal_management @digest
  Scenario: A pipeline digest email is queued when notify_email is set
    Given there is an open deal with 1 active investor
    And the investor has an overdue activity "NDA Executed" due 5 days ago
    And the agent has notify_email "ops@example.com"
    When the DealManagementAgent runs for the deal
    Then a DealManagementDigestMailer email is queued to "ops@example.com"
    And the digest email subject contains "ALERT"

  @deal_management @digest
  Scenario: Overdue activities appear in the digest email body
    Given there is an open deal with 1 active investor
    And the investor has an overdue activity "NDA Executed" due 5 days ago
    And the agent has notify_email "ops@example.com"
    When the DealManagementAgent runs for the deal
    Then the digest email body contains "NDA Executed"

  @deal_management @digest
  Scenario: No digest email is queued when notify_email is blank
    Given there is an open deal with 1 active investor
    And the agent has notify_email ""
    When the DealManagementAgent runs for the deal
    Then no DealManagementDigestMailer email is queued

  # ── 9. Reports ────────────────────────────────────────────────────────────

  @deal_management @reports
  Scenario: Re-running the agent overwrites the existing deal report
    Given there is an open deal with 1 active investor
    And the DealManagementAgent has already run once for the deal
    When the DealManagementAgent runs for the deal
    Then there is exactly 1 deal-level SupportAgentReport for the deal

  @deal_management @reports
  Scenario: Score leaderboard in deal report is sorted descending by ai_score
    Given there is an open deal with 2 active investors with documents
    And the agent has a scoring_skill_file uploaded
    And the LLM returns scores 82 and 55 for the two investors
    When the DealManagementAgent runs for the deal with score_investors enabled
    Then the deal report score_leaderboard first entry has ai_score 82
