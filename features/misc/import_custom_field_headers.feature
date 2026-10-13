@import @rack_test
Feature: Import custom field headers
  Spreadsheet imports that use a Form Tag match each custom column to a form custom field.
  A column must match the label shown on screen (and in the upload template) even when the
  stored label is blank, and the field name shown as "Import Column Name".
  investor_category (blank label, shown as "Investor Category") and sebi_investor_category
  (explicitly labelled "Investor Category") collide: the explicit label wins, as it always did.

Scenario: Columns resolve to fields with blank, nil, hyphenated and underscored labels
  Given there is a user "" for an entity "name=Urban;entity_type=Investment Fund"
  Given there is a FormType "name=CapitalCommitment;tag=TNcustomform"
  Given the form type has custom fields with stored labels
    | name                   | label                 |
    | carry_from_kyc         | <blank>               |
    | udr_1                  | <nil>                 |
    | pre_money_val          | Pre-Money Valuation   |
    | joint_holder_photo     | Photo - Joint Holder  |
    | investor_category      | <blank>               |
    | sebi_investor_category | Investor Category     |
  Then the import columns resolve to these custom fields
    | column                | field                  |
    | Carry From Kyc        | carry_from_kyc         |
    | carry_from_kyc        | carry_from_kyc         |
    | Udr 1                 | udr_1                  |
    | Pre-Money Valuation   | pre_money_val          |
    | Photo - Joint Holder  | joint_holder_photo     |
    | Investor Category     | sebi_investor_category |
  And the import column "Not A Field" does not resolve to a custom field
  And importing the columns into a capital commitment stores them under the field names

Scenario: A blank label entered on the form is saved as the label shown on screen
  Given there is a user "" for an entity "name=Urban;entity_type=Investment Fund"
  Given there is a FormType "name=CapitalCommitment;tag=Default"
  When a custom field "carry_from_kyc" is created with label ""
  Then the custom field "carry_from_kyc" has label "Carry From Kyc"
  When a custom field "folio_definition" is created without a label
  Then the custom field "folio_definition" has label "Folio definition"
