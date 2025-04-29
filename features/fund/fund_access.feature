Feature: Fund Access
  Can create and view a fund as a company

Scenario Outline: Access fund
  Given there is a user "<user>" for an entity "<entity>"
  Given the user has role "<role>"
  Given there is a fund "name=Test fund" for the entity
  And I am "<given>" employee access to the fund
  Then user "<should>" have "<access>" access to the fund
  
  Examples:
  	|user	    |entity                         |role           |given  |should	|access |
  	|  	        |entity_type=Investment Fund  |company_admin  |no    |true    |show,edit,update   |
    |  	        |entity_type=Investment Fund  |employee   |no    |false  |show,edit,update,destroy   |
    |  	        |entity_type=Investment Fund  |employee   |yes   |true   |show|
    |  	        |entity_type=Investment Fund  |employee   |yes   |false   |edit,update,destroy      |
    


Scenario Outline: Access fund & details as Employee
  Given there is a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "<role>"
  Given there is an existing investor ""
  Given there is an existing investor ""
  Given there is a fund "name=Test fund" for the entity
  And I am "<given>" employee access to the fund
  And the fund right has access "<crud>"  
  Then user "<should>" have "<access>" access to his own fund
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
  Given the fund has Fund Unit Settings
  Then user "<should>" have "<access>" access to the fund unit settings
  Given the fund has Fund Units
  Then user "<should>" have "<access>" access to the fund units
  Given the fund has "2" Fund Formulas
  Then user "<should>" have "<access>" access to the fund formulas
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
  Given there is an investment instrument for the portfolio company "name=Stock"
  Given there are "2" portfolio investments "quantity=200"
  Then user "<should>" have "<access>" access to the portfolio investments
  Then user "<should>" have "<access>" access to the aggregate portfolio investments
  Given the fund has "2" Fund Ratios
  Then user "<should>" have "<access>" access to the fund ratios
  
  
  Examples:
  	|role           |given |should |access                     | crud |
  	|company_admin  |no    |true   |show,edit,update,destroy   | |
    |company_admin  |yes   |true   |show,edit,update,destroy   | |
    |employee       |no    |false  |show,edit,update,destroy   | |
    |employee       |yes   |true   |show| |
    |employee       |yes   |false  |edit,update,destroy        | |
    |employee       |yes   |true   |show,update,destroy        | create,read,update,destroy |
        

Scenario Outline: Access fund & details as Investor
  Given there is a user "first_name=Mohith" for an entity "entity_type=Investment Fund"
  Given there is an existing investor "entity_type=Family Office"
  Given there is an existing investor entity "entity_type=Family Office" with employee "first_name=Investor"
  Given there is a fund "name=Test fund;show_portfolios=true;show_fund_ratios=true" for the entity
  And another user is "<given>" investor access to the fund
  Given the user has role "<role>"
  Then user "<given>" have "show" access to his own fund
  Given the fund has capital commitments from each investor
  Then user "<should>" have "<access>" access to his own capital commitment
  Given the fund has "2" capital call
  # Investors can no longer access calls
  Then user "false" have "<access>" access to the capital calls 
  Given the capital calls are approved
  Then user "<should>" have "<inv_access>" access to his own capital remittances
  Given the fund has "2" capital distribution
  Then user "false" have "<access>" access to the capital distributions
  Given the capital distributions are approved
  Then user "<should>" have "<access>" access to his own capital distribution payments
  Given the fund has Fund Unit Settings
  Then user "<should>" have "<access>" access to the fund unit settings
  Given the fund has Fund Units
  Then user "<should>" have "<access>" access to the fund units
  Given the fund has "2" Fund Formulas
  Then user "<should>" have "<access>" access to the fund formulas
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
  Given there is an investment instrument for the portfolio company "name=Stock"
  Given there are "2" portfolio investments "quantity=200"
  Then user "<should>" have "<access>" access to the portfolio investments
  Then user "<should>" have "<access>" access to the aggregate portfolio investments
  Given the fund has "2" Fund Ratios
  Then user "<should>" have "<access>" access to the fund ratios
  
  Examples:
  	|role       |given |should |access | inv_access |
    |investor   |no    |false  |show,edit,update,destroy| show,edit,update,destroy|
    |investor   |yes   |true   |show   | show  |
    |investor   |yes   |false  |edit,update,destroy| |


Scenario Outline: Access fund & details as Advisor
  Given there is a user "<user>" for an entity "<entity>"
  Given there is an existing investor "entity_type=Family Office"
  Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor"
  Given there is a fund "name=Test fund" for the entity
  And another user is "<given>" fund advisor access to the fund
  Given the user has role "<role>"
  Given the fund has capital commitments from each investor
  Then user "<should>" have "<access>" access to his own capital commitment
  Given the fund has "2" capital call
  Then user "<should>" have "<access>" access to the capital calls
  Given the capital calls are approved
  Then user "<should>" have "<inv_access>" access to his own capital remittances
  Given the fund has "2" capital distribution
  Then user "<should>" have "<access>" access to the capital distributions
  Given the capital distributions are approved
  Then user "<should>" have "<access>" access to his own capital distribution payments
  
  Examples:
  	|user	    |entity                         |role       |given  |should	|access | inv_access |
    |  	        |entity_type=Investment Fund  |employee   |no    |false  |show,edit,update,destroy   | show,edit,update,destroy |
    |  	        |entity_type=Investment Fund  |employee   |yes   |true   |show  | show |
    |  	        |entity_type=Investment Fund  |employee   |yes   |false   |edit,update,destroy     ||
    

Scenario Outline: Access fund & details as Investor Advisor
  Given there is a user "<user>" for an entity "<entity>"
  Given there is an existing investor "entity_type=Family Office"
  Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=IA"
  Given there is a fund "name=Test fund" for the entity
  And another user is "<given>" investor advisor access to the fund
  Given the user has role "<role>"
  Then user "<given>" have "show" access to his own fund
  Given the fund has capital commitments from each investor
  Then user "<should>" have "<access>" access to his own capital commitment
  Given the fund has "2" capital call
  Then user "false" have "<access>" access to the capital calls
  Given the capital calls are approved
  Then user "<should>" have "<inv_access>" access to his own capital remittances
  Given the fund has "2" capital distribution
  Then user "false" have "<access>" access to the capital distributions
  Given the capital distributions are approved
  Then user "<should>" have "<access>" access to his own capital distribution payments
  
  Examples:
  	|user	      |entity                       |role       |given |should |access | inv_access |
    |  	        |entity_type=Investment Fund  |investor   |no    |false  |show,edit,update,destroy| show,edit,update,destroy|
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show  | show|
    |  	        |entity_type=Investment Fund  |investor   |yes   |false   |edit,update,destroy     | |
    |  	        |entity_type=Investment Fund  |investor   |yes   |false   |     |edit,update |
    |  	        |entity_type=Investment Fund  |company_admin   |no    |false  |show,edit,update,destroy| show,edit,update,destroy|
    |  	        |entity_type=Investment Fund  |company_admin   |yes   |true   |show  | show|
    |  	        |entity_type=Investment Fund  |company_admin   |yes   |false   |edit,update,destroy     | |
    |  	        |entity_type=Investment Fund  |company_admin   |yes   |false   |     |edit,update |


Scenario Outline: Access fund & details as Advisor with update access
  Given there is a user "<user>" for an entity "<entity>"
  Given there is an existing investor "entity_type=Family Office"
  Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor"
  Given there is a fund "name=Test fund" for the entity
  And another user is "<given>" fund advisor access to the fund
  And the access right has access "<crud>"
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
  	|user	    |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show  | read |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |edit,update     | update |
    |  	       |entity_type=Investment Fund  |investor   |yes   |false   |destroy     | update |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |destroy     | destroy |
    # |  	        |entity_type=Investment Fund  |investor   |yes   |false   |edit,update     | destroy |


Scenario Outline: View Access Rights with Access to fund as Advisor with update
  Given there is a user "<user>" for an entity "<entity>"
  Given the user has role "<role>"
  Given there is an existing investor "entity_type=Family Office"
  Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor"
  Given there is a fund "name=Test fund" for the entity
  And another user is "<given>" investor access to the fund
  And the access right has access "<crud>"
  Given I log in as the first user
  Then user should see the access rights of the fund "<crud>"
  
  Examples:
  	|user	    |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |company_admin   |yes   |true   |show  | read |
    |  	        |entity_type=Investment Fund  |company_admin   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |