Feature: Fund Ratio Access
  Can access fund ratios as a company

Scenario Outline: Access Fund Ratios as company admin
  Given there is a user "<user>" for an entity "<entity>"
  Given the user has role "<role>"
  Given there is a fund "name=Test fund" for the entity
  Given the fund has fund ratios
  Then "<user>" has "<boolean>" "<crud>" access to the fund_ratios

  Examples:
  	|user	               |entity               |role |crud|investor|boolean|
  	|first_name=AdminUser|entity_type=Company;name=TestCompany123  |company_admin|"index,show"|investor_name=Investor12|true|
  	|first_name=AdminUser|entity_type=Company;name=TestCompany123  |company_admin|"create,new,update,edit,destroy"|investor_name=Investor12|false|
    |first_name=approver  |entity_type=Company;name=TestCompany223  |approver |"index,show"|investor_name=Investor22|true|
    |first_name=approver  |entity_type=Company;name=TestCompany223  |approver |"create,new,update,edit,destroy"|investor_name=Investor22|false|
    |first_name=signatory  |entity_type=Company;name=TestCompany323  |signatory |"index,show"|investor_name=Investor32|true|
    |first_name=signatory  |entity_type=Company;name=TestCompany323  |signatory |"create,new,update,edit,destroy"|investor_name=Investor32|false|

Scenario Outline: Access Fund Ratios as Other User
  Given there is a user "<user>" for an entity "<entity>"
  And the user has role "<role>"
  Given there is a fund "name=Test fund" for the entity
  Given the fund has fund ratios
  Given there is another user "<another_user>" for another entity "entity_type=Consulting"
  Then "<another_user>" has "false" "<crud>" access to the fund_ratios

  Examples:
  |user	               |entity               |role |crud|investor|another_user|
  |first_name=AdminUser|entity_type=Company;name=TestCompany123  |company_admin|"show,create,new,update,edit,destroy"|investor_name=Investor12|first_name=Investor2|
  |first_name=approver  |entity_type=Company;name=TestCompany223  |approver |"show,create,new,update,edit,destroy"|investor_name=Investor22|first_name=Investor2|
  |first_name=signatory  |entity_type=Company;name=TestCompany323  |signatory |"show,create,new,update,edit,destroy"|investor_name=Investor32|first_name=Investor2|
