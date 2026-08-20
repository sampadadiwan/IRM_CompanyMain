Feature: A logged-in user can open their own account edit page
  As any logged-in user
  I want to visit my own /users/edit page without error
  So that account-editing links (e.g. from a dashboard notice) work

  # Regression for a bug where WithAuthentication#authenticate_user! (a 0-arg
  # override) broke on Devise::RegistrationsController#edit/update/destroy,
  # which internally call authenticate_scope! -> authenticate_user!(force: true).
  # Any user hitting /users/edit (or updating/deleting their own account) hit
  # an ArgumentError — this had nothing to do with InvestorNotice, it was just
  # the first thing to ever link to that route.

  Scenario: Visiting the account edit page does not raise
    Given there is a user "email=selfedit@example.com" for an entity "name=Self Edit Co"
    And I log in with email "selfedit@example.com"
    When I visit the account edit page
    Then I should not see an application error
