@form_custom_fields
Feature: FormCustomField Validations
  Browser-based end-to-end tests for custom field validation rules,
  covering both the admin setup UI and the data-capture forms.
  Each scenario includes a "without validation rules" counterpart to confirm
  that unconstrained fields accept any value without blocking the save.

  Background:
    Given Im logged in as a user "" for an entity "name=Fund1;entity_type=Investment Fund"
    Given the user has role "company_admin"

  # ── FCF Setup: validation-rule UI is field-type-aware ────────────────────
  # The Stimulus fcf-setup controller hides inputs irrelevant to the chosen
  # field type. These scenarios confirm that behaviour in a real browser.

  @ui
  Scenario: Validation Rules panel hides date inputs for a NumberField
    Given the entity has a persisted NumberField FCF named "Score" for "Investor"
    When I visit the form type edit page for "Investor"
    And I expand the validation rules panel for the "Score" custom field
    Then the date-range inputs should not be visible within that panel
    And the number-range inputs should be visible within that panel

  @ui
  Scenario: Validation Rules panel hides number inputs for a TextField
    Given the entity has a persisted TextField FCF named "Code" for "Investor"
    When I visit the form type edit page for "Investor"
    And I expand the validation rules panel for the "Code" custom field
    Then the number-range inputs should not be visible within that panel
    And the text-length inputs should be visible within that panel

  @ui
  Scenario: Admin saves min/max value rules for a NumberField via the UI
    Given the entity has a persisted NumberField FCF named "Score" for "Investor"
    When I visit the form type edit page for "Investor"
    And I expand the validation rules panel for the "Score" custom field
    And I fill in the "Min Value" validation input with "0"
    And I fill in the "Max Value" validation input with "100"
    And I save the form type
    Then the "Score" FCF should have validation rule "min_value" equal to "0"
    And the "Score" FCF should have validation rule "max_value" equal to "100"

  @ui
  Scenario: Admin saves max_length rule for a TextField via the UI
    Given the entity has a persisted TextField FCF named "Code" for "Investor"
    When I visit the form type edit page for "Investor"
    And I expand the validation rules panel for the "Code" custom field
    And I fill in the "Max Length" validation input with "5"
    And I save the form type
    Then the "Code" FCF should have validation rule "max_length" equal to "5"

  # ── Data Capture: WITHOUT validation rules — anything is accepted ─────────
  # These confirm that the absence of validation_rules does not block any value.

  @ui
  Scenario: TextField with no validation rules accepts any text
    Given the entity has a persisted TextField FCF named "Notes" for "Investor"
    And there is a test investor
    When I visit the investor edit page
    And I fill in custom field "notes" with "Hello — this is a very long note with special chars #@!"
    And I submit the investor form
    Then I should see "successfully" on the page

  @ui
  Scenario: NumberField with no validation rules accepts any number
    Given the entity has a persisted NumberField FCF named "Score" for "Investor"
    And there is a test investor
    When I visit the investor edit page
    And I fill in custom field "score" with "99999"
    And I submit the investor form
    Then I should see "successfully" on the page

  @ui
  Scenario: DateField with no validation rules accepts any date
    Given the entity has a persisted DateField FCF named "Join Date" for "Investor"
    And there is a test investor
    When I visit the investor edit page
    And I fill in custom field "join_date" with "2000-01-01"
    And I submit the investor form
    Then I should see "successfully" on the page

  # ── Data Capture: WITH validation rules — required ────────────────────────

  @ui
  Scenario: Required TextField left blank shows an error in the browser
    Given the entity has a persisted TextField FCF named "Ref Number" for "Investor" with required true
    And there is a test investor
    When I visit the investor edit page
    And I clear custom field "ref_number"
    And I submit the investor form
    Then I should see "required" on the page

  @ui
  Scenario: Required TextField filled saves successfully
    Given the entity has a persisted TextField FCF named "Ref Number" for "Investor" with required true
    And there is a test investor
    When I visit the investor edit page
    And I fill in custom field "ref_number" with "REF-001"
    And I submit the investor form
    Then I should see "successfully" on the page

  # ── Data Capture: WITH validation rules — numeric range ──────────────────

  @ui
  Scenario: NumberField value below min_value shows an error
    Given the entity has a persisted NumberField FCF named "Age" for "Investor" with validation_rules "min_value=18"
    And there is a test investor
    When I visit the investor edit page
    And I fill in custom field "age" with "5"
    And I submit the investor form
    Then I should see "at least 18" on the page

  @ui
  Scenario: NumberField value within the valid range saves successfully
    Given the entity has a persisted NumberField FCF named "Age" for "Investor" with validation_rules "min_value=18,max_value=100"
    And there is a test investor
    When I visit the investor edit page
    And I fill in custom field "age" with "25"
    And I submit the investor form
    Then I should see "successfully" on the page

  @ui
  Scenario: NumberField value above max_value shows an error
    Given the entity has a persisted NumberField FCF named "Age" for "Investor" with validation_rules "max_value=100"
    And there is a test investor
    When I visit the investor edit page
    And I fill in custom field "age" with "150"
    And I submit the investor form
    Then I should see "at most 100" on the page

  # ── Data Capture: WITH validation rules — text length ────────────────────

  @ui
  Scenario: TextField exceeding max_length shows an error
    Given the entity has a persisted TextField FCF named "Code" for "Investor" with validation_rules "max_length=5"
    And there is a test investor
    When I visit the investor edit page
    And I fill in custom field "code" with "TOOLONGVALUE"
    And I submit the investor form
    Then I should see "at most 5 characters" on the page

  @ui
  Scenario: TextField within max_length saves successfully
    Given the entity has a persisted TextField FCF named "Code" for "Investor" with validation_rules "max_length=5"
    And there is a test investor
    When I visit the investor edit page
    And I fill in custom field "code" with "AB123"
    And I submit the investor form
    Then I should see "successfully" on the page

  @ui
  Scenario: TextField below min_length shows an error
    Given the entity has a persisted TextField FCF named "Code" for "Investor" with validation_rules "min_length=5"
    And there is a test investor
    When I visit the investor edit page
    And I fill in custom field "code" with "AB"
    And I submit the investor form
    Then I should see "at least 5 characters" on the page

  # ── Data Capture: WITH validation rules — format ──────────────────────────

  @ui
  Scenario: TextField with invalid PAN format shows an error
    Given the entity has a persisted TextField FCF named "PAN" for "Investor" with validation_rules "format=pan"
    And there is a test investor
    When I visit the investor edit page
    And I fill in custom field "pan" with "INVALID"
    And I submit the investor form
    Then I should see "valid pan" on the page

  @ui
  Scenario: TextField with valid PAN format saves successfully
    Given the entity has a persisted TextField FCF named "PAN" for "Investor" with validation_rules "format=pan"
    And there is a test investor
    When I visit the investor edit page
    And I fill in custom field "pan" with "ABCDE1234F"
    And I submit the investor form
    Then I should see "successfully" on the page

  # ── Data Capture: WITH validation rules — date range ─────────────────────

  @ui
  Scenario: DateField before min_date shows an error
    Given the entity has a persisted DateField FCF named "Join Date" for "Investor" with validation_rules "min_date=today"
    And there is a test investor
    When I visit the investor edit page
    And I fill in custom field "join_date" with a date 1 year ago
    And I submit the investor form
    Then I should see "cannot be before" on the page

  @ui
  Scenario: DateField on or after min_date saves successfully
    Given the entity has a persisted DateField FCF named "Join Date" for "Investor" with validation_rules "min_date=today"
    And there is a test investor
    When I visit the investor edit page
    And I fill in custom field "join_date" with today's date
    And I submit the investor form
    Then I should see "successfully" on the page
