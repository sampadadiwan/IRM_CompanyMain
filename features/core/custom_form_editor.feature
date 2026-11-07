@custom_form_editor
Feature: Custom form editor
  The custom form edit page lists the fields on the left, grouped by wizard step, and shows one field's settings on
  the right. Only the screen changed: the page still submits the same nested form_custom_fields_attributes, so these
  scenarios check both what the editor shows and what ends up stored.

  Background:
    Given Im logged in as a user "" for an entity "name=Fund1;entity_type=Investment Fund"
    Given the user has role "company_admin"
    And the "Investor" custom form has the fields:
      | label    | field_type  | meta_data       | step | position |
      | Founder  | TextField   |                 | end  | 1        |
      | Domicile | Select      | Domestic,Foreign | end  | 2        |
      | Score    | NumberField |                 | one  | 3        |

  # Edge case: an untouched form must save exactly what it holds — no widget may rewrite a stored value
  Scenario: Opening and saving an untouched form changes nothing
    Given the "Investor" custom form also has a hidden calculation field at position 10
    And I note every field of the "Investor" custom form
    When I open the custom form editor for "Investor"
    And I save the custom form
    Then every field of the "Investor" custom form is unchanged

  Scenario: Fields are listed by step and one field opens at a time
    When I open the custom form editor for "Investor"
    Then the form editor lists "Score" under "Step 1"
    And the form editor lists "Founder, Domicile" under "Step 3 (Default)"
    When I open the "Domicile" field in the form editor
    Then the form editor shows the "Domicile" field's settings only

  Scenario: Choices are edited as chips and saved as text
    When I open the custom form editor for "Investor"
    And I open the "Domicile" field in the form editor
    And I add the choice "Other" in the form editor
    And I remove the choice "Foreign" in the form editor
    Then the form editor preview offers "Domestic, Other"
    When I save the custom form
    Then the "Domicile" field's meta data is "Domestic,Other"

  Scenario: Number format is picked, not typed
    When I open the custom form editor for "Investor"
    And I open the "Score" field in the form editor
    And I pick 2 decimal places in the form editor
    And I save the custom form
    Then the "Score" field's meta data is "2,comma"

  # Edge case: fields the page does not show (calculations for non-support users) keep their positions
  Scenario: Dragging a field reorders it and keeps hidden fields in place
    Given the "Investor" custom form also has a hidden calculation field at position 10
    When I open the custom form editor for "Investor"
    And I drag "Founder" below "Domicile" in the form editor
    Then the form editor shows "1 unsaved change"
    When I save the custom form
    Then the "Investor" custom form's fields are ordered "Domicile, Founder"
    And the hidden calculation field is still at position 10

  Scenario: Dropping a field on a step heading moves it to that step
    When I open the custom form editor for "Investor"
    And I drag "Founder" onto the "Step 1" heading in the form editor
    And I save the custom form
    Then the "Founder" field is on step "one"

  Scenario: A condition is set as one sentence
    When I open the custom form editor for "Investor"
    And I open the "Founder" field in the form editor
    And I set the form editor condition to "Domicile" "is" "Foreign"
    And I save the custom form
    Then the "Founder" field shows only when "domicile" "eq" "Foreign"

  Scenario: Visible to picks users instead of typing ids
    When I open the custom form editor for "Investor"
    And I open the "Founder" field in the form editor
    And I make the field visible only to me in the form editor
    And I save the custom form
    Then the "Founder" field is shown only to me

  # Edge case: FormCustomField#read_only_and_required — the switches never allow both
  Scenario: Required and Read only cannot both be on
    When I open the custom form editor for "Investor"
    And I open the "Founder" field in the form editor
    And I turn on "required" in the form editor
    And I turn on "read_only" in the form editor
    Then the form editor has "read_only" on and "required" off
    And I should see "A field can't be both required and read only"

  Scenario: A new field takes its stored name from its label and goes last
    When I open the custom form editor for "Investor"
    And I add the field "Source of funds" in the form editor
    Then the form editor's stored name for the new field is "source_of_funds"
    When I save the custom form
    Then the "Investor" custom form has a field "source_of_funds" placed last

  Scenario: Removing a field can be undone until saved
    When I open the custom form editor for "Investor"
    And I open the "Founder" field in the form editor
    And I press "Remove field"
    Then I should see "This field will be removed when you save"
    When I click on "Undo"
    And I press "Remove field"
    And I save the custom form
    Then the "Investor" custom form has no field "founder"

  # Edge case: a failed save keeps what was typed and opens the field that failed
  Scenario: A failed save keeps the edits and opens the field that failed
    When I open the custom form editor for "Investor"
    And I open the "Founder" field in the form editor
    And I change the form editor label to "Founder name"
    And I open the "Domicile" field in the form editor
    And I remove the choice "Domestic" in the form editor
    And I remove the choice "Foreign" in the form editor
    And I save the custom form expecting an error
    Then the form editor shows the "Domicile" field's settings only
    And I should see "must provide at least one option"
    When I open the "Founder name" field in the form editor
    Then the form editor label is "Founder name"

  Scenario: Leaving with unsaved changes asks first
    When I open the custom form editor for "Investor"
    And I open the "Founder" field in the form editor
    And I change the form editor label to "Founder name"
    And I follow the "Custom Forms" breadcrumb
    Then I should see "Leave without saving?"
    When I press "Stay on this page"
    Then the form editor label is "Founder name"

  # Edge case: an older type name (text_field) is saved as the current name of the same type, never as whichever
  # option comes first (the old page's CheckBox) — the model accepts current names only
  Scenario: An older field type name is saved as its current name
    Given the "Investor" custom form's "Founder" field has the older type "text_field"
    When I open the custom form editor for "Investor"
    And I open the "Founder" field in the form editor
    Then I should see "Stored under the older type name text_field"
    When I save the custom form
    Then the "Founder" field's type is "TextField"
