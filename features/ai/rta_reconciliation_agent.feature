Feature: RTA Reconciliation Agent
  As a fund operations admin I want an RtaReconciliationAgent that accepts an uploaded
  RTA unit statement PDF and reconciles its figures against CapHive's capital_commitments
  data at summary and folio level, flagging breaks and pending requests in a report.

  Background:
    Given there is a user "first_name=RtaAdmin" for an entity "name=RtaTestEntity;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an RtaReconciliationAgent configured for the entity

  # ── 1. Agent registration ──────────────────────────────────────────────────

  @rta_reconciliation @registration
  Scenario: RtaReconciliationAgent is a recognised support agent type
    Then "RtaReconciliationAgent" is a recognised support agent type

  # ── 2. Missing PDF ─────────────────────────────────────────────────────────

  @rta_reconciliation @validation
  Scenario: Running without an uploaded PDF records a blocking issue
    Given there is a fund "name=Test Fund" for the entity
    When the RtaReconciliationAgent runs for the fund without a PDF
    Then a fund-level SupportAgentReport is saved
    And the report has a blocking issue matching "No RTA statement PDF"

  # ── 3. Summary reconciliation — match ──────────────────────────────────────

  @rta_reconciliation @reconciliation
  Scenario: All units match produces a 100% health score
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has 3 capital commitments with folio_ids and unit_type "Class A" totalling 31379 units
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 31379
    And the PDF folio breakdown matches all 3 capital commitments exactly
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved
    And the RTA report has no blocking issues
    And the report scheme_results show summary_match true for ISIN "INF123A010AX"
    And the report health_score is 100

  # ── 4. Summary reconciliation — break ──────────────────────────────────────

  @rta_reconciliation @reconciliation
  Scenario: Summary unit count mismatch beyond tolerance records a blocking issue
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has 1 capital commitment with folio_id "FX-001" and unit_type "Class A" with 31000 units
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 31379
    And the PDF folio breakdown has folio "FX-001" with closing units 31379
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved
    And the report has a blocking issue matching "Summary break"
    And the report scheme_results show summary_match false for ISIN "INF123A010AX"

  # ── 5. Folio break ─────────────────────────────────────────────────────────

  @rta_reconciliation @reconciliation
  Scenario: A folio with mismatched units records a blocking folio break issue
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has 1 capital commitment with folio_id "FX-001" and unit_type "Class A" with 31000 units
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 31379
    And the PDF folio breakdown has folio "FX-001" with closing units 31375
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved
    And the report has a blocking issue matching "Folio FX-001 break"

  # ── 6. Unmatched RTA folio ─────────────────────────────────────────────────

  @rta_reconciliation @reconciliation
  Scenario: A folio in the RTA statement not found in CapHive records a blocking issue
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has no capital commitments
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 100
    And the PDF folio breakdown has folio "UNKNOWN-001" with closing units 100
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved
    And the report has a blocking issue matching "UNKNOWN-001 not found in CapHive"

  # ── 7. Missing RTA folio (reverse check) ───────────────────────────────────

  @rta_reconciliation @reconciliation
  Scenario: A CapHive commitment absent from the RTA statement records a warning
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has 1 capital commitment with folio_id "ORPHAN-001" and unit_type "Class A" with 100 units
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 0
    And the PDF folio breakdown is empty
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved
    And the report has a warning issue matching "ORPHAN-001 is in CapHive but missing from RTA"

  # ── 8. Pending requests ────────────────────────────────────────────────────

  @rta_reconciliation @pending
  Scenario: Folios with pending requests are flagged as warnings
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has 1 capital commitment with folio_id "FX-001" and unit_type "Class A" with 500 units
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 500
    And the PDF folio breakdown has folio "FX-001" with closing units 500 and pending requests "Redemption in process"
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved
    And the report has a warning issue matching "FX-001 has pending request"

  # ── 9. Unknown ISIN ────────────────────────────────────────────────────────

  @rta_reconciliation @validation
  Scenario: An ISIN in the PDF not found in FundUnitSetting records a warning and skips the scheme
    Given there is a fund "name=Test Fund" for the entity
    And the fund has no FundUnitSettings
    And the RTA statement PDF contains scheme "Test Fund" ISIN "UNKNOWN999" closing units 1000
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved
    And the report has a warning issue matching "ISIN UNKNOWN999 not found in FundUnitSetting"
    And the RTA report has no blocking issues

  # ── 10. Tolerance ──────────────────────────────────────────────────────────

  @rta_reconciliation @tolerance
  Scenario: A difference within tolerance is not flagged as a break
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has 1 capital commitment with folio_id "FX-001" and unit_type "Class A" with 31378.99 units
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 31379
    And the PDF folio breakdown has folio "FX-001" with closing units 31379
    And the agent tolerance_units is "0.02"
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved
    And the RTA report has no blocking issues

  # ── 11. Email on breaks ────────────────────────────────────────────────────

  @rta_reconciliation @email
  Scenario: When breaks are found and send_report is Yes an email is sent with RTA BREAK subject
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has 1 capital commitment with folio_id "FX-001" and unit_type "Class A" with 31000 units
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 31379
    And the PDF folio breakdown has folio "FX-001" with closing units 31379
    And the agent is configured to send reports to "ops@example.com"
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved
    And an email is delivered to "ops@example.com"
    And the email subject contains "[RTA BREAK]"

  # ── 12. Email on clean run ─────────────────────────────────────────────────

  @rta_reconciliation @email
  Scenario: When all units match and send_report is Yes an email is sent with RTA OK subject
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has 1 capital commitment with folio_id "FX-001" and unit_type "Class A" with 31379 units
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 31379
    And the PDF folio breakdown has folio "FX-001" with closing units 31379
    And the agent is configured to send reports to "ops@example.com"
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved
    And an email is delivered to "ops@example.com"
    And the email subject contains "[RTA OK]"

  # ── 13. All matched — multi-scheme health 100% ──────────────────────────────

  @rta_reconciliation @health_states
  Scenario: A statement where every scheme matches produces 100% health
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has a FundUnitSetting with ISIN "INF456B020BY" and name "Class B"
    And the fund has 1 capital commitment with folio_id "FA-001" and unit_type "Class A" with 100 units
    And the fund has 1 capital commitment with folio_id "FB-001" and unit_type "Class B" with 200 units
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 100
    And the RTA statement PDF also contains scheme "Test Fund" ISIN "INF456B020BY" closing units 200
    And the PDF folio breakdown for ISIN "INF123A010AX" has folio "FA-001" with closing units 100
    And the PDF folio breakdown for ISIN "INF456B020BY" has folio "FB-001" with closing units 200
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved
    And the RTA report has no blocking issues
    And the report scheme_results show summary_match true for ISIN "INF123A010AX"
    And the report scheme_results show summary_match true for ISIN "INF456B020BY"
    And the report health_score is 100

  # ── 14. None matched — multi-scheme health 0% ───────────────────────────────

  @rta_reconciliation @health_states
  Scenario: A statement where every scheme breaks produces 0% health
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has a FundUnitSetting with ISIN "INF456B020BY" and name "Class B"
    And the fund has 1 capital commitment with folio_id "FA-001" and unit_type "Class A" with 100 units
    And the fund has 1 capital commitment with folio_id "FB-001" and unit_type "Class B" with 200 units
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 150
    And the RTA statement PDF also contains scheme "Test Fund" ISIN "INF456B020BY" closing units 250
    And the PDF folio breakdown for ISIN "INF123A010AX" has folio "FA-001" with closing units 150
    And the PDF folio breakdown for ISIN "INF456B020BY" has folio "FB-001" with closing units 250
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved
    And the report scheme_results show summary_match false for ISIN "INF123A010AX"
    And the report scheme_results show summary_match false for ISIN "INF456B020BY"
    And the report health_score is 0

  # ── 15. Some matched — mixed schemes and mixed folios within a broken scheme ─

  @rta_reconciliation @health_states
  Scenario: A statement where one scheme matches and another breaks produces partial health
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has a FundUnitSetting with ISIN "INF456B020BY" and name "Class B"
    And the fund has 1 capital commitment with folio_id "FA-001" and unit_type "Class A" with 100 units
    And the fund has 1 capital commitment with folio_id "FB-001" and unit_type "Class B" with 200 units
    And the fund has 1 capital commitment with folio_id "FB-002" and unit_type "Class B" with 50 units
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 100
    And the RTA statement PDF also contains scheme "Test Fund" ISIN "INF456B020BY" closing units 280
    And the PDF folio breakdown for ISIN "INF123A010AX" has folio "FA-001" with closing units 100
    And the PDF folio breakdown for ISIN "INF456B020BY" has folio "FB-001" with closing units 200
    And the PDF folio breakdown for ISIN "INF456B020BY" has folio "FB-002" with closing units 80
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved
    And the report scheme_results show summary_match true for ISIN "INF123A010AX"
    And the report scheme_results show summary_match false for ISIN "INF456B020BY"
    And the report has a blocking issue matching "Folio FB-002 break"
    And the report health_score is 33

  # ── 16. Investor name mismatch ───────────────────────────────────────────────

  @rta_reconciliation @mismatch_types
  Scenario: A folio number matching CapHive but a different investor name records a warning
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has 1 capital commitment with folio_id "FX-001" and unit_type "Class A" with 100 units
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 100
    And the PDF folio breakdown for ISIN "INF123A010AX" has folio "FX-001" with investor name "Totally Different Holdings LLP" and closing units 100
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved
    And the report has a warning issue matching "investor name mismatch"

  # ── 17. Opening balance continuity break across two runs ─────────────────────

  @rta_reconciliation @mismatch_types
  Scenario: An opening balance that doesn't follow from the prior run's closing balance records a warning
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has 1 capital commitment with folio_id "FX-001" and unit_type "Class A" with 100 units
    And the RTA statement date is "2024-01-31"
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 100
    And the PDF folio breakdown for ISIN "INF123A010AX" has folio "FX-001" with closing units 100
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved

    Given the RTA statement date is "2024-02-29"
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 100
    And the PDF folio breakdown for ISIN "INF123A010AX" has folio "FX-001" with opening units 50 and closing units 100
    When the RtaReconciliationAgent runs again for the fund
    Then the report has a warning issue matching "opening balance"

  # ── 18. Unit movement break despite a matching closing balance ───────────────

  @rta_reconciliation @mismatch_types
  Scenario: A subscription the RTA reports with no matching CapHive ledger entry records a movement break
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has 1 capital commitment with folio_id "FX-001" and unit_type "Class A" with 100 units
    And the RTA statement date is "2024-01-31"
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 100
    And the PDF folio breakdown for ISIN "INF123A010AX" has folio "FX-001" with closing units 100
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved

    Given the RTA statement date is "2024-02-29"
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 100
    And the PDF folio breakdown for ISIN "INF123A010AX" has folio "FX-001" with closing units 100
    And the PDF summary for ISIN "INF123A010AX" reports 30 units subscribed
    When the RtaReconciliationAgent runs again for the fund
    Then the report scheme_results show movement_matched false for ISIN "INF123A010AX"

  # ── 19. Unit movement matches a real CapHive ledger entry ────────────────────

  @rta_reconciliation @mismatch_types
  Scenario: A subscription corroborated by a real CapHive ledger entry records a movement match
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has 1 capital commitment with folio_id "FX-001" and unit_type "Class A" with 100 units
    And the RTA statement date is "2024-01-31"
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 100
    And the PDF folio breakdown for ISIN "INF123A010AX" has folio "FX-001" with closing units 100
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved

    Given there is a FundUnit record for the fund with unit_type "Class A" quantity 30.0 issued on "2024-02-15"
    And the RTA statement date is "2024-02-29"
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 130
    And the PDF folio breakdown for ISIN "INF123A010AX" has folio "FX-001" with opening units 100 and closing units 130
    And the PDF summary for ISIN "INF123A010AX" reports 30 units subscribed
    When the RtaReconciliationAgent runs again for the fund
    Then the report scheme_results show movement_matched true for ISIN "INF123A010AX"
    And the RTA report has no blocking issues

  # ── 20. A configured scheme entirely missing from this statement ────────────

  @rta_reconciliation @mismatch_types
  Scenario: A scheme with an ISIN configured but absent from the statement records a coverage gap
    Given there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has a FundUnitSetting with ISIN "INF456B020BY" and name "Class B"
    And the fund has 1 capital commitment with folio_id "FA-001" and unit_type "Class A" with 100 units
    And the fund has 1 capital commitment with folio_id "FB-001" and unit_type "Class B" with 200 units
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 100
    And the PDF folio breakdown for ISIN "INF123A010AX" has folio "FA-001" with closing units 100
    When the RtaReconciliationAgent runs for the fund
    Then a fund-level SupportAgentReport is saved
    And the report has a blocking issue matching "scheme entirely missing from statement"

  # ── 21. A unit type with no ISIN configured at all (fund-wide readiness gap) ─

  @rta_reconciliation @mismatch_types
  Scenario: A unit type with live commitments but no FundUnitSetting at all is flagged as unreconcilable
    Given there is a fund "name=Test Fund" for the entity
    And the fund recognizes unit type "Class C"
    And the fund has 1 capital commitment with folio_id "FC-001" and unit_type "Class C" with 300 units
    When the RtaReconciliationAgent runs for the fund without a PDF
    Then a fund-level SupportAgentReport is saved
    And the report has a blocking issue matching "no FundUnitSetting configured"
