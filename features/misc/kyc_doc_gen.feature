Feature: KYC DOC Generation
  Can Generate documents for a KYC


Scenario Outline: Generate KYC document
  Given Im logged in as a user "first_name=Testuser" for an entity "name=Urban1;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing investor "investor_name=Investor 11"
  Given I create a new InvestorKyc "PAN=ABCDE1234F;full_name=Some Name" to trigger aml report generation
  Then I should see the "Investor kyc was successfully saved."
  Given I go to view the KYC
  Given I click on "Verify"
  Then I should see the "Investor kyc was successfully verified."
  Given There is a folder "KYC Templates" for the KYC
  Given there is a template "KYC Template1" in folder "KYC Templates"
  Given I go to view the KYC
  Given I click on "KYC Actions"
  Given I click on "Generate Docs"
  Given I fill in the kyc doc gen details
  Given I click on "Generate Now"
  Then I should see the "Document generation in progress. Please check back in a few minutes."
  Then the document should be successfully generated for the KYC
