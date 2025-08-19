Feature: RegulatoryCustomFields
  Test behavior of the RegulatoryCustomFields


Scenario Outline: Create investor kyc - with a Regulatory Custom Form and regulatory custom fields
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "name=Investor 1" with "1" users
  Given I go to add a new custom form
  Given I add a custom form for "IndividualKyc" with reg env "SEBI" and tag "SEBI"
  Then "SEBI" regulatory fields are added to the "IndividualKyc" form 
  Given I go to KYCs page
  Given I add a new "IndividualKyc" KYC with custom form tag "SEBI"
  Given I fill InvestorKyc details with regulatory fields "PAN=ABCD9876F;properties=sebi_investor_category:Domestic,sebi_investor_sub_category:NBFCs" with files "" for ""
  Then I should see the "Investor kyc was successfully saved."
  Then I should see the investor kyc details on the details page and regulatory fields "present"
  Given I go to add a new custom form
  Given I add a custom form for "IndividualKyc" with reg env "WRONG" and tag "WRONG"
  Then "" regulatory fields are added to the "IndividualKyc" form 
  Given I go to KYCs page
  Given I add a new "IndividualKyc" KYC with custom form tag "WRONG"
  Given I fill InvestorKyc details with regulatory fields "PAN=ABCD9876F" with files "" for ""
  Then I should see the "Investor kyc was successfully saved."
  Then I should see the investor kyc details on the details page and regulatory fields "absent"
  Given I log out
  When I log in as the investor user
  Given I go to KYCs page
  Given I edit the "first" kyc
  Given I fill InvestorKyc details with regulatory fields "PAN=ABCD9876F" with files "pan,address proof" for ""
  Then I should see the "Investor kyc was successfully saved."
  Then I should see the investor kyc details on the details page and regulatory fields "absent"

Scenario Outline: Create investment instrument - with a Regulatory Custom Form and regulatory custom fields
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
  Given I go to add a new custom form
  Given I add a custom form for "InvestmentInstrument" with reg env "SEBI" and tag "SEBI"
  Then "SEBI" regulatory fields are added to the "InvestmentInstrument" form 
  Given I go to PortfolioCompany show page
  Given I go to the Instruments tab
  Given I add a new Instrument with custom form tag "SEBI"
  And I fill the instrument form with the regulatory fields
  Then I should see the "Investment instrument was successfully created"
  Then I should see the Instrument details on the details page and regulatory fields "present"

  Given I go to add a new custom form
  Given I add a custom form for "InvestmentInstrument" with reg env "WRONG" and tag "WRONG"
  Then "" regulatory fields are added to the "InvestmentInstrument" form 
  Given I go to PortfolioCompany show page
  Given I go to the Instruments tab
  Given I add a new Instrument with custom form tag "WRONG"
  And I fill the instrument form without the regulatory fields
  Then I should see the "Investment instrument was successfully created"
  Then I should see the Instrument details on the details page and regulatory fields "absent"
  
  Examples:
    |entity                             |fund                |
    |entity_type=Investment Fund;       |name=Test fund      |

Scenario Outline: Create investment instrument - with a incorrect Regulatory Custom Form Reg Env and then correct the reg env and edit the instrument
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
  Given I go to add a new custom form
  Given I add a custom form for "InvestmentInstrument" with reg env "NOTSEBI" and tag "NOTSEBI"
  Then "" regulatory fields are added to the "InvestmentInstrument" form 
  Then "SEBI" regulatory fields are not added to the "InvestmentInstrument" form
  Given I go to PortfolioCompany show page
  Given I go to the Instruments tab
  Given I add a new Instrument with custom form tag "NOTSEBI"
  And I fill the instrument form without the regulatory fields
  Then I should see the "Investment instrument was successfully created"
  Then I should see the Instrument details on the details page and regulatory fields "absent"

  Given I go and edit the "InvestmentInstrument" custom form with tag "NOTSEBI" and url param "debug=true"
  Given I fill in the reg env with "SEBI" and save
  Then "SEBI" regulatory fields are added to the "InvestmentInstrument" form 
  Given I am using the last instrument created with the custom form tag "NOTSEBI"
  Given I go to see the Instrument details on the details page
  Then I should see "Sebi Reporting Fields"
  Given I go to edit the instrument created with the custom form tag "NOTSEBI"
  And I edit the instrument form with the regulatory fields
  Then I should see the "Investment instrument was successfully updated"
  Then I should see the Instrument details on the details page and regulatory fields "present"
  
  Examples:
    |entity                             |fund                |
    |entity_type=Investment Fund;       |name=Test fund      |

Scenario Outline: Create investor kyc - with a Regulatory Custom Form and regulatory custom fields and verify it and edit
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "name=Investor 1" with "1" users
  Given I go to add a new custom form
  Given I add a custom form for "IndividualKyc" with tag "SEBIFORM"
  Given I go the the form types index page
  And I click add "SEBI" reporting fields to "IndividualKyc" form from the dropdown  
  Then "SEBI" regulatory fields are added to the "IndividualKyc" form 
  Given I go to KYCs page
  Given I add a new "IndividualKyc" KYC with custom form tag "SEBI"
  Given I fill InvestorKyc details with regulatory fields "PAN=ABCD9876F;properties=sebi_investor_category:Domestic,sebi_investor_sub_category:NBFCs" with files "" for ""
  Then I should see the "Investor kyc was successfully saved."
  Then I should see the investor kyc details on the details page and regulatory fields "present"
  Given I verify the KYC
  Then I should see the "Investor kyc was successfully verified"
  Then I should see the investor kyc details on the details page and regulatory fields "present"
  Given I edit the reporting fields for the verified KYC
  Given I fill in the regulatory fields with "sebi_investor_category:Foreign,sebi_investor_sub_category:FPIs"    
  Then I should see the investor kyc details on the details page and regulatory fields "present"
  Given I log out
  When I log in as the investor user
  Given I go to KYCs page
  Given I edit the "last" kyc
  Then I should see the "Access Denied"
  Given The Kyc is unverified
  Given I edit the "last" kyc
  Given I fill InvestorKyc details with regulatory fields "PAN=ABCD9876F" with files "pan,address proof" for ""
  Then I should see the "Investor kyc was successfully saved."
  Then I should see the investor kyc details on the details page and regulatory fields "absent"
  Given I try to edit the reporting via URL
  Then I should see the "Access Denied"