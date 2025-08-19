Feature: Kyc Sebi fields

@import
Scenario Outline: Import KYCs - with Form Tag
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C1" for the entity
  Given there is a FormType "name=IndividualKyc;tag=Default" with custom fields "Fathers Name, Mothers Name, Age, Agreement Unit Type,Custom Field 1, Custom field 2"
  Given there is a FormType "name=IndividualKyc;tag=Gift City" with custom fields "Gift City ID, Agreement Unit Type, Custom Field 1, Custom field 2"
  Given there is a FormType "name=NonIndividualKyc;tag=Default" with custom fields "Agreement Unit Type, Custom Field 1, Custom field 2"
  And Given I upload an investors file for the fund
  And Given import file "investor_kycs_with_tags.xlsx" for "InvestorKyc"
  Then There should be "4" investor kycs created
  And the investor kycs must have the data in the sheet "investor_kycs_with_tags.xlsx"
  And there are "2" records for the form type "IndividualKyc"
  And there are "1" records for the form type "NonIndividualKyc"



@import
Scenario Outline: Import KYCs - No Form Tag
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C1" for the entity
  And Given I upload an investors file for the fund
  And Given import file "investor_kycs.xlsx" for "InvestorKyc"
  Then There should be "4" investor kycs created
  And the investor kycs must have the data in the sheet "investor_kycs.xlsx"
  And there are "1" records for the form type "IndividualKyc"
  And there are "1" records for the form type "NonIndividualKyc"

