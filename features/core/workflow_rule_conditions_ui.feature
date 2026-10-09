Feature: Auto-assignment rule conditions — the rule form builder
  The rule form builds conditions as rows of field / operator / value from the record type's field
  list, can show them as JSON, and refuses on save any condition that could never match. The
  template page describes each rule's conditions in words.
  Worked examples H1, H5, E1, E4, E5, E6, X1, X2, X3, X4, X5 in
  openspec/changes/workflow-rule-condition-builder/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_kycs=true;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And the entity's investor KYC journeys are seeded
    And the entity has the KYC form types "Individual — Default, Individual — Fund IV, Non Individual — Default"
    And the "Individual" KYC forms have the custom fields:
      | name          | label         | field_type  | meta_data    |
      | nationality   | Nationality   | Select      | India,USA,UK |
      | ticket_size   | Ticket size   | NumberField |              |
      | passport_copy | Passport copy | File        |              |
    And the template "Investor KYC" is duplicated as "Investor KYC — Fund IV (domestic)"

  # H1 (builder) + H5 — a rule built from rows saves, routes, and reads in words on the template page
  Scenario: A rule built from rows saves and reads in words
    When I open a new rule for "Investor KYC — Fund IV (domestic)"
    And I add the condition "Form type" "is" "Individual — Fund IV"
    And I add the condition "Nationality" "is" "India"
    And I save the rule
    Then the rule should be saved
    And the rule for "Investor KYC — Fund IV (domestic)" should have the stored conditions:
      """
      [{"attribute":"form_type_id","operator":"eq","value":"<form type: Individual — Fund IV>"},
       {"attribute":"json_fields.nationality","operator":"eq","value":"India"}]
      """
    And the rules table on "Investor KYC — Fund IV (domestic)" should read "Form type is Individual — Fund IV and Nationality is India"
    When these KYCs are created:
      | kyc | form type            | nationality |
      | A   | Individual — Fund IV | India       |
      | B   | Individual — Fund IV | USA         |
    Then they should get the templates:
      | kyc | template                          |
      | A   | Investor KYC — Fund IV (domestic) |
      | B   | Investor KYC                      |

  # E1 — the field list: search fields, form type, custom fields; not identifiers, files or other companies' fields
  Scenario: The field list offers this company's fields only
    Given another entity has its own KYC form type "Other Co"
    When I open a new rule for "Investor KYC — Fund IV (domestic)"
    Then the field list on the rule form should include "Form type, Verified, Expiry date, Nationality, Ticket size"
    And the field list on the rule form should not include "Passport copy, PAN, Committed amount"

  # E4 — a saved rule opens as rows, with no separate KYC form type control
  Scenario: A saved rule loads into the builder as rows
    Given a rule on "Investor KYC — Fund IV (domestic)" at priority 0 with conditions:
      """
      [{"attribute":"form_type_id","operator":"eq","value":"<form type: Individual — Fund IV>"},
       {"attribute":"json_fields.ticket_size","operator":"gteq","value":"10"}]
      """
    When I edit the rule on "Investor KYC — Fund IV (domestic)"
    Then the rule form should show the conditions:
      | field       | operator | value                |
      | Form type   | is       | Individual — Fund IV |
      | Ticket size | at least | 10                   |
    And I should not see "KYC form type"

  # E5 — a change made in View as JSON comes back to the rows and is saved
  Scenario: Editing through View as JSON round-trips to the rows
    When I open a new rule for "Investor KYC — Fund IV (domestic)"
    And I add the condition "Nationality" "is" "India"
    And I toggle View as JSON
    And I change "India" to "UK" in the conditions JSON
    And I toggle View as JSON
    Then the rule form should show the conditions:
      | field       | operator | value |
      | Nationality | is       | UK    |
    When I save the rule
    Then the rule should be saved
    And the rules table on "Investor KYC — Fund IV (domestic)" should read "Nationality is UK"

  # E6 — a deleted custom field: the rule stops matching, and the form makes the admin fix it
  Scenario: A rule on a deleted custom field stops matching and must be fixed
    Given a rule on "Investor KYC — Fund IV (domestic)" at priority 0 with conditions:
      """
      [{"attribute":"form_type_id","operator":"eq","value":"<form type: Individual — Fund IV>"},
       {"attribute":"json_fields.nationality","operator":"eq","value":"India"}]
      """
    And the custom field "nationality" is deleted from the KYC forms
    When these KYCs are created:
      | kyc | form type            | nationality |
      | A   | Individual — Fund IV | India       |
    Then they should get the templates:
      | kyc | template     |
      | A   | Investor KYC |
    When I edit the rule on "Investor KYC — Fund IV (domestic)"
    Then the rule form should show the unknown field "nationality"
    When I save the rule
    Then the rule should not be saved and the form should show "Condition 2: Unknown field \"nationality\"."
    When I remove the unknown condition
    And I save the rule
    Then the rule should be saved

  # X1 — unknown field
  Scenario: An unknown field is refused
    When I open a new rule for "Investor KYC — Fund IV (domestic)"
    And I replace the conditions JSON with:
      """
      [{"attribute":"json_fields.nationalty","operator":"eq","value":"India"}]
      """
    And I save the rule
    Then the rule should not be saved and the form should show "Condition 1: Unknown field \"nationalty\"."

  # X2 — an operator the field does not allow
  Scenario: An operator the field does not allow is refused
    When I open a new rule for "Investor KYC — Fund IV (domestic)"
    And I replace the conditions JSON with:
      """
      [{"attribute":"form_type_id","operator":"gt","value":"<form type: Individual — Fund IV>"}]
      """
    And I save the rule
    Then the rule should not be saved and the form should show "Condition 1: \"greater than\" can't be used with Form type."

  # X3 — another company's form type
  Scenario: Another company's form type is refused
    Given another entity has its own KYC form type "Other Co"
    When I open a new rule for "Investor KYC — Fund IV (domestic)"
    And I replace the conditions JSON with:
      """
      [{"attribute":"form_type_id","operator":"eq","value":"999999"}]
      """
    And I save the rule
    Then the rule should not be saved and the form should show "Condition 1: Form type 999999 is not one of this company's form types."

  # X4 — a non-number and a missing value
  Scenario: A non-number and a missing value are refused
    When I open a new rule for "Investor KYC — Fund IV (domestic)"
    And I replace the conditions JSON with:
      """
      [{"attribute":"json_fields.ticket_size","operator":"gteq","value":"abc"},
       {"attribute":"json_fields.nationality","operator":"eq","value":""}]
      """
    And I save the rule
    Then the rule should not be saved and the form should show "Condition 1: Ticket size needs a number."
    And the rule should not be saved and the form should show "Condition 2: Nationality needs a value."

  # X5 — JSON that is not a list of conditions
  Scenario: Malformed JSON is refused without an error page
    When I open a new rule for "Investor KYC — Fund IV (domestic)"
    And I replace the conditions JSON with:
      """
      {"attribute":"verified"}
      """
    And I save the rule
    Then the rule should not be saved and the form should show "The JSON is not a valid list of conditions."
