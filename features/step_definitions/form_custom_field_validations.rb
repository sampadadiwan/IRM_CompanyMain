# Browser-based step definitions for FormCustomField validation features.
# Uses Capybara for all UI interactions.

# ── Private helpers ────────────────────────────────────────────────────────────

def fcv_form_type(class_name)
  # Find or create an empty FormType for the given class — does NOT add FCFs.
  @entity.form_types.where(name: class_name, tag: "Default").first_or_initialize.tap do |ft|
    ft.save!(validate: false) if ft.new_record?
  end
end

def fcv_parse_rules(rules_str)
  return {} if rules_str.blank?
  rules_str.split(",").each_with_object({}) do |pair, h|
    k, v = pair.split("=", 2)
    h[k.strip] = v.strip
  end
end

# ── Backend setup: FCF creation ────────────────────────────────────────────────

# Creates (or updates) a single persisted FCF with no constraints.
Given('the entity has a persisted {word} FCF named {string} for {string}') do |field_type, name, class_name|
  @form_type = fcv_form_type(class_name)
  @fcf = @form_type.form_custom_fields
                   .where(name: FormCustomField.to_name(name))
                   .first_or_initialize
  @fcf.assign_attributes(field_type: field_type,
                          position:   @form_type.form_custom_fields.count + 1)
  @fcf.save!
end

# Creates a persisted FCF with required: true.
Given('the entity has a persisted {word} FCF named {string} for {string} with required true') do |field_type, name, class_name|
  @form_type = fcv_form_type(class_name)
  @fcf = @form_type.form_custom_fields
                   .where(name: FormCustomField.to_name(name))
                   .first_or_initialize
  @fcf.assign_attributes(field_type: field_type,
                          position:   @form_type.form_custom_fields.count + 1,
                          required:   true)
  @fcf.save!
end

# Creates a persisted FCF with validation_rules parsed from "key=value,..." CSV.
Given('the entity has a persisted {word} FCF named {string} for {string} with validation_rules {string}') do |field_type, name, class_name, rules_str|
  @form_type = fcv_form_type(class_name)
  @fcf = @form_type.form_custom_fields
                   .where(name: FormCustomField.to_name(name))
                   .first_or_initialize
  @fcf.assign_attributes(field_type:       field_type,
                          position:         @form_type.form_custom_fields.count + 1,
                          validation_rules: fcv_parse_rules(rules_str))
  @fcf.save!
end

# ── Backend setup: investor creation ──────────────────────────────────────────

# Builds and saves an investor linked to @form_type, bypassing custom-field
# validation so the step works regardless of FCF required/rule settings.
# This prevents FactoryBot.create from failing when the FormType already has
# required custom fields.
Given('there is a test investor') do
  raise "Call a FCF setup step first so @form_type is defined" unless @form_type

  investor_entity = FactoryBot.create(:entity,
    name:        "Test Investor Entity #{SecureRandom.hex(4)}",
    entity_type: "Investment Fund")

  @investor = FactoryBot.build(:investor,
    investor_entity_id: investor_entity.id,
    entity_id:          @entity.id,
    investor_name:      "Test Investor")

  # Assign form_type so the edit page renders custom field inputs.
  @investor.form_type          = @form_type
  @investor.skip_cf_before_save = true  # skip both required-field and format checks
  @investor.save!
end

# ── FCF setup UI steps ─────────────────────────────────────────────────────────

When('I visit the form type edit page for {string}') do |class_name|
  @form_type ||= @entity.form_types.where(name: class_name, tag: "Default").last
  visit edit_form_type_path(@form_type)
end

# Expands the Bootstrap-collapsible Validation Rules section for the given FCF.
# The template renders THREE divs that share the same id="custom_condition_row_<id>"
# (conditions row 1, conditions row 2, and validation rules). We click the toggle
# to expand all three, then store the last one — which is always the Validation Rules
# panel — as @vr_panel for subsequent scoped assertions.
When('I expand the validation rules panel for the {string} custom field') do |name|
  fcf = @form_type.form_custom_fields.find_by!(name: FormCustomField.to_name(name))
  # Click the collapse toggle (first matching anchor — same href for all three).
  find("a[href='#custom_condition_row_#{fcf.id}']", match: :first).click
  sleep(1) # allow Bootstrap collapse animation to finish
  # The Validation Rules section is always the LAST of the three same-id divs.
  @vr_panel = all("[id='custom_condition_row_#{fcf.id}']", visible: :all).last
end

# Visibility assertions driven by Stimulus fcf-setup controller.
# All use @vr_panel (a specific Element, not an ambiguous id selector).

Then('the date-range inputs should not be visible within that panel') do
  within(@vr_panel) do
    all(".fcf-vr-datefield", visible: :all).each do |el|
      expect(el).not_to be_visible,
        "Expected date-range input to be hidden for this field type but it was visible"
    end
  end
end

Then('the number-range inputs should be visible within that panel') do
  within(@vr_panel) do
    expect(page).to have_css(".fcf-vr-numberfield", visible: true)
  end
end

Then('the number-range inputs should not be visible within that panel') do
  within(@vr_panel) do
    all(".fcf-vr-numberfield", visible: :all).each do |el|
      expect(el).not_to be_visible,
        "Expected number-range input to be hidden for this field type but it was visible"
    end
  end
end

Then('the text-length inputs should be visible within that panel') do
  within(@vr_panel) do
    expect(page).to have_css(".fcf-vr-textfield", visible: true)
  end
end

# Fills a validation rule input by its visible label text (more stable than IDs,
# which embed an unpredictable index in the form_custom_fields_attributes array).
When('I fill in the {string} validation input with {string}') do |label_text, value|
  within(@vr_panel) do
    fill_in label_text, with: value
  end
end

When('I save the form type') do
  click_on "Save"
  sleep(1)
  @form_type.reload
end

Then('the {string} FCF should have validation rule {string} equal to {string}') do |name, rule_key, expected|
  fcf = @form_type.form_custom_fields.find_by!(name: FormCustomField.to_name(name))
  fcf.reload
  actual = (fcf.validation_rules || {})[rule_key].to_s
  expect(actual).to eq(expected),
    "Expected validation_rules['#{rule_key}'] = #{expected.inspect}, got #{actual.inspect}"
end

# ── Data capture browser steps ─────────────────────────────────────────────────

When('I visit the investor edit page') do
  raise "No @investor found — add 'Given there is a test investor' step" unless @investor
  visit edit_investor_path(@investor)
end

# Sets a custom field value via JavaScript, bypassing browser-enforced HTML5
# constraints (maxlength, min, max, pattern). Selenium's fill_in sends keystrokes
# which ARE limited by maxlength — typing "TOOLONGVALUE" into a maxlength=5 input
# would only commit "TOOLO", defeating the server-side validation test.
def set_custom_field(page, field_name, value)
  field_id = "investor_properties_#{field_name}"
  page.execute_script("document.getElementById(#{field_id.to_json}).value = #{value.to_json}")
end

When('I fill in custom field {string} with {string}') do |field_name, value|
  set_custom_field(page, field_name, value)
end

When('I clear custom field {string}') do |field_name|
  set_custom_field(page, field_name, "")
end

When('I fill in custom field {string} with a date 1 year ago') do |field_name|
  set_custom_field(page, field_name, (Time.zone.today - 1.year).iso8601)
end

When("I fill in custom field {string} with today's date") do |field_name|
  set_custom_field(page, field_name, Time.zone.today.iso8601)
end

When('I submit the investor form') do
  # Strip HTML5 constraint attributes from every custom field input so the browser
  # does not block the submit. Server-side Rails validation is what's under test;
  # client-side constraints (min, max, minlength, maxlength, required, pattern) would
  # swallow the submit event and prevent Rails validation from running at all.
  page.execute_script(<<~JS)
    document.querySelectorAll('.custom_field').forEach(function(el) {
      ['required', 'min', 'max', 'minlength', 'maxlength', 'pattern'].forEach(function(attr) {
        el.removeAttribute(attr);
      });
    });
  JS
  click_on "Save"
  sleep(1)
end

Then('I should see {string} on the page') do |text|
  expect(page).to have_content(text, wait: 5)
end
