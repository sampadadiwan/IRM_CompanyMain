@rack_test
Feature: Investment Instrument Portfolio Company Field
  The investment instrument form lets you pick which portfolio company an instrument belongs
  to when opened generically (e.g. from the main Investment Instruments list), and locks that
  choice when opened from a specific portfolio company's own instruments tab, so it can't be
  changed away from that company by accident.

@investment_instrument
Scenario Outline: Generic new instrument page offers a choice of portfolio company
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "<fund>" for the entity
  Given there is an existing portfolio company "name=Delta Ventures;category=Portfolio Company"
  Given there is an existing portfolio company "name=Awesome Ventures;category=Portfolio Company"
  When I visit the new investment instrument page
  Then the "For" field should not be locked
  And the "For" field should offer "Delta Ventures" and "Awesome Ventures" as choices

  Examples:
    |entity                             |fund                           |
    |entity_type=Investment Fund;       |name=Test fund;currency=INR    |

@investment_instrument
Scenario Outline: New instrument page opened from a portfolio company locks the field to that company
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "<fund>" for the entity
  Given there is an existing portfolio company "name=Delta Ventures;category=Portfolio Company"
  When I visit the new investment instrument page for that portfolio company
  Then the "For" field should be locked to "Delta Ventures"
  When I fill in the investment instrument name as "Ordinary Shares" and save
  Then the investment instrument should have been created for the portfolio company "Delta Ventures"

  Examples:
    |entity                             |fund                           |
    |entity_type=Investment Fund;       |name=Test fund;currency=INR    |
