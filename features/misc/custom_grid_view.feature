Feature: Grid View Preferences
  Can create custom grid views

Scenario Outline: Create custom grid view for Investors
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the form type page
  When I create a form type and custom grid view for "Investor"
  When I select each option and click Add
  And I visit Investor Page and find 6 columns in the grid
	When I visit Custom Grid View page and uncheck "Category"
	Given I should not find "Category" column in the Investor Grid

Examples:
  |user	      |entity|
  |  	        |entity_type=Company|

Scenario Outline: Create custom grid view for PortfolioInvestments
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the form type page
  When I create a form type and custom grid view for "PortfolioInvestment"
  When I select each option and click Add
  And I visit PortfolioInvestment Page and find 6 columns in the grid
  When I visit Custom Grid View page and uncheck "amount"
  And I should not find "amount" column in the Portfolio Investment Grid

Examples:
  |user       |entity|
  |           |entity_type=Company|

Scenario Outline: Create custom AG grid view for PortfolioInvestments
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the form type page
  And I create a derived field "PortfolioInvestment"
  When I visit Portfolio Investment AG Grid and find the derived field

Examples:
  |user       |entity|
  |           |entity_type=Company|

Scenario Outline: Create custom grid view for PortfolioInvestments Reports
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the reports page
  When I create a report and custom grid view for "PortfolioInvestment"
  When I select each option and click Add
  And I visit PortfolioInvestment Page from reports
  When I visit Report Custom Grid View page and uncheck "amount"
  And I should not find "amount" column in the Report PI Grid

Examples:
  |user       |entity|
  |           |entity_type=Company|

Scenario Outline: Create custom grid view for AggregatePortfolioInvestments
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the form type page
  When I create a form type and custom grid view for "AggregatePortfolioInvestment"
  When I select each option and click Add
  And I visit AggregatePortfolioInvestment Page and find 6 columns in the grid
  When I visit Custom Grid View page and uncheck "investment_instrument"
  And I should not find "investment_instrument" column in the Investor Grid

Examples:
  |user       |entity|
  |           |entity_type=Company|

Scenario Outline: Create custom grid view for CapitalCommitment
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the form type page
  When I create a form type and custom grid view for "CapitalCommitment"
  When I select each option and click Add
  And I visit CapitalCommitment Page and find 6 columns in the grid
  When I visit Custom Grid View page and uncheck "investor_name"
  And I should not find "investor_name" column in the Investor Grid

Examples:
  |user       |entity|
  |           |entity_type=Company|

Scenario Outline: Create custom grid view for InvestorKyc
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the form type page
  When I create a form type and custom grid view for "InvestorKyc"
  When I select each option and click Add
  And I visit InvestorKyc Page and find 6 columns in the grid
  When I visit Custom Grid View page and uncheck "kyc"
  And I should not find "kyc" column in the Investor Grid

Examples:
  |user       |entity|
  |           |entity_type=Company|

Scenario Outline: Create custom grid view for FundUnitSetting
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the form type page
  When I create a form type and custom grid view for "FundUnitSetting"
  When I select each option and click Add
  And I visit FundUnitSetting Page and find columns in the grid
  When I visit Custom Grid View page and uncheck "isin"
  And I should not find "isin" column in the Investor Grid

Examples:
  |user       |entity|
  |           |entity_type=Company|


Scenario Outline: Create custom grid view for CapitalRemittance, CapitalCall, Offer, FundRatio, FundReport, KpiReport
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the form type page
  When I create a form type and custom grid view for "<class_name>"
  When I select each option and click Add
  And I visit "<class_name>" Page and find columns in the grid
  When I visit Custom Grid View page and uncheck "<uncheck_column>"
  And I should not find "<uncheck_column>" column in the "<class_name>" Grid

Examples:
  |user       |entity             | class_name |uncheck_column|
  |           |entity_type=Company|CapitalRemittance|Payment_Date|
  |           |entity_type=Company|CapitalCall|Collected_Amount|
  |           |entity_type=Company|FundReport|Name_Of_Scheme|
  |           |entity_type=Company|FundRatio|Display_Value|
  |           |entity_type=Company|KpiReport|Period|
  |           |entity_type=Company|Offer|Allocation_Quantity|
