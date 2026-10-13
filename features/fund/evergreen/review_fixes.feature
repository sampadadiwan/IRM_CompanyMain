Feature: Evergreen review fixes and decisions (10 October 2026)
  Decisions 3 and 4 — docs/modules/funds/evergreen_design_decisions.md — and review fixes 1–10 from the
  evergreen FAQ verification. Each scenario names its worked example (H101+, E301+, X201+: numbered apart
  from the open-ended-funds design's H/E/X so parallel work can't collide).

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And today is "2026-09-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;notice_days=5;gate_pct=5;gate_method=fifo"
    And "A Ltd" is an investor of the fund with a portal user
    And "B LLP" is an investor of the fund with a portal user
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And "Others" holds "81000" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"

  # ---- Decision 3: Confirm only after the last deadline ----

  # H101 — Happy path: on 27 Sep both deadlines of the 1 Oct date (cut-off and Class A notice, 26 Sep 23:59) have passed, so it confirms.
  Scenario: A dealing date confirms once its last deadline has passed
    Given "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    And today is "2026-09-27"
    When the fund admin confirms dealing date "2026-10-01"
    Then the dealing date "2026-10-01" should be "confirmed"

  # E301 — Edge case: on 20 Sep the 26 Sep cut-off is still open, so Confirm is refused and names it.
  Scenario: Confirm is refused before the subscription cut-off
    Given "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    And today is "2026-09-20"
    When the fund admin tries to confirm dealing date "2026-10-01"
    Then the confirm should be refused with "Cut-off is 26 September 2026 — confirm after it"
    And the dealing date "2026-10-01" should be "open"

  # E302 — Edge case: Class A gives only 2 days' notice, so its deadline (29 Sep) is later than the cut-off (26 Sep) and is the one that blocks on 28 Sep.
  Scenario: A class whose notice ends after the cut-off blocks Confirm until then
    Given class "A" of the fund has "notice_days=2"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    And today is "2026-09-28"
    When the fund admin tries to confirm dealing date "2026-10-01"
    Then the confirm should be refused with "Redemption notice for Class A ends 29 September 2026 — confirm after it"

  # H102 — Happy path: the dealing date page shows Confirm disabled with the deadline beside it.
  @rack_test
  Scenario: The dealing date page names the deadline that blocks Confirm
    Given "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    And today is "2026-09-20"
    When I open the dealing date "2026-10-01"
    Then the confirm button should be disabled
    And I should see "Cut-off is 26 September 2026 — confirm after it"

  # E303 — Edge case: the Ready to confirm alert waits for the last deadline too — nothing on 20 Sep, sent on 27 Sep.
  Scenario: Ready to confirm is not sent while a deadline is open
    Given there is an employee "Ravi" tagged "FundOps"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    When the daily notification check runs on "2026-09-20"
    Then "Ravi" should not get any alert containing "ready to confirm"
    When the daily notification check runs on "2026-09-27"
    Then "Ravi" should get an alert containing "is ready to confirm"

  # ---- Decision 4 (option B): never two dealing dates at the same NAV ----

  # E304 — Edge case: 1 Oct was priced at the 31 Aug NAV; with no newer NAV, 2 Nov is refused instead of dealing at the same price.
  Scenario: A dealing date can't reuse the NAV its previous date priced at
    Given "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    And today is "2026-09-27"
    And the fund admin confirms dealing date "2026-10-01"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=500" received "2026-10-05 10:00"
    And today is "2026-10-30"
    When the fund admin tries to confirm dealing date "2026-11-02"
    Then the confirm should be refused with "Class A's 31 August 2026 NAV already priced 01 October 2026 — draft and approve a newer NAV first"

  # E322 — Edge case: 2 Nov's ready redemption can't be priced (the 31 Aug NAV already priced 1 Oct), but its tab still lists it as "Waiting for NAV" with that reason, so the tab count matches the dealing dates list.
  @rack_test
  Scenario: A redemption waiting for a NAV still shows on the dealing date
    Given "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    And today is "2026-09-27"
    And the fund admin confirms dealing date "2026-10-01"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=500" received "2026-10-05 10:00"
    And today is "2026-10-30"
    When I open the dealing date "2026-11-02"
    Then I should see "Redemptions (1)"
    And the redemption of "B LLP" should be waiting for a NAV with "Class A's 31 August 2026 NAV already priced 01 October 2026"

  # H103 — Happy path: once the 31 Oct NAV is approved, 2 Nov prices at it and confirms.
  Scenario: A newer approved NAV lets the next dealing date confirm
    Given "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    And today is "2026-09-27"
    And the fund admin confirms dealing date "2026-10-01"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=500" received "2026-10-05 10:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "99000"
    And today is "2026-11-01"
    When the fund admin confirms dealing date "2026-11-02"
    Then the dealing date "2026-11-02" should be "confirmed"

  # X201 — Error case recovered: undoing 1 Oct removes its fills, so the 31 Aug NAV is no longer "used" and 2 Nov may price at it.
  Scenario: Undoing the previous date frees its NAV
    Given "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    And today is "2026-09-27"
    And the fund admin confirms dealing date "2026-10-01"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=500" received "2026-10-05 10:00"
    And today is "2026-10-30"
    When the fund admin undoes dealing date "2026-10-01"
    Then the undo should succeed
    When the fund admin confirms dealing date "2026-11-02"
    Then the dealing date "2026-11-02" should be "confirmed"

  # ---- Review fix 2: a stale NAV can't be approved ----

  # E305 — Edge case: the ledger changes after the draft, so the draft is stale and approving it is refused.
  Scenario: A stale draft NAV can't be approved
    Given the user has role "approver"
    And the portfolio fair value is "95,00,00,000"
    And the fund ledger has "Cash In Hand" of "8,00,00,000" on "2026-09-15"
    And "Asha" drafts the NAV for "2026-09-15"
    When a portfolio input dated "2026-09-10" changes
    And I try to approve the class "A" NAV for "2026-09-15" directly
    Then the approval is refused with "Inputs changed since drafted — recalculate before approving"

  # E306 — Edge case: confirming a LATER dealing date doesn't make an earlier draft stale, so it can still be approved.
  Scenario: Dealing after the NAV date leaves the draft fresh
    Given the user has role "approver"
    And the portfolio fair value is "95,00,00,000"
    And the fund ledger has "Cash In Hand" of "8,00,00,000" on "2026-08-15"
    And "Asha" drafts the NAV for "2026-08-15"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    And today is "2026-09-27"
    And the fund admin confirms dealing date "2026-10-01"
    When I try to approve the class "A" NAV for "2026-08-15" directly
    Then the approval should succeed

  # ---- Review fix 4: uploaded NAVs ----

  # E307 — Edge case: drafting a date that has an uploaded draft is refused, so the administrator's figures are never silently replaced.
  Scenario: Drafting refuses to overwrite an uploaded NAV
    Given a draft NAV for class "A" on "2026-09-30" with NAV per unit "10,050" and units "100000"
    And the portfolio fair value is "95,00,00,000"
    When "Asha" tries to draft the NAV for "2026-09-30"
    Then drafting should be refused with "An uploaded NAV exists for Class A on 30 September 2026 — delete it to draft this date from the ledger"
    And the class "A" NAV for "2026-09-30" should be:
      | source             | uploaded |
      | nav_per_unit_cents | 10,050   |

  # E308 — Edge case: an uploaded NAV of a fee-charging class shows no "run the fee formula" warning and raises no Fee accrual behind alert.
  Scenario: An uploaded NAV has no fee-accrual warning
    Given class "A" charges a management fee of "2"
    And a draft NAV for class "A" on "2026-09-30" with NAV per unit "10,050" and units "100000"
    Then the class "A" NAV for "2026-09-30" should show no fee accrual warning

  # ---- Review fix 5: settlement ----

  # E309 — Edge case: money 5 paise short of the amount due (recorded elsewhere, not verified) offers Verify, not Record payment.
  @rack_test
  Scenario: A payment within 10 paise can be verified on the dealing date
    Given the fund setting has "payment_timing=after"
    And "B LLP" has placed a "subscription" order "amount=10000000" received "2026-09-10 10:00"
    And today is "2026-09-27"
    And the fund admin confirms dealing date "2026-10-01"
    And "B LLP" has an unverified payment "0.05" short of the subscription on "2026-10-05"
    When I open the dealing date "2026-10-01"
    Then the tracker row of "B LLP" on "2026-10-01" should offer "Verify" and not "Record payment"

  # X202 — Error case: undoing brings back a pre-funded subscription that confirm cancelled (unpaid, fund set to cancel); if its folio can't be re-opened the undo is refused with the reason and the date stays confirmed.
  Scenario: Undo reports a folio error instead of failing
    Given the fund setting has "unready_handling=cancel"
    And "B LLP" has placed a "subscription" order "amount=10000000" received "2026-09-10 10:00"
    And today is "2026-09-27"
    And the fund admin confirms dealing date "2026-10-01"
    And the order of "B LLP" should have status "cancelled"
    And re-opening a folio fails with "Folio could not be saved"
    When the fund admin undoes dealing date "2026-10-01"
    Then the undo should be refused with "Folio could not be saved"
    And the dealing date "2026-10-01" should be "confirmed"

  # X203 — Error case: once a dealing date is closed, a settlement action posted directly is refused.
  Scenario: A closed dealing date takes no more settlement actions
    Given "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    And today is "2026-09-27"
    And the fund admin confirms dealing date "2026-10-01"
    And the dealing date "2026-10-01" is closed
    When "Asha" posts "mark_paid" for the fill of "A Ltd" on "2026-10-01" directly with "payment_date=2026-10-05;reference=LATE"
    Then the direct request should be refused with "This dealing date is closed — no more settlement actions"

  # ---- Review fix 6: email templates ----

  # E310 — Edge case: an evergreen template with WhatsApp text now reaches WhatsApp (the notifier answers custom_notification).
  Scenario: An evergreen template's WhatsApp text is used
    Given the fund has an evergreen template for "redemption_acknowledgement" with "whatsapp=Your redemption is queued"
    When "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    Then the evergreen notification for the order of "A Ltd" should carry WhatsApp text "Your redemption is queued"

  # E311 — Edge case: a custom template with Show details and Show details link keeps the summary and the "View your request" link.
  Scenario: A custom evergreen email keeps the summary and the link when asked
    Given the fund has an evergreen template for "redemption_acknowledgement" with "subject=Got it;body=Thanks;show_details=true;show_details_link=true"
    When "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    Then "A Ltd" receives an email with subject "Got it" containing "View your request"
    And "A Ltd" receives an email with subject "Got it" containing "F-012"

  # E312 — Edge case: a template file on a folio is the GP's working file and never shows in the investor's Documents.
  @rack_test
  Scenario: Folio templates are hidden from the investor
    Given folio "F-012" has a template document "Contract Note Template A Ltd"
    When "A Ltd" logs in to the portal
    And I open the fund page
    Then I should not see "Contract Note Template A Ltd"

  # ---- Review fix 7: queue number ----

  # E313 — Edge case: B LLP's request is the only one on 2 Nov, so it is #1 there even though A Ltd's 1 Oct request was received first.
  Scenario: The queue number counts only the same dealing date
    Given "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=500" received "2026-09-28 10:00"
    Then the redemption of "A Ltd" should be "#1" in its queue
    And the redemption of "B LLP" should be "#1" in its queue

  # E314 — Edge case: under a pro-rata gate the queue tooltip says every request is filled by the same %, not FIFO.
  Scenario: The queue tooltip follows a pro-rata gate
    Given the fund setting has "gate_method=pro_rata"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    Then the queue tooltip of "A Ltd" should say "the gate is pro-rata"

  # ---- Review fix 8: gate used earlier in the period ----

  # E315 — Edge case: with a quarterly 5% gate, ₹1 Cr paid on 1 Oct leaves ₹4 Cr of the ₹5 Cr gate for 2 Nov.
  Scenario: A quarterly gate shows what is left after earlier dates
    Given the fund setting has "gate_period=quarter"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    And today is "2026-09-27"
    And the fund admin confirms dealing date "2026-10-01"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=500" received "2026-10-05 10:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,000" and units "99000"
    Then the gate of dealing date "2026-11-02" should have "1,00,00,000" used and "3,95,00,000" left

  # ---- Review fix 9: buttons and wording ----

  # E316 — Edge case: an employee with read access only sees no New Order, no Calendar settings and no Save settings.
  @rack_test
  Scenario: Read-only users aren't offered actions they can't take
    Given there is an employee "Vik" who can only read the fund
    When the user "Vik" signs in
    And I open the fund page
    Then I should not see "New Order"
    When I open the dealing list
    Then I should not see "Calendar settings"
    When I open the evergreen settings of the fund
    Then I should see "View only — you need update access on the fund to change these settings"

  # E317 — Edge case: when the top-up minimum differs, the subscription form shows both minimums.
  @rack_test
  Scenario: The subscription form shows both minimums
    Given the fund setting has "min_initial_subscription=25000000;min_additional_subscription=10000000"
    When I start a "subscription" for the fund
    Then I should see "first subscription"
    And I should see "top-up"

  # ---- Fund 356 review (11 Oct 2026): the same fact reads the same on every screen ----

  # E323 — Edge case: A Ltd asks 12,000 units; the 5 % gate fills 5,000 on 1 Oct and carries 7,000 to 2 Nov. The dealing list still counts 1 redemption on 1 Oct (its fill), and the order book and unit register show the 7,000 still to redeem, "of 12,000 requested" (F2, F6, F7).
  @rack_test
  Scenario: A part-filled redemption reads the same on the list, the order book and the register
    Given "A Ltd" has placed a "redemption" order "folio=F-012;units=12000" received "2026-09-10 10:00"
    And today is "2026-09-27"
    And the fund admin confirms dealing date "2026-10-01"
    When I open the dealing list
    Then the dealing list row of "2026-10-01" should show 1 redemptions
    When I open the redemptions list
    Then the "Units" cell of the order of "A Ltd" should show "7,000.0000"
    And the "Units" cell of the order of "A Ltd" should show "of 12,000.0000 requested"
    When I open the unit register
    Then the register row of folio "F-012" should show "7,000" units queued

  # E324 — Edge case: on 6 Oct, 2 Nov's cut-off is weeks away, so the NAV it will price at can't exist yet — no red "draft and approve a newer NAV" alert, the step is "Open for orders", and B LLP's row says its figures are estimated until Class A's NAV is approved (F3, F4, F5).
  @rack_test
  Scenario: A missing NAV before the cut-off is not flagged as a problem
    Given "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    And today is "2026-09-27"
    And the fund admin confirms dealing date "2026-10-01"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=500" received "2026-10-05 10:00"
    And today is "2026-10-06"
    When I open the dealing date "2026-11-02"
    Then I should not see "draft and approve a newer NAV first"
    And I should see "Class A will be priced once that NAV is approved"
    And the redemption of "B LLP" should be waiting for a NAV with "Estimated until Class A's NAV is approved"
    When I open the dealing list
    Then the dealing list row of "2026-11-02" should be at step "Open for orders"

  # E326 — Edge case: the fund page's NAV and units cards say the date they are at — the 31 Aug NAV — so they aren't read as today's figures (F9).
  @rack_test
  Scenario: The NAV and units cards name their NAV date
    When I open the evergreen overview
    Then I should see "NAV at 31/08/2026"

  # E327 — Edge case: Net flows QTD counts at Confirm — after 1 Oct's ₹1,00,00,000 redemption is dealt but before it is paid, the card already reads −₹1,00,00,000, and its tooltip says ₹1,00,00,000 is not yet paid (F10).
  @rack_test
  Scenario: Net flows count a redemption once it is dealt, not once it is paid
    Given "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    And today is "2026-09-27"
    And the fund admin confirms dealing date "2026-10-01"
    And today is "2026-10-05"
    When I open the evergreen overview
    Then the net flows card should show an outflow of "1,00,00,000.00" with "1,00,00,000.00 not yet paid"

  # E328 — Edge case: B LLP's redemption waits for Class A's NAV but keeps its place in the gate queue — the page says the gate figures are an estimate and still shows its outcome, "Will be paid in full", as the Redemptions list does (F11).
  @rack_test
  Scenario: A redemption waiting for a NAV still shows its estimated gate outcome
    Given "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 10:00"
    And today is "2026-09-27"
    And the fund admin confirms dealing date "2026-10-01"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=500" received "2026-10-05 10:00"
    And today is "2026-10-30"
    When I open the dealing date "2026-11-02"
    Then I should see "Estimate."
    And the redemption of "B LLP" should be waiting for a NAV with "Will be paid in full"
