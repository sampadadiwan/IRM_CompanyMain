Feature: Capital Calls
  Calls to capital commitments

Scenario Outline: Create a capital call
  Given there is a user "<user>" for an entity "<entity>"
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR;fund_close=Second Close" for the last investor
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
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR;fund_close=Second Close" for the last investor
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
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR;fund_close=Second Close" for the last investor
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
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  Given there is a capital call "<call>"
  Given there is an existing investor "" with "1" users
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000" for the last investor
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

Scenario Outline: Generate fund units from capital call with phased remittance payments
  Given there is a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "investor_name=Investor 1" with "1" users
  Given there is an existing investor "investor_name=Investor 2" with "1" users
  Given there is a fund "name=TestFund" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "<commitment>" from each investor
  Given there is a capital call "<call>"
  Then the corresponding remittances should be created

  # Phase 1: Pay 50%
  Given remittances are paid "<paid_percentage1>" and verified
  Given the units are generated
  Then there should be correct units generated for the latest payment

  # Phase 2: Pay remaining 50%
  Given remittances are paid "<paid_percentage2>" and verified
  Given the units are generated
  Then there should be correct units generated for the latest payment
  And the total units should match the total paid amount
  Then the total units should be "4" 

Examples:
  | commitment                     | call                 | paid_percentage1         | paid_percentage2         |
  | orig_folio_committed_amount_cents=100000000 | percentage_called=20 | 50 | 50 |

Scenario Outline: Delete Remittance with no payments
  Given there is a user "<user>" for an entity "<entity>"
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "investor_name=Investor 1" with "1" users
  Given there is an existing investor "investor_name=Investor 2" with "1" users
  Given there is a fund "name=TestFund" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "<commitment>" from each investor
  Given there is a capital call "<call>"
  Then the corresponding remittances should be created
  Given I delete a remittance with no payments
  Then the remittance is successfully deleted
Examples:
  | commitment                     | call                 | paid_percentage1         | paid_percentage2         | user |entity |
  | orig_folio_committed_amount_cents=100000000 | percentage_called=20 | 50 | 50 | first_name=Test |name=Urban;entity_type=Investment Fund |

Scenario Outline: Delete Remittance with payment units alocated
  Given there is a user "<user>" for an entity "<entity>"
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "investor_name=Investor 1" with "1" users
  Given there is an existing investor "investor_name=Investor 2" with "1" users
  Given there is a fund "name=TestFund" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "<commitment>" from each investor
  Given there is a capital call "<call>"
  Then the corresponding remittances should be created
  Given remittances are paid "<paid_percentage1>" and verified
  Given the units are generated
  Then there should be correct units generated for the latest payment
  Given I delete a remittance having payments with allocated units
  Then I get the error "Cannot delete this remittance as units have already been allocated for payments"

Examples:
  | commitment                     | call                 | paid_percentage1         | paid_percentage2         | user |entity |
  | orig_folio_committed_amount_cents=100000000 | percentage_called=20 | 50 | 50 | first_name=Test |name=Urban;entity_type=Investment Fund |
