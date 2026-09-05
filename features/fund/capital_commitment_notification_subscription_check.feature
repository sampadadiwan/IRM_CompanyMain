Feature: Proactive missing Capital Call notification subscription check
  Business rationale (docs/user_guides/capital_call_actions_and_notifications_matrix.md,
  Open Question 6): before this, "no investor contacts are subscribed to Capital Call
  notifications" only ever surfaced reactively, as a Send Call Notification grey-out reason,
  once someone was already trying to notify that investor. Adding a commitment now checks this
  up front, so the gap is caught before it can block a send later.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the user has role "company_admin"
    Given there is a fund "name=TestFund;currency=INR" for the entity
    # The proactive check is a rule-engine rule, so the defaults must exist for it to fire
    And the default validation rules are seeded


  Scenario: Adding a commitment for an investor with nobody subscribed shows a warning
    Given there is an existing investor "name=Unsubscribed Investor" with "0" users
    Given the investors are added to the fund
    When I add a capital commitment "1000000" for investor "Unsubscribed Investor"
    Then I should see "Warning: No investor contacts are subscribed to Capital Call notifications for Unsubscribed Investor"


  Scenario: Adding a commitment for an investor with a subscribed user shows no warning
    Given there is an existing investor "name=Subscribed Investor" with "1" users
    Given the investors are added to the fund
    When I add a capital commitment "1000000" for investor "Subscribed Investor"
    Then I should not see "Warning: No investor contacts are subscribed"


  # The spreadsheet importer is the normal onboarding path, so it runs the same check once all
  # rows are in and fund access has been granted, and raises one aggregated alert for the
  # uploading user. Investors created from the investors sheet have no contacts, so every
  # imported commitment is for an unsubscribed investor.
  @import
  Scenario: Importing commitments for unsubscribed investors raises one aggregated warning alert
    Given Given I upload an investors file for the fund
    And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
    Then the import should have raised a warning alert naming every imported investor without Capital Call subscribers
