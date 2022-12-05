Feature: Holdings
  Employee can view holdings

Scenario Outline:  Options Acknowledged
  Given there is a user "" for an entity "<entity>"
  Given a esop pool "<option_pool>" is created with vesting schedule "<schedule>"
  Given there are "1" employee investors
  And there is an option holding "approved=true;orig_grant_quantity=1000;investment_instrument=Options" for each employee investor
  Given Im logged in as the employee investor
  When I go to the dashboard I must see the employee holding
  When I acknowledge the holding
  Then the holding must be acknowledged

Examples:
    |entity               |option_pool                                      |schedule            |    
    |entity_type=Company  |number_of_options=10000;excercise_period_months=98|12:20,24:30,36:50  |
    |entity_type=Company  |number_of_options=10000;excercise_period_months=90|12:20,24:30,36:50  |    
    