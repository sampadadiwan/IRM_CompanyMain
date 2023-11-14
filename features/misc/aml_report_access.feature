
Feature: Access
  Can access models as a company

Scenario Outline: Access Aml Report as company admin
  Given there is a user "<user>" for an entity "<entity>"
  Given the user has role "<role>"
  Given the entity "<entity>" has aml enabled "<aml_enabled>"
  Given there is an existing investor "" with "1" users
  Given the investor has investor kyc and aml report
  Then "<user>" has "<boolean>" "<crud>" access to the aml_report of investor

  Examples:
  	|user	               |entity               |role |crud|boolean|aml_enabled|
  	|first_name=AdminUser|entity_type=Investment Fund;name=TestCompany901  |company_admin|"index,show,toggle_approved,generate_new"|true|true|# not relevant as we have removed admin condition for now
  	|first_name=AdminUser|entity_type=Investment Fund;name=TestCompany902 |company_admin|"index,show,toggle_approved,generate_new"|false|false|
    |first_name=approver  |entity_type=Investment Fund;name=TestCompany903  |approver |"index,show,toggle_approved,generate_new"|true|true|
    |first_name=signatory  |entity_type=Investment Fund;name=TestCompany904  |signatory |"index,show,toggle_approved,generate_new"|true|true|

Scenario Outline: Access Aml Report as Other User
  Given there is a user "<user>" for an entity "<entity>"
  And the user has role "<role>"
  Given there is an existing investor "" with "1" users
  Given the investor has investor kyc and aml report
  Given there is another user "<another_user>" for another entity "entity_type=Consulting"
  Then "<another_user>" has "<boolean>" "<crud>" access to the aml_report of investor

  Examples:
  |user	               |entity               |role |crud|another_user|boolean|
  |first_name=AdminUser|entity_type=Investment Fund;name=TestCompany877  |company_admin|"index,show,create,toggle_approved,generate_new"|first_name=Investor21|false|
  |first_name=approver  |entity_type=Investment Fund;name=TestCompany867  |approver |"index,show,create,toggle_approved,generate_new"|first_name=Investor22|false|
  |first_name=signatory  |entity_type=Investment Fund;name=TestCompany887  |signatory |"index,show,create,toggle_approved,generate_new"|first_name=Investor23|false|

Scenario Outline: Auto Create new Aml Report
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given the entity "<entity>" has aml enabled "true"
  Given there is an existing investor "" with "1" users
  Then investor kyc and aml report is generated for it

  Examples:
  |user	    |entity                      |fund                	|
  |  	      |entity_type=Investment Fund |name=Test fund|

Scenario Outline: Do not Create new Aml Report with blank name
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given the entity "<entity>" has aml enabled "true"
  Given there is an existing investor "" with "1" users
  Then investor kyc and aml report is not generated for it

  Examples:
  |user	    |entity                       |fund                	|
  |  	      |entity_type=Investment Fund  |name=Test fund|
