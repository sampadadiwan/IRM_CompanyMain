Feature: LP fund page stats cards for calls and distributions
  On the LP fund page, the Calls section shows Called (before fees) / Fees / Collected / Under Verification / Due / Overdue
  cards (verified basis: a payment is collected once the fund verifies it) and the
  Distributions section shows Total / Received / Pending / Last distribution cards, over every row
  the LP can see in the fund (CapitalRemittance.lp_totals, CapitalDistributionPayment.lp_totals).
  Every card is the total of a grid column the LP sees below it - as displayed, to the paisa - so the
  cards and the grid can never disagree. The fund owner's lists show no such cards.
  Amounts in the tables below are in major units (rupees) of the fund currency.

  Background:
    Given there is a user "first_name=Gita" for an entity "entity_type=Investment Fund;enable_funds=true"
    And the user has role "company_admin"
    And there is a fund "name=Stats Fund;currency=INR" for the entity
    And there is an existing investor "" with "1" users
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor

  # S1 — Edge case: Collected is verified payments only - Call 3's 150,000 is recorded but unverified, so it shows under
  #      Under Verification and stays due (the LP grid's Collected Amount / Under Verification columns)
  # S2 — Edge case: Due is the grid's "Due Amount" total (call + fee - verified collected per row), so Call 4's verified 30,000
  #      overpayment offsets the others; it equals the commitment's Due Amount (counters are verified-only too)
  # S3 — Edge case: Overdue is the "Due Amount" total of the Overdue rows only (Call 2: 210,000 - 50,000; Call 5: 40,000), with their count
  @rack_test
  Scenario: Remittance totals - each card is the total of the grid column the LP sees
    Given the LP has these remittances in the fund:
      | call   | call_amount | other_fee | collected | verified | status  |
      | Call 1 | 100000      | 0         | 100000    | true     | Paid    |
      | Call 2 | 200000      | 10000     | 50000     | true     | Overdue |
      | Call 3 | 150000      | 0         | 150000    | false    | Pending |
      | Call 4 | 50000       | 0         | 80000     | true     | Paid    |
      | Call 5 | 40000       | 0         | 0         | false    | Overdue |
    Then the LP remittance totals should be:
      | called             | 540000 |
      | fees               | 10000  |
      | collected          | 230000 |
      | under_verification | 150000 |
      | due                | 320000 |
      | overdue            | 200000 |
      | overdue_count      | 2      |
    And the LP remittance totals should equal the totals of the LP grid columns
    And the commitment card's due amount should equal the LP remittance due
    # S16 — Edge case: the LP grid's Status flags a recorded-but-unverified payment so a paid call doesn't read as a plain default;
    #       a call with nothing recorded (Call 5) or a verified one (Call 2) keeps its plain status
    And the LP grid status of "Call 3" should be "Pending · Payment under verification"
    And the LP grid status of "Call 5" should be "Overdue"
    And the LP grid status of "Call 2" should be "Overdue"
    And the LP grid status badges of "Call 3" should be "Pending:bg-warning, Payment under verification:bg-info"
    And the LP grid status badges of "Call 2" should be "Overdue:bg-danger"

  # S4 — Edge case: Total is the grid's "Net Payable" total (= Received + Pending); Gross Payable is not a card, since the legacy
  #      March row stores gross 0 and a gross total would understate what was paid
  # S5 — Edge case: Received is "Net Payable" of completed payments only; Pending is "Net Payable" of not-completed ones
  # S6 — Edge case: Last distribution is the completed row with the latest "Payment Date" - the June payment is later but not
  #      completed, and the March one has no payment date (blank in the grid), so February's is the last
  @rack_test
  Scenario: Distribution totals - each card is the total of the grid column the LP sees
    Given the LP has these distribution payments in the fund:
      | title    | distribution_date | payment_date | gross  | net   | tax   | completed |
      | Dist Jan | 2026-01-15        | 2026-01-20   | 100000 | 90000 | 10000 | true      |
      | Dist Mar | 2026-03-10        |              | 0      | 50000 | 0     | true      |
      | Dist Feb | 2026-02-01        | 2026-02-05   | 60000  | 54000 | 6000  | true      |
      | Dist Jun | 2026-06-01        | 2026-06-01   | 40000  | 36000 | 4000  | false     |
    Then the LP distribution totals should be:
      | total       | 230000     |
      | received    | 194000     |
      | pending     | 36000      |
      | last_amount | 54000      |
      | last_date   | 2026-02-05 |
    And the LP distribution totals should equal the totals of the LP grid columns

  # S7 — Edge case: the LP holds two fund access rights (by investor and by category), so the investor scope repeats every row;
  #      the controller's where(id: ...select(:id)) dedup keeps each row counted once
  @rack_test
  Scenario: An LP granted fund access twice is not double counted
    Given the LP has these remittances in the fund:
      | call   | call_amount | other_fee | collected | verified | status  |
      | Call 1 | 100000      | 0         | 40000     | true     | Overdue |
    And the LP has these distribution payments in the fund:
      | title    | distribution_date | payment_date | gross  | net   | tax   | completed |
      | Dist Jan | 2026-01-15        | 2026-01-20   | 100000 | 90000 | 10000 | true      |
    And the LP is granted access to the fund a second time
    Then the LP's investor scope should repeat each remittance and distribution payment
    And the LP remittance totals should be:
      | called        | 100000 |
      | collected     | 40000  |
      | due           | 60000  |
      | overdue       | 60000  |
      | overdue_count | 1      |
    And the LP distribution totals should be:
      | total       | 90000      |
      | received    | 90000      |
      | pending     | 0          |
      | last_amount | 90000      |
      | last_date   | 2026-01-20 |

  # S15 — Edge case: amounts carry fractional paise and the grid shows each row cut to whole paise
  #       (14,158,099.4088 shows as .40). The cards add the rows as shown, so Total is .60, not the
  #       .61 that summing the stored values first would show
  @rack_test
  Scenario: Cards add the grid rows as displayed, to the paisa
    Given the LP has these remittances in the fund:
      | call   | call_amount     | other_fee | collected      | verified | status  |
      | Call 1 | 14158099.4088   | 0         | 1000.0049      | true     | Overdue |
      | Call 2 | 33012890.2035   | 0.0066    | 33012890.2035  | true     | Paid    |
    And the LP has these distribution payments in the fund:
      | title    | distribution_date | payment_date | gross | net           | tax | completed |
      | Dist Jan | 2026-01-15        | 2026-01-20   | 0     | 33012890.2035 | 0   | true      |
      | Dist Jun | 2026-06-01        | 2026-06-01   | 0     | 14158099.4088 | 0   | false     |
    Then the LP remittance totals should equal the totals of the LP grid columns
    And the LP distribution totals should equal the totals of the LP grid columns

  # S8 — Edge case: the LP sees the remittance cards above their list in the lazily loaded Calls section, including
  #      Under Verification for Call 3's recorded-but-unverified payment (which stays in Due)
  Scenario: LP sees the remittance stats cards in the Calls section
    Given the LP has these remittances in the fund:
      | call   | call_amount | other_fee | collected | verified | status  |
      | Call 1 | 100000      | 0         | 100000    | true     | Paid    |
      | Call 2 | 200000      | 10000     | 50000     | true     | Overdue |
      | Call 3 | 150000      | 0         | 150000    | false    | Pending |
    And I login as the investor user
    When I open the Calls section of the fund page as the investor
    Then the LP remittance stats cards should be:
      | subtitle          | amount |
      | Called             | 450000 |
      | Fees               | 10000  |
      | Collected          | 150000 |
      | Under Verification | 150000 |
      | Due                | 310000 |
      | Overdue (1 call)   | 160000 |

  # S17 — Edge case: the LP fund page explains itself - each section header carries a one-line subtitle, every stats card an
  #       info tooltip saying how it is worked out, and the LP grid's money/status columns a header tooltip.
  #       Ratios and Portfolio are off for a new fund (FundEnabled::NEW_FUND_DEFAULTS), so they are switched on to show every section
  Scenario: LP sees section subtitles, card tooltips and column help in the Calls section
    Given the LP has these remittances in the fund:
      | call   | call_amount | other_fee | collected | verified | status  |
      | Call 1 | 100000      | 0         | 0         | false    | Overdue |
    And the fund shows its ratios and portfolio to investors
    And I login as the investor user
    When I open the Calls section of the fund page as the investor
    Then the fund page sections should show their subtitles
    And every LP remittance stats card should have a help tooltip
    And the LP grid headers "Status, Due Amount, Collected Amount, Under Verification, Payment Date" should have help tooltips

  # S9 — Edge case: with a pending payout, all four distribution cards show, the last one dated
  Scenario: LP sees the distribution stats cards in the Distributions section
    Given the LP has these distribution payments in the fund:
      | title    | distribution_date | payment_date | gross  | net   | tax   | completed |
      | Dist Jan | 2026-01-15        | 2026-01-20   | 100000 | 90000 | 10000 | true      |
      | Dist Jun | 2026-06-01        | 2026-06-01   | 40000  | 36000 | 4000  | false     |
    And I login as the investor user
    When I open the Distributions section of the fund page as the investor
    Then the LP distribution stats cards should be:
      | subtitle          | amount | date       |
      | Total Distributions | 126000 |            |
      | Received            | 90000  |            |
      | Pending Payout      | 36000  |            |
      | Last Distribution   | 90000  | 2026-01-20 |

  # S10 — Edge case: nothing pending, so the Pending Payout card is left out (a zero card is noise)
  Scenario: LP distribution stats hide the Pending card when it is zero
    Given the LP has these distribution payments in the fund:
      | title    | distribution_date | payment_date | gross  | net    | tax | completed |
      | Dist Jan | 2026-01-15        | 2026-01-20   | 100000 | 100000 | 0   | true      |
    And I login as the investor user
    When I open the Distributions section of the fund page as the investor
    Then the LP distribution stats cards should be:
      | subtitle          | amount | date       |
      | Total Distributions | 100000 |            |
      | Received            | 100000 |            |
      | Last Distribution   | 100000 | 2026-01-20 |
    And the LP distribution stats should not show the cards "Pending Payout, Gross Distributed, Tax Withheld"

  # S11 — Edge case: the fund owner's remittance list for the fund (fund_id of their own fund) gets no LP stats cards
  Scenario: Fund owner's remittance list shows no LP stats cards
    Given the LP has these remittances in the fund:
      | call   | call_amount | other_fee | collected | verified | status |
      | Call 1 | 100000      | 0         | 100000    | true     | Paid   |
    And I am signed in as the current user
    When I visit the fund's capital remittances list
    Then I should not see the LP remittance stats
    # S18 — Edge case: the fund team's grid explains its own columns too - its Due/Collected count every recorded
    #       payment, verified or not, and the help says so (LPs see the verified basis)
    And the remittance grid headers "Status, Verified, Due Amount, Collected Amount, Payment Date" should have help tooltips

  # S12 — Edge case: long unit words are shortened so the value fits a narrow card (Crores -> Cr, Million -> M, Lakhs -> L)
  # S13 — Edge case: a value without a trailing unit word (a date) is left as it is
  # S14 — Edge case: an html_safe amount stays html_safe after shortening, so its markup is not escaped
  @rack_test
  Scenario: NumberStatsComponent shortens unit words in the amount
    Then the stats card amount "₹383.02 Crores" should render as "₹383.02 Cr"
    And the stats card amount "1.5 Million" should render as "1.5 M"
    And the stats card amount "₹12.5 Lakhs" should render as "₹12.5 L"
    And the stats card amount "Aug 19, 2026" should render as "Aug 19, 2026"
    And the html-safe stats card amount "<b>7</b> Crores" should render bold "7" followed by " Cr"

  # S19 — Edge case: ratio names get a plain-language meaning; a currency variant ("TVPI (USD)") reuses the base text with a
  #       currency note; a custom variant the app can't know ("MOIC no fmv") gets none rather than a wrong one
  @rack_test
  Scenario: Ratio glossary covers standard ratios and their currency variants only
    Then the ratio help for "TVPI" should mention "paid-in"
    And the ratio help for "TVPI (USD)" should mention "Computed in USD"
    And the ratio help for "Gross Portfolio IRR (EUR)" should mention "Computed in EUR"
    And there should be no ratio help for "MOIC no fmv"

  # S20 — Edge case: the Ratios grid name tooltip and the column help show to LPs and the fund team alike
  @rack_test
  Scenario: Ratio name and column help render for investors and the fund team
    Given the fund has a ratio "TVPI" with value "1.5x"
    Then the ratio grid should show help for "TVPI" to an investor and to the fund team
    And the ratio grid header should show column help to an investor and to the fund team

  # S21 — Edge case: portfolio dashboard widgets explain themselves on their title
  @rack_test
  Scenario: Portfolio widget titles carry help
    Then the "FMV %" widget title should carry help
    And a widget without help such as "Agent Chart" should carry none

  # S22 — Edge case: an LP with no units sees why the Units grid is empty, and each column explains itself
  Scenario: LP Units section explains an empty grid and its columns
    Given I login as the investor user
    When I open the "units" section of the fund page as the investor
    Then I should see "No units have been allotted to your folios yet."
    And the "units" section grid headers should have help tooltips

  # S23 — Edge case: ?tab=commitments-tab (the commitment card's Fund Details button) keeps the already-open
  #       Commitments section open instead of toggling it shut
  Scenario: Linking to the open Commitments section keeps it open
    Given I login as the investor user
    When I visit the fund page with tab "commitments-tab"
    Then the "Commitments" section should be open

  # S24 — Edge case: on the fund team's grid Collected counts every recorded payment (Call 3's unverified 150,000 included),
  #       Unverified is the Collected Amount of Verified = No rows, Due is the raw Due Amount total - each a column the fund
  #       team sees (FOR_COMMITMENT_COLUMNS), so the cards still equal the grid
  @rack_test
  Scenario: Fund team remittance totals - recorded basis with Unverified
    Given the LP has these remittances in the fund:
      | call   | call_amount | other_fee | collected | verified | status  |
      | Call 1 | 100000      | 0         | 100000    | true     | Paid    |
      | Call 2 | 200000      | 10000     | 50000     | true     | Overdue |
      | Call 3 | 150000      | 0         | 150000    | false    | Paid    |
      | Call 4 | 50000       | 0         | 80000     | true     | Paid    |
      | Call 5 | 40000       | 0         | 0         | false    | Overdue |
    Then the fund team remittance totals for the LP's commitment should be:
      | called             | 540000 |
      | fees               | 10000  |
      | collected          | 380000 |
      | under_verification | 150000 |
      | due                | 170000 |
      | overdue            | 200000 |
      | overdue_count      | 2      |
    And the fund team remittance totals should equal the totals of the fund team grid columns

  # S25 — Edge case: the fund team sees the cards on the commitment page's Remittances and Distributions tabs, covering the
  #       folio's rows; the remittance cards are on the recorded basis, so an unverified payment shows under Unverified
  # S30 — Edge case: the completed-payments card is worded from the viewer's side - the fund team sees "Paid" for the
  #       figure an LP sees as "Received"
  Scenario: Fund team sees stats cards on the commitment page tabs
    Given the LP has these remittances in the fund:
      | call   | call_amount | other_fee | collected | verified | status  |
      | Call 1 | 100000      | 0         | 100000    | true     | Paid    |
      | Call 2 | 200000      | 10000     | 50000     | false    | Overdue |
    And the LP has these distribution payments in the fund:
      | title    | distribution_date | payment_date | gross  | net   | tax   | completed |
      | Dist Jan | 2026-01-15        | 2026-01-20   | 100000 | 90000 | 10000 | true      |
    And I am signed in as the current user
    When I open the "remittances" tab of the LP's commitment page
    Then the stats cards in "#lp_remittance_stats" should be:
      | subtitle         | amount |
      | Called           | 300000 |
      | Fees             | 10000  |
      | Collected        | 150000 |
      | Unverified       | 50000  |
      | Due              | 160000 |
      | Overdue (1 call) | 160000 |
    When I open the "distributions" tab of the LP's commitment page
    Then the stats cards in "#lp_distribution_stats" should be:
      | subtitle            | amount | date       |
      | Total Distributions | 90000  |            |
      | Paid                | 90000  |            |
      | Last Distribution   | 90000  | 2026-01-20 |

  # S26 — Edge case: units are totalled per unit type, never across types (Series A and Series C are different
  #       instruments); a transfer out (negative quantity) reduces its type's total, as the grid row shows
  @rack_test
  Scenario: Fund unit totals per unit type and Amount
    Given the LP's commitment has these fund units:
      | unit_type | quantity | price | premium |
      | Series A  | 2600     | 10    | 1       |
      | Series A  | -2       | 10    | 1       |
      | Series C  | 5200     | 5     | 0       |
    Then the fund unit totals for the LP's commitment should be:
      | Series A | 2598   |
      | Series C | 5200   |
      | amount   | 54578  |

  # S27 — Edge case: the fund team sees the per-type units and Amount cards on the commitment page's Units tab
  Scenario: Fund team sees fund unit stats cards on the commitment page
    Given the LP's commitment has these fund units:
      | unit_type | quantity | price | premium |
      | Series A  | 100      | 10    | 0       |
      | Series C  | 50       | 2     | 0       |
    And I am signed in as the current user
    When I open the Units tab of the LP's commitment page
    Then the fund unit stats cards should be:
      | subtitle      | value  |
      | Series A held | 100.0  |
      | Series C held | 50.0   |
    And the fund unit Amount card should be "1100"

  # S28 — Edge case: a headline card is the fund-level row with the latest On date for that ratio (an older TVPI is
  #       skipped), Default scenario first on a tie; currency variants ("TVPI (USD)") and non-headline ratios get no card;
  #       ratios the fund doesn't have get no card
  @rack_test
  Scenario: Headline ratio cards pick each ratio's latest fund-level row
    Given the fund has these ratios:
      | name       | display_value | end_date   | scenario |
      | TVPI       | 1.2x          | 2025-03-31 | Default  |
      | TVPI       | 1.5x          | 2025-12-31 | Default  |
      | TVPI       | 1.9x          | 2025-12-31 | Upside   |
      | TVPI (USD) | 1.4x          | 2025-12-31 | Default  |
      | XIRR       | 16.2 %        | 2025-12-31 | Default  |
      | Fund Utilization | 80 %    | 2025-12-31 | Default  |
    Then the headline ratio cards should be "XIRR=16.2 %, TVPI=1.5x"

  # S29 — Edge case: the fund team sees the headline cards on its Ratios tab, under one shared "as of" line
  Scenario: Fund team sees headline ratio cards on the fund's Ratios tab
    Given the fund has these ratios:
      | name | display_value | end_date   | scenario |
      | TVPI | 1.5x          | 2025-12-31 | Default  |
      | DPI  | 0.4x          | 2025-12-31 | Default  |
    And I am signed in as the current user
    When I open the fund team's Ratios tab
    Then I should see the headline ratio cards "TVPI=1.5x, DPI=0.4x"

  # S31 — Edge case: the LP fund page's top card names the completed-payments figure "Received", the same name as the
  #       Distributions section's card, so the two never read as different numbers
  Scenario: LP fund page top card names distributions Received
    Given the LP has these distribution payments in the fund:
      | title    | distribution_date | payment_date | gross  | net   | tax   | completed |
      | Dist Jan | 2026-01-15        | 2026-01-20   | 100000 | 90000 | 10000 | true      |
      | Dist Jun | 2026-06-01        | 2026-06-01   | 40000  | 36000 | 4000  | false     |
    And I login as the investor user
    When I visit the fund page as the investor
    Then the LP fund page top card "Received" should show "90000"
    And the LP fund page top cards should not include "Distributed"
