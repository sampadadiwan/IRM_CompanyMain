@investor_kyc_xlsx_export
Feature: Investor KYC xlsx export formats custom fields by type
  The investor_kycs xlsx export must render each custom field according to its
  field type instead of exporting every value as plain text: DateField values
  become real date cells, NumberField/Money values become real numeric cells,
  and MultiSelect values are joined into readable text. TextField values stay
  plain text.

  Scenario: Downloaded IndividualKyc xlsx renders each custom field type correctly
    Given there is a user "" for an entity "name=Urban;entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given the entity has custom fields "name=Review Date;field_type=DateField#name=Investment Amount;field_type=NumberField#name=Advisory Fee;field_type=Money#name=Preferred Channels;field_type=MultiSelect;meta_data=Email,Phone,Post#name=Notes;field_type=TextField" for "IndividualKyc"
    Given there is an existing investor "investor_name=Investor 1"
    Given there is an IndividualKyc for the investor with custom field values "Review Date:2026-03-15|Investment Amount:125000|Advisory Fee:2500.75|Preferred Channels:Email,Phone|Notes:Some plain text"
    When I download the "IndividualKyc" xlsx export
    Then the exported xlsx custom field "Review Date" should be a date cell with value "2026-03-15"
    And the exported xlsx custom field "Investment Amount" should be a numeric cell with value "125000"
    And the exported xlsx custom field "Advisory Fee" should be a numeric cell with value "2500.75"
    And the exported xlsx custom field "Preferred Channels" should be the text "Email, Phone"
    And the exported xlsx custom field "Notes" should be the text "Some plain text"
