Feature: Access
  Can access models as a company

Scenario Outline: Access Aml Report as company admin
  Given there is a user "<user>" for an entity "<entity>"
  Given the user has role "<role>"
  Given the entity "<entity>" has aml enabled "<aml_enabled>"
  Given there is an investor "<investor>" with investor kyc and aml report for the entity "<entity>"
  Then "<user>" has "<boolean>" "<crud>" access to the aml_report of investor "<investor>"

  Examples:
  	|user	               |entity               |role |crud|investor|boolean|aml_enabled|
  	|first_name=AdminUser|entity_type=Company;name=TestCompany901  |company_admin|"index,show,toggle_approved,generate_new"|investor_name=Investor101|true|true|# not relevant as we have removed admin condition for now
  	|first_name=AdminUser|entity_type=Company;name=TestCompany902 |company_admin|"index,show,toggle_approved,generate_new"|investor_name=Investor102|false|false|
    |first_name=approver  |entity_type=Company;name=TestCompany903  |approver |"index,show,toggle_approved,generate_new"|investor_name=Investor202|true|true|
    |first_name=signatory  |entity_type=Company;name=TestCompany904  |signatory |"index,show,toggle_approved,generate_new"|investor_name=Investor302|true|true|

Scenario Outline: Access Aml Report as Other User
  Given there is a user "<user>" for an entity "<entity>"
  And the user has role "<role>"
  Given there is an investor "<investor>" with investor kyc and aml report for the entity "<entity>"
  Given there is another user "<another_user>" for another entity "entity_type=Consulting"
  Then "<another_user>" has "false" "<crud>" access to the aml_report of investor "<investor>"

  Examples:
  |user	               |entity               |role |crud|investor|another_user|
  |first_name=AdminUser|entity_type=Company;name=TestCompany801  |company_admin|"index,show,create,toggle_approved,generate_new"|investor_name=Investor112|first_name=Investor21|
  |first_name=approver  |entity_type=Company;name=TestCompany802  |approver |"index,show,create,toggle_approved,generate_new"|investor_name=Investor212|first_name=Investor22|
  |first_name=signatory  |entity_type=Company;name=TestCompany803  |signatory |"index,show,create,toggle_approved,generate_new"|investor_name=Investor312|first_name=Investor23|

Scenario Outline: Auto Create new Aml Report
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given the entity "<entity>" has aml enabled "true"
  Then there is an investor "<investor>" for the entity "<entity>" with investor kyc and aml report is generated for it

  Examples:
  |user	    |entity                                 |fund                	|investor|
  |  	      |entity_type=Investment Fund;enable_funds=true |name=Test fund|investor_name=Investor12|

Scenario Outline: Do not Create new Aml Report with blank name
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given the entity "<entity>" has aml enabled "true"
  Then there is an investor "<investor>" for the entity "<entity>" with investor kyc and aml report is not generated for it

  Examples:
  |user	    |entity                                 |fund                	|investor|
  |  	      |entity_type=Investment Fund;enable_funds=true |name=Test fund|investor_name=Investor12|


