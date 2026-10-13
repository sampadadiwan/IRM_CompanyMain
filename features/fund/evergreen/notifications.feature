Feature: Evergreen notifications — investor emails, team alerts, switches, send-once, copy from fund
  Who hears about what, and when: reminders and updates to investors (customisable per fund), in-app
  and email alerts to the fund's team, per-fund switches with defaults, one send per record, and
  copying investor-email templates from another evergreen fund.
  Worked examples H40–H56, E52–E63, E65, X21–X25 — openspec/changes/open-ended-funds/design.md#worked-examples
  (E64 is in regression.feature)

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the user is tagged "FundOps"
    And the entity has evergreen funds switched on
    And today is "2026-09-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And the fund setting has "payment_instructions=Pay to HDFC Bank A/c 50200012345, IFSC HDFC0000001"
    And "A Ltd" is an investor of the fund with a portal user
    And "B LLP" is an investor of the fund with "2" portal users
    And "C HUF" is an investor of the fund with a portal user
    And "P Family Trust" is an investor of the fund with a portal user
    And "Q Capital" is an investor of the fund with a portal user
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And "C HUF" holds "2000" units of class "A" in folio "F-044" issued "2025-09-01"
    And "Others" holds "79000" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"

  # H40 — Happy path: an unpaid pre-funded subscription gets a payment reminder two days before the cut-off, logged once.
  @rack_test
  Scenario: Payment reminder
    Given today is "2026-10-20"
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-10-20 09:00"
    And the email queue is cleared
    When the daily notification check runs on "2026-10-26"
    Then "Q Capital" should receive 1 email with subject "Alpha Long-Short Fund: Payment due before the cut-off"
    And the email "Alpha Long-Short Fund: Payment due before the cut-off" to "Q Capital" should contain "₹2,50,00,000.00"
    And the email "Alpha Long-Short Fund: Payment due before the cut-off" to "Q Capital" should contain "Oct 28, 2026"
    And the email "Alpha Long-Short Fund: Payment due before the cut-off" to "Q Capital" should contain "Pay to HDFC Bank A/c 50200012345, IFSC HDFC0000001"
    And there should be 1 "payment_reminder" notification log for the order of "Q Capital"

  # H41 — Happy path: an order with an unfinished journey step gets Action needed naming the step and that it will roll.
  @rack_test
  Scenario: Action needed names the step and its fate
    Given the fund setting has "order_journeys=subscriptions;unready_handling=roll"
    And "R Trust" is an investor of the fund with a portal user
    And "R Trust" has a verified KYC
    And today is "2026-10-20"
    And "R Trust" has placed a "subscription" order "amount=25000000" received "2026-10-20 09:00"
    And the order of "R Trust" should be waiting on "Collect signed subscription form"
    And the email queue is cleared
    When the daily notification check runs on "2026-10-26"
    Then "R Trust" should receive 1 email with subject "Alpha Long-Short Fund: Action needed on your request"
    And the email "Alpha Long-Short Fund: Action needed on your request" to "R Trust" should contain "Collect signed subscription form"
    And the email "Alpha Long-Short Fund: Action needed on your request" to "R Trust" should contain "Oct 28, 2026"
    And the email "Alpha Long-Short Fund: Action needed on your request" to "R Trust" should contain "will move to the next subscription date"

  # H42 — Happy path: a verified subscription payment sends Payment received with the amount and dealing date.
  @rack_test
  Scenario: Payment received
    Given today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And today is "2026-10-23"
    And the email queue is cleared
    When "P Family Trust" has paid the subscription on "2026-10-23"
    Then "P Family Trust" should receive 1 email with subject "Alpha Long-Short Fund: Payment received"
    And the email "Alpha Long-Short Fund: Payment received" to "P Family Trust" should contain "₹5,00,00,000.00"
    And the email "Alpha Long-Short Fund: Payment received" to "P Family Trust" should contain "Nov 02, 2026"

  # H43 — Happy path: on the day a lot's lock-up ends, the folio's investor gets Units now free to redeem.
  @rack_test
  Scenario: Units unlocked
    Given class "A" of the fund has "lock_up_months=12;lock_up_type=hard"
    And the fund notification "units_unlocked" is switched "on"
    And "P Family Trust" holds "4892.3679" units of class "A" in folio "F-101" issued "2026-11-02"
    And the email queue is cleared
    When the daily notification check runs on "2027-11-02"
    Then "P Family Trust" should receive 1 email with subject "Alpha Long-Short Fund: Units now free to redeem"
    And the email "Alpha Long-Short Fund: Units now free to redeem" to "P Family Trust" should contain "4,892.3679 units"
    And the email "Alpha Long-Short Fund: Units now free to redeem" to "P Family Trust" should contain "F-101"

  # H44 — Happy path: approving a NAV with NAV update on emails each folio its NAV per unit and holding value.
  @rack_test
  Scenario: NAV update
    Given the fund notification "nav_update" is switched "on"
    And "P Family Trust" holds "4892.3679" units of class "A" in folio "F-101" issued "2026-11-02"
    And there is an approver "Ravi" in the entity
    And today is "2026-12-02"
    And a draft NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "104892.3679"
    And the email queue is cleared
    When "Ravi" approves the class "A" NAV for "2026-11-30"
    Then "P Family Trust" should receive 1 email with subject "Alpha Long-Short Fund: NAV update"
    And the email "Alpha Long-Short Fund: NAV update" to "P Family Trust" should contain "10,160.94"
    And the email "Alpha Long-Short Fund: NAV update" to "P Family Trust" should contain "Nov 30, 2026"
    And the email "Alpha Long-Short Fund: NAV update" to "P Family Trust" should contain "F-101"
    And the email "Alpha Long-Short Fund: NAV update" to "P Family Trust" should contain "4,892.3679"
    And the email "Alpha Long-Short Fund: NAV update" to "P Family Trust" should contain "₹4,97,11,056.69"

  # H45 — Happy path: a portal order alerts the investor's relationship manager and not Fund ops.
  @rack_test
  Scenario: New order goes to the relationship manager
    Given there is an employee "Karan"
    And "P Family Trust" is managed by "Karan"
    And today is "2026-10-20"
    And the email queue is cleared
    When "P Family Trust" places a "subscription" order "amount=50000000" in the portal received "2026-10-20 09:00"
    Then "Karan" should get the alert "New subscription: P Family Trust ₹5,00,00,000.00 for Nov 02, 2026"
    And "Asha" should not get any alert containing "New subscription"

  # H46 — Happy path: a drafted NAV alerts the other approvers, never the preparer.
  @rack_test
  Scenario: NAV awaiting approval skips the preparer
    Given the user has role "approver"
    And there is an approver "Ravi" in the entity
    And the portfolio fair value is "102,20,00,000"
    And today is "2026-11-01"
    And the email queue is cleared
    When "Asha" drafts the NAV for "2026-10-31"
    Then "Ravi" should get the alert "NAV awaiting approval: Class A, Oct 31, 2026"
    And "Asha" should not get any alert containing "NAV awaiting approval"

  # H47 — Happy path: an approved NAV alerts the preparer once even though she is also Fund ops.
  @rack_test
  Scenario: NAV approved goes to the preparer and Fund ops once
    Given the user has role "approver"
    And there is an approver "Ravi" in the entity
    And the portfolio fair value is "102,20,00,000"
    And today is "2026-11-01"
    And "Asha" drafts the NAV for "2026-10-31"
    And the email queue is cleared
    When "Ravi" approves the class "A" NAV for "2026-10-31"
    Then "Asha" should get the alert "NAV approved: Class A, Oct 31, 2026, ₹10,220.00" once

  # H48 — Happy path: the day after a cut-off Fund ops get one summary of subscriptions, unpaid, not ready and redemptions.
  @rack_test
  Scenario: Cut-off summary
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=25000000" received "2026-09-18 09:15"
    And "C HUF" has placed a "redemption" order "folio=F-044;amount=10000000" received "2026-09-19 11:30"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-10-20 09:30"
    And today is "2026-10-25"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And the email queue is cleared
    When the daily notification check runs on "2026-10-29"
    Then "Asha" should get the alert "Cut-off passed: Nov 02, 2026" once
    And the alert "Cut-off passed: Nov 02, 2026" to "Asha" should list "2 subscriptions (₹7,50,00,000.00)"
    And the alert "Cut-off passed: Nov 02, 2026" to "Asha" should list "1 unpaid (Q Capital ₹2,50,00,000.00 — will roll)"
    And the alert "Cut-off passed: Nov 02, 2026" to "Asha" should list "0 not ready"
    And the alert "Cut-off passed: Nov 02, 2026" to "Asha" should list "3 redemptions (₹6,50,00,000.00)"

  # H49 — Happy path: approving the NAV after the cut-off tells Fund ops and approvers the dealing date is ready to confirm.
  @rack_test
  Scenario: Ready to confirm
    Given there is an approver "Ravi" in the entity
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And today is "2026-10-25"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And a draft NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the email queue is cleared
    When "Ravi" approves the class "A" NAV for "2026-10-31"
    Then "Asha" should get the alert "Nov 02, 2026 is ready to confirm" once
    And "Ravi" should get the alert "Nov 02, 2026 is ready to confirm" once
    And the alert "Nov 02, 2026 is ready to confirm" to "Ravi" should link to the dealing date "2026-11-02"

  # H50 — Happy path: confirming with a gate tells Compliance and Fund ops what was paid and carried.
  @rack_test
  Scenario: Gate applied
    Given the fund setting has "gate_pct=5;gate_method=fifo"
    And there is an employee "Meera" tagged "Compliance"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=25000000" received "2026-09-18 09:15"
    And "C HUF" has placed a "redemption" order "folio=F-044;amount=10000000" received "2026-09-19 11:30"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the email queue is cleared
    When the fund admin confirms dealing date "2026-11-02"
    Then "Meera" should get the alert "Gate applied on Nov 02, 2026: ₹5,11,00,000.00 paid, ₹1,39,00,000.00 carried to Dec 01, 2026" once
    And "Asha" should get the alert "Gate applied on Nov 02, 2026: ₹5,11,00,000.00 paid, ₹1,39,00,000.00 carried to Dec 01, 2026" once

  # H51 — Happy path: a redemption above the threshold alerts Compliance and the relationship manager.
  @rack_test
  Scenario: Large redemption
    Given there is an employee "Karan"
    And there is an employee "Meera" tagged "Compliance"
    And "D Partners" is an investor of the fund with a portal user
    And "D Partners" holds "30000" units of class "A" in folio "F-050" issued "2025-09-01"
    And "D Partners" is managed by "Karan"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-10"
    And the email queue is cleared
    When "D Partners" has placed a "redemption" order "folio=F-050;amount=25000000" received "2026-11-10 10:00"
    Then "Meera" should get the alert "Large redemption: D Partners ₹2,50,00,000.00 (2.45 % of Class A NAV)"
    And "Karan" should get the alert "Large redemption: D Partners ₹2,50,00,000.00 (2.45 % of Class A NAV)"

  # H52 — Happy path: a redemption payment unpaid after its due date alerts Fund ops with the overdue line.
  @rack_test
  Scenario: Redemption payment overdue
    Given the fund setting has "gate_pct=5;gate_method=fifo"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=25000000" received "2026-09-18 09:15"
    And "C HUF" has placed a "redemption" order "folio=F-044;amount=10000000" received "2026-09-19 11:30"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    And the email queue is cleared
    When the daily notification check runs on "2026-11-17"
    Then "Asha" should get the alert "Settlement overdue on Nov 02, 2026" once
    And the alert "Settlement overdue on Nov 02, 2026" to "Asha" should list "A Ltd ₹3,00,00,000.00, due Nov 16, 2026"

  # H53 — Happy path: drafting a NAV while the management fee lags alerts Fund accounting.
  @rack_test
  Scenario: Fee accrual behind
    Given the user is tagged "FundOps,FundAccounting"
    And class "A" charges a management fee of "1.5"
    And folio "F-012" accrued a management fee of "12,51,805" on "2026-10-31"
    And the portfolio fair value is "102,20,00,000"
    And today is "2026-12-01"
    And the email queue is cleared
    When "Asha" drafts the NAV for "2026-11-30"
    Then "Asha" should get the alert "Management fee accrued only to Oct 31, 2026 — run the fee formula to Nov 30, 2026, then recalculate (it can't be approved until then)"

  # H54 — Happy path: the Notifications wizard step shows defaults; reminder days changed to 3 moves the reminder a day earlier.
  @rack_test
  Scenario: Notifications step in the wizard, then reminder days changed to 3
    Given today is "2026-10-20"
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-10-20 09:00"
    When I open the notifications step of the evergreen settings
    Then the notifications step should show every switch at its default with a tooltip and recipients
    And the reminder days should show "2" and the large redemption threshold "2"
    When I set the reminder days to "3"
    And I save the evergreen settings
    Then I should see "Settings saved"
    And the fund reminder days should be "3"
    And every notification switch of the fund should be at its default
    Given the email queue is cleared
    When the daily notification check runs on "2026-10-25"
    Then "Q Capital" should receive 1 email with subject "Alpha Long-Short Fund: Payment due before the cut-off"

  # H55 — Happy path: copying from another evergreen fund into a fund with no templates copies all three.
  @rack_test
  Scenario: Copy into a fund with none
    Given the evergreen fund "Gamma Income Fund" of the entity has evergreen notifications for "payment_reminder,contract_note,gate_notice"
    And the fund should have no evergreen notifications
    When I open Copy from fund for the fund
    And I copy the notifications from "Gamma Income Fund"
    Then I should see "3 templates copied from Gamma Income Fund"
    And the fund should have the evergreen notifications of "Gamma Income Fund" for "payment_reminder,contract_note,gate_notice"

  # H56 — Happy path: a fund's Evergreen custom notification replaces the reminder's subject and body with placeholders filled.
  @rack_test
  Scenario: Customised wording
    Given the fund has an evergreen notification for "payment_reminder" with subject "Reminder: fund your {{fund_name}} subscription" and body "Dear {{investor_name}}, please fund your subscription before the cut-off."
    And today is "2026-10-20"
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-10-20 09:00"
    And the email queue is cleared
    When the daily notification check runs on "2026-10-26"
    Then "Q Capital" should receive 1 email with subject "Reminder: fund your Alpha Long-Short Fund subscription"
    And the email "Reminder: fund your Alpha Long-Short Fund subscription" to "Q Capital" should contain "Dear Q Capital, please fund your subscription before the cut-off."

  # E52 — Edge case: an advisor not allowed to see the order gets no acknowledgement until granted access to it.
  @rack_test
  Scenario: Advisor without access to the order, then approved to see it
    Given "B LLP" has an advisor "Vikram" from "Vikram Advisors"
    And today is "2026-10-20"
    And the email queue is cleared
    When "B LLP" has placed a "redemption" order "folio=F-031;amount=10000000" received "2026-10-20 09:00"
    Then "B LLP" should receive 1 email with subject "Alpha Long-Short Fund: Redemption request received"
    And "Vikram" should receive no email with subject "Alpha Long-Short Fund: Redemption request received"
    Given the advisor "Vikram" is allowed to see the orders of "B LLP"
    And the email queue is cleared
    When "B LLP" has placed a "redemption" order "folio=F-031;amount=5000000" received "2026-10-20 10:00"
    Then "B LLP" should receive 1 email with subject "Alpha Long-Short Fund: Redemption request received"
    And "Vikram" should receive 1 email with subject "Alpha Long-Short Fund: Redemption request received"

  # E53 — Edge case: an investor with no relationship manager sends the new-order alert to Fund ops.
  @rack_test
  Scenario: No relationship manager falls back to Fund ops
    Given today is "2026-10-20"
    And the email queue is cleared
    When "Q Capital" places a "subscription" order "amount=25000000" in the portal received "2026-10-20 09:00"
    Then "Asha" should get the alert "New subscription: Q Capital ₹2,50,00,000.00 for Nov 02, 2026"

  # E54 — Edge case: the payment reminder switched off sends nothing and logs nothing.
  @rack_test
  Scenario: Switched off
    Given the fund notification "payment_reminder" is switched "off"
    And today is "2026-10-20"
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-10-20 09:00"
    And the email queue is cleared
    When the daily notification check runs on "2026-10-26"
    Then "Q Capital" should receive no email with subject "Alpha Long-Short Fund: Payment due before the cut-off"
    And there should be 0 "payment_reminder" notification logs for the order of "Q Capital"

  # E55 — Edge case: switches never saved, so default-off NAV update sends nothing while default-on NAV approved still goes.
  @rack_test
  Scenario: Default-off notification
    Given the fund notifications were never saved
    And "P Family Trust" holds "4892.3679" units of class "A" in folio "F-101" issued "2026-10-01"
    And there is an approver "Ravi" in the entity
    And a draft NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "104892.3679"
    And today is "2026-11-02"
    And the email queue is cleared
    When "Ravi" approves the class "A" NAV for "2026-10-31"
    Then "P Family Trust" should receive no email with subject "Alpha Long-Short Fund: NAV update"
    And "Asha" should get the alert "NAV approved: Class A, Oct 31, 2026, ₹10,220.00"

  # E56 — Edge case: the daily check run twice the same day sends one reminder and one log row.
  @rack_test
  Scenario: Daily check run twice
    Given today is "2026-10-20"
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-10-20 09:00"
    And the email queue is cleared
    When the daily notification check runs on "2026-10-26"
    And the daily notification check runs again
    Then "Q Capital" should receive 1 email with subject "Alpha Long-Short Fund: Payment due before the cut-off"
    And there should be 1 "payment_reminder" notification log for the order of "Q Capital"

  # E57 — Edge case: copying skips an email the fund already customises and leaves it unchanged.
  @rack_test
  Scenario: Copy skips existing customisations
    Given the evergreen fund "Gamma Income Fund" of the entity has evergreen notifications for "payment_reminder,contract_note,gate_notice"
    And the fund has an evergreen notification for "contract_note" with subject "Alpha contract note" and body "Alpha wording for the contract note."
    When I open Copy from fund for the fund
    And I copy the notifications from "Gamma Income Fund"
    Then I should see "2 templates copied from Gamma Income Fund, 1 skipped (already set here)"
    And the evergreen notification "contract_note" of the fund should have subject "Alpha contract note"
    And the fund should have the evergreen notifications of "Gamma Income Fund" for "payment_reminder,gate_notice"

  # E58 — Edge case: the preparer is the only approver, so nobody gets NAV awaiting approval.
  @rack_test
  Scenario: The preparer is the only approver
    Given the user has role "approver"
    And there is an employee "Ravi"
    And the portfolio fair value is "102,20,00,000"
    And today is "2026-11-01"
    And the email queue is cleared
    When "Asha" drafts the NAV for "2026-10-31"
    Then nobody should get an alert containing "NAV awaiting approval"

  # E59 — Edge case: a Compliance-tagged user removed from the fund's access list gets no gate alert.
  @rack_test
  Scenario: Tagged user who cannot see the fund
    Given the fund setting has "gate_pct=5;gate_method=fifo"
    And there is an employee "Meera" tagged "Compliance" with access to the fund through its access list
    And "Meera" is removed from the fund access list
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=25000000" received "2026-09-18 09:15"
    And "C HUF" has placed a "redemption" order "folio=F-044;amount=10000000" received "2026-09-19 11:30"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the email queue is cleared
    When the fund admin confirms dealing date "2026-11-02"
    Then "Meera" should not get any alert containing "Gate applied"
    And "Asha" should get the alert "Gate applied on Nov 02, 2026: ₹5,11,00,000.00 paid, ₹1,39,00,000.00 carried to Dec 01, 2026" once

  # E60 — Edge case: a redemption below the large-redemption threshold sends no alert.
  @rack_test
  Scenario: Redemption below the threshold
    Given there is an employee "Meera" tagged "Compliance"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-10"
    And the email queue is cleared
    When "C HUF" has placed a "redemption" order "folio=F-044;amount=10000000" received "2026-11-10 10:00"
    Then nobody should get an alert containing "Large redemption"

  # E61 — Edge case: pay-after-dealing money not in by its pay-by date is listed as settlement overdue.
  @rack_test
  Scenario: Pay-after money overdue
    Given the fund setting has "payment_timing=after;pay_after_days=7"
    And today is "2026-11-10"
    And "Q Capital" has placed a "subscription" order "amount=50000000" received "2026-11-10 09:00"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,000" and units "100000"
    And today is "2026-12-01"
    And the fund admin confirms dealing date "2026-12-01"
    And the email queue is cleared
    When the daily notification check runs on "2026-12-09"
    Then "Asha" should get the alert "Settlement overdue on Dec 01, 2026" once
    And the alert "Settlement overdue on Dec 01, 2026" to "Asha" should list "Q Capital ₹5,00,00,000.00, pay by Dec 08, 2026"

  # E62 — Edge case: with unready handling Cancel, Action needed says the request will be cancelled.
  @rack_test
  Scenario: Action needed when unready orders are cancelled
    Given the fund setting has "order_journeys=subscriptions;unready_handling=cancel"
    And "R Trust" is an investor of the fund with a portal user
    And "R Trust" has a verified KYC
    And today is "2026-10-20"
    And "R Trust" has placed a "subscription" order "amount=25000000" received "2026-10-20 09:00"
    And the email queue is cleared
    When the daily notification check runs on "2026-10-26"
    Then "R Trust" should receive 1 email with subject "Alpha Long-Short Fund: Action needed on your request"
    And the email "Alpha Long-Short Fund: Action needed on your request" to "R Trust" should contain "will be cancelled"
    And the email "Alpha Long-Short Fund: Action needed on your request" to "R Trust" should contain "Oct 28, 2026"

  # E63 — Edge case: a fully paid subscription gets no payment reminder while the unpaid one does.
  @rack_test
  Scenario: No reminder when paid
    Given today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-10-20 09:30"
    And today is "2026-10-25"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And the email queue is cleared
    When the daily notification check runs on "2026-10-26"
    Then "P Family Trust" should receive no email with subject "Alpha Long-Short Fund: Payment due before the cut-off"
    And "Q Capital" should receive 1 email with subject "Alpha Long-Short Fund: Payment due before the cut-off"

  # E65 — Edge case: a saved switch set missing payment_received uses its default on, and re-saving the payment sends nothing again.
  @rack_test
  Scenario: Missing key uses the default; the replayed event sends nothing
    Given the fund notifications are saved as '{"payment_reminder": false}'
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And today is "2026-10-23"
    And the email queue is cleared
    When "P Family Trust" has paid the subscription on "2026-10-23"
    Then "P Family Trust" should receive 1 email with subject "Alpha Long-Short Fund: Payment received"
    When the subscription payment of "P Family Trust" is saved again with a corrected reference
    Then "P Family Trust" should receive 1 email with subject "Alpha Long-Short Fund: Payment received"

  # X21 — Error case: reminder days 0 is refused and the stored value stays 2.
  @rack_test
  Scenario: Invalid reminder days
    When I open the notifications step of the evergreen settings
    And I set the reminder days to "0"
    And I save the evergreen settings
    Then I should see "Reminder days must be"
    And the fund reminder days should be "2"

  # X22 — Error case: a large-redemption threshold of 0 or 120 is refused and the stored value stays 2.
  @rack_test
  Scenario: Invalid large-redemption threshold
    When I open the notifications step of the evergreen settings
    And I set the large redemption threshold to "0"
    And I save the evergreen settings
    Then I should see "Large redemption threshold must be above 0 and at most 100"
    And the fund large redemption threshold should be "2"
    When I open the notifications step of the evergreen settings
    And I set the large redemption threshold to "120"
    And I save the evergreen settings
    Then I should see "Large redemption threshold must be above 0 and at most 100"
    And the fund large redemption threshold should be "2"

  # X23 — Error case: no other evergreen fund has templates, so Copy from fund says there is nothing to copy.
  Scenario: Nothing to copy from
    Given there is another evergreen fund "Gamma Income Fund"
    When I open Copy from fund for the fund
    Then I should see "No other evergreen fund of this entity has notification templates yet."
    And the fund should have no evergreen notifications

  # X24 — Error case: an investor user and another entity's user cannot copy templates or switch notifications by direct request.
  @rack_test
  Scenario: Copy or switch without rights is refused
    Given the evergreen fund "Gamma Income Fund" of the entity has evergreen notifications for "payment_reminder,contract_note"
    And there is a user "Gary" of another entity "Gamma Advisors"
    When "Q Capital" tries to copy the notifications from "Gamma Income Fund" to the fund
    And "Q Capital" tries to switch the fund notification "payment_reminder" off
    And "Gary" tries to copy the notifications from "Gamma Income Fund" to the fund
    And "Gary" tries to switch the fund notification "payment_reminder" off
    Then the fund should have no evergreen notifications
    And the fund notification "payment_reminder" should still be "on"

  # X25 — Error case: one fund's daily check raising an error is reported and the other funds still get their reminders.
  @rack_test
  Scenario: A daily check error on one fund does not stop the others
    Given there is another evergreen fund "Gamma Income Fund"
    And the daily check of "Gamma Income Fund" raises an error
    And today is "2026-10-20"
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-10-20 09:00"
    And the email queue is cleared
    When the daily notification check runs on "2026-10-26"
    Then "Q Capital" should receive 1 email with subject "Alpha Long-Short Fund: Payment due before the cut-off"
    And the error in the daily check of "Gamma Income Fund" should have been reported

  # E160 — Edge case: a redemption worth exactly the 2 % threshold (₹2,04,40,000 of a ₹102,20,00,000 class NAV) still raises the large-redemption alert.
  @rack_test
  Scenario: A redemption exactly at the large-redemption threshold is alerted
    Given there is an employee "Meera" tagged "Compliance"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-10"
    And the email queue is cleared
    When "A Ltd" has placed a "redemption" order "folio=F-012;amount=20440000" received "2026-11-10 10:00"
    Then "Meera" should get the alert "Large redemption: A Ltd ₹2,04,40,000.00 (2.0 % of Class A NAV)" once
    And "Asha" should get the alert "Large redemption: A Ltd ₹2,04,40,000.00 (2.0 % of Class A NAV)" once

  # E161 — Edge case: the daily check runs on two days inside the reminder window (26 and 27 Oct), and the payment reminder still goes out only once.
  @rack_test
  Scenario: The payment reminder is not repeated the next day
    Given today is "2026-10-20"
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-10-20 09:00"
    And the email queue is cleared
    When the daily notification check runs on "2026-10-26"
    And the daily notification check runs on "2026-10-27"
    Then "Q Capital" should receive 1 email with subject "Alpha Long-Short Fund: Payment due before the cut-off"
    And there should be 1 "payment_reminder" notification log for the order of "Q Capital"

  # E162 — Edge case: with the default 2 reminder days, the check on 25 Oct (3 days before the 28 Oct cut-off) sends no reminder yet.
  @rack_test
  Scenario: No reminder before the reminder day
    Given today is "2026-10-20"
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-10-20 09:00"
    And the email queue is cleared
    When the daily notification check runs on "2026-10-25"
    Then "Q Capital" should receive no email with subject "Alpha Long-Short Fund: Payment due before the cut-off"
    And there should be 0 "payment_reminder" notification logs for the order of "Q Capital"

  # E163 — Edge case: Asha is both an approver and tagged FundOps, so she is in both recipient groups yet gets "ready to confirm" only once.
  @rack_test
  Scenario: A user in two recipient roles gets one alert
    Given the user has role "approver"
    And there is an approver "Ravi" in the entity
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And today is "2026-10-25"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And a draft NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the email queue is cleared
    When "Ravi" approves the class "A" NAV for "2026-10-31"
    Then "Asha" should get the alert "Nov 02, 2026 is ready to confirm" once
    And "Ravi" should get the alert "Nov 02, 2026 is ready to confirm" once

  # E164 — Edge case: the investor's "Managed by" user belongs to another entity and cannot see the fund, so the new-order alert falls back to Fund ops.
  @rack_test
  Scenario: A relationship manager from another entity falls back to Fund ops
    Given "Q Capital" is managed by "Gary" of another entity "Gamma Advisors"
    And today is "2026-10-20"
    And the email queue is cleared
    When "Q Capital" places a "subscription" order "amount=25000000" in the portal received "2026-10-20 09:00"
    Then "Asha" should get the alert "New subscription: Q Capital ₹2,50,00,000.00 for Nov 02, 2026" once
    And "Gary" should not get any alert containing "New subscription"

  # E165 — Edge case: the investor's relationship manager has been deactivated, so the new-order alert goes to Fund ops instead.
  @rack_test
  Scenario: A deactivated relationship manager falls back to Fund ops
    Given there is an employee "Karan"
    And "Q Capital" is managed by "Karan"
    And the employee "Karan" is deactivated
    And today is "2026-10-20"
    And the email queue is cleared
    When "Q Capital" places a "subscription" order "amount=25000000" in the portal received "2026-10-20 09:00"
    Then "Asha" should get the alert "New subscription: Q Capital ₹2,50,00,000.00 for Nov 02, 2026" once
    And "Karan" should not get any alert containing "New subscription"

  # E166 — Edge case: the New order team alert is switched off, so no one is alerted, while the always-on investor acknowledgement is still sent.
  @rack_test
  Scenario: A team alert switched off sends nothing
    Given the fund notification "new_order" is switched "off"
    And there is an employee "Karan"
    And "P Family Trust" is managed by "Karan"
    And today is "2026-10-20"
    And the email queue is cleared
    When "P Family Trust" places a "subscription" order "amount=50000000" in the portal received "2026-10-20 09:00"
    Then nobody should get an alert containing "New subscription"
    And "P Family Trust" should receive 1 email with subject "Alpha Long-Short Fund: Subscription received"

  # E167 — Edge case: an overdue redemption payment is alerted on 17 Nov, not again on 20 Nov, and again a week later on 24 Nov.
  @rack_test
  Scenario: Settlement overdue repeats weekly, not daily
    Given the fund setting has "gate_pct=5;gate_method=fifo"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=25000000" received "2026-09-18 09:15"
    And "C HUF" has placed a "redemption" order "folio=F-044;amount=10000000" received "2026-09-19 11:30"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    And the email queue is cleared
    When the daily notification check runs on "2026-11-17"
    And the daily notification check runs on "2026-11-20"
    Then "Asha" should get the alert "Settlement overdue on Nov 02, 2026" once
    When the daily notification check runs on "2026-11-24"
    Then "Asha" should get the alert "Settlement overdue on Nov 02, 2026" 2 times

  # E168 — Edge case: with a 1-month lock-up, lots issued on 30 and 31 Oct both unlock on 30 Nov (month end), each folio is told once, and a re-run sends nothing more.
  @rack_test
  Scenario: Units unlocked at a month end, sent once
    Given class "A" of the fund has "lock_up_months=1;lock_up_type=hard"
    And the fund notification "units_unlocked" is switched "on"
    And "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2026-10-31"
    And "Q Capital" holds "500" units of class "A" in folio "F-102" issued "2026-10-30"
    And the email queue is cleared
    When the daily notification check runs on "2026-11-30"
    And the daily notification check runs again
    Then "P Family Trust" should receive 1 email with subject "Alpha Long-Short Fund: Units now free to redeem"
    And the email "Alpha Long-Short Fund: Units now free to redeem" to "P Family Trust" should contain "1,000.0000 units"
    And the email "Alpha Long-Short Fund: Units now free to redeem" to "P Family Trust" should contain "F-101"
    And "Q Capital" should receive 1 email with subject "Alpha Long-Short Fund: Units now free to redeem"
    And the email "Alpha Long-Short Fund: Units now free to redeem" to "Q Capital" should contain "500.0000 units"
    And the email "Alpha Long-Short Fund: Units now free to redeem" to "Q Capital" should contain "F-102"
    And "C HUF" should receive no email with subject "Alpha Long-Short Fund: Units now free to redeem"

  # E169 — Edge case: an investor with no portal users has an unpaid subscription; the daily check sends it nothing and still reminds the other investor.
  @rack_test
  Scenario: An investor without portal users does not stop the reminders
    Given "Others" has no portal users
    And today is "2026-10-20"
    And "Others" has placed a "subscription" order "amount=10000000" received "2026-10-20 09:00"
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-10-20 09:30"
    And the email queue is cleared
    When the daily notification check runs on "2026-10-26"
    Then "Q Capital" should receive 1 email with subject "Alpha Long-Short Fund: Payment due before the cut-off"
    And exactly 1 email with subject "Alpha Long-Short Fund: Payment due before the cut-off" should have been sent

  # E170 — Edge case: a custom payment reminder uses amount, date and payment-instruction placeholders in subject and body, and each is filled in email format.
  @rack_test
  Scenario: Custom wording fills money, date and instruction placeholders
    Given the fund has an evergreen notification for "payment_reminder" with subject "{{fund_name}}: pay {{requested_amount}} by {{cutoff_date}}" and body "Dear {{investor_name}}, your {{request_type}} for the {{dealing_date}} dealing date is unpaid. {{payment_instructions}}"
    And today is "2026-10-20"
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-10-20 09:00"
    And the email queue is cleared
    When the daily notification check runs on "2026-10-26"
    Then "Q Capital" should receive 1 email with subject "Alpha Long-Short Fund: pay ₹2,50,00,000.00 by Oct 28, 2026"
    And the email "Alpha Long-Short Fund: pay ₹2,50,00,000.00 by Oct 28, 2026" to "Q Capital" should contain "Dear Q Capital, your Subscription for the Nov 02, 2026 dealing date is unpaid. Pay to HDFC Bank A/c 50200012345, IFSC HDFC0000001"

  # X100 — Error case: B LLP's advisor is on its access list but not allowed to see its folio, so the NAV update reaches only B LLP's own users.
  @rack_test
  Scenario: An advisor without access to the folio gets no NAV update
    Given the fund notification "nav_update" is switched "on"
    And "B LLP" has an advisor "Vikram" from "Vikram Advisors"
    And there is an approver "Ravi" in the entity
    And today is "2026-12-02"
    And a draft NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "100000"
    And the email queue is cleared
    When "Ravi" approves the class "A" NAV for "2026-11-30"
    Then "B LLP" should receive 1 email with subject "Alpha Long-Short Fund: NAV update"
    And the email "Alpha Long-Short Fund: NAV update" to "B LLP" should contain "7,000.0000"
    And the email "Alpha Long-Short Fund: NAV update" to "B LLP" should contain "₹7,11,26,580.00"
    And "Vikram" should receive no email with subject "Alpha Long-Short Fund: NAV update"

  # X101 — Error case: a direct copy request naming another entity's evergreen fund is refused and nothing is copied.
  @rack_test
  Scenario: Copy from another entity's fund is refused
    Given there is an evergreen fund "Delta Fund" of another entity "Delta Capital" with evergreen notifications for "payment_reminder,contract_note"
    When I try to copy the notifications from "Delta Fund" directly
    Then the copy should have been refused
    And the fund should have no evergreen notifications

  # X102 — Error case: a closed-ended fund of the same entity carrying Evergreen templates is not offered as a source, and a direct copy from it is refused.
  @rack_test
  Scenario: A closed-ended fund is not a copy source
    Given the closed-ended fund "Beta Growth Fund" of the entity has evergreen notifications for "payment_reminder"
    When I open Copy from fund for the fund
    Then I should see "No other evergreen fund of this entity has notification templates yet."
    When I try to copy the notifications from "Beta Growth Fund" directly
    Then the copy should have been refused
    And the fund should have no evergreen notifications

  # X103 — Error case: an employee who can update only Alpha is not offered Gamma Income Fund (which he cannot see), and a direct copy from it is refused.
  @rack_test
  Scenario: Copy offers only funds the user can see
    Given the evergreen fund "Gamma Income Fund" of the entity has evergreen notifications for "payment_reminder,contract_note,gate_notice"
    And there is an employee "Nikhil" who can update only the fund
    When the user "Nikhil" signs in
    And I open Copy from fund for the fund
    Then I should see "No other evergreen fund of this entity has notification templates yet."
    When I try to copy the notifications from "Gamma Income Fund" directly
    Then the copy should have been refused
    And the fund should have no evergreen notifications
