Feature: Capital Calls
  Adjustments to capital commitments

Scenario Outline: Create a capital call
  Given there is a user "<user>" for an entity "<entity>"
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a capital commitment of "folio_committed_amount_cents=100000000;folio_currency=INR;fund_close=Second Close" for the last investor
  When I create a Capital Call with percentage of commitment
  Given it should create Capital Remittances according to the close percentage

  Examples:
    | user             | entity                           |
    | first_name=Test  | name=Urban;entity_type=Investment Fund |

Scenario Outline: Create a capital call with Upload call basis
  Given there is a user "<user>" for an entity "<entity>"
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a capital commitment of "folio_committed_amount_cents=100000000;folio_currency=INR;fund_close=Second Close" for the last investor
  When I create a Capital Call with upload call basis
  Given it should create a Capital Call with given data

  Examples:
    | user             | entity                           |
    | first_name=Test  | name=Urban;entity_type=Investment Fund |

Scenario Outline: Create a capital call with Upload call basis
  Given there is a user "<user>" for an entity "<entity>"
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a capital commitment of "folio_committed_amount_cents=100000000;folio_currency=INR;fund_close=Second Close" for the last investor
  When I create a Capital Call with investable call basis
  Given it should create a Investable Capital Call with given data

  Examples:
    | user             | entity                           |
    | first_name=Test  | name=Urban;entity_type=Investment Fund |

Scenario Outline: Generate fund units from capital call
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "folio_committed_amount_cents=100000000" from each investor
  Given there is a capital call "<call>"
  Given there is an existing investor "" with "1" users
  Given there is a capital commitment of "folio_committed_amount_cents=100000000" for the last investor
  Given the investors are added to the fund
  Then the corresponding remittances should be created
  Then I should see the remittances
  Given the remittances are paid and verified
  Given the remittances has some units already allocated
  Given the units are generated
  Then it should generate only the remaining units
  Given the units are generated
  Then error email for fund units already allocated should be sent

Examples:
    |user     |entity                                 |fund                 | call |
    |           |entity_type=Investment Fund;enable_funds=true  |name=Test  | percentage_called=20 |