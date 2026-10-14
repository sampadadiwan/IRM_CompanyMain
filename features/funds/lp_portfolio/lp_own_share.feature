Feature: LP sees their own share
  Under Allocated, with their own share, each LP sees Your Cost and Your FMV beside the fund's figures, read from
  their own folio entries under the allocation formula and the Your FMV formula — never recomputed on screen.
  Worked examples: openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
  (H3, E5, E6, E6a, E29–E41)

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity
    Given the fund has the LP allocation formulas
    Given the fund "Growth Fund I" holds:
      | company         | instrument    | purchases | cost_cr | fmv_cr |
      | Acme Robotics   | Series B CCPS | 2         | 25.00   | 40.00  |
      | Bluefin Health  | Series A CCPS | 1         | 20.00   | 22.00  |
      | Cedar Logistics | Series A CCPS | 1         | 15.00   | 18.00  |
      | Delta AI        | Seed CCPS     | 1         | 3.00    | 3.00   |
    Given LP "Ravi Menon" has folio "F-012" in "Growth Fund I"
    Given folio "F-012" has allocation entries:
      | formula                  | company         | instrument    | amount | purchase | date       |
      | Allocated Portfolio Cost | Acme Robotics   | Series B CCPS | 1.00   | 1        | 30/09/2026 |
      | Allocated Portfolio Cost | Acme Robotics   | Series B CCPS | 1.50   | 2        | 30/09/2026 |
      | Allocated Portfolio FMV  | Acme Robotics   | Series B CCPS | 3.60   | 1        | 30/06/2026 |
      | Allocated Portfolio FMV  | Acme Robotics   | Series B CCPS | 4.00   | 1        | 30/09/2026 |
      | Allocated Portfolio Cost | Cedar Logistics | Series A CCPS | 1.50   | 1        | 30/09/2026 |
      | Allocated Portfolio FMV  | Cedar Logistics | Series A CCPS | 1.80   | 1        | 30/09/2026 |
      | Allocated Portfolio Cost | Bluefin Health  | Series A CCPS | 0.00   | 1        | 30/09/2026 |
    Given the fund "Growth Fund I" LP portfolio view is "allocated_with_share" with allocation formula "Allocated Portfolio Cost" and FMV formula "Allocated Portfolio FMV"

  # H3 — Happy path: Acme 2.50 / 4.00, Cedar 1.50 / 1.80; totals 4.00 / 5.80, multiple 5.80 ÷ 4.00 = 1.45x
  Scenario: Own share shown
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see Your cost "₹2.50 Cr" and Your FMV "₹4.00 Cr" for "Acme Robotics"
    And the LP should see Your cost "₹1.50 Cr" and Your FMV "₹1.80 Cr" for "Cedar Logistics"
    And the LP own share totals should be cost "₹4.00 Cr" and FMV "₹5.80 Cr"
    And the LP own share note should read "Your cost = \"Allocated Portfolio Cost\", Your FMV = \"Allocated Portfolio FMV\"."
    And the LP own share note should read "multiple 1.45x"

  # E5 — Edge case: a renamed formula keeps working and the note shows the new name
  Scenario: Renamed formula
    When the formula "Allocated Portfolio FMV" is renamed to "LP FMV"
    And LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see Your cost "₹2.50 Cr" and Your FMV "₹4.00 Cr" for "Acme Robotics"
    And the LP own share note should read "Your FMV = \"LP FMV\""

  # E6 — Edge case: the Your FMV formula deleted — holdings still listed, no Your columns, fund team told to re-pick
  Scenario: Deleted FMV formula
    When the formula "Allocated Portfolio FMV" is deleted
    And LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see the holdings "Acme Robotics, Cedar Logistics"
    And the LP should not see the Your columns
    When the fund team opens the fund page of "Growth Fund I"
    Then I should see "Pick a new formula for Your FMV for the LP portfolio view."

  # E6a — Edge case: the allocation formula deleted — no holdings for LPs, fund team told to re-pick
  Scenario: Deleted allocation formula
    Given the fund "Growth Fund I" LP portfolio view is "allocated" with allocation formula "Allocated Portfolio Cost"
    When the formula "Allocated Portfolio Cost" is deleted
    And LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP folio banner should read "No investments have been allocated to your folio yet."
    When the fund team opens the fund page of "Growth Fund I"
    Then I should see "Pick a new allocation formula for the LP portfolio view."

  # E29 — Edge case: the latest FMV entry on or before today wins (30/09 ₹4.00 over 30/06 ₹3.60)
  Scenario: Latest date used
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see Your cost "₹2.50 Cr" and Your FMV "₹4.00 Cr" for "Acme Robotics"

  # E30 — Edge case: a future-dated FMV entry is ignored
  Scenario: Future-dated ignored
    Given folio "F-012" has allocation entries:
      | formula                 | company       | instrument    | amount | purchase | date       |
      | Allocated Portfolio FMV | Acme Robotics | Series B CCPS | 4.40   | 1        | 31/12/2099 |
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see Your cost "₹2.50 Cr" and Your FMV "₹4.00 Cr" for "Acme Robotics"

  # E31 — Edge case: the deleted 30/09 FMV entry falls back to 30/06's ₹3.60
  Scenario: Deleted latest ignored
    When folio "F-012" entry "Allocated Portfolio FMV" for "Acme Robotics" dated "30/09/2026" is deleted
    And LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see Your cost "₹2.50 Cr" and Your FMV "₹3.60 Cr" for "Acme Robotics"

  # E32 — Edge case: the two purchases' cost entries (1.00 + 1.50) sum to the holding's ₹2.50 Cr
  Scenario: Purchases summed
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see Your cost "₹2.50 Cr" and Your FMV "₹4.00 Cr" for "Acme Robotics"

  # E33 — Edge case: each purchase uses its own latest entry — purchase 1's older 0.80 is replaced by 1.00, purchase 2 stays 1.50
  Scenario: Purchases with different latest dates
    Given folio "F-012" has allocation entries:
      | formula                  | company       | instrument    | amount | purchase | date       |
      | Allocated Portfolio Cost | Acme Robotics | Series B CCPS | 0.80   | 1        | 31/03/2026 |
      | Allocated Portfolio Cost | Acme Robotics | Series B CCPS | 1.20   | 2        | 30/06/2026 |
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see Your cost "₹2.50 Cr" and Your FMV "₹4.00 Cr" for "Acme Robotics"

  # E34 — Edge case: an aggregated-holding FMV formula maps straight to the holding (₹4.10 Cr)
  Scenario: Aggregated-holding FMV formula
    Given the fund "Growth Fund I" LP portfolio view is "allocated_with_share" with allocation formula "Allocated Portfolio Cost" and FMV formula "Portfolio FMV by API"
    Given folio "F-012" has allocation entries:
      | formula              | company       | instrument    | amount |
      | Portfolio FMV by API | Acme Robotics | Series B CCPS | 4.10   |
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see Your cost "₹2.50 Cr" and Your FMV "₹4.10 Cr" for "Acme Robotics"

  # E35 — Edge case: Priya's two folios add up — Acme cost 1.00 + 0.50 = ₹1.50 Cr
  Scenario: Several folios added
    Given LP "Priya Shah" has folio "F-050" in "Growth Fund I"
    Given LP "Priya Shah" has folio "F-051" in "Growth Fund I"
    Given folio "F-050" has allocation entries:
      | formula                  | company       | instrument    | amount |
      | Allocated Portfolio Cost | Acme Robotics | Series B CCPS | 1.00   |
      | Allocated Portfolio FMV  | Acme Robotics | Series B CCPS | 1.20   |
    Given folio "F-051" has allocation entries:
      | formula                  | company       | instrument    | amount |
      | Allocated Portfolio Cost | Acme Robotics | Series B CCPS | 0.50   |
      | Allocated Portfolio FMV  | Acme Robotics | Series B CCPS | 0.60   |
    When LP "Priya Shah" opens the portfolio of "Growth Fund I"
    Then the LP should see Your cost "₹1.50 Cr" and Your FMV "₹1.80 Cr" for "Acme Robotics"

  # E36 — Edge case: a feeder LP's own share comes from the feeder fund's formulas, in the feeder's USD
  Scenario: Feeder figures in feeder currency
    Given there is a fund "name=Master Fund M;currency=INR;show_portfolios=true" for the entity
    Given the fund "Master Fund M" holds:
      | company    | instrument | purchases | cost_cr | fmv_cr |
      | Echo Foods | Equity     | 1         | 30.00   | 33.00  |
    Given the fund "Master Fund M" has the formula "Master Fund Cost" of type "AllocatePortfolioInvestment"
    Given the fund "Master Fund M" LP portfolio view is "allocated" with allocation formula "Master Fund Cost"
    Given there is a feeder fund "Feeder Fund F" of "Master Fund M" in "USD"
    Given the fund "Feeder Fund F" has the formula "Master PI Cost" of type "AllocateMasterFundPortfolioInvestment"
    Given the fund "Feeder Fund F" has the formula "Master PI FMV" of type "AllocateMasterFundPortfolioInvestment"
    Given the fund "Feeder Fund F" LP portfolio view is "allocated_with_share" with allocation formula "Master PI Cost" and FMV formula "Master PI FMV"
    Given LP "Sunil Kapoor" has folio "FF-01" in "Feeder Fund F"
    Given folio "FF-01" has allocation entries:
      | formula        | company    | instrument | amount     | holding fund  |
      | Master PI Cost | Echo Foods | Equity     | 120000 USD | Master Fund M |
      | Master PI FMV  | Echo Foods | Equity     | 132000 USD | Master Fund M |
    When LP "Sunil Kapoor" opens the portfolio of "Master Fund M"
    Then the LP should see Your cost "$120,000" and Your FMV "$132,000" for "Echo Foods"

  # E37 — Edge case: a re-run changing Acme's cost (purchase 1: 1.00 → 1.10) shows ₹2.60 Cr on the next load
  Scenario: Re-run changes figures
    When folio "F-012" entry "Allocated Portfolio Cost" for "Acme Robotics" "Series B CCPS" purchase 1 changes to "1.10"
    And LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see Your cost "₹2.60 Cr" and Your FMV "₹4.00 Cr" for "Acme Robotics"
    And the LP own share totals should be cost "₹4.10 Cr" and FMV "₹5.80 Cr"

  # E38 — Edge case: Delta has a cost entry (0.70) but no FMV entry — FMV "—", left out of the FMV total and counted
  Scenario: Dash for missing FMV entry
    Given folio "F-012" has allocation entries:
      | formula                  | company  | instrument | amount |
      | Allocated Portfolio Cost | Delta AI | Seed CCPS  | 0.70   |
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see Your cost "₹0.70 Cr" and Your FMV "—" for "Delta AI"
    And the LP own share totals should be cost "₹4.70 Cr" and FMV "₹5.80 Cr"
    And the LP own share note should read "Excludes 1 holding not yet allocated."

  # E39 — Edge case: a zero entry is a figure — Priya's Bluefin cost is 0.00 + 1.00 = ₹1.00 Cr, not a dash
  Scenario: Zero entry is a figure, not a dash
    Given LP "Priya Shah" has folio "F-050" in "Growth Fund I"
    Given LP "Priya Shah" has folio "F-051" in "Growth Fund I"
    Given folio "F-050" has allocation entries:
      | formula                  | company        | instrument    | amount |
      | Allocated Portfolio Cost | Bluefin Health | Series A CCPS | 0.00   |
      | Allocated Portfolio FMV  | Bluefin Health | Series A CCPS | 0.00   |
    Given folio "F-051" has allocation entries:
      | formula                  | company        | instrument    | amount |
      | Allocated Portfolio Cost | Bluefin Health | Series A CCPS | 1.00   |
      | Allocated Portfolio FMV  | Bluefin Health | Series A CCPS | 1.10   |
    When LP "Priya Shah" opens the portfolio of "Growth Fund I"
    Then the LP should see Your cost "₹1.00 Cr" and Your FMV "₹1.10 Cr" for "Bluefin Health"

  # E40 — Edge case: Allocated to their folio (picks still stored) shows no Your columns
  Scenario: Columns absent elsewhere
    Given the fund "Growth Fund I" LP portfolio view is "allocated"
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see the holdings "Acme Robotics, Cedar Logistics"
    And the LP should not see the Your columns

  # E41 — Edge case: the multiple uses the LP's figures — Acme 4.00 ÷ 2.50 = 1.60x, total 1.45x
  Scenario: Multiple uses LP figures
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see Your multiple "1.60x" for "Acme Robotics"
    And the LP own share note should read "multiple 1.45x"
