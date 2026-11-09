@security @maker_checker
Feature: Maker–checker cannot be bypassed (OWASP review 2026-11 M13 — F5)
  The rule lives in the Approve permission, so a preparer is refused on every path — the page, a direct URL, the
  JSON API and bulk approve — and nobody outside the firm, no investor and no read-only user can approve or ask
  for approval. Mass assignment can't set the approval.
  Worked examples X3–X15:
  openspec/changes/capital-call-distribution-maker-checker/business-rules.md#5-direct-requests-api-bulk-other-firms--phase-2

  Background:
    Given the firm "Nilgiri Capital" has maker-checker on

  # X3 — Error case: Meera (preparer) POSTs the call's approve URL directly → Access Denied, unapproved
  Scenario: X3 A preparer forcing the call's approve URL is refused
    Given "Meera" created the call "Q4 2026 Drawdown"
    When "Meera" approves the call "Q4 2026 Drawdown"
    Then "Meera" is refused with Access Denied
    And the call "Q4 2026 Drawdown" is not approved

  # X4 — Error case: Meera approves through the API with a bearer token → 403 {"error":"Access Denied"}
  Scenario: X4 A preparer approving a call through the API is refused
    Given "Meera" created the call "Q4 2026 Drawdown"
    When "Meera" approves the call "Q4 2026 Drawdown" through the API
    Then the API answers 403 Access Denied
    And the call "Q4 2026 Drawdown" is not approved

  # X5 — Error case: Meera POSTs the distribution's approve URL directly → Access Denied
  Scenario: X5 A preparer forcing the distribution's approve URL is refused
    Given "Meera" created the distribution "Tea Estates Exit"
    When "Meera" approves the distribution "Tea Estates Exit"
    Then "Meera" is refused with Access Denied
    And the distribution "Tea Estates Exit" is not approved

  # X6 — Error case: Meera approves the distribution through the API → 403
  Scenario: X6 A preparer approving a distribution through the API is refused
    Given "Meera" created the distribution "Tea Estates Exit"
    When "Meera" approves the distribution "Tea Estates Exit" through the API
    Then the API answers 403 Access Denied
    And the distribution "Tea Estates Exit" is not approved

  # X7 — Error case: Meera bulk-approves her two calls and Anil's → Anil's approved; hers listed with the reason
  Scenario: X7 Bulk approve of calls reports the preparer's own calls
    Given "Meera" created the call "Q4 2026 Drawdown"
    And "Meera" created the call "Q1 2027 Drawdown"
    And "Anil" created the call "Sep 2026 Top-up"
    When "Meera" bulk-approves the calls of "Nilgiri Capital" through the API
    Then the maker-checker API answers 202
    And the call "Sep 2026 Top-up" is approved by "Meera"
    And the call "Q4 2026 Drawdown" is not approved
    And the call "Q1 2027 Drawdown" is not approved
    And the bulk errors email says "You prepared Q4 2026 Drawdown — another approver must approve it"
    And the bulk errors email says "You prepared Q1 2027 Drawdown — another approver must approve it"

  # X8 — Error case: Meera bulk-approves her distribution and Anil's → Pharma Exit approved; Tea Estates refused with the reason
  Scenario: X8 Bulk approve of distributions reports the preparer's own
    Given "Meera" created the distribution "Tea Estates Exit"
    And "Anil" created the distribution "Pharma Exit"
    When "Meera" bulk-approves the distributions of "Nilgiri Capital" through the API
    Then the maker-checker API answers 202
    And the distribution "Pharma Exit" is approved by "Meera"
    And the distribution "Tea Estates Exit" is not approved
    And the bulk errors email says "You prepared Tea Estates Exit — another approver must approve it"

  # X9 — Error case: Kiran (another firm's admin + approver) POSTs approve on Q4 → Access Denied
  Scenario: X9 Another firm's approver is refused
    Given "Meera" created the call "Q4 2026 Drawdown"
    When "Kiran" approves the call "Q4 2026 Drawdown"
    Then "Kiran" is refused with Access Denied
    And the call "Q4 2026 Drawdown" is not approved

  # X10 — Error case: Sunil (support), acting as Meera, created Q4; acting as Ravi he POSTs approve → refused, he prepared it
  Scenario: X10 Support cannot approve what they prepared while acting as anyone
    Given CapHive support "Sunil" supports "Nilgiri Capital"
    And CapHive support "Sunil" acting as "Meera" creates the call "Support Drawdown"
    When CapHive support "Sunil" acting as "Ravi" approves the call "Support Drawdown"
    Then "Sunil" is refused with Access Denied
    And the call "Support Drawdown" is not approved

  # X11 — Error case: Ravi already approved Q4 and re-submits approve → Access Denied; approved by stays Ravi
  Scenario: X11 A second approve is refused
    Given "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" approved the call "Q4 2026 Drawdown"
    When "Ravi" approves the call "Q4 2026 Drawdown"
    Then "Ravi" is refused with Access Denied
    And the call "Q4 2026 Drawdown" is approved by "Ravi"

  # X12 — Error case: Meera PATCHes Q4 with approved=1 and approved_by_user_id=Meera → fields ignored, unapproved
  Scenario: X12 Mass assignment cannot approve
    Given "Meera" created the call "Q4 2026 Drawdown"
    When "Meera" sends approved and approved_by_user_id in an edit of "Q4 2026 Drawdown"
    Then the call "Q4 2026 Drawdown" is not approved

  # X13 — Error case: Kiran (another firm) POSTs request_approval on Q4 → Access Denied; nothing sent
  Scenario: X13 Another firm cannot request approval
    Given "Meera" created the call "Q4 2026 Drawdown"
    When "Kiran" requests approval of the call "Q4 2026 Drawdown"
    Then "Kiran" is refused with Access Denied
    And no maker-checker email is sent

  # X14 — Error case: Arun (an LP of the fund) POSTs request_approval → Access Denied; nothing sent
  Scenario: X14 An investor cannot request approval
    Given "Meera" created the call "Q4 2026 Drawdown"
    When "Arun" requests approval of the call "Q4 2026 Drawdown"
    Then "Arun" is refused with Access Denied
    And no maker-checker email is sent

  # X15 — Error case: Vikram (read-only fund access) POSTs request_approval → Access Denied; nothing sent
  Scenario: X15 A read-only employee cannot request approval
    Given "Meera" created the call "Q4 2026 Drawdown"
    When "Vikram" requests approval of the call "Q4 2026 Drawdown"
    Then "Vikram" is refused with Access Denied
    And no maker-checker email is sent
