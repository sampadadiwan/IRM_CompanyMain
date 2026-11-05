Feature: Manual duties
  Recurring duties (filings, attestations) scheduled per fund by the attached packs, with evidence.
  Worked examples: openspec/changes/fund-compliance-monitoring/business-rules.md (group 5)

  Background:
    Given the Horizon compliance setup

  # H27 — Happy path: the quarterly duty is done with an acknowledgement; the next quarter's is scheduled
  Scenario: H27 Quarterly duty done with evidence
    When the nightly compliance run happens on "2026-11-05"
    And "Meera" marks the "Quarterly SEBI report filed" duty of "Horizon Growth Fund I" done with evidence on "2027-01-10"
    Then the "Quarterly SEBI report filed" duty for "FY27-Q3" is done with an evidence document
    When the nightly compliance run happens on "2027-01-11"
    Then "Horizon Growth Fund I" has a "Quarterly SEBI report filed" duty for "FY27-Q4" due "2027-04-15"

  # H28 — Happy path: a new investor added 05 Nov gets a due-diligence duty due 20 Nov
  Scenario: H28 Event duty for a new investor
    Given a new investor "Nova Family Office" commits ₹2.0 cr to "Horizon Growth Fund I" on "2026-11-05"
    When the nightly compliance run happens on "2026-11-05"
    Then "Horizon Growth Fund I" has a due-diligence duty for "Nova Family Office" due "2026-11-20"

  # E41 — Edge case: due 15 Nov with a 7-day window — scheduled on 7 Nov, due on 8 Nov
  Scenario: E41 Reminder window opens
    Given a duty of "Horizon Growth Fund I" is due on "2026-11-15"
    Then on "2026-11-07" the duty is "scheduled"
    And on "2026-11-08" the duty is "due"

  # E42 — Edge case: not done by 15 Nov — overdue on 16 Nov
  Scenario: E42 Overdue duty
    Given a duty of "Horizon Growth Fund I" is due on "2026-11-15"
    Then on "2026-11-16" the duty is "overdue"

  # E43 — Edge case: done on 18 Nov is recorded late by 3 days
  Scenario: E43 Done late
    Given a duty of "Horizon Growth Fund I" is due on "2026-11-15"
    When "Meera" marks that duty done with evidence on "2026-11-18"
    Then that duty is done "late (3 days)"

  # E44 — Edge case: two new investors the same day get one duty each
  Scenario: E44 Two new investors same day
    Given a new investor "Nova One" commits ₹2.0 cr to "Horizon Growth Fund I" on "2026-11-05"
    And a new investor "Nova Two" commits ₹2.0 cr to "Horizon Growth Fund I" on "2026-11-05"
    When the nightly compliance run happens on "2026-11-05"
    And the nightly compliance run happens on "2026-11-06"
    Then "Horizon Growth Fund I" has 2 due-diligence duties

  # X33 — Error case: a duty that needs evidence refuses "done" without a document
  Scenario: X33 Evidence missing
    When the nightly compliance run happens on "2026-11-05"
    Then marking the "Quarterly SEBI report filed" duty of "Horizon Growth Fund I" done without evidence is refused with "Upload the evidence"
