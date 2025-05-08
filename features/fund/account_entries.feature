Feature: Account Entries
  Can run allocation

Scenario Outline: Allocate Account Entries
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "committed_amount_cents=100000000" from each investor
  Given there are Fund Formulas are added to the fund
  When I am at the fund details page
  Given that Account Entries are allocated
  Then I see AllocationRun created

  Examples:
      |user     |entity                                 |fund                 |
      |           |entity_type=Investment Fund;enable_funds=true  |name=Test  |

Scenario Outline: When AllocationRun is locked
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "committed_amount_cents=100000000" from each investor
  Given there are Fund Formulas are added to the fund
  When I am at the fund details page
  Given that Account Entries are allocated
  Then I see AllocationRun created
  Given I lock the AllocationRun
  Given that Account Entries are allocated
  Then I get the error on AllocationRun creation

  Examples:
      |user     |entity                                 |fund                 |
      |           |entity_type=Investment Fund;enable_funds=true  |name=Test  |

Scenario Outline: Create New Account Entry for commitment
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "committed_amount_cents=100000000" from each investor
  Given I am at the capital commitment page
  Given I add a new account entry
  Then an account entry is created for the commitment

  Examples:
      |user     |entity                                 |fund                 |
      |           |entity_type=Investment Fund;enable_funds=true  |name=Test  |
