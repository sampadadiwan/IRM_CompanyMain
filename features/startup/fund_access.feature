Feature: Fund Access
  Can create and view a fund as a startup

Scenario Outline: Access fund
  Given there is a user "<user>" for an entity "<entity>"
  Given the user has role "<role>"
  Given there is a fund "name=Test fund" for the entity
  And I am "<given>" employee access to the fund
  Then user "<should>" have "<access>" access to the fund
  
  Examples:
  	|user	    |entity                                         |role           |given  |should	|access |
  	|  	        |entity_type=Investment Fund;enable_funds=true  |company_admin  |no    |true    |show,edit,update,destroy   |
    |  	        |entity_type=Investment Fund;enable_funds=true  |fund_manager   |no    |false  |show,edit,update,destroy   |
    |  	        |entity_type=Investment Fund;enable_funds=true  |fund_manager   |yes   |true   |show,edit,update,destroy      |
    


Scenario Outline: Access fund
  Given there is a user "<user>" for an entity "<entity>"
  Given the user has role "<role>"
  Given there is an existing investor "name=Arun Gupta"
  Given there is an existing investor "name=Brahmos Family"
  Given there is a fund "name=Test fund" for the entity
  And I am "<given>" employee access to the fund
  Given the fund has capital commitments from each investor
  Then user "<should>" have "<access>" access to the capital commitment
  Given the fund has "2" capital call
  Then user "<should>" have "<access>" access to the capital calls
  Given the capital calls are approved
  Then user "<should>" have "<access>" access to the capital remittances
  Given the fund has "2" capital distribution
  Then user "<should>" have "<access>" access to the capital distributions
  Given the capital distributions are approved
  Then user "<should>" have "<access>" access to the capital distribution payments
  
  Examples:
  	|user	    |entity                                         |role           |given  |should	|access |
  	|  	        |entity_type=Investment Fund;enable_funds=true  |company_admin  |no    |true    |show,edit,update,destroy   |
    |  	        |entity_type=Investment Fund;enable_funds=true  |fund_manager   |no    |false  |show,edit,update,destroy   |
    |  	        |entity_type=Investment Fund;enable_funds=true  |fund_manager   |yes   |true   |show,edit,update,destroy      |
    

Scenario Outline: Access fund
  Given there is a user "<user>" for an entity "<entity>"
  Given there is an existing investor "name=Arun Gupta;entity_type=Family Office"
  Given there is an existing investor entity "entity_type=Family Office" with employee "first_name=Investor"
  Given there is a fund "name=Test fund" for the entity
  And another user is "<given>" investor access to the fund
  Given the user has role "<role>"
  Given the fund has capital commitments from each investor
  Then user "<should>" have "<access>" access to his own capital commitment
  Given the fund has "2" capital call
  Then user "<should>" have "<access>" access to the capital calls
  Given the capital calls are approved
  Then user "<should>" have "<access>" access to his own capital remittances
  Given the fund has "2" capital distribution
  Then user "<should>" have "<access>" access to the capital distributions
  Given the capital distributions are approved
  Then user "<should>" have "<access>" access to his own capital distribution payments
  
  Examples:
  	|user	    |entity                                         |role           |given  |should	|access |
    |  	        |entity_type=Investment Fund;enable_funds=true  |investor   |no    |false  |show,edit,update,destroy   |
    |  	        |entity_type=Investment Fund;enable_funds=true  |investor   |yes   |true   |show  |
    |  	        |entity_type=Investment Fund;enable_funds=true  |investor   |yes   |false   |edit,update,destroy     |


