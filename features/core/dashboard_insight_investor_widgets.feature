# Worked examples H17, H18, E45–E53 — openspec/changes/archive/2026-11-07-dashboard-insight-widgets/business-rules.md#6
Feature: Investor Dashboard insight widgets
  Investor Pending Actions lists what is still outstanding with an LP (unpaid calls, KYC, approvals awaiting a
  reply, documents awaiting e-signature); Side-letter Obligations lists that LP's obligations falling due.

  Background:
    Given today is "2026-09-30"
    And Im logged in as a user "first_name=Meera;last_name=Ops" for an entity "name=Demo Capital;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the ops insight LP "Asha Family Office" has a commitment in "Growth Fund I"
    And the "Investor Pending Actions" widget on the "Investor Dashboard" has settings ""
    And the "Side-letter Obligations" widget on the "Investor Dashboard" has settings ""

  # H17 — Happy path: one unpaid call, one unverified KYC, one approval awaiting a reply, one document awaiting e-sign
  @rack_test
  Scenario: Investor Pending Actions lists what is outstanding
    Given the ops insight LP "Asha Family Office" owes 20 lakh on call "Call 3" in "Growth Fund I" due "2026-09-15" with status "Overdue"
    And the ops insight LP "Asha Family Office" has a KYC "Asha Mehta" with status "completed" expiring "2027-06-30"
    And the ops insight LP "Asha Family Office" has an approval "Extend fund term" due "2026-10-10" that is "published"
    And the ops insight LP "Asha Family Office" has a document "Commitment Agreement" in "Growth Fund I" with e-sign status "requested"
    When I open the investor dashboard of "Asha Family Office" for the ops insight widgets
    Then the ops insight section "Unpaid calls" should count 1
    And the ops insight section "Unpaid calls" should list "Call 3"
    And the ops insight section "Unpaid calls" row "Call 3" should show "20,00,000"
    And the ops insight section "KYC" should count 1
    And the ops insight section "KYC" row "Asha Mehta" should show "Not verified"
    And the ops insight section "Approvals awaiting reply" should count 1
    And the ops insight section "Approvals awaiting reply" should list "Extend fund term"
    And the ops insight section "Awaiting e-signature" should count 1
    And the ops insight section "Awaiting e-signature" should list "Commitment Agreement"

  # H18 — Happy path: an active obligation of this LP falling due within 30 days
  @rack_test
  Scenario: Side-letter Obligations on the Investor Dashboard
    Given the ops insight LP "Asha Family Office" has a side-letter obligation "Quarterly ESG report" in "Growth Fund I" due "2026-10-15" with status "active" and review "approved"
    When I open the investor dashboard of "Asha Family Office" for the ops insight widgets
    Then the ops insight widget "Side-letter Obligations" should list "Quarterly ESG report"
    And the ops insight widget "Side-letter Obligations" row "Quarterly ESG report" should show "2026"

  # E45 — Edge case: a verified KYC expiring within 60 days (20 Nov 2026 is 51 days away) is listed
  @rack_test
  Scenario: A KYC expiring within the warning window is listed
    Given the ops insight LP "Asha Family Office" has a KYC "Asha Mehta" with status "verified" expiring "2026-11-20"
    When I open the investor dashboard of "Asha Family Office" for the ops insight widgets
    Then the ops insight section "KYC" should count 1
    And the ops insight section "KYC" row "Asha Mehta" should show "Expires"

  # E46 — Edge case: a verified KYC expiring after the window (31 Dec 2026 is 92 days away) is not listed
  @rack_test
  Scenario: A KYC expiring after the warning window is not listed
    Given the ops insight LP "Asha Family Office" has a KYC "Asha Mehta" with status "verified" expiring "2026-12-31"
    And the ops insight LP "Asha Family Office" owes 5 lakh on call "Call 4" in "Growth Fund I" due "2026-10-15" with status "Pending"
    When I open the investor dashboard of "Asha Family Office" for the ops insight widgets
    Then the ops insight section "KYC" should count 0

  # E47 — Edge case: an approval past its due date, and one not yet published, are not awaiting a reply
  @rack_test
  Scenario: Closed or unpublished approvals are left out
    Given the ops insight LP "Asha Family Office" has an approval "Old consent" due "2026-09-01" that is "published"
    And the ops insight LP "Asha Family Office" has an approval "Draft consent" due "2026-10-20" that is "not published"
    And the ops insight LP "Asha Family Office" owes 5 lakh on call "Call 4" in "Growth Fund I" due "2026-10-15" with status "Pending"
    When I open the investor dashboard of "Asha Family Office" for the ops insight widgets
    Then the ops insight section "Approvals awaiting reply" should count 0

  # E48 — Edge case: a document whose e-signature is completed is not awaiting signature
  @rack_test
  Scenario: A completed e-signature is left out
    Given the ops insight LP "Asha Family Office" has a document "Commitment Agreement" in "Growth Fund I" with e-sign status "completed"
    And the ops insight LP "Asha Family Office" owes 5 lakh on call "Call 4" in "Growth Fund I" due "2026-10-15" with status "Pending"
    When I open the investor dashboard of "Asha Family Office" for the ops insight widgets
    Then the ops insight section "Awaiting e-signature" should count 0

  # E49 — Edge case: nothing outstanding shows one sentence instead of four empty sections
  @rack_test
  Scenario: Nothing outstanding
    Given the ops insight LP "Asha Family Office" owes 0 lakh on call "Call 1" in "Growth Fund I" due "2026-06-30" with status "Paid"
    When I open the investor dashboard of "Asha Family Office" for the ops insight widgets
    Then the ops insight widget "Investor Pending Actions" should say "Nothing outstanding with Asha Family Office."

  # E50 — Edge case: another LP's overdue remittance is not shown on this LP's dashboard
  @rack_test
  Scenario: Another LP's items are not shown
    Given the ops insight LP "Bharat LP" owes 10 lakh on call "Bharat Call" in "Growth Fund I" due "2026-09-01" with status "Overdue"
    And the ops insight LP "Asha Family Office" owes 20 lakh on call "Call 3" in "Growth Fund I" due "2026-09-15" with status "Overdue"
    When I open the investor dashboard of "Asha Family Office" for the ops insight widgets
    Then the ops insight section "Unpaid calls" should list "Call 3"

  # E51 — Edge case: due in 30 days is inside the default window, due in 31 days is outside
  @rack_test
  Scenario: Obligation due window
    Given the ops insight LP "Asha Family Office" has a side-letter obligation "Due in 30 days" in "Growth Fund I" due "2026-10-30" with status "active" and review "approved"
    And the ops insight LP "Asha Family Office" has a side-letter obligation "Due in 31 days" in "Growth Fund I" due "2026-10-31" with status "active" and review "approved"
    When I open the investor dashboard of "Asha Family Office" for the ops insight widgets
    Then the ops insight widget "Side-letter Obligations" should list "Due in 30 days"

  # E52 — Edge case: an overdue obligation is listed first and flagged
  @rack_test
  Scenario: Overdue obligation listed first
    Given the ops insight LP "Asha Family Office" has a side-letter obligation "Quarterly ESG report" in "Growth Fund I" due "2026-10-15" with status "active" and review "approved"
    And the ops insight LP "Asha Family Office" has a side-letter obligation "Annual audit copy" in "Growth Fund I" due "2026-09-01" with status "active" and review "approved"
    When I open the investor dashboard of "Asha Family Office" for the ops insight widgets
    Then the ops insight widget "Side-letter Obligations" should list "Annual audit copy, Quarterly ESG report"
    And the ops insight widget "Side-letter Obligations" row "Annual audit copy" should show "Overdue"

  # E53 — Edge case: fulfilled, waived and still-unreviewed obligations are left out
  @rack_test
  Scenario: Fulfilled, waived and unreviewed obligations are left out
    Given the ops insight LP "Asha Family Office" has a side-letter obligation "Fulfilled one" in "Growth Fund I" due "2026-10-05" with status "fulfilled" and review "approved"
    And the ops insight LP "Asha Family Office" has a side-letter obligation "Waived one" in "Growth Fund I" due "2026-10-05" with status "waived" and review "approved"
    And the ops insight LP "Asha Family Office" has a side-letter obligation "Unreviewed one" in "Growth Fund I" due "2026-10-05" with status "active" and review "pending_review"
    When I open the investor dashboard of "Asha Family Office" for the ops insight widgets
    Then the ops insight widget "Side-letter Obligations" should say "No side-letter obligation falls due in the next 30 days."
