Feature: LP fund page stats cards for calls and distributions
  On the LP fund page, the Calls section shows Called / Collected / Due / Overdue cards and the
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

  # S1 — Edge case: Collected is the grid's "Collected Amount" total, verified or not - Call 3's unverified 150,000 counts
  # S2 — Edge case: Due is the grid's "Due Amount" total (call + fee - collected per row), so Call 4's 30,000 overpayment offsets the others
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
      | called        | 550000 |
      | collected     | 380000 |
      | due           | 170000 |
      | overdue       | 200000 |
      | overdue_count | 2      |
    And the LP remittance totals should equal the totals of the LP grid columns

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

  # S8 — Edge case: the LP sees the four remittance cards above their list in the lazily loaded Calls section
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
      | Called            | 460000 |
      | Collected         | 300000 |
      | Due               | 160000 |
      | Overdue (1 call)  | 160000 |

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
