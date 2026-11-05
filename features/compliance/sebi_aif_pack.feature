Feature: SEBI — AIF pack
  The first CapHive pack: concentration, continuing interest, minimum investment, investor count and duties.
  Figures pending counsel review. Worked examples: openspec/changes/fund-compliance-monitoring/business-rules.md (group 7)

  Background:
    Given the Horizon compliance setup

  # H32 — Happy path: the SEBI pack offers five classifications, both Large Value Fund ones included
  Scenario: H32 Classifications offered
    Then the SEBI pack offers the classifications "Category I; Category II; Category III; Category I — LVF; Category II — LVF"

  # H33 — Happy path: exactly 25% passes (₹50 cr of ₹200 cr investable)
  Scenario: H33 Exactly 25% passes
    Given "Acme Foods" costs ₹50.0 cr
    And the investable funds of "Horizon Growth Fund I" are ₹200.0 cr
    When the nightly compliance run happens on "2026-11-05"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "pass"
    And the working shows "25.00% ≤ 25%"

  # H34 — Happy path: the ₹5 cr cap applies (lower of 7.50 and 5.00); ₹6 cr ≥ ₹5 cr passes
  Scenario: H34 Continuing interest cap applies
    When the nightly compliance run happens on "2026-11-05"
    Then the "Continuing interest — amount" check on "Horizon Growth Fund I" is "pass"
    And the working shows "Required continuing interest = lower of ₹7.50 cr and ₹5.00 cr = ₹5.00 cr"
    And the working shows "₹6.00 cr ≥ ₹5.00 cr"

  # H35 — Happy path: pro-rata shortfall 132.30 ÷ 294.00 = 45%; 5.00 × 45% = 2.25; 2.10 < 2.25
  Scenario: H35 Pro-rata shortfall
    When the nightly compliance run happens on "2026-11-05"
    Then the "Continuing interest — pro-rata" check on "Horizon Growth Fund I" is "breach"
    And the working shows "Others' paid-in share = ₹132.30 cr ÷ ₹294.00 cr = 45.00%"
    And the working shows "₹2.10 cr < ₹2.25 cr"

  # H36 — Happy path: monitoring on schedules the quarterly SEBI report duty with its due date
  Scenario: H36 Quarterly report duty
    When the nightly compliance run happens on "2026-11-05"
    Then "Horizon Growth Fund I" has a "Quarterly SEBI report filed" duty for "FY27-Q3" due "2027-01-15"

  # E48 — Edge case: above 25% breaches (26.67%)
  Scenario: E48 Above 25% breaches
    When the nightly compliance run happens on "2026-11-05"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    And the working shows "26.67%"

  # E49 — Edge case: a Category II — LVF fund passes at 40% and breaches at 50.01%
  Scenario: E49 Large Value Fund limit
    Given "Horizon Growth Fund I" is classified "Category II — LVF" under SEBI
    And "Acme Foods" costs ₹108.0 cr
    When the nightly compliance run happens on "2026-11-05"
    Then the "Single-investee concentration (Large Value Fund)" check on "Horizon Growth Fund I" is "pass"
    And the working shows "40.00%"
    Given "Acme Foods" costs ₹135.03 cr
    When the nightly compliance run happens on "2026-11-06"
    Then the "Single-investee concentration (Large Value Fund)" check on "Horizon Growth Fund I" is "breach"
    And the working shows "50.01%"

  # E50 — Edge case: the percentage applies (corpus ₹100 cr → required ₹2.50 cr; ₹2.00 cr is short ₹0.50 cr)
  Scenario: E50 Percentage applies
    Given "Small Corpus Fund" has a corpus of ₹100.0 cr with a sponsor commitment of ₹2.0 cr
    When the nightly compliance run happens on "2026-11-05" for "Small Corpus Fund"
    Then the "Continuing interest — amount" check on "Small Corpus Fund" is "breach"
    And the working shows "lower of ₹2.50 cr and ₹5.00 cr = ₹2.50 cr"
    And the working shows "₹2.00 cr < ₹2.50 cr"

  # E51 — Edge case: both equal (corpus ₹200 cr → 2.5% = ₹5.00 cr = cap)
  Scenario: E51 Both equal
    Given "Mid Corpus Fund" has a corpus of ₹200.0 cr with a sponsor commitment of ₹5.0 cr
    When the nightly compliance run happens on "2026-11-05" for "Mid Corpus Fund"
    Then the "Continuing interest — amount" check on "Mid Corpus Fund" is "pass"
    And the working shows "lower of ₹5.00 cr and ₹5.00 cr = ₹5.00 cr"

  # E52 — Edge case: an employee at ₹25,00,000 passes; at ₹24,99,999 breaches short ₹1
  Scenario: E52 Employee minimum
    Given employees and directors are mapped to the category "Directors/ Partners/ Employees of Sponsor"
    And "Horizon Growth Fund I" has an employee committing ₹2500000
    When the nightly compliance run happens on "2026-11-05"
    Then the "Minimum investment — employees/directors" check on "Horizon Growth Fund I" is "pass"
    Given "Horizon Growth Fund I" has an employee committing ₹2499999
    When the nightly compliance run happens on "2026-11-06"
    Then the "Minimum investment — employees/directors" check on "Horizon Growth Fund I" is "breach"
    And the working shows "(short ₹1)"

  # E53 — Edge case: exactly 1,000 investors passes
  Scenario: E53 Investor count 1,000
    Given "Thousand Fund" has exactly 1000 investors
    When the nightly compliance run happens on "2026-11-05" for "Thousand Fund"
    Then the "Investors in scheme" check on "Thousand Fund" is "pass"
    And the working shows "1,000 ≤ 1,000"

  # E54 — Edge case: 1,001 investors breaches
  Scenario: E54 Investor count 1,001
    Given "Big Fund" has exactly 1001 investors
    When the nightly compliance run happens on "2026-11-05" for "Big Fund"
    Then the "Investors in scheme" check on "Big Fund" is "breach"

  # X37 — Error case: the yearly compliance test report duty needs evidence
  Scenario: X37 Yearly duty without evidence
    When the nightly compliance run happens on "2026-11-05"
    Then marking the "Annual compliance test report / PPM audit" duty of "Horizon Growth Fund I" done without evidence is refused with "Upload the evidence"

  # X38 — Error case: a Category III fund with no NAV → "Could not check — missing: NAV"
  Scenario: X38 Cat III without NAV
    Given a "Category III" fund "Cat Three Fund" with no NAV
    When the nightly compliance run happens on "2026-11-05" for "Cat Three Fund"
    Then the "Single-investee concentration (Category III)" check on "Cat Three Fund" is "could_not_check"
    And the working shows "Could not check — missing: NAV"
