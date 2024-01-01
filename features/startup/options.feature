Feature: Option
  Can create and view esop pools

Scenario Outline: Create Options pool
  Given Im logged in as a user "" for an entity "<entity>"
  And the user has role "approver"
  And I am at the Option Pools page
  When I create a new esop pool "<option_pool>"
  Then I should see the "Option pool was successfully created."
  And an esop pool should be created
  And I should see the esop pool details on the details page
  And I should see the esop pool in all esop pools page
  And the trust company must have no investment
  And when I approve the esop pool in the UI
  Then the trust company must have the investment
Examples:
    |entity               |option_pool                                                         |
    |entity_type=Company  |name=Pool 123;number_of_options=10000;excercise_price_cents=2000  |
    |entity_type=Company  |name=Pool 567;number_of_options=80000;excercise_price_cents=3000  |



Scenario Outline: Create Options pool
  Given there is a user "" for an entity "<entity>"
  Given a esop pool "<option_pool>" is created with vesting schedule "<schedule>"
  Then an esop pool should be created
  And the corresponding funding round is created for the pool
  And the vesting schedule must also be created
Examples:
    |entity               |option_pool                                                         |schedule      |
    |entity_type=Company  |name=Pool 123;number_of_options=10000;excercise_price_cents=2000;approved=false  |12:100        |
    |entity_type=Company  |name=Pool 567;number_of_options=80000;excercise_price_cents=3000;approved=false  |12:50,24:50   |
    |entity_type=Company  |name=Pool 567;number_of_options=80000;excercise_price_cents=3000;approved=false  |12:20,24:30,36:50   |


Scenario Outline: Create Options pool fails
  Given there is a user "" for an entity "<entity>"
  Given a esop pool "<option_pool>" is created with vesting schedule "<schedule>"
  Then an esop pool should not be created
Examples:
    |entity               |option_pool                                                         |schedule      |
    |entity_type=Company  |name=Pool 123;number_of_options=10000;excercise_price_cents=2000  |12:80         |
    |entity_type=Company  |name=Pool 123;number_of_options=10000;excercise_price_cents=2000  |12:20,24:20   |
    |entity_type=Company  |name=Pool 123;number_of_options=10000;excercise_price_cents=2000  |12:180        |



Scenario Outline:  Options Approved
  Given there is a user "" for an entity "<entity>"
  Given a esop pool "<option_pool>" is created with vesting schedule "<schedule>"
  Given there are "1" employee investors
  And there is an option holding "approved=true;orig_grant_quantity=1000;investment_instrument=Options;option_type=Regular" for each employee investor
  And the option grant date is "<months>" ago
  Then the option pool must have "<option_pool_quantites>"
  Then the option holding must have "<holding_quantites>"
  And the investment total quantity must be "10000"
  And the trust esop holdings must be reduced by "1000"

Examples:
    |entity               |option_pool                                      |schedule            | months  | option_pool_quantites | holding_quantites |
    
    |entity_type=Company  |number_of_options=10000;excercise_period_months=98|12:20,24:30,36:50  | 12      | allocated_quantity=1000;vested_quantity=200;net_unvested_quantity=800;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=200     | quantity=1000;vested_quantity=200;net_unvested_quantity=800;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=200 |

    |entity_type=Company  |number_of_options=10000;excercise_period_months=90|12:20,24:30,36:50  | 24      | allocated_quantity=1000;vested_quantity=500;net_unvested_quantity=500;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=500     | quantity=1000;vested_quantity=500;net_unvested_quantity=500;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=500 |
    
    |entity_type=Company  |number_of_options=10000;excercise_period_months=98|12:20,24:30,36:50  | 36      | allocated_quantity=1000;vested_quantity=1000;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=1000    | quantity=1000;vested_quantity=1000;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=1000  |



Scenario Outline: Import holdings to pool
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
  Given a esop pool "name=Pool 1" is created with vesting schedule "12:20,24:30,36:50"
  And Given I upload a holdings file
  Then I should see the "Import in progress"
  And when the holdings are approved
  And the pool granted amount should be "700"


Scenario Outline:  Options vested
  Given there is a user "" for an entity "<entity>"
  Given a esop pool "<option_pool>" is created with vesting schedule "<schedule>"
  Given there are "1" employee investors
  And there is an option holding "approved=true;orig_grant_quantity=1000;investment_instrument=Options;option_type=Regular" for each employee investor
  And the option grant date is "<months>" ago
  Then the option pool must have "<option_pool_quantites>"
  Then the option holding must have "<holding_quantites>"
Examples:
    |entity               |option_pool                            |schedule           | months | option_pool_quantites | holding_quantites |
    
    |entity_type=Company  |name=Pool 123;number_of_options=10000  |12:20,24:30,36:50  | 10     | allocated_quantity=1000;vested_quantity=0;net_unvested_quantity=1000;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=0    | quantity=1000;vested_quantity=0;net_unvested_quantity=1000;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=0     |
    
    |entity_type=Company  |name=Pool 123;number_of_options=10000  |12:20,24:30,36:50  | 12     | allocated_quantity=1000;vested_quantity=200;net_unvested_quantity=800;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=200   | quantity=1000;vested_quantity=200;net_unvested_quantity=800;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=200    |
    
    |entity_type=Company  |name=Pool 567;number_of_options=80000  |12:20,24:30,36:50  | 24     | allocated_quantity=1000;vested_quantity=500;net_unvested_quantity=500;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=500  | quantity=1000;vested_quantity=500;net_unvested_quantity=500;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=500    |
    
    |entity_type=Company  |name=Pool 567;number_of_options=80000  |12:20,24:30,36:50  | 36     | allocated_quantity=1000;vested_quantity=1000;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=1000 | quantity=1000;vested_quantity=1000;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=1000     |


Scenario Outline:  Options lapsed
  Given there is a user "" for an entity "<entity>"
  Given a esop pool "<option_pool>" is created with vesting schedule "<schedule>"
  Given there are "1" employee investors
  And there is an option holding "approved=true;orig_grant_quantity=1000;investment_instrument=Options;option_type=Regular" for each employee investor
  And the option grant date is "<months>" ago
  Then the option holding must have "<holding_quantites>"
  Then the option pool must have "<option_pool_quantites>"
  
Examples:
    |entity               |option_pool                    |schedule           | months  | option_pool_quantites | holding_quantites | 
    
    |entity_type=Company  |excercise_period_months=12;number_of_options=10000|12:20,24:30,36:50  | 10      | allocated_quantity=1000;vested_quantity=0;net_unvested_quantity=1000;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=0  | quantity=1000;vested_quantity=0;net_unvested_quantity=1000;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=0   | 
    
    |entity_type=Company  |excercise_period_months=12;number_of_options=10000|12:20,24:30,36:50  | 12      | allocated_quantity=1000;vested_quantity=200;net_unvested_quantity=800;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=200  | quantity=1000;vested_quantity=200;net_unvested_quantity=800;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=200   |
    
    |entity_type=Company  |excercise_period_months=12;number_of_options=10000|12:20,24:30,36:50  | 24      | allocated_quantity=800;vested_quantity=500;net_unvested_quantity=500;lapsed_quantity=200;excercised_quantity=0;net_avail_to_excercise_quantity=300 | quantity=800;vested_quantity=500;net_unvested_quantity=500;lapsed_quantity=200;excercised_quantity=0;net_avail_to_excercise_quantity=300 |
    
    |entity_type=Company  |excercise_period_months=12;number_of_options=10000|12:20,24:30,36:50  | 36      | allocated_quantity=500;vested_quantity=1000;net_unvested_quantity=0;lapsed_quantity=500;excercised_quantity=0;net_avail_to_excercise_quantity=500 | quantity=500;vested_quantity=1000;net_unvested_quantity=0;lapsed_quantity=500;excercised_quantity=0;net_avail_to_excercise_quantity=500 |


Scenario Outline:  Options Excercised
  Given there is a user "" for an entity "<entity>"
  Given a esop pool "<option_pool>" is created with vesting schedule "<schedule>"
  Given there are "1" employee investors
  And there is an option holding "approved=true;orig_grant_quantity=1000;investment_instrument=Options;option_type=Regular" for each employee investor
  And the option grant date is "<months>" ago
  Then the investment total quantity must be "10000"
  Then when the option is excercised "approved=false"
  And the excercise is approved
  Then the option pool must have "<option_pool_quantites>"
  Then the option holding must have "<holding_quantites>"
  And the new investment and holding must be created with excercised quantity
  And the investment total quantity must be "10000"
  And the trust esop holdings must be reduced by "1000"

Examples:
    |entity               |option_pool                                      |schedule            | months  | option_pool_quantites | holding_quantites |
    
    |entity_type=Company  |number_of_options=10000;excercise_period_months=98|12:20,24:30,36:50  | 12      | allocated_quantity=1000;vested_quantity=200;net_unvested_quantity=800;lapsed_quantity=0;excercised_quantity=200;net_avail_to_excercise_quantity=0     | quantity=800;vested_quantity=200;net_unvested_quantity=800;lapsed_quantity=0;excercised_quantity=200;net_avail_to_excercise_quantity=0 |

    |entity_type=Company  |number_of_options=10000;excercise_period_months=90|12:20,24:30,36:50  | 24      | allocated_quantity=1000;vested_quantity=500;net_unvested_quantity=500;lapsed_quantity=0;excercised_quantity=500;net_avail_to_excercise_quantity=0     | quantity=500;vested_quantity=500;net_unvested_quantity=500;lapsed_quantity=0;excercised_quantity=500;net_avail_to_excercise_quantity=0 |
    
    |entity_type=Company  |number_of_options=10000;excercise_period_months=98|12:20,24:30,36:50  | 36      | allocated_quantity=1000;vested_quantity=1000;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=1000;net_avail_to_excercise_quantity=0    | quantity=0;vested_quantity=1000;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=1000;net_avail_to_excercise_quantity=0  |



Scenario Outline:  Options cancelled
  Given there is a user "" for an entity "<entity>"
  Given a esop pool "<option_pool>" is created with vesting schedule "<schedule>"
  Given there are "1" employee investors
  And there is an option holding "approved=true;orig_grant_quantity=1000;investment_instrument=Options;option_type=Regular" for each employee investor
  And the option grant date is "<months>" ago
  And the option is cancelled "<cancel>"
  Then the option holding must have "<holding_quantites>"
  Then the option pool must have "<option_pool_quantites>"
  And the investment total quantity must be "10000"
  
Examples:
    |entity               |option_pool                    |schedule           | months  | option_pool_quantites | holding_quantites | cancel | subject |
    
    |entity_type=Company  |excercise_period_months=120;number_of_options=10000|12:20,24:30,36:50  | 12      | allocated_quantity=0;vested_quantity=200;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=0  | quantity=0;vested_quantity=200;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=0;cancelled_quantity=1000;unexcercised_cancelled_quantity=200;unvested_cancelled_quantity=800   | all | Your Options have been Cancelled |
    
    |entity_type=Company  |excercise_period_months=120;number_of_options=10000|12:20,24:30,36:50  | 12      | allocated_quantity=200;vested_quantity=200;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=200  | quantity=200;vested_quantity=200;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=200;cancelled_quantity=800;unexcercised_cancelled_quantity=0;unvested_cancelled_quantity=800   | unvested | Your Options have been Cancelled |
    
    |entity_type=Company  |excercise_period_months=120;number_of_options=10000|12:20,24:30,36:50  | 24      | allocated_quantity=0;vested_quantity=500;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=0  | quantity=0;vested_quantity=500;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=0;cancelled_quantity=1000;unexcercised_cancelled_quantity=500;unvested_cancelled_quantity=500   | all | Your Options have been Cancelled |
    
    |entity_type=Company  |excercise_period_months=120;number_of_options=10000|12:20,24:30,36:50  | 24      | allocated_quantity=500;vested_quantity=500;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=500  | quantity=500;vested_quantity=500;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=500;cancelled_quantity=500;unexcercised_cancelled_quantity=0;unvested_cancelled_quantity=500   | unvested | Your Options have been Cancelled |

    |entity_type=Company  |excercise_period_months=240;number_of_options=10000|12:20,24:30,36:50  | 36      | allocated_quantity=0;vested_quantity=1000;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=0 | quantity=0;vested_quantity=1000;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=0;cancelled_quantity=1000;unexcercised_cancelled_quantity=0;unvested_cancelled_quantity=1000 | all | Your Options have been Cancelled |
    
    |entity_type=Company  |excercise_period_months=360;number_of_options=10000|12:20,24:30,36:50  | 36      | allocated_quantity=1000;vested_quantity=1000;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=1000 | quantity=1000;vested_quantity=1000;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=0;net_avail_to_excercise_quantity=1000;cancelled_quantity=0;unexcercised_cancelled_quantity=0;unvested_cancelled_quantity=1000 | unvested | Your Options have been Cancelled |



Scenario Outline:  Options Excercised, Cancelled and Lapsed
  Given there is a user "" for an entity "<entity>"
  Given a esop pool "<option_pool>" is created with vesting schedule "<schedule>"
  Given there are "1" employee investors
  And there is an option holding "approved=true;orig_grant_quantity=1000;investment_instrument=Options;option_type=Regular" for each employee investor
  And the option grant date is "<months>" ago
  Then the investment total quantity must be "10000"
  Then when the option is excercised "approved=false;quantity=10"
  And the excercise is approved
  And the option is cancelled "unvested"
  Then the option pool must have "<option_pool_quantites>"
  Then the option holding must have "<holding_quantites>"
  And the new investment and holding must be created with excercised quantity
  And the investment total quantity must be "10000"
  And the trust esop holdings must be reduced by "<trust_quantity>"

Examples:
    |entity               |option_pool                                      |schedule            | months  | option_pool_quantites | holding_quantites | trust_quantity |
    
    |entity_type=Company  |number_of_options=10000;excercise_period_months=98|12:20,24:30,36:50  | 12      | allocated_quantity=200;vested_quantity=200;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=10;net_avail_to_excercise_quantity=190     | quantity=200;vested_quantity=200;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=10;net_avail_to_excercise_quantity=190 | 200 |

    |entity_type=Company  |number_of_options=10000;excercise_period_months=90|12:20,24:30,36:50  | 24      | allocated_quantity=500;vested_quantity=500;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=10;net_avail_to_excercise_quantity=490     | quantity=500;vested_quantity=500;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=10;net_avail_to_excercise_quantity=490 | 500 |

    |entity_type=Company  |number_of_options=10000;excercise_period_months=12|12:20,24:30,36:50  | 24      | allocated_quantity=300;vested_quantity=500;net_unvested_quantity=0;lapsed_quantity=200;excercised_quantity=10;net_avail_to_excercise_quantity=290     | quantity=300;vested_quantity=500;net_unvested_quantity=0;lapsed_quantity=200;excercised_quantity=10;net_avail_to_excercise_quantity=290 | 300 |


    |entity_type=Company  |number_of_options=10000;excercise_period_months=98|12:20,24:30,36:50  | 36      | allocated_quantity=1000;vested_quantity=1000;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=10;net_avail_to_excercise_quantity=990    | quantity=990;vested_quantity=1000;net_unvested_quantity=0;lapsed_quantity=0;excercised_quantity=10;net_avail_to_excercise_quantity=990  | 1000 |

    |entity_type=Company  |number_of_options=10000;excercise_period_months=12|12:20,24:30,36:50  | 36      | allocated_quantity=500;vested_quantity=1000;net_unvested_quantity=0;lapsed_quantity=500;excercised_quantity=10;net_avail_to_excercise_quantity=490     | quantity=490;vested_quantity=1000;net_unvested_quantity=0;lapsed_quantity=500;excercised_quantity=10;net_avail_to_excercise_quantity=490 | 500 |
