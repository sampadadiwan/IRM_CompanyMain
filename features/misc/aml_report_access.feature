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
  	|first_name=AdminUser|entity_type=Company;name=TestCompany123  |company_admin|"index,show,toggle_approved,generate_new"|investor_name=Investor12|true|true|# not relevant as we have removed admin condition for now
  	|first_name=AdminUser|entity_type=Company;name=TestCompany123  |company_admin|"index,show,toggle_approved,generate_new"|investor_name=Investor12|false|false|
    |first_name=approver  |entity_type=Company;name=TestCompany223  |approver |"index,show,toggle_approved,generate_new"|investor_name=Investor22|true|true|
    |first_name=signatory  |entity_type=Company;name=TestCompany323  |signatory |"index,show,toggle_approved,generate_new"|investor_name=Investor32|true|true|

Scenario Outline: Access Aml Report as Other User
  Given there is a user "<user>" for an entity "<entity>"
  And the user has role "<role>"
  Given there is an investor "<investor>" with investor kyc and aml report for the entity "<entity>"
  Given there is another user "<another_user>" for another entity "entity_type=Consulting"
  Then "<another_user>" has "false" "<crud>" access to the aml_report of investor "<investor>"

  Examples:
  |user	               |entity               |role |crud|investor|another_user|
  |first_name=AdminUser|entity_type=Company;name=TestCompany123  |company_admin|"index,show,create,toggle_approved,generate_new"|investor_name=Investor12|first_name=Investor2|
  |first_name=approver  |entity_type=Company;name=TestCompany223  |approver |"index,show,create,toggle_approved,generate_new"|investor_name=Investor22|first_name=Investor2|
  |first_name=signatory  |entity_type=Company;name=TestCompany323  |signatory |"index,show,create,toggle_approved,generate_new"|investor_name=Investor32|first_name=Investor2|
