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

# fix-custom-field-filter-scoping — worked examples in openspec/changes/fix-custom-field-filter-scoping/report.md

# H1 — a number custom field filters as a number, not as text ("9" > "10")
Scenario: A number custom field filters numerically
  Given Im logged in as a user "" for an entity "name=TestFund;entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given there is a FormType "name=CapitalCommitment;tag=Default"
  Given the form type has a filterable number field "ticket_size" labelled "Ticket Size"
  Given there is an existing fund "name=FilterFund"
  Given there is an existing investor "investor_name=Investor A"
  Given there is an existing capital commitment "committed_amount=111111;json_fields=ticket_size:9" for "FilterFund" and "Investor A"
  Given there is an existing capital commitment "committed_amount=222222;json_fields=ticket_size:25" for "FilterFund" and "Investor A"
  Given there is an existing capital commitment "committed_amount=333333;json_fields=ticket_size:100" for "FilterFund" and "Investor A"
  When I filter capital commitments by "ticket_size" greater than "10"
  Then I should see "2" capital commitment in the results
  And the result should contain committed amount "222,222"
  And the result should contain committed amount "333,333"
  And the result should not contain committed amount "111,111"

# E1 — another company's filterable fields never appear in my filter dropdown
Scenario: Another company's custom fields are not offered in my filter
  Given Im logged in as a user "" for an entity "name=TestFund;entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given there is a FormType "name=CapitalCommitment;tag=Default"
  Given the form type has a filterable text field "source_of_funds" labelled "Source of Funds"
  Given another company has a filterable "TextField" field "a_only_field" labelled "A Only Field" and its user has opened the commitments filter
  When I visit the capital commitments index with filter open
  Then I should see a filter row labelled "Source of Funds"
  And I should not see a filter row labelled "A Only Field"

# E2 — the same field name is text for another company and a number for mine: mine still compares numbers
Scenario: A field name another company uses as text still filters numerically for me
  Given Im logged in as a user "" for an entity "name=TestFund;entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given another company has a filterable "TextField" field "ticket_size" labelled "Ticket Size" and its user has opened the commitments filter
  Given there is a FormType "name=CapitalCommitment;tag=Default"
  Given the form type has a filterable number field "ticket_size" labelled "Ticket Size"
  Given there is an existing fund "name=FilterFund"
  Given there is an existing investor "investor_name=Investor A"
  Given there is an existing capital commitment "committed_amount=111111;json_fields=ticket_size:9" for "FilterFund" and "Investor A"
  Given there is an existing capital commitment "committed_amount=333333;json_fields=ticket_size:100" for "FilterFund" and "Investor A"
  When I filter capital commitments by "ticket_size" greater than "10"
  Then I should see "1" capital commitment in the results
  And the result should contain committed amount "333,333"

# E3 — un-ticking Show in Filter takes the field out of the filter without a restart
Scenario: A field no longer shown in filters disappears from the filter
  Given Im logged in as a user "" for an entity "name=TestFund;entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given there is a FormType "name=CapitalCommitment;tag=Default"
  Given the form type has a filterable text field "source_of_funds" labelled "Source of Funds"
  When I visit the capital commitments index with filter open
  Then I should see a filter row labelled "Source of Funds"
  When the field "source_of_funds" is no longer shown in filters
  And I visit the capital commitments index with filter open
  Then I should not see a filter row labelled "Source of Funds"

# X1 — with no signed-in user (jobs, MCP, console) no custom-field filter names apply, and nothing raises
Scenario: Search without a signed-in user offers no custom-field filters
  Given Im logged in as a user "" for an entity "name=TestFund;entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given there is a FormType "name=CapitalCommitment;tag=Default"
  Given the form type has a filterable text field "source_of_funds" labelled "Source of Funds"
  When I visit the capital commitments index with filter open
  Then without a signed-in user the commitment search fields should not include "source_of_funds"
