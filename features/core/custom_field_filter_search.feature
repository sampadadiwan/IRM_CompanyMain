@form_custom_fields
Feature: Custom Field Filter Search
  Entity admins can mark FormCustomFields as "Show in Filter" so users can
  search records by their custom field values directly in the filter panel.

Scenario: Admin enables a text custom field for filtering and user sees the row
  Given Im logged in as a user "" for an entity "name=TestFund;entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given there is a FormType "name=CapitalCommitment;tag=Default"
  Given the form type has a filterable text field "source_of_funds" labelled "Source of Funds"
  Given there is an existing fund "name=FilterFund"
  Given there is an existing investor "investor_name=Investor A"
  Given there is an existing capital commitment "committed_amount=100000;json_fields=source_of_funds:Savings" for "FilterFund" and "Investor A"
  Given there is an existing capital commitment "committed_amount=200000;json_fields=source_of_funds:Inheritance" for "FilterFund" and "Investor A"
  When I visit the capital commitments index with filter open
  Then I should see a filter row labelled "Source of Funds"

Scenario: User filters capital commitments by a text custom field
  Given Im logged in as a user "" for an entity "name=TestFund;entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given there is a FormType "name=CapitalCommitment;tag=Default"
  Given the form type has a filterable text field "source_of_funds" labelled "Source of Funds"
  Given there is an existing fund "name=FilterFund"
  Given there is an existing investor "investor_name=Investor A"
  Given there is an existing capital commitment "committed_amount=100000;json_fields=source_of_funds:Savings" for "FilterFund" and "Investor A"
  Given there is an existing capital commitment "committed_amount=200000;json_fields=source_of_funds:Inheritance" for "FilterFund" and "Investor A"
  When I filter capital commitments by "source_of_funds" contains "Savings"
  Then I should see "1" capital commitment in the results
  And the result should contain committed amount "100,000"
  And the result should not contain committed amount "200,000"

Scenario: User filters capital commitments by a select custom field
  Given Im logged in as a user "" for an entity "name=TestFund;entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given there is a FormType "name=CapitalCommitment;tag=Default"
  Given the form type has a filterable select field "investment_stage" labelled "Investment Stage" with options "Seed,Series A,Series B"
  Given there is an existing fund "name=FilterFund"
  Given there is an existing investor "investor_name=Investor A"
  Given there is an existing capital commitment "committed_amount=100000;json_fields=investment_stage:Seed" for "FilterFund" and "Investor A"
  Given there is an existing capital commitment "committed_amount=200000;json_fields=investment_stage:Series A" for "FilterFund" and "Investor A"
  When I filter capital commitments by "investment_stage" equals "Seed"
  Then I should see "1" capital commitment in the results
  And the result should contain committed amount "100,000"

Scenario: Filterable fields from multiple form types appear together
  Given Im logged in as a user "" for an entity "name=TestFund;entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given there is a FormType "name=CapitalCommitment;tag=Default"
  Given the form type has a filterable text field "source_of_funds" labelled "Source of Funds"
  Given there is a second FormType "name=CapitalCommitment;tag=Alt"
  Given the second form type has a filterable text field "risk_profile" labelled "Risk Profile"
  When I visit the capital commitments index with filter open
  Then I should see a filter row labelled "Source of Funds"
  And I should see a filter row labelled "Risk Profile"

Scenario: Duplicate field name across form types shows only one filter row
  Given Im logged in as a user "" for an entity "name=TestFund;entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given there is a FormType "name=CapitalCommitment;tag=Default"
  Given the form type has a filterable text field "source_of_funds" labelled "Source of Funds"
  Given there is a second FormType "name=CapitalCommitment;tag=Alt"
  Given the second form type has a filterable text field "source_of_funds" labelled "Source of Funds"
  When I visit the capital commitments index with filter open
  Then I should see exactly "1" filter row labelled "Source of Funds"

Scenario: File and Calculation fields do not appear in filter even if filter_in_search is set
  Given Im logged in as a user "" for an entity "name=TestFund;entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given there is a FormType "name=CapitalCommitment;tag=Default"
  Given the form type has a non-filterable "File" field "attachment" labelled "Attachment"
  Given the form type has a non-filterable "Calculation" field "calc_result" labelled "Calc Result"
  When I visit the capital commitments index with filter open
  Then I should not see a filter row labelled "Attachment"
  And I should not see a filter row labelled "Calc Result"

Scenario: Partial date range fill applies only the provided bound
  Given Im logged in as a user "" for an entity "name=TestFund;entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given there is a FormType "name=CapitalCommitment;tag=Default"
  Given the form type has a filterable date field "kyc_date" labelled "KYC Date"
  Given there is an existing fund "name=FilterFund"
  Given there is an existing investor "investor_name=Investor A"
  Given there is an existing capital commitment "committed_amount=100000;json_fields=kyc_date:2025-03-01" for "FilterFund" and "Investor A"
  Given there is an existing capital commitment "committed_amount=200000;json_fields=kyc_date:2024-01-01" for "FilterFund" and "Investor A"
  When I filter capital commitments by "kyc_date" from "2025-01-01" to ""
  Then I should see "1" capital commitment in the results
  And the result should contain committed amount "100,000"
