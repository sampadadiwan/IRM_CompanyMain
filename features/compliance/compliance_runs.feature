Feature: Compliance runs and results
  Nightly runs evaluate every attached pack's checks for a fund and store each result with its working.
  Worked examples: openspec/changes/fund-compliance-monitoring/business-rules.md (group 3)

  Background:
    Given the Horizon compliance setup

  # H19 — Happy path: the nightly run stores every attached pack's checks for Growth Fund I
  Scenario: H19 Nightly run stores each check
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    When the nightly compliance run happens on "2026-11-05"
    Then "Horizon Growth Fund I" has 1 compliance run on "2026-11-05"
    And the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    And the "Single-sector limit" check on "Horizon Growth Fund I" is "pass"

  # H20 — Happy path: concentration breach shows its working (300.00 − 30.00 = 270.00; 72.00 ÷ 270.00 = 26.67% > 25%)
  Scenario: H20 Concentration breach with working
    When the nightly compliance run happens on "2026-11-05"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    And the working shows "Investable funds = ₹300.00 cr − ₹30.00 cr = ₹270.00 cr"
    And the working shows "Acme Foods: ₹72.00 cr ÷ ₹270.00 cr = 26.67%"
    And the working shows "26.67% > 25%"

  # H21 — Happy path: a continuous check catches a passive breach after an LP default shrinks investable funds
  Scenario: H21 Continuous check catches a passive breach
    Given "Acme Foods" costs ₹50.0 cr
    And the investable funds of "Horizon Growth Fund I" are ₹200.0 cr
    When the nightly compliance run happens on "2026-11-05"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "pass"
    Given the investable funds of "Horizon Growth Fund I" are ₹180.0 cr
    When the nightly compliance run happens on "2026-11-06"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    And the working shows "27.78%"

  # H22 — Happy path: IC note list "14 of 17 OK · 3 failing · 120 earlier not checked"
  Scenario: H22 IC note list
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    And "Horizon Growth Fund I" has 14 investments with signed IC notes from "2026-04-02"
    And "Horizon Growth Fund I" invested in "Acme B2" on "2026-09-12" with no IC note
    And "Horizon Growth Fund I" invested in "Zen Seed" on "2026-10-03" with an IC note scan not marked signed
    And "Horizon Growth Fund I" invested in "Kite A" on "2026-10-20" with an IC note e-signed on "2026-10-24"
    And "Horizon Growth Fund I" has 117 investments before "2026-04-01" with no IC note
    When the nightly compliance run happens on "2026-11-05"
    Then the "IC note for every investment" check on "Horizon Growth Fund I" is "breach"
    And the IC note list shows "14 of 17 OK · 3 failing · 120 earlier not checked"
    And the IC note list includes "Acme B2" as "Missing"
    And the IC note list includes "Zen Seed" as "Not signed — mark as signed (wet ink)"
    And the IC note list includes "Kite A" as "after investment date"

  # H23 — Happy path: a wet-ink note signed 10 Sep and scanned 15 Sep passes for a 12 Sep investment
  Scenario: H23 Wet ink scanned after the investment
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    And "Horizon Growth Fund I" invested in "Orbit Health" on "2026-09-12" with a wet-ink IC note signed on "2026-09-10" and uploaded on "2026-09-15"
    When the nightly compliance run happens on "2026-11-05"
    Then the "IC note for every investment" check on "Horizon Growth Fund I" is "pass"

  # E18 — Edge case: Run now pressed twice gives one result set
  Scenario: E18 Run now twice
    When Run now is pressed twice on "2026-11-05" for "Horizon Growth Fund I"
    Then "Horizon Growth Fund I" has 1 compliance run on "2026-11-05"

  # E19 — Edge case: a wound-up fund is not run
  Scenario: E19 Closed fund not run
    Given "Horizon Growth Fund I" is wound up
    When the nightly compliance run happens on "2026-11-05"
    Then "Horizon Growth Fund I" has 0 compliance runs on "2026-11-05"

  # H24 — Happy path: a USD 150,000 minimum on a ₹1.20 cr commitment at ₹83.00/USD — 1,20,00,000 ÷ 83.00 = USD 144,578 < 150,000 → Breach; rate shown
  Scenario: H24 USD limit on an INR figure
    Given the IFSCA pack is published
    And "Horizon India Feeder" is an INR fund classified "Restricted Scheme" under IFSCA with an investor committing ₹1.20 cr
    And the USD to INR rate is 83.00 on "2026-11-04"
    When the nightly compliance run happens on "2026-11-05" for "Horizon India Feeder"
    Then the "Minimum investment per investor (Restricted Scheme)" check on "Horizon India Feeder" is "breach"
    And the working shows "Rate: ₹83.00 per USD on 04/11/2026 (manual)"
    And the working shows "₹1,20,00,000 ÷ 83.00 = USD 144,578 < USD 150,000"
    And the result's working records the rate 83.00 from "INR" to "USD"

  # E20 — Edge case: correcting data later does not rewrite an earlier result
  Scenario: E20 Corrected data does not rewrite history
    When the nightly compliance run happens on "2026-11-05"
    Given "Acme Foods" costs ₹65.0 cr
    When the nightly compliance run happens on "2026-11-06"
    Then the "Single-investee concentration" result of "Horizon Growth Fund I" on "2026-11-05" is still "breach" with "26.67%"
    And the "Single-investee concentration" check on "Horizon Growth Fund I" is "pass"
    And the working shows "24.07%"

  # E21 — Edge case: a check tested "when a record is made" ignores later changes to investable funds
  Scenario: E21 Record-time check ignores later changes
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    And the fund agreement concentration check is tested when a record is made
    And "Acme Foods" costs ₹50.0 cr
    And the investable funds of "Horizon Growth Fund I" are ₹270.0 cr
    When the nightly compliance run happens on "2026-11-05"
    Then the fund agreement concentration has 3 record results
    Given the investable funds of "Horizon Growth Fund I" are ₹180.0 cr
    When the nightly compliance run happens on "2026-11-06"
    Then the fund agreement concentration has 3 record results
    And no fund agreement concentration result is a breach after "2026-11-06"

  # E22 — Edge case: 25.0037% shows 25.00% and passes; 25.0111% shows 25.01% and breaches
  Scenario: E22 Rounding at the limit
    Given "Acme Foods" costs ₹67.51 cr
    When the nightly compliance run happens on "2026-11-05"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "pass"
    And the working shows "25.00%"
    Given "Acme Foods" costs ₹67.53 cr
    When the nightly compliance run happens on "2026-11-06"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    And the working shows "25.01%"

  # E23 — Edge case: investors below the ₹1 cr minimum are each listed with their shortfall
  Scenario: E23 Investors below the minimum listed
    Given "Horizon Growth Fund I" has investors committing "9000000,9999999"
    When the nightly compliance run happens on "2026-11-05"
    Then the "Minimum investment per investor" check on "Horizon Growth Fund I" is "breach"
    And the working shows "Small LP 1: ₹90,00,000 (short ₹10,00,000)"
    And the working shows "Small LP 2: ₹99,99,999 (short ₹1)"

  # E24 — Edge case: SEBI ≤ 25% and fund agreement ≤ 20% both fail, one breach per pack
  Scenario: E24 SEBI and fund agreement both fail
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    When the nightly compliance run happens on "2026-11-05"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    And the "Fund agreement concentration" check on "Horizon Growth Fund I" is "breach"
    And "Horizon Growth Fund I" has open register items for "Single-investee concentration" and "Fund agreement concentration"

  # E25 — Edge case: an investment on the checks-from date is checked; the day before is counted "not checked"
  Scenario: E25 Checks-from boundary
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    And "Horizon Growth Fund I" invested in "March Co" on "2026-03-31" with no IC note
    And "Horizon Growth Fund I" invested in "April Co" on "2026-04-01" with no IC note
    When the nightly compliance run happens on "2026-11-05"
    Then the "IC note for every investment" check on "Horizon Growth Fund I" is "breach"
    And the IC note list includes "April Co" as "Missing"
    And the IC note list does not include "March Co"
    And the IC note list shows "0 of 1 OK · 1 failing · 4 earlier not checked"

  # E26 — Edge case: a note signed on the investment day passes (12 Sep ≤ 12 Sep)
  Scenario: E26 Signed on investment day
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    And "Horizon Growth Fund I" invested in "Same Day Co" on "2026-09-12" with a wet-ink IC note signed on "2026-09-12" and uploaded on "2026-09-20"
    When the nightly compliance run happens on "2026-11-05"
    Then the "IC note for every investment" check on "Horizon Growth Fund I" is "pass"

  # E27 — Edge case: e-sign completed after the investment is "signed late"; a later upload does not clear it
  Scenario: E27 E-sign completed after the investment
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    And "Horizon Growth Fund I" invested in "Kite Pay A" on "2026-10-20" with an IC note e-signed on "2026-10-24"
    When the nightly compliance run happens on "2026-11-05"
    Then the IC note list includes "Kite Pay A" as "after investment date"
    Given a newer IC note for "Kite Pay A" is uploaded and e-signed on "2026-11-06"
    When the nightly compliance run happens on "2026-11-07"
    Then the "IC note for every investment" check on "Horizon Growth Fund I" is "breach"
    And the IC note list includes "Kite Pay A" as "after investment date"

  # E28 — Edge case: 25 h after the last success is current; 26 h 01 m is "may be out of date"
  Scenario: E28 Staleness boundary
    Given the last successful run of "Horizon Growth Fund I" finished 25 hours and 0 minutes ago
    Then the results of "Horizon Growth Fund I" are current
    Given the last successful run of "Horizon Growth Fund I" finished 26 hours and 1 minutes ago
    Then the results of "Horizon Growth Fund I" are stale

  # E29 — Edge case: a US entity runs at 02:00 Eastern time
  Scenario: E29 Entity time zone
    Given Horizon's compliance time zone is "Eastern Time (US & Canada)"
    When the hourly compliance tick happens at "2026-11-05 02:05" "Eastern Time (US & Canada)"
    Then "Horizon Growth Fund I" has 1 compliance run on "2026-11-05"

  # E30 — Edge case: a fund with no investments passes concentration at 0% and lists 0 of 0
  Scenario: E30 Zero investments
    Given "Empty Fund" is a fund with no investments, category "Category II"
    And "Empty Fund" also carries the fund agreement pack
    When the nightly compliance run happens on "2026-11-05" for "Empty Fund"
    Then the "Single-investee concentration" check on "Empty Fund" is "pass"
    And the working shows "0.00%"
    And the "IC note for every investment" check on "Empty Fund" is "pass"
    And the IC note list shows "0 of 0 OK"

  # X24 — Error case: blank estimated expenses → "Could not check — missing: estimated expenses"
  Scenario: X24 Missing input
    Given the estimated expenses of "Horizon Growth Fund I" are blank
    When the nightly compliance run happens on "2026-11-05"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "could_not_check"
    And the working shows "Could not check — missing: estimated expenses"

  # X25 — Error case: no INR/USD rate on or before the run date → "Could not check — missing: INR/USD rate for <date>"
  Scenario: X25 Missing exchange rate
    Given the IFSCA pack is published
    And "Horizon India Feeder" is an INR fund classified "Restricted Scheme" under IFSCA with an investor committing ₹1.20 cr
    When the nightly compliance run happens on "2026-11-05" for "Horizon India Feeder"
    Then the "Minimum investment per investor (Restricted Scheme)" check on "Horizon India Feeder" is "could_not_check"
    And the working shows "Could not check — missing: INR/USD rate for 05/11/2026"

  # X26 — Error case: an IC note scan not marked signed is "Not signed — mark as signed (wet ink)"
  Scenario: X26 Scan not marked signed
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    And "Horizon Growth Fund I" invested in "Zen Labs Seed" on "2026-10-03" with an IC note scan not marked signed
    When the nightly compliance run happens on "2026-11-05"
    Then the IC note list includes "Zen Labs Seed" as "Not signed — mark as signed (wet ink)"

  # X27 — Error case: a signed date in the future is refused
  Scenario: X27 Future signed date refused
    Given the compliance date is "2026-11-05"
    Then marking a document signed on "2026-11-06" is refused with "Signed date cannot be in the future"

  # X28 — Error case: a failed run shows the last successful run as out of date and tells owners and CapHive support
  Scenario: X28 Failed run
    When the nightly compliance run happens on "2026-11-05"
    And the nightly compliance run on "2026-11-06" fails
    Then the latest run of "Horizon Growth Fund I" is "failed"
    And "Meera" got the compliance notice "Compliance run failed for Horizon Growth Fund I"
    And CapHive support got an email about "Compliance run failed"
    Given 26 hours pass after the last successful run
    Then the results of "Horizon Growth Fund I" are stale

  # X29 — Error case: unmapped sponsor/manager → continuing-interest checks "Could not check — missing: Sponsor/manager"
  Scenario: X29 Missing sponsor mapping
    Given the sponsor/manager input is unmapped
    When the nightly compliance run happens on "2026-11-05"
    Then the "Continuing interest — amount" check on "Horizon Growth Fund I" is "could_not_check"
    And the working shows "Could not check — missing: Sponsor/manager"
    And the "Continuing interest — pro-rata" check on "Horizon Growth Fund I" is "could_not_check"
