# LP mobile app — reading the investor's data (design card ④). The app reads the website's own
# .json endpoints with its phone token wherever they exist; only Home, the LP document list and
# /me are mobile endpoints.
# Worked examples: openspec/changes/lp-mobile-app/design.md#worked-examples
@cross-region-cache
Feature: LP mobile app data

  Background:
    Given a mobile investor "rahul@sharmafo.in" of "Sharma Family Office" with fund manager "Arka Capital"
    And Arka Growth Fund I is set up for Sharma Family Office
    And "rahul@sharmafo.in" is signed in on the phone "iPhone 15"

  # H4 — Happy path: Home shows the website card's four figures and the To do list
  Scenario: Home figures and To do
    Given the commitment has a document "Side Letter"
    And the document "Side Letter" is waiting for "rahul@sharmafo.in" to sign through "Digio"
    When the phone "iPhone 15" requests "/api/mobile/v1/home"
    Then the phone gets the status 200
    And the phone sees the Arka card with committed "50000000.00", called "20000000.00", due "7500000.00" and distributed "3000000.00"
    And the JSON at "cards.0.called_pct" is "40.0"
    And the phone's To do lists "Capital Call 3, Side Letter"
    And the JSON at "todo.0.due_date" is "2026-10-30"

  # H5 — Happy path: the Fund screen's calls come from the website's capital remittances JSON
  Scenario: Fund calls list
    When the phone "iPhone 15" opens the Arka fund's calls
    Then the phone gets the status 200
    And the phone sees the calls "Capital Call 3 7500000.00 Pending; Capital Call 2 5000000.00 Paid; Capital Call 1 7500000.00 Paid"

  # H5 — Happy path (distributions segment): the website's distribution payments JSON, for a phone
  Scenario: Fund distributions list
    When the phone "iPhone 15" opens the Arka fund's distributions
    Then the phone gets the status 200
    And the phone sees the distribution "Distribution 1" of "3000000.00"

  # H6 — Happy path: the Capital call screen, with its approved call notice
  Scenario: Capital call with its notice
    Given Call 3 has an approved call notice
    When the phone "iPhone 15" opens Capital Call 3
    Then the phone gets the status 200
    And the phone sees the capital call "Capital Call 3" with status "Pending", due amount "7500000.00" and due date "2026-10-30"
    And the capital call's notice is the approved call notice

  # H7 — Happy path: opening a document records "viewed by", as the website does
  Scenario: Opening a document is recorded
    Given the commitment has a document "Q2 2026 Statement"
    When the phone "iPhone 15" opens the document "Q2 2026 Statement"
    Then the phone gets the status 200
    And "rahul@sharmafo.in" is recorded as having viewed "Q2 2026 Statement"

  # H8 — Happy path: an advisor lists their personas on /me and switches with the website's action
  Scenario: Advisor switches investor
    Given "anil@advisors.in" is an investor advisor approved by Sharma Family Office
    And "anil@advisors.in" is signed in on the phone "Anil's iPhone"
    When the phone "Anil's iPhone" requests "/api/mobile/v1/me"
    Then the JSON at "personas.0.name" is "Sharma Family Office"
    When the phone "Anil's iPhone" switches to the persona "Sharma Family Office"
    And the phone "Anil's iPhone" requests "/api/mobile/v1/home"
    Then the phone sees 1 fund card
    And the JSON at "cards.0.fund_name" is "Arka Growth Fund I"

  # H9 — Happy path: marking an alert read in the app is the website bell's read state
  Scenario: Mark read is shared with the website
    Given "rahul@sharmafo.in" has an unread notification for Capital Call 3
    When the phone "iPhone 15" requests "/notifications.json?all=1"
    Then the JSON at "0.link" is "/capital-calls/{call3}"
    And the JSON at "0.category" is "capital_calls"
    When the phone "iPhone 15" marks the Capital Call 3 notification read
    Then the phone gets the status 204
    And "rahul@sharmafo.in" has 0 unread notifications

  # E15 — Edge case: an item the app has no screen for (a KYC request) opens the website page
  Scenario: KYC alert links to the website
    Given "rahul@sharmafo.in" has a KYC request alert from Arka Capital
    When the phone "iPhone 15" requests "/notifications.json?all=1"
    Then the alert opens the website KYC form
    And the JSON at "0.category" is "other"

  # H15 — Happy path: push categories are saved per user
  Scenario: Category preferences saved
    When the phone "iPhone 15" sends "PATCH" to "/api/mobile/v1/me/push_preferences" with:
      """
      { "push_preferences": { "distributions": false } }
      """
    Then the phone gets the status 200
    And the JSON at "push_preferences.distributions" is "false"
    And the JSON at "push_preferences.capital_calls" is "true"

  # E16 — Edge case: two folios in one fund are two cards
  Scenario: Two folios in one fund
    Given Sharma Family Office has a second commitment to Arka Growth Fund I of 10000000
    When the phone "iPhone 15" requests "/api/mobile/v1/home"
    Then the phone sees 2 fund cards

  # E17 — Edge case: an evergreen folio gets the evergreen card (value / units / NAV), not committed / called
  Scenario: Evergreen folio card
    Given Sharma Family Office holds a folio in the evergreen fund "Arka Income Fund"
    When the phone "iPhone 15" requests "/api/mobile/v1/home"
    Then the phone sees an evergreen card for "Arka Income Fund" with no NAV yet

  # E18 — Edge case: a paid call leaves the To do list; an overdue one stays
  Scenario: Paid call drops off, overdue call stays
    Given Call 3 has been paid
    And a call "Catch-up Call" that was due yesterday is unpaid
    When the phone "iPhone 15" requests "/api/mobile/v1/home"
    Then the phone's To do lists "Catch-up Call"
    And the JSON at "todo.0.status" is "Overdue"

  # E19 — Edge case: 30 documents page as 25 then 5
  Scenario: Document list pages at 25
    Given the commitment has 30 documents
    When the phone "iPhone 15" requests "/api/mobile/v1/documents"
    Then the phone's document list has 25 items and next page "2"
    When the phone "iPhone 15" requests "/api/mobile/v1/documents?page=2"
    Then the phone's document list has 5 items and next page ""

  # E20 — Edge case: fund-level / data room documents stay on the website (behind its NDA gate)
  Scenario: Data room documents are not listed in the app
    Given the commitment has a document "Q2 2026 Statement"
    And the fund has a data room document "Data Room Model.xlsx"
    When the phone "iPhone 15" requests "/api/mobile/v1/documents"
    Then the phone's document list includes "Q2 2026 Statement"
    And the phone's document list does not include "Data Room Model.xlsx"

  # E21 — Edge case: a DocuSign document is signed from DocuSign's email, not in the app
  Scenario: DocuSign sign action
    Given the commitment has a document "Subscription Addendum"
    And the document "Subscription Addendum" is waiting for "rahul@sharmafo.in" to sign through "Docusign"
    When the phone "iPhone 15" opens the document "Subscription Addendum"
    Then the JSON at "sign_action" is "docusign_email"
    And the JSON at "sign_url" is ""

  # H18 (server side) — a Digio document gives the app Digio's signing page
  Scenario: Digio sign action
    Given the commitment has a document "Side Letter"
    And the document "Side Letter" is waiting for "rahul@sharmafo.in" to sign through "Digio"
    When the phone "iPhone 15" opens the document "Side Letter"
    Then the JSON at "sign_action" is "digio_url"
    And the JSON at "signature_status" is "requested"

  # E22 — Edge case: a notice generated but not yet approved is not shown
  Scenario: No notice yet
    Given Call 3 has a generated call notice that is not approved yet
    When the phone "iPhone 15" opens Capital Call 3
    Then the capital call has no notice

  # E24 — Edge case: a US English phone gets the US date format
  Scenario: US date format
    Given the phone "iPhone 15" uses the language "en-US"
    When the phone "iPhone 15" requests "/api/mobile/v1/me"
    Then the JSON at "date_format" is "%m/%d/%Y"

  # H4 (India date) — an Indian English phone gets dd/mm/yyyy
  Scenario: Indian date format
    When the phone "iPhone 15" requests "/api/mobile/v1/me"
    Then the JSON at "date_format" is "%d/%m/%Y"

  # E25 — Edge case: Mark all read
  Scenario: Mark all read
    Given "rahul@sharmafo.in" has received 3 notifications
    When the phone "iPhone 15" marks all notifications read as "rahul@sharmafo.in"
    Then "rahul@sharmafo.in" has 0 unread notifications

  # E28 — Edge case: nothing to do and no calls yet
  Scenario: All caught up
    Given a mobile investor "neha@newlp.in" of "New LP Trust" with fund manager "Arka Capital"
    And "neha@newlp.in" is signed in on the phone "Neha's Pixel"
    When the phone "Neha's Pixel" requests "/api/mobile/v1/home"
    Then the phone's To do is empty
    And the phone sees 0 fund cards

  # E29 — Edge case: funds of two fund managers
  Scenario: Two fund managers
    Given Sharma Family Office has a commitment of 20000000 to "Beta Opportunities" managed by "Beta Partners"
    When the phone "iPhone 15" requests "/api/mobile/v1/home"
    Then the phone sees fund cards from "Arka Capital, Beta Partners"

  # X8 — Error case: another investor's capital call is refused
  Scenario: Another investor's capital call
    Given Kapoor Holdings has a capital call in Arka Growth Fund I
    When the phone "iPhone 15" opens Kapoor's capital call
    Then the phone gets the status 403

  # X9 — Error case: an app older than the minimum version must update
  Scenario: Old app version
    Given the minimum app version is "1.2.0"
    And the phone "iPhone 15" sends app version "1.1.9"
    When the phone "iPhone 15" requests "/api/mobile/v1/home"
    Then the phone gets the status 426
    And the phone sees the message "Please update CapHive to continue."

  # X18 — Error case: another investor's document is refused and not recorded as viewed
  Scenario: Document outside scope
    Given Kapoor Holdings has a capital call in Arka Growth Fund I
    When the phone "iPhone 15" opens the document "Kapoor Statement"
    Then the phone gets the status 403
    And "rahul@sharmafo.in" has not viewed "Kapoor Statement"

  # X17 — Error case: an advisor cannot switch into a persona that is not theirs
  Scenario: Advisor switch not approved
    Given "anil@advisors.in" is an investor advisor approved by Sharma Family Office
    And "anil@advisors.in" is signed in on the phone "Anil's iPhone"
    And Kapoor Holdings has its own investor advisor
    When the phone "Anil's iPhone" switches to Kapoor's advisor persona
    Then the phone gets the status 403
