Feature: A capital call needs at least one applicable commitment
  A new capital call is refused when no commitment in the fund applies to it
  (openspec/changes/block-capital-call-without-commitments, worked examples in design.md Part 4)

Background:
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users

# H1
Scenario: A call for all closes on a fund with commitments is created from the form
  Given there is a fund "name=SAAS Fund" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000;fund_close=First Close" from each investor
  When I create a new capital call "percentage_called=10"
  Then the corresponding remittances should be created

# H2
Scenario: An Upload call on a fund with commitments is created
  Given there is a fund "name=SAAS Fund" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000;fund_close=First Close" from each investor
  When I create a capital call through the operation for "All" closes with basis "Upload"
  Then the capital call is created

# H2, through the form: an Upload call arrives with no fund closes, which means every commitment
Scenario: An Upload call from the New Call form on a fund with commitments is created
  Given there is a fund "name=SAAS Fund" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000;fund_close=First Close" from each investor
  When I create a Capital Call with upload call basis
  Then it should create a Capital Call with given data

# H3
Scenario: A call naming a close with commitments and one without is created
  Given there is a fund "name=SAAS Fund" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000;fund_close=First Close" from each investor
  When I create a capital call through the operation for "First Close, Second Close" closes with basis "Percentage of Commitment"
  Then the capital call is created
  And remittances are created only for the "First Close" commitments

# E1
Scenario: Editing a call to a close with no commitments is not blocked
  Given there is a fund "name=SAAS Fund" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000;fund_close=First Close" from each investor
  When I create a capital call through the operation for "First Close" closes with basis "Percentage of Commitment"
  Then the capital call is created
  When I change the capital call closes to "Second Close"
  Then the capital call edit is saved

# E2
Scenario: A call for a close with no commitments is refused
  Given there is a fund "name=SAAS Fund" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000;fund_close=First Close" from each investor
  When I create a capital call through the operation for "Second Close" closes with basis "Percentage of Commitment"
  Then the capital call create is refused with the no commitments message
  And no capital call is created

# X1
Scenario: The New Call form on a fund with no commitments shows the error and keeps the input
  Given there is a fund "name=Empty Fund" for the entity
  When I submit the new capital call form named "QA X1"
  Then the capital call form shows the no commitments error and keeps the name "QA X1"
  And no capital call is created

# X2
Scenario: An Upload call on a fund with no commitments is refused
  Given there is a fund "name=Empty Fund" for the entity
  When I create a capital call through the operation for "All" closes with basis "Upload"
  Then the capital call create is refused with the no commitments message
  And no capital call is created

# X3
Scenario: A refused call leaves nothing behind
  Given there is a fund "name=Empty Fund" for the entity
  When I create a capital call through the operation for "All" closes with basis "Percentage of Commitment"
  Then the capital call create is refused with the no commitments message
  And no capital call is created

# X4
Scenario: The JSON create endpoint refuses a call on a fund with no commitments
  Given there is a fund "name=Empty Fund" for the entity
  When I post a capital call as JSON for the fund
  Then the JSON response is refused with the no commitments message
  And no capital call is created

# X5
@import
Scenario: A call import fails only the row whose closes have no commitments
  Given there is a fund "name=SAAS Fund" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000;fund_close=First Close" from each investor
  And Given I upload "capital_calls_no_commitments.xlsx" file for "Calls" of the fund with errors
  Then the capital call should fail with error "No commitments in this fund apply to this call. Add commitments for the selected fund closes before creating a capital call."
  And There should be "1" capital calls created
  And the fund has a capital call named "All Closes Call"
