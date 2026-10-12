Feature: Derivatives — listed contracts and FX forwards
  Funds with the Derivatives feature record contracts and their events. Values come from the
  exchange settlement price or the counterparty's statement; events post to the fund ledger;
  physical exercise creates the share purchase or sale. No pricing models.
  Worked examples: openspec/changes/fund-market-data/business-rules.md (H11–H16, E48–E55, E57, X16–X25)

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the user is tagged "FundAccounting"
    Given these funds exist with rate sources:
      | fund                   | currency | sources       | prices        |
      | Horizon Evergreen Fund | INR      | manual,market | manual,market |
      | Bridge Hybrid Fund     | INR      | manual        | manual        |
    And the fund "Horizon Evergreen Fund" has derivatives switched on
    And there is an INR instrument "ACMEIND"
    And these exchange rates exist:
      | from | to  | rate  | as_of       | source | provider    |
      | USD  | INR | 83.00 | 01 Apr 2026 | manual | User        |
      | USD  | INR | 85.00 | 30 Oct 2026 | market | ECB via EUR |

  # H11 — Happy path: a long Nifty put (1 × 75, strike 24,000, premium ₹40,000) is recorded; the ledger shows −₹40,000 "Derivative Premium"
  Scenario: Listed put recorded
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name          | Nifty 24000 put   |
      | contract_type | option            |
      | side          | long              |
      | option_type   | put               |
      | underlying_type | index           |
      | underlying_name | NIFTY           |
      | strike        | 24000             |
      | lots          | 1                 |
      | lot_size      | 75                |
      | premium       | 40000             |
      | trade_date    | 12 Oct 2026       |
      | expiry_date   | 26 Nov 2026       |
      | exchange      | NSE               |
      | feed_symbol   | NIFTY26NOV24000PE |
    Then the contract should be saved
    And the contract "Nifty 24000 put" should be open
    And "Nifty 24000 put" should have 1 "trade" event
    And the ledger should have a "Derivative Premium" entry of "-40000" for "Nifty 24000 put"

  # H12 — Happy path: a short USD→INR forward on USD 1,00,000 at 84.00 with Bank X is recorded with no premium entry
  Scenario: FX forward recorded
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name              | FX fwd USD       |
      | contract_type     | fx_forward       |
      | side              | short            |
      | underlying_type   | currency_pair    |
      | underlying_name   | USD/INR          |
      | notional          | 100000           |
      | forward_rate      | 84.00            |
      | trade_date        | 12 Oct 2026      |
      | expiry_date       | 29 Jan 2027      |
      | listed            | false            |
      | counterparty_name | Bank X           |
    Then the contract should be saved
    And the contract "FX fwd USD" should be open
    And the ledger should have no "Derivative Premium" entry for "FX fwd USD"

  # H13 — Happy path: NSE F&O settles the put at ₹333.33; value ₹24,999.75 is stored and the change −₹15,000.25 is posted
  @sync-http
  Scenario: Listed contract valued from the feed
    Given the price feed is on with providers "nse_fo"
    And "Horizon Evergreen Fund" has a derivative contract:
      | name          | Nifty 24000 put   |
      | contract_type | option            |
      | side          | long              |
      | option_type   | put               |
      | underlying_type | index           |
      | underlying_name | NIFTY           |
      | strike        | 24000             |
      | lots          | 1                 |
      | lot_size      | 75                |
      | premium       | 40000             |
      | trade_date    | 12 Oct 2026       |
      | expiry_date   | 26 Nov 2026       |
      | exchange      | NSE               |
      | feed_symbol   | NIFTY26NOV24000PE |
    And NSE F&O reports a settlement price of "333.33" for "NIFTY26NOV24000PE" on "30 Oct 2026"
    When the price feed runs for "30 Oct 2026"
    Then the value of "Nifty 24000 put" on "30 Oct 2026" should be "24999.75"
    And the ledger should have a "Derivative Unrealised Gain/Loss" entry of "-15000.25" for "Nifty 24000 put"

  # H14 — Happy path: Bank X's statement valuing the forward at −₹1,50,000 is uploaded; the contract shows as a liability
  Scenario: Counterparty upload
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name              | FX fwd USD    |
      | contract_type     | fx_forward    |
      | side              | short         |
      | underlying_type   | currency_pair |
      | underlying_name   | USD/INR       |
      | notional          | 100000        |
      | forward_rate      | 84.00         |
      | trade_date        | 12 Oct 2026   |
      | expiry_date       | 29 Jan 2027   |
      | listed            | false         |
      | counterparty_name | Bank X        |
    When a derivative valuation upload row values "FX fwd USD" at "-150000" on "30 Oct 2026" by "Bank X"
    Then the value of "FX fwd USD" on "30 Oct 2026" should be "-150000"
    And I am at the login page
    When I fill and submit the login page
    And I open the contract "FX fwd USD"
    Then I should see "Upload · Bank X"
    And I should see "liability"

  # H15 — Happy path: exercising a long ACMEIND call (1 × 75, strike ₹1,000, premium ₹7,500) buys 75 shares at ₹1,100 and closes the call
  Scenario: Call exercised into shares
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name                  | ACME 1000 call |
      | contract_type         | option         |
      | side                  | long           |
      | option_type           | call           |
      | underlying_instrument | ACMEIND        |
      | strike                | 1000           |
      | lots                  | 1              |
      | lot_size              | 75             |
      | premium               | 7500           |
      | settlement            | physical       |
      | trade_date            | 12 Oct 2026    |
      | expiry_date           | 26 Nov 2026    |
      | exchange              | NSE            |
    When the event "type=exercise;date=13 Oct 2026" is recorded on "ACME 1000 call"
    Then the event should be recorded
    And "Horizon Evergreen Fund" should hold "75" "ACMEIND" bought at "1100" each from the exercise
    And the contract "ACME 1000 call" should be closed

  # H16 — Happy path: the forward marked as hedging Nimbus shows on Nimbus's holding page as "Hedged by: FX forward, sell USD 1,00,000 @ 84.00"
  Scenario: Forward hedges a holding
    Given "Horizon Evergreen Fund" holds 1000 "Nimbus Inc" (USD) bought at "100" each on "01 Apr 2026"
    And "Horizon Evergreen Fund" has a derivative contract:
      | name              | FX fwd USD    |
      | contract_type     | fx_forward    |
      | side              | short         |
      | underlying_type   | currency_pair |
      | underlying_name   | USD/INR       |
      | notional          | 100000        |
      | forward_rate      | 84.00         |
      | trade_date        | 12 Oct 2026   |
      | expiry_date       | 29 Jan 2027   |
      | listed            | false         |
      | counterparty_name | Bank X        |
      | hedges            | Nimbus Inc    |
    And the event "type=valuation;date=10 Oct 2026;value=-150000;provider=Bank X;source=upload" is recorded on "FX fwd USD"
    And I am at the login page
    When I fill and submit the login page
    And I open the holding "Nimbus Inc" in "Horizon Evergreen Fund"
    Then I should see "Hedged by"
    And I should see "FX forward, sell USD 100,000 @ 84.00"

  # E48 — Edge case: a short call with ₹30,000 premium received posts +₹30,000
  Scenario: Short option receives premium
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name          | ACME 1300 call short |
      | contract_type | option               |
      | side          | short                |
      | option_type   | call                 |
      | underlying_instrument | ACMEIND      |
      | strike        | 1300                 |
      | lots          | 1                    |
      | lot_size      | 75                   |
      | premium       | 30000                |
      | trade_date    | 12 Oct 2026          |
      | expiry_date   | 26 Nov 2026          |
      | exchange      | NSE                  |
    Then the ledger should have a "Derivative Premium" entry of "30000" for "ACME 1300 call short"

  # E49 — Edge case: closing 1 of 2 lots of a long put (premium ₹80,000) for ₹18,000 leaves 1 lot open and posts −₹22,000 realised
  Scenario: Partial close-out
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name          | Nifty put 2 lots |
      | contract_type | option           |
      | side          | long             |
      | option_type   | put              |
      | underlying_type | index          |
      | underlying_name | NIFTY          |
      | strike        | 24000            |
      | lots          | 2                |
      | lot_size      | 75               |
      | premium       | 80000            |
      | trade_date    | 12 Oct 2026      |
      | expiry_date   | 26 Nov 2026      |
      | exchange      | NSE              |
    When the event "type=close_out;date=20 Oct 2026;lots=1;amount=18000" is recorded on "Nifty put 2 lots"
    Then the event should be recorded
    And the contract "Nifty put 2 lots" should have "1" open lots
    And the ledger should have a "Derivative Realised Gain/Loss" entry of "-22000" for "Nifty put 2 lots"

  # E50 — Edge case: the put valued at ₹24,999.75 expires worthless; it closes, realised −₹40,000, the −₹15,000.25 unrealised is reversed
  Scenario: Option expires worthless
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name          | Nifty 24000 put |
      | contract_type | option          |
      | side          | long            |
      | option_type   | put             |
      | underlying_type | index         |
      | underlying_name | NIFTY         |
      | strike        | 24000           |
      | lots          | 1               |
      | lot_size      | 75              |
      | premium       | 40000           |
      | trade_date    | 12 Oct 2026     |
      | expiry_date   | 26 Nov 2026     |
      | exchange      | NSE             |
    And the event "type=valuation;date=30 Oct 2026;value=24999.75;source=market;provider=NSE F&O" is recorded on "Nifty 24000 put"
    When the event "type=expiry;date=26 Nov 2026" is recorded on "Nifty 24000 put"
    Then the contract "Nifty 24000 put" should be closed
    And the ledger should have a "Derivative Realised Gain/Loss" entry of "-40000" for "Nifty 24000 put"
    And the ledger should have a "Derivative Unrealised Gain/Loss" entry of "15000.25" for "Nifty 24000 put"

  # E51 — Edge case: the same exercise submitted twice (same key) records one event and one share purchase
  Scenario: Double submission
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name                  | ACME 1000 call |
      | contract_type         | option         |
      | side                  | long           |
      | option_type           | call           |
      | underlying_instrument | ACMEIND        |
      | strike                | 1000           |
      | lots                  | 1              |
      | lot_size              | 75             |
      | premium               | 7500           |
      | settlement            | physical       |
      | trade_date            | 12 Oct 2026    |
      | expiry_date           | 26 Nov 2026    |
      | exchange              | NSE            |
    When the event "type=exercise;date=13 Oct 2026" is recorded on "ACME 1000 call" with key "form-123"
    And the event "type=exercise;date=13 Oct 2026" is recorded on "ACME 1000 call" with key "form-123"
    Then "ACME 1000 call" should have 1 "exercise" event
    And "Horizon Evergreen Fund" should have 1 holding created by exercise

  # E52 — Edge case: a USD contract valued at $2,000 is ₹1,70,000 in Horizon (Market USD→INR 85.00)
  Scenario: Contract in a foreign currency
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name              | USD option OTC |
      | contract_type     | option         |
      | side              | long           |
      | option_type       | call           |
      | underlying_type   | index          |
      | underlying_name   | SPX            |
      | strike            | 5000           |
      | lots              | 1              |
      | lot_size          | 1              |
      | currency          | USD            |
      | trade_date        | 12 Oct 2026    |
      | expiry_date       | 26 Nov 2026    |
      | listed            | false          |
      | counterparty_name | Bank Y         |
    And the event "type=valuation;date=30 Oct 2026;value=2000;provider=Bank Y;source=upload" is recorded on "USD option OTC"
    Then the value of "USD option OTC" in its fund on "30 Oct 2026" should be "170000"

  # E53 — Edge case: exercising a long ACMEIND put (1 × 75, strike ₹1,300) sells 75 shares at ₹1,300 with lot attribution
  Scenario: Put exercised physically
    Given "Horizon Evergreen Fund" holds 100 "ACMEIND" (INR) bought at "1000" each on "01 Apr 2026"
    And "Horizon Evergreen Fund" has a derivative contract:
      | name                  | ACME 1300 put |
      | contract_type         | option        |
      | side                  | long          |
      | option_type           | put           |
      | underlying_instrument | ACMEIND       |
      | strike                | 1300          |
      | lots                  | 1             |
      | lot_size              | 75            |
      | premium               | 3000          |
      | settlement            | physical      |
      | trade_date            | 12 Oct 2026   |
      | expiry_date           | 26 Nov 2026   |
      | exchange              | NSE           |
    When the event "type=exercise;date=13 Oct 2026" is recorded on "ACME 1300 put"
    Then the event should be recorded
    And "Horizon Evergreen Fund" should have sold "75" "ACMEIND" at "1300" each from the exercise

  # E54 — Edge case: a cash-settled index option exercised for ₹12,000 posts a ₹12,000 settlement and creates no holding
  Scenario: Cash-settled index option
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name          | Nifty 24500 call |
      | contract_type | option           |
      | side          | long             |
      | option_type   | call             |
      | underlying_type | index          |
      | underlying_name | NIFTY          |
      | strike        | 24500            |
      | lots          | 1                |
      | lot_size      | 75               |
      | premium       | 5000             |
      | trade_date    | 12 Oct 2026      |
      | expiry_date   | 26 Nov 2026      |
      | exchange      | NSE              |
    When the event "type=exercise;date=26 Nov 2026;amount=12000" is recorded on "Nifty 24500 call"
    Then the ledger should have a "Derivative Settlement" entry of "12000" for "Nifty 24500 call"
    And "Horizon Evergreen Fund" should have 0 holdings created by exercise

  # E55 — Edge case: a contract marked as hedging share class "Class B" shows "Hedges: Class B"
  Scenario: Contract hedges a share class
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name              | Class B hedge |
      | contract_type     | fx_forward    |
      | side              | short         |
      | underlying_type   | currency_pair |
      | underlying_name   | USD/INR       |
      | notional          | 50000         |
      | forward_rate      | 84.50         |
      | trade_date        | 12 Oct 2026   |
      | expiry_date       | 29 Jan 2027   |
      | listed            | false         |
      | counterparty_name | Bank X        |
      | hedge_unit_type   | Class B       |
    And I am at the login page
    When I fill and submit the login page
    And I open the contract "Class B hedge"
    Then I should see "Class B"

  # E57 — Edge case: the put expiring 26 Nov is reminded once, on 19 Nov (5 business days before); the 20 Nov run sends nothing
  Scenario: Reminder sent once
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name          | Nifty 24000 put |
      | contract_type | option          |
      | side          | long            |
      | option_type   | put             |
      | underlying_type | index         |
      | underlying_name | NIFTY         |
      | strike        | 24000           |
      | lots          | 1               |
      | lot_size      | 75              |
      | premium       | 40000           |
      | trade_date    | 12 Oct 2026     |
      | expiry_date   | 26 Nov 2026     |
      | exchange      | NSE             |
    When the expiry reminder job runs on "18 Nov 2026"
    Then 0 emails should mention "Nifty 24000 put expires on"
    When the expiry reminder job runs on "19 Nov 2026"
    And the expiry reminder job runs on "20 Nov 2026"
    Then 1 email should mention "Nifty 24000 put expires on Nov 26, 2026"

  # X16 — Error case: Bridge (derivatives off) has no Derivatives page; a direct request is refused
  Scenario: Fund without the feature
    Then the derivatives of "Bridge Hybrid Fund" should be refused to "the user"

  # X17 — Error case: with the entity's Derivatives feature off, the fund's derivatives are refused even with the fund flag set
  Scenario: Entity feature off
    When support turns off the entity derivatives feature
    Then the derivatives of "Horizon Evergreen Fund" should be refused to "the user"

  # X18 — Error case: a user of another entity is refused a contract
  Scenario: Other entity's user
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name              | FX fwd USD    |
      | contract_type     | fx_forward    |
      | side              | short         |
      | underlying_type   | currency_pair |
      | underlying_name   | USD/INR       |
      | notional          | 100000        |
      | forward_rate      | 84.00         |
      | trade_date        | 12 Oct 2026   |
      | expiry_date       | 29 Jan 2027   |
      | listed            | false         |
      | counterparty_name | Bank X        |
    Then a user of another entity should be refused the contract "FX fwd USD"

  # X19 — Error case: an option without a strike is refused
  Scenario: Option without strike
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name          | No strike put |
      | contract_type | option        |
      | side          | long          |
      | option_type   | put           |
      | underlying_type | index       |
      | underlying_name | NIFTY       |
      | lots          | 1             |
      | lot_size      | 75            |
      | trade_date    | 12 Oct 2026   |
      | expiry_date   | 26 Nov 2026   |
      | exchange      | NSE           |
    Then the contract should be refused with "Strike can't be blank"

  # X20 — Error case: an OTC contract without a counterparty is refused
  Scenario: OTC contract without counterparty
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name            | No CP forward |
      | contract_type   | fx_forward    |
      | side            | short         |
      | underlying_type | currency_pair |
      | underlying_name | USD/INR       |
      | notional        | 100000        |
      | forward_rate    | 84.00         |
      | trade_date      | 12 Oct 2026   |
      | expiry_date     | 29 Jan 2027   |
      | listed          | false         |
    Then the contract should be refused with "Counterparty can't be blank"

  # X21 — Error case: a valuation dated 11 Oct on a contract traded 12 Oct is refused
  Scenario: Event before trade date
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name              | FX fwd USD    |
      | contract_type     | fx_forward    |
      | side              | short         |
      | underlying_type   | currency_pair |
      | underlying_name   | USD/INR       |
      | notional          | 100000        |
      | forward_rate      | 84.00         |
      | trade_date        | 12 Oct 2026   |
      | expiry_date       | 29 Jan 2027   |
      | listed            | false         |
      | counterparty_name | Bank X        |
    When the event "type=valuation;date=11 Oct 2026;value=-1000" is recorded on "FX fwd USD"
    Then the event should be refused with "must be on or after the trade date"

  # X22 — Error case: an event on an expired (closed) contract is refused
  Scenario: Event on a closed contract
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name          | Nifty 24000 put |
      | contract_type | option          |
      | side          | long            |
      | option_type   | put             |
      | underlying_type | index         |
      | underlying_name | NIFTY         |
      | strike        | 24000           |
      | lots          | 1               |
      | lot_size      | 75              |
      | premium       | 40000           |
      | trade_date    | 12 Oct 2026     |
      | expiry_date   | 26 Nov 2026     |
      | exchange      | NSE             |
    And the event "type=expiry;date=26 Nov 2026" is recorded on "Nifty 24000 put"
    When the event "type=valuation;date=27 Nov 2026;value=0" is recorded on "Nifty 24000 put"
    Then the event should be refused with "Contract is closed"

  # X23 — Error case: closing 2 lots when 1 is open is refused
  Scenario: Close more lots than open
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name          | Nifty put 1 lot |
      | contract_type | option          |
      | side          | long            |
      | option_type   | put             |
      | underlying_type | index         |
      | underlying_name | NIFTY         |
      | strike        | 24000           |
      | lots          | 1               |
      | lot_size      | 75              |
      | premium       | 40000           |
      | trade_date    | 12 Oct 2026     |
      | expiry_date   | 26 Nov 2026     |
      | exchange      | NSE             |
    When the event "type=close_out;date=20 Oct 2026;lots=2;amount=20000" is recorded on "Nifty put 1 lot"
    Then the event should be refused with "Only 1 lots open"

  # X24 — Error case: exercising a physical put on 75 shares when the fund holds 50 is refused
  Scenario: Put exercised without enough shares
    Given "Horizon Evergreen Fund" holds 50 "ACMEIND" (INR) bought at "1000" each on "01 Apr 2026"
    And "Horizon Evergreen Fund" has a derivative contract:
      | name                  | ACME 1300 put |
      | contract_type         | option        |
      | side                  | long          |
      | option_type           | put           |
      | underlying_instrument | ACMEIND       |
      | strike                | 1300          |
      | lots                  | 1             |
      | lot_size              | 75            |
      | premium               | 3000          |
      | settlement            | physical      |
      | trade_date            | 12 Oct 2026   |
      | expiry_date           | 26 Nov 2026   |
      | exchange              | NSE           |
    When the event "type=exercise;date=13 Oct 2026" is recorded on "ACME 1300 put"
    Then the event should be refused with "Fund holds only 50 shares of ACMEIND"

  # X25 — Error case: an employee without update access to the fund cannot record events
  Scenario: Read-only user records event
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name              | FX fwd USD    |
      | contract_type     | fx_forward    |
      | side              | short         |
      | underlying_type   | currency_pair |
      | underlying_name   | USD/INR       |
      | notional          | 100000        |
      | forward_rate      | 84.00         |
      | trade_date        | 12 Oct 2026   |
      | expiry_date       | 29 Jan 2027   |
      | listed            | false         |
      | counterparty_name | Bank X        |
    And an employee "ravi@example.com" of the entity without fund access
    Then recording events on "FX fwd USD" should be refused to "ravi@example.com"
