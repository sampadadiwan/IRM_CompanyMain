# Worked examples H10–H15, H21, E13–E22, X13–X15 — openspec/changes/grid-columns-inline-settings/business-rules.md#3-custom-fields-on-record-pages--phase-4
# (X10–X12, X16–X18: features/security/custom_fields_inline_settings_isolation.feature)
Feature: Custom fields in place
  A record's page has a custom fields icon on the card holding its fields; the side panel lists the record's form
  type fields and saves every change at once, then the page refreshes in place.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And there is an investor named "Ravi Menon"
    And there is an investor named "Acme Family Office"
    And my firm's "Investor" form type has the fields:
      | name                 | label                | type        | flags    | meta            |
      | risk_rating          | Risk rating          | Select      | required | Low,Medium,High |
      | relationship_manager | Relationship manager | TextField   | internal |                 |
      | kyc_due              | KYC due              | DateField   |          |                 |
      | net_worth            | Net worth            | Calculation |          | 1 + 1           |
    And the investor "Ravi Menon" is on my firm's "Investor" form type
    And the investor "Acme Family Office" is on my firm's "Investor" form type
    And the investor "Ravi Menon" has "kyc_due" set to "2027-03-31"

  # H10 — Happy path: the icon on the details card; the panel lists the form type's fields in order
  Scenario: Icon and fields list
    When I open the page of the investor "Ravi Menon"
    Then the details card should have the custom fields icon
    When I open the custom fields panel
    Then the fields panel should be titled "Investor fields · Default"
    And the fields panel should list "Risk rating, Relationship manager, KYC due, Net worth"

  # H11 — Happy path: reorder, rename, flags, help text and a new Select, saved at once; the page refreshes
  Scenario: Edit fields and save
    When I open the page of the investor "Ravi Menon"
    And I open the custom fields panel
    And I move the field "kyc_due" above "risk_rating"
    And I rename the field "relationship_manager" to "RM"
    And I switch "Internal" on for the field "risk_rating"
    And I set the help text of the field "risk_rating" to "From the onboarding review"
    And I add the field "Source of funds" of type "Select" with options "Salary, Business, Inheritance"
    And I save the fields
    Then the fields panel should close
    And a saved message should say "Investor fields saved"
    And my firm's "Investor" fields should be "kyc_due, risk_rating, relationship_manager, net_worth, source_of_funds"
    And the field "relationship_manager" should have label "RM"
    And the field "risk_rating" should be required, read only "no", internal "yes", help text "From the onboarding review"
    And the field "source_of_funds" should be a "Select" with options "Salary,Business,Inheritance"

  # H12 — Happy path: the new field shows for every record on the form type
  Scenario: Shared by the form type
    When I open the page of the investor "Ravi Menon"
    And I open the custom fields panel
    And I add the field "Source of funds" of type "TextField"
    And I save the fields
    Then my firm's "Investor" fields should be "risk_rating, relationship_manager, kyc_due, net_worth, source_of_funds"
    And the edit form of the investor "Acme Family Office" should offer "Source of funds"

  # H13 — Happy path: no form type for the record type — the save creates one and links the record
  Scenario: Form type created and linked
    Given my firm has no "Valuation" form type and a valuation with none
    When I open the page of the valuation
    And I open the custom fields panel
    And I add the field "Method note" of type "TextField"
    And I save the fields
    Then my firm should have a "Valuation" form type with the field "method_note", linked to the valuation

  # H14 — Happy path: removing a field deletes its definition; the value entered stays on the record
  Scenario: Remove a field
    When I open the page of the investor "Ravi Menon"
    And I open the custom fields panel
    And I remove the field "kyc_due"
    Then the panel should warn that removed fields keep their values
    When I save the fields
    Then my firm's "Investor" fields should be "risk_rating, relationship_manager, net_worth"
    And the investor "Ravi Menon" should still have "kyc_due" = "2027-03-31"

  # H21 — Happy path: the icon at the form level too, in the form card's header; the panel warns about the refresh
  Scenario: Icon on the record's form
    When I open the edit form of the investor "Ravi Menon"
    Then the form header should have the custom fields icon
    When I open the custom fields panel
    Then the fields panel should warn that saving refreshes the page
    And the fields panel should list "Risk rating, Relationship manager, KYC due, Net worth"

  # H15 — Happy path: Escape closes the panel and nothing is saved
  Scenario: Cancel with Escape
    When I open the page of the investor "Ravi Menon"
    And I open the custom fields panel
    And I rename the field "risk_rating" to "Risk band"
    And I press Escape
    Then the fields panel should close
    And the field "risk_rating" should have label "Risk rating"

  # E13 — Edge case: a record with no form type lists the firm's and is linked on save
  Scenario: Record without a form type, firm has one
    Given the investor "Acme Family Office" has no form type
    When I open the page of the investor "Acme Family Office"
    And I open the custom fields panel
    Then the fields panel should list "Risk rating, Relationship manager, KYC due, Net worth"
    When I add the field "Tier" of type "TextField"
    And I save the fields
    Then the investor "Acme Family Office" should be on my firm's "Investor" form type

  # E14 — Edge case: a calculation field is locked for a company admin who is not support
  Scenario: Calculation locked
    When I open the page of the investor "Ravi Menon"
    And I open the custom fields panel
    Then the field "net_worth" should be locked for me

  # E15 — Edge case: CapHive support may rename a calculation field; its formula stays
  Scenario: Support renames a calculation
    Given I am CapHive support
    When I open the page of the investor "Ravi Menon"
    And I open the custom fields panel
    And I rename the field "net_worth" to "Net worth (₹)"
    And I save the fields
    Then the field "net_worth" should have label "Net worth (₹)"
    And the field "net_worth" should keep type "Calculation" and meta "1 + 1"

  # E16 — Edge case: regulatory fields are not listed and keep their place
  Scenario: Regulatory fields
    Given my firm's "Investor" form type has the fields:
      | name      | label     | type      | flags | meta | reg_env |
      | sebi_code | SEBI code | TextField |       |      | SEBI    |
    When I open the page of the investor "Ravi Menon"
    And I open the custom fields panel
    Then the fields panel should not list "SEBI code"
    When I move the field "kyc_due" above "risk_rating"
    And I save the fields
    Then my firm's "Investor" fields including regulatory ones should be "kyc_due, risk_rating, relationship_manager, net_worth, sebi_code"

  # E17 — Edge case: a renamed field keeps its name, type and stored values
  Scenario: Rename keeps data
    When I open the page of the investor "Ravi Menon"
    And I open the custom fields panel
    And I rename the field "kyc_due" to "KYC review date"
    And I save the fields
    Then the field "kyc_due" should have label "KYC review date"
    And the field "kyc_due" should keep type "DateField" and meta ""
    And the investor "Ravi Menon" should still have "kyc_due" = "2027-03-31"

  # E18 — Edge case: a field removed by someone else while the panel is open stays removed
  Scenario: Field removed meanwhile
    When I open the page of the investor "Ravi Menon"
    And I open the custom fields panel
    And someone else removes the field "kyc_due"
    And I rename the field "kyc_due" to "KYC review date"
    And I save the fields
    Then the fields panel should close
    And my firm's "Investor" fields should be "risk_rating, relationship_manager, net_worth"

  # E19 — Edge case: a reporting fields list (fields chosen elsewhere) gets no icon
  Scenario: Reporting fields list
    Given an investment instrument with reporting fields
    When I open the page of the investment instrument
    Then the reporting fields card should have no custom fields icon

  # E20 — Edge case: a Money field uses the firm's currency
  Scenario: Money field
    When I open the page of the investor "Ravi Menon"
    And I open the custom fields panel
    And I add the field "Ticket size" of type "Money"
    And I save the fields
    Then the field "ticket_size" should be a "Money" with options "INR"

  # E21 — Edge case: a record on a second form type edits that one
  Scenario: Second form type
    Given my firm has "CapitalCommitment" form types tagged "Default, Feeder"
    And a commitment of "Ravi Menon" on my firm's "CapitalCommitment" form type tagged "Feeder"
    When I open the page of the commitment
    And I open the custom fields panel
    Then the fields panel should be titled "Capital commitment fields · Feeder"
    When I add the field "Side letter" of type "TextField"
    And I save the fields
    Then the "CapitalCommitment" form type tagged "Feeder" should have the field "side_letter"
    And the "CapitalCommitment" form type tagged "Default" should not have the field "side_letter"

  # E22 — Edge case: a double click on Save adds the field once
  Scenario: Double click on Save
    When I open the page of the investor "Ravi Menon"
    And I open the custom fields panel
    And I add the field "Source of funds" of type "TextField"
    And I click Save twice quickly
    Then my firm's "Investor" form type should have exactly one field named "source_of_funds"

  # X13 — Error case: a new field named like an existing one is refused; nothing is saved
  Scenario: Duplicate name
    When I open the page of the investor "Ravi Menon"
    And I open the custom fields panel
    And I add the field "Risk rating" of type "TextField"
    And I save the fields
    Then the fields panel should say "A field named Risk rating already exists"
    And my firm's "Investor" fields should be "risk_rating, relationship_manager, kyc_due, net_worth"

  # X14 — Error case: Add with an empty label adds nothing
  Scenario: No label
    When I open the page of the investor "Ravi Menon"
    And I open the custom fields panel
    And I click Add with an empty label
    Then the fields panel should still list 4 fields

  # X15 — Error case: a Select without options is refused
  Scenario: Select without options
    When I open the page of the investor "Ravi Menon"
    And I open the custom fields panel
    And I add the field "Tier" of type "Select"
    And I save the fields
    Then the fields panel should say "Add at least one option for Tier"
    And my firm's "Investor" fields should be "risk_rating, relationship_manager, kyc_due, net_worth"
