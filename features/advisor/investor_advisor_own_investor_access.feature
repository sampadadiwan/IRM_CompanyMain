Feature: An advisor keeps their own investor access
  A user who advises others is often also an approved contact of their OWN investor record. An
  advisor grant comes in two kinds, and both hand out the same global investor_advisor role:
    - Investor Advisor: the grant belongs to a client investor's entity; switched in, they act as that investor.
    - Fund Advisor: the grant belongs to the fund manager's entity; switched in, they act as its staff.
  Switched in, they act under that grant. At home they act as themselves: exactly what a plain
  contact of their own investor gets, and nothing from any grant.
  Worked examples: openspec/changes/fix-advisor-own-investor-access/report.md#verification

  Production shape (prod user 2564 / investor 4800 / fund 159): the advisor's home is an
  Investor-type entity, their only role at home is investor_advisor, curr_role is investor, the
  fund grants access to their investor record (no personal grant), and a plain co-contact receives
  the call notices the advisor silently did not.

  Background:
    Given Im logged in as a user "first_name=Srikant" for an entity "name=Srikant Home;entity_type=Investor"
    And the advisor is at home holding only the investor_advisor role
    And there is a fund company "name=Artha;entity_type=Investment Fund" with a fund "name=Artha Select"
    And the advisor and a plain contact are approved contacts of the advisor's own investor on the fund
    And there is an approved capital call on the fund with a pending remittance for the own investor

  # H1 — Happy path: an advisor at home receives the call reminder for their own remittance
  @security @rack_test
  Scenario: H1 An advisor at home receives the reminder for their own remittance
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    When the capital call reminder is sent
    Then the advisor and the plain contact are notified for the own remittance

  # H2 — Happy path: an advisor at home receives the call notice for their own remittance
  @security @rack_test
  Scenario: H2 An advisor at home receives the call notice for their own remittance
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    When the call notice is sent for the own remittance
    Then the advisor and the plain contact are notified for the own remittance

  # H3 — Happy path: an advisor at home can open their own fund and remittance
  @security @rack_test
  Scenario: H3 An advisor at home can open their own fund and remittance
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    Then the advisor can see the fund
    And the advisor can see the own remittance
    When I visit the own remittance
    Then I am not denied access

  # H4 — Happy path: a switched Investor Advisor still acts for the client
  @security @rack_test
  Scenario: H4 A switched Investor Advisor is notified for and can open the client's remittance
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And the advisor has switched into the client "Harshal"
    When the capital call reminder is sent
    Then the advisor is notified for the client remittance
    And the advisor can see the client remittance

  # H5 — Happy path: a Fund Advisor at home receives the call reminder for their own remittance
  @security @rack_test
  Scenario: H5 A Fund Advisor at home receives the reminder for their own remittance
    Given the advisor is a Fund Advisor for the fund company with roles "employee"
    When the capital call reminder is sent
    Then the advisor and the plain contact are notified for the own remittance
    And the advisor can see the fund

  # H6 — Happy path: a switched Fund Advisor works as staff of the fund company
  @security @rack_test
  Scenario: H6 A switched Fund Advisor sees the fund and every investor's remittance as staff
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And the advisor is a Fund Advisor for the fund company with roles "employee"
    And the advisor has switched into the fund company
    Then the advisor can see the fund
    And the advisor can see the client remittance

  # H7 — Happy path: a family-office home whose home roles start with investor keeps own access
  @security @rack_test
  Scenario: H7 A family-office advisor whose home roles start with investor receives their own reminder
    Given the advisor's home is an advisory firm with home roles "investor,investor_advisor"
    And the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    When the capital call reminder is sent
    Then the advisor and the plain contact are notified for the own remittance

  # E1 — Edge case: switched into a client with no grant on the fund, the own reminder still arrives (home persona)
  @security @rack_test
  Scenario: E1 Switched into a client with no grant on the fund, the advisor still gets their own reminder
    Given the advisor is an Investor Advisor for a client "Mehta" who has no grant on the fund
    And the advisor has switched into the client "Mehta"
    When the capital call reminder is sent
    Then the advisor and the plain contact are notified for the own remittance

  # E2 — Edge case: switched into a client that also has a grant on the fund, the own reminder still arrives
  @security @rack_test
  Scenario: E2 Switched into a client with a grant on the same fund, the advisor still gets their own reminder
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And the advisor has switched into the client "Harshal"
    When the capital call reminder is sent
    Then the advisor and the plain contact are notified for the own remittance

  # E3 — Edge case: at home, the client's remittance stays hidden even though the advisor is its approved contact
  @security @rack_test
  Scenario: E3 At home the client's remittance is hidden
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    Then the advisor cannot see the client remittance
    And the advisor is still a recipient for the client investor through their personal grant

  # E4 — Edge case: at home, a fund granted only to the client is hidden
  @security @rack_test
  Scenario: E4 At home a fund granted only to the client is hidden
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And there is a second fund at the fund company granted only to the client
    Then the advisor cannot see the second fund
    And the advisor is not a recipient for the client investor on the second fund

  # E5 — Edge case: topic tags still apply to the advisor's own contact row
  @security @rack_test
  Scenario: E5 An advisor subscribed only to KYC does not get the call reminder
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And the advisor's own contact row is tagged "KYC"
    When the capital call reminder is sent
    Then only the plain contact is notified for the own remittance

  # E6 — Edge case: a surviving personal grant on the home entity does not double-notify
  @security @rack_test
  Scenario: E6 An advisor who also has a personal grant on the fund is notified exactly once
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And the advisor also has a personal grant on the fund in their home entity
    When the capital call reminder is sent
    Then the advisor is notified exactly once for the own remittance

  # E7 — Edge case: an advisory-firm user at home (curr_role employee) gains nothing from the fallback
  @security @rack_test
  Scenario: E7 A user at home in an advisory firm does not see the fund through a client's contact row
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And there is an advisory-firm user who is an approved contact of the client's investor
    Then the advisory-firm user cannot see the fund

  # E8 — Edge case: the notification preview counts the advisor the same way sending does
  @security @rack_test
  Scenario: E8 The fund's recipient preview counts the advisor at home
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    Then the recipient preview for the own investor counts the advisor

  # E9 — Edge case: for an Investor-type home, the home persona equals a real revert, curr_role included
  @security @rack_test
  Scenario: E9 The home persona matches a real revert for an Investor-type home
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And the advisor has switched into the client "Harshal"
    Then the home persona's entity, roles and current role equal the user's after a real revert

  # E10 — Edge case: a Fund Advisor switched into the fund company still receives their own reminder
  @security @rack_test
  Scenario: E10 A switched Fund Advisor still gets their own reminder
    Given the advisor is a Fund Advisor for the fund company with roles "employee"
    And the advisor has switched into the fund company
    When the capital call reminder is sent
    Then the advisor and the plain contact are notified for the own remittance

  # E11 — Edge case: a Fund Advisor's staff rights do not come home with them
  @security @rack_test
  Scenario: E11 A Fund Advisor at home cannot see another investor's remittance
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And the advisor is a Fund Advisor for the fund company with roles "employee"
    Then the advisor cannot see the client remittance

  # E12 — Edge case: every advisor grant deleted but the role kept (prod history) still leaves own access
  @security @rack_test
  Scenario: E12 An advisor whose grants were all deleted keeps their own access
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And all of the advisor's advisor grants are deleted
    When the capital call reminder is sent
    Then the advisor and the plain contact are notified for the own remittance
    And the advisor can see the fund

  # X1 — Error case: no grant for the own investor on the fund, so nobody is notified and the advisor is denied
  @security @rack_test
  Scenario: X1 Without a fund grant for the own investor nobody is notified
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And the own investor's grant on the fund is removed
    When the capital call reminder is sent
    Then nobody is notified for the own remittance
    And the advisor cannot see the fund

  # X2 — Error case: an unapproved own contact row receives nothing
  @security @rack_test
  Scenario: X2 An unapproved advisor contact row is not notified
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And the advisor's own contact row is unapproved
    When the capital call reminder is sent
    Then only the plain contact is notified for the own remittance

  # X3 — Error case: a deleted own contact row receives nothing
  @security @rack_test
  Scenario: X3 A deleted advisor contact row is not notified
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And the advisor's own contact row is deleted
    When the capital call reminder is sent
    Then only the plain contact is notified for the own remittance

  # X4 — Error case: the at-home fallback never applies while switched into a client
  @security @rack_test
  Scenario: X4 A switched advisor cannot open their own remittance through the client session
    Given the advisor is an Investor Advisor for a client "Mehta" who has no grant on the fund
    And the advisor has switched into the client "Mehta"
    Then the advisor cannot see the own remittance

  # X5 — Error case: a contact dropped by the access check is logged, not silently skipped
  @security @rack_test
  Scenario: X5 A contact dropped by the access check is logged
    Given the own investor's grant on the fund is removed
    When the recipients for the own investor are computed while capturing the log
    Then the log names the advisor's contact row and the fund

  # X6 — Error case: a legacy advisor with no recorded home (advisor_entity_id nil) switched into a client is not treated as at home
  @security @rack_test
  Scenario: X6 A switched legacy advisor gets nothing from the client's investor-level grant
    Given the advisor is a legacy advisor with no recorded home
    And the advisor is an Investor Advisor for a client "Patel" whose investor has a grant on the fund but gave the advisor no personal grant
    And the legacy advisor has switched into the client "Patel"
    Then the advisor cannot see the fund

  # X7 — Error case: at home, a client who shares the fund but gave no personal grant on it does not reach the advisor
  @security @rack_test
  Scenario: X7 At home, a client's notice on a shared fund without a personal grant is not sent to the advisor
    Given the advisor is an approved contact of a client "Rao" who invests in the fund without giving the advisor a personal grant
    When the capital call reminder is sent
    Then the advisor is not notified for the "Rao" remittance
    And the advisor and the plain contact are notified for the own remittance

  # X8 — Error case: switched into one client, another client's notice on the same fund does not ride on that client's grant
  @security @rack_test
  Scenario: X8 Switched into one client, another client's notice on the same fund is not sent to the advisor
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And the advisor is an approved contact of a client "Rao" who invests in the fund without giving the advisor a personal grant
    And the advisor has switched into the client "Harshal"
    When the capital call reminder is sent
    Then the advisor is notified for the client remittance
    And the advisor is not notified for the "Rao" remittance

  # E13 — Edge case: a Fund Advisor's opt-out on their own contact row is respected
  @security @rack_test
  Scenario: E13 A Fund Advisor at home who opted out of email on their own contact row is not emailed
    Given the advisor is a Fund Advisor for the fund company with roles "employee"
    And the advisor's own contact row has email turned off
    When the capital call reminder is sent
    Then the advisor and the plain contact are notified for the own remittance
    And the advisor's notification for the own remittance is not emailed
    And the plain contact's notification for the own remittance is emailed

  # E14 — Edge case: deal notices reach an advisor at home like any contact (overview?, not show?)
  @security @rack_test
  Scenario: E14 An advisor at home is a recipient of their own investor's deal notice
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And there is a deal at the fund company granted to the own investor
    Then the advisor and the plain contact are recipients for the deal

  # E15 — Edge case: an advisor at home opens their own KYC with no commitment, and receives its KYC form
  @security @rack_test
  Scenario: E15 An advisor at home can open their own KYC that has no commitment yet
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And the own investor has a KYC with no commitment
    Then the advisor can see the own KYC
    And the advisor is a recipient of the own KYC form

  # E16 — Edge case: an advisor account whose home roles leave out investor_advisor still never opens client-only funds at home
  @security @rack_test
  Scenario: E16 An advisor account without the advisor role at home does not see a fund granted only to a client
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And there is a second fund at the fund company granted only to the client
    And the advisor has reverted to a home whose stored roles leave out investor_advisor
    Then the advisor cannot see the second fund
    And the advisor can see the fund

  # H8 — Happy path: at home, a denied client record names the client and the button switches and returns to it
  @security @rack_test
  Scenario: H8 At home, Access Denied on a client's remittance offers a switch that lands back on it
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    When I visit the client remittance
    Then I am told "Access Denied: You can view this as an advisor for Harshal. Switch your persona to Harshal to view it."
    When I press "Switch to Harshal" in the Access Denied alert
    Then I am on the client remittance
    And the switch confirmation says "You have now been switched to the advisor role for Harshal."

  # E17 — Edge case: switched into the wrong client, the message names both
  @security @rack_test
  Scenario: E17 Switched into the wrong client, Access Denied names where they are and where to go
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And the advisor is an Investor Advisor for a client "Mehta" who has no grant on the fund
    And the advisor has switched into the client "Mehta"
    When I visit the client remittance
    Then I am told "Access Denied: you are currently switched into Mehta. You can view this as an advisor for Harshal. Switch your persona to Harshal to view it."

  # E18 — Edge case: a Fund Advisor's staff grant is offered for a record only staff can see
  @security @rack_test
  Scenario: E18 At home, Access Denied on another investor's remittance offers the Fund Advisor switch
    Given the advisor is an approved contact of a client "Rao" who invests in the fund without giving the advisor a personal grant
    And the advisor is a Fund Advisor for the fund company with roles "employee"
    When I visit the "Rao" remittance
    Then I am told "Access Denied: You can view this as an advisor for Artha. Switch your persona to Artha to view it."

  # X9 — Error case: when no switch would help, the message stays a bare Access Denied
  @security @rack_test
  Scenario: X9 A record no grant can open gets a plain Access Denied
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And there is a second fund at the fund company granted only to the client
    When I visit the second fund
    Then I am told exactly "Access Denied"

  # X10 — Error case: the switch's return path can never redirect off-site
  @security @rack_test
  Scenario: X10 An off-site return path on the switch is ignored
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    When the advisor switches into "Harshal" with return path "//evil.example.com/steal"
    Then the switch does not redirect off-site
    When the advisor switches into "Harshal" with return path "https://evil.example.com/steal"
    Then the switch does not redirect off-site

  # X11 — Error case: an admin-editable company name is escaped in the message and the button
  @security @rack_test
  Scenario: X11 The client's name is shown escaped, not rendered as markup
    Given the advisor is an Investor Advisor for a client "Harshal" who invests in the fund
    And the client entity is renamed to "Client <b>Bold</b> & Co"
    When I visit the client remittance
    Then the alert shows "Client <b>Bold</b> & Co" as text, not markup
